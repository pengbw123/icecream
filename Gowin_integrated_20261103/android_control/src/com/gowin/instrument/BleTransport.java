package com.gowin.instrument;

import android.annotation.TargetApi;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanFilter;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.os.ParcelUuid;
import android.util.Log;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

/**
 * 极简 GATT 传输层：扫描 -> 连接 -> 服务发现 -> 打开通知(CCCD) -> 严格单操作在途地写帧。
 *
 * 线程模型（本版重点修正）：
 *  - Binder 线程来的任何 GATT/扫描回调都不直接改状态，一律 main.post，
 *    在 Runnable 运行时再核对 (myGeneration == generation) 且 (g == gatt)，然后才 handle。
 *  - pendingOp / generation / queueIndex / scanGen 等全部状态只在主线程读写。
 *
 * 流程按厂家 APP 的标准 BLE 做法实现（非拷贝厂家代码）：
 *  - connectGatt(Activity, false, callback, TRANSPORT_LE)，不请求 MTU（初始 23 字节可容纳 12 字节帧）。
 *  - 服务 0000ffe0-...，特征 0000ffe1-...，通知 CCCD 00002902-...。
 *  - 任何时刻只有一个 GATT 操作在途；每阶段独立超时；超时后操作作废，迟到回调不算成功。
 *  - 普通帧优先 WRITE_TYPE_DEFAULT；经协商的115200曲谱窗口可在特征支持时用NO_RESPONSE。
 *    NO_RESPONSE 只有本地写出，绝不声称 FPGA 已确认。无自动重试：状态未知一律中止。
 *  - 所有回调都切到主线程；close() 之后不再投递任何回调。
 *  - 不自动发送任何帧（包括 AT），必须由上层用户动作触发。
 */
public final class BleTransport {

    private static final String TAG = "GowinBle";

    public static final UUID SERVICE_UUID = UUID.fromString("0000ffe0-0000-1000-8000-00805f9b34fb");
    public static final UUID NOTIFY_UUID = UUID.fromString("0000ffe1-0000-1000-8000-00805f9b34fb");
    public static final UUID CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");

    /** 扫描时长（毫秒）。 */
    public static final long SCAN_TIMEOUT_MS = 10000L;
    /** 连接（GATT 链路建立）超时。 */
    public static final long CONNECT_TIMEOUT_MS = 15000L;
    /** 服务发现超时。 */
    public static final long DISCOVER_TIMEOUT_MS = 15000L;
    /** CCCD（通知开关）写入超时。 */
    public static final long CCCD_TIMEOUT_MS = 5000L;
    /** 单帧特征写超时。 */
    public static final long WRITE_TIMEOUT_MS = 2500L;
    /** 两帧之间的最小间隔：模块 UART 9600，保守 40ms（要求 >= 30ms）。 */
    public static final long WRITE_SPACING_MS = 40L;
    /** 一帧 12 字节；初始 MTU 23 足够，不请求 MTU。 */
    public static final int FRAME_BYTES = 12;
    /** 完整音色帧数：4 帧包络 + 128 帧谐波 + 1 帧 0x42 完成标记。 */
    public static final int FULL_TONE_FRAMES = 133;

    /** 通知字节超过该长度视为异常，直接丢弃。 */
    private static final int MAX_NOTIFY_BYTES = 512;

    // ---------------------------------------------------------------- 回调接口

    /** 扫描结果条目，不可变。 */
    public static final class ScanEntry {
        public final String name;
        public final String address;
        public final int rssi;
        public final boolean hasFfe0;

        ScanEntry(String name, String address, int rssi, boolean hasFfe0) {
            this.name = name;
            this.address = address;
            this.rssi = rssi;
            this.hasFfe0 = hasFfe0;
        }

        public String display() {
            String n = (name == null || name.isEmpty()) ? "(无名称)" : name;
            return n + "   " + address + "   " + rssi + "dBm" + (hasFfe0 ? "   [广播含FFE0]" : "");
        }

        @Override public String toString() { return display(); }
    }

    /** 发送进度。written 只是「本地写出」计数，不代表 FPGA 已确认。 */
    public static final class SendProgress {
        public final int total;
        public final int written;
        public final int writeType;
        public final boolean finished;
        public final boolean cancelled;

        SendProgress(int total, int written, int writeType, boolean finished, boolean cancelled) {
            this.total = total;
            this.written = written;
            this.writeType = writeType;
            this.finished = finished;
            this.cancelled = cancelled;
        }

        /** true 表示每帧有 ATT 写响应；false 表示只有本地写出提交。 */
        public boolean ackedByPeer() {
            return writeType == BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT;
        }

        public String writeTypeLabel() {
            return ackedByPeer() ? "带响应写(WRITE_TYPE_DEFAULT)" : "无响应写(WRITE_TYPE_NO_RESPONSE)";
        }

        public String summary() {
            StringBuilder s = new StringBuilder();
            s.append(written).append('/').append(total);
            if (finished) s.append(cancelled ? " 已取消" : " 已发送完毕");
            return s.toString();
        }
    }

    /** 全部回调在主线程触发；close() 之后不再触发。 */
    public interface Listener {
        void onBluetoothState(boolean enabled, boolean bleSupported);
        void onScanStarted();
        void onScanEntry(ScanEntry entry);
        void onScanFinished(int count);
        void onScanFailed(String message);
        /** GATT 链路已连上，但服务/CCCD 尚未就绪。 */
        void onLinkUp(String address);
        /** 连接成功且通知已打开，可以收发。 */
        void onConnected(String address);
        void onDisconnected(String reason);
        /** 任一环节失败，status 为 GATT 状态码，无状态码时为 -1。 */
        void onError(String stage, int status, String message);
        void onNotifyEnabled(String characteristicDescription);
        void onNotification(byte[] data);
        void onSendProgress(SendProgress progress);
        void onSendError(String message);
    }

    // ---------------------------------------------------------------- 成员

    private final Context appContext;
    private final Listener listener;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final LinkedHashMap<String, ScanEntry> scanResults = new LinkedHashMap<>();
    private final ReplyDecoder decoder = new ReplyDecoder();

    private final BroadcastReceiver adapterReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            String action = intent == null ? null : intent.getAction();
            if (!BluetoothAdapter.ACTION_STATE_CHANGED.equals(action)) return;
            int state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR);
            if (state == BluetoothAdapter.STATE_TURNING_OFF || state == BluetoothAdapter.STATE_OFF) {
                // 蓝牙关闭：中止扫描与发送并断开，避免界面停在错误的“已连接”。
                abortEverything("蓝牙已关闭，扫描/发送已中止，连接已断开");
            } else {
                emitAdapterState();
            }
        }
    };
    private boolean receiverRegistered;

    private BluetoothAdapter adapter;
    private volatile boolean closed;

    // 扫描状态（只在主线程读写）
    private BluetoothLeScanner scanner;
    private ScanCallback scanCallback;
    private int scanGen;
    private boolean scanning;

    // 连接状态（只在主线程读写）
    private BluetoothGatt gatt;
    private int generation;
    private volatile boolean linkUp;
    private volatile boolean ready;
    private String peerAddress;
    private boolean disconnecting;

    // 单操作在途
    private static final int OP_NONE = 0;
    private static final int OP_CONNECT = 1;
    private static final int OP_DISCOVER = 2;
    private static final int OP_CCCD = 3;
    private static final int OP_WRITE = 4;
    private int pendingOp = OP_NONE;
    private Runnable opTimeout;
    private int timeoutSeq;

    private int resolvedWriteType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT;

    // 发送状态（只在主线程读写）
    private List<byte[]> queue;
    private int queueIndex;
    private int writtenCount;
    private boolean sending;

    public BleTransport(Context context, Listener listener) {
        this.appContext = context.getApplicationContext();
        this.listener = listener;
        this.adapter = adapterOf(this.appContext);
        IntentFilter filter = new IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED);
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                // Android 13+ 动态注册非系统广播必须显式声明导出标志；
                // Bluetooth broadcasts may originate from a privileged non-system UID.
                // ACTION_STATE_CHANGED is protected; ordinary apps cannot spoof it.
                this.appContext.registerReceiver(adapterReceiver, filter, Context.RECEIVER_EXPORTED);
            } else {
                this.appContext.registerReceiver(adapterReceiver, filter);
            }
            this.receiverRegistered = true;
        } catch (RuntimeException e) {
            Log.w(TAG, "注册蓝牙状态接收器失败: " + e);
            this.receiverRegistered = false;
        }
        Log.i(TAG, "BleTransport 初始化，BLE 支持=" + (this.adapter != null));
    }

    // ---------------------------------------------------------------- 静态工具

    /** 从 ACTION_REQUEST_ENABLE 的结果判断用户是否同意打开蓝牙（只认 RESULT_OK）。 */
    public static boolean isEnableResultOk(int resultCode) {
        return resultCode == android.app.Activity.RESULT_OK;
    }

    /**
     * 权限检查。必须在任何蓝牙 API（isEnabled / getBluetoothLeScanner / getRemoteDevice 等）之前调用。
     * 返回 null 表示当前系统版本所需权限都已具备。
     */
    public static String permissionProblem(Context context) {
        if (Build.VERSION.SDK_INT >= 31) {
            if (!granted(context, "android.permission.BLUETOOTH_SCAN")) {
                return "缺少蓝牙扫描权限：Android 12+ 需要「附近的设备」权限(BLUETOOTH_SCAN)，"
                        + "请在系统设置里授予后重试。";
            }
            if (!granted(context, "android.permission.BLUETOOTH_CONNECT")) {
                return "缺少蓝牙连接权限：Android 12+ 需要「附近的设备」权限(BLUETOOTH_CONNECT)，"
                        + "请在系统设置里授予后重试。";
            }
            return null;
        }
        if (!granted(context, "android.permission.ACCESS_FINE_LOCATION")) {
            return "缺少定位权限：Android 11 及以下扫描 BLE 必须授予「位置信息」权限，"
                    + "并在系统设置里打开位置开关，否则扫描不到设备。";
        }
        return null;
    }

    /** 23..30 的额外提醒：定位开关必须打开（本 APP 不会替用户改开关）。 */
    public static String locationSwitchHint(Context context) {
        if (Build.VERSION.SDK_INT < 31
                && granted(context, "android.permission.ACCESS_FINE_LOCATION")) {
            return "提醒（Android 11 及以下）：如果一直扫不到设备，请在系统设置里打开「位置信息」开关。"
                    + "本 APP 不会替用户修改该开关。";
        }
        return null;
    }

    private static boolean granted(Context context, String permission) {
        try {
            return context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED;
        } catch (RuntimeException e) {
            return false;
        }
    }

    public static BluetoothAdapter adapterOf(Context context) {
        try {
            BluetoothManager manager = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
            return manager == null ? null : manager.getAdapter();
        } catch (RuntimeException e) {
            return null;
        }
    }

    public static String gattStatusHint(int status) {
        switch (status) {
            case 1: return "（INVALID_HANDLE，句柄无效）";
            case 2: return "（GATT_READ_NOT_PERMITTED）";
            case 3: return "（GATT_WRITE_NOT_PERMITTED）";
            case 5: return "（GATT_INSUFFICIENT_AUTHENTICATION）";
            case 6: return "（GATT_REQUEST_NOT_SUPPORTED）";
            case 7: return "（GATT_INVALID_OFFSET）";
            case 8: return "（INSUFFICIENT_AUTHORIZATION，未授权）";
            case 13: return "（GATT_INVALID_ATTRIBUTE_LENGTH，值长度非法）";
            case 133: return "（133 常见原因：模块已被旧 APP/其它手机连着、连接参数不兼容、远端主动断开）";
            case 257: return "（GATT_FAILURE 通用失败）";
            default: return "";
        }
    }

    /** 扫描失败 errorCode 的解释。 */
    public static String scanErrorHint(int errorCode) {
        switch (errorCode) {
            case 1: return "（SCAN_FAILED_ALREADY_STARTED，已在扫描）";
            case 2: return "（SCAN_FAILED_APPLICATION_REGISTRATION_FAILED，应用注册失败）";
            case 3: return "（SCAN_FAILED_INTERNAL_ERROR，内部错误）";
            case 4: return "（SCAN_FAILED_FEATURE_UNSUPPORTED，特性不支持）";
            case 5: return "（SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES，硬件资源不足）";
            case 6: return "（SCAN_FAILED_SCANNING_TOO_FREQUENTLY，扫描过于频繁）";
            default: return "";
        }
    }

    /** 协议帧格式校验：必须正好 12 字节，A5 5A 开头，末尾 XOR 正确。 */
    public static boolean isValidFrame(byte[] frame) {
        if (frame == null || frame.length != FRAME_BYTES) return false;
        if ((frame[0] & 0xff) != 0xa5 || (frame[1] & 0xff) != 0x5a) return false;
        int xor = frame[2] & 0xff;
        for (int i = 3; i < 11; i++) xor ^= frame[i] & 0xff;
        return (frame[11] & 0xff) == xor;
    }

    /** 供界面展示用，避免 UUID 常量被误改。 */
    public static Map<String, UUID> uuids() {
        Map<String, UUID> map = new LinkedHashMap<>();
        map.put("service", SERVICE_UUID);
        map.put("notify", NOTIFY_UUID);
        map.put("cccd", CCCD_UUID);
        return map;
    }

    // ---------------------------------------------------------------- 状态查询

    /** 读蓝牙开关：未授权或异常时返回 false，绝不抛 SecurityException。 */
    public boolean isBluetoothEnabled() {
        try {
            BluetoothAdapter a = adapter;
            if (a == null) return false;
            if (permissionProblem(appContext) != null) return false;
            return a.isEnabled();
        } catch (RuntimeException e) {
            Log.w(TAG, "读取蓝牙开关失败: " + e);
            return false;
        }
    }

    public boolean isScanning() { return scanning; }

    /** 蓝牙链路是否已连上（未必可收发）。 */
    public boolean isLinkUp() { return linkUp; }

    /** 连接成功且通知已打开，可以收发。 */
    public boolean isReady() { return ready; }
    public String peerAddress() { return peerAddress; }

    public boolean isSending() { return sending; }

    /** Best effort link-parameter hint; true means requested, not negotiated. No data frame is sent. */
    public boolean requestTransferPriority(boolean high) {
        BluetoothGatt current = gatt;
        if (closed || current == null || !linkUp || !ready) return false;
        if (Build.VERSION.SDK_INT >= 31 && !granted(appContext, "android.permission.BLUETOOTH_CONNECT")) return false;
        try {
            return current.requestConnectionPriority(high ? BluetoothGatt.CONNECTION_PRIORITY_HIGH : BluetoothGatt.CONNECTION_PRIORITY_BALANCED);
        } catch (RuntimeException ex) {
            Log.w(TAG, "连接优先级请求失败，保留原连接参数", ex);
            return false;
        }
    }

    public boolean isClosed() { return closed; }

    public String describeWriteType() {
        return resolvedWriteType == BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                ? "带响应写(WRITE_TYPE_DEFAULT)" : "无响应写(WRITE_TYPE_NO_RESPONSE)";
    }

    // ---------------------------------------------------------------- 生命周期

    /** 释放 GATT / 扫描 / Handler 任务 / 广播接收器，并停止一切后续回调。 */
    public void close() {
        closed = true;
        stopScanInternal();
        abortSend("界面关闭");
        main.removeCallbacksAndMessages(null);
        cancelOpTimeout();
        pendingOp = OP_NONE;
        disconnectInternal("界面关闭，已释放蓝牙资源", true);
        if (receiverRegistered) {
            try {
                appContext.unregisterReceiver(adapterReceiver);
            } catch (RuntimeException e) {
                Log.w(TAG, "反注册接收器失败: " + e);
            }
            receiverRegistered = false;
        }
        adapter = null;
        Log.i(TAG, "BleTransport 已释放");
    }

    /** 蓝牙关闭时统一中止：扫描 + 发送 + 连接。 */
    private void abortEverything(String reason) {
        stopScanInternal();
        abortSend(reason);
        if (linkUp || gatt != null || pendingOp != OP_NONE) {
            disconnectInternal(reason, true);
        }
        emitAdapterState();
    }

    /** 通知界面当前蓝牙开关状态（未授权时 enabled=false，不抛异常）。 */
    public void emitAdapterState() {
        try {
            BluetoothAdapter a = adapter;
            final boolean bleSupported = a != null;
            final boolean enabled = isBluetoothEnabled();
            deliver(new Runnable() {
                @Override public void run() { listener.onBluetoothState(enabled, bleSupported); }
            });
        } catch (RuntimeException e) {
            Log.w(TAG, "上报蓝牙状态失败: " + e);
        }
    }

    // ---------------------------------------------------------------- 回调投递

    /** 统一回调投递：主线程 + 存活判断，close() 之后一律丢弃。 */
    private void deliver(Runnable r) {
        if (closed) return;
        if (Looper.myLooper() == Looper.getMainLooper()) {
            if (!closed) r.run();
        } else {
            main.post(new Runnable() {
                @Override public void run() { if (!closed) r.run(); }
            });
        }
    }

    // ---------------------------------------------------------------- 扫描

    /** 扫描 10 秒。不使用服务 UUID 过滤：部分 JDY 模块广播里没有 FFE0。 */
    public boolean startScan() {
        if (closed) return false;
        if (scanning) return true;
        BluetoothAdapter a = adapter;
        if (a == null) {
            fail("扫描", -1, "本机不支持蓝牙低功耗(BLE)。");
            return false;
        }
        String problem = permissionProblem(appContext);
        if (problem != null) {
            fail("扫描", -1, problem);
            return false;
        }
        boolean enabled;
        try {
            enabled = a.isEnabled();
        } catch (SecurityException e) {
            fail("扫描", -1, "缺少蓝牙权限，无法读取蓝牙开关状态：" + e);
            return false;
        } catch (RuntimeException e) {
            fail("扫描", -1, "读取蓝牙开关状态失败：" + e);
            return false;
        }
        if (!enabled) {
            fail("扫描", -1, "蓝牙未打开，请先打开蓝牙。");
            return false;
        }
        BluetoothLeScanner s;
        try {
            s = a.getBluetoothLeScanner();
        } catch (SecurityException e) {
            fail("扫描", -1, "缺少蓝牙扫描权限：" + e);
            return false;
        } catch (RuntimeException e) {
            fail("扫描", -1, "获取 BLE 扫描器失败：" + e);
            return false;
        }
        if (s == null) {
            fail("扫描", -1, "无法获取 BLE 扫描器。");
            return false;
        }
        final int myScanGen = ++scanGen;
        scanResults.clear();
        scanner = s;
        scanning = true;
        ScanCallback callback = new ScanCallback() {
            @Override public void onScanResult(int callbackType, ScanResult result) {
                handleScanResult(myScanGen, result);
            }
            @Override public void onBatchScanResults(List<ScanResult> results) {
                if (results == null) return;
                for (ScanResult r : results) handleScanResult(myScanGen, r);
            }
            @Override public void onScanFailed(int errorCode) {
                handleScanFailed(myScanGen, errorCode);
            }
        };
        scanCallback = callback;
        ScanSettings settings = new ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build();
        List<ScanFilter> filters = Collections.emptyList();
        try {
            s.startScan(filters, settings, callback);
        } catch (SecurityException e) {
            scanning = false;
            scanCallback = null;
            scanner = null;
            fail("扫描", -1, "缺少蓝牙扫描权限或被系统拒绝：" + e);
            return false;
        } catch (RuntimeException e) {
            scanning = false;
            scanCallback = null;
            scanner = null;
            fail("扫描", -1, "启动扫描异常：" + e);
            return false;
        }
        deliver(new Runnable() {
            @Override public void run() { listener.onScanStarted(); }
        });
        // 10 秒计时绑定本代扫描：代次不符就不允许停掉新扫描。
        main.postDelayed(new Runnable() {
            @Override public void run() {
                if (closed || myScanGen != scanGen || !scanning) return;
                stopScanInternal();
            }
        }, SCAN_TIMEOUT_MS);
        return true;
    }

    public void stopScan() {
        stopScanInternal();
    }

    /** 停止当前扫描并递增代次，旧回调与旧计时器随之全部失效。 */
    private void stopScanInternal() {
        boolean wasScanning = scanning;
        scanGen++;                 // 旧回调、旧计时器全部作废
        scanning = false;
        BluetoothLeScanner s = scanner;
        ScanCallback callback = scanCallback;
        scanner = null;
        scanCallback = null;
        if (s != null && callback != null) {
            try {
                s.stopScan(callback);
            } catch (SecurityException e) {
                Log.w(TAG, "停止扫描缺少权限: " + e);
            } catch (RuntimeException e) {
                Log.w(TAG, "停止扫描异常: " + e);
            }
        }
        if (wasScanning) postScanFinished();
    }

    private void postScanFinished() {
        final int count = scanResults.size();
        deliver(new Runnable() {
            @Override public void run() { listener.onScanFinished(count); }
        });
    }

    private void handleScanResult(final int myScanGen, final ScanResult result) {
        if (closed || result == null) return;
        deliver(new Runnable() {
            @Override public void run() {
                if (closed) return;
                if (myScanGen != scanGen || !scanning) return;   // 旧扫描的迟到结果
                processScanResult(result);
            }
        });
    }

    private void processScanResult(ScanResult result) {
        BluetoothDevice device = result.getDevice();
        if (device == null) return;
        String address;
        try {
            address = device.getAddress();
        } catch (SecurityException e) {
            return;
        }
        if (address == null) return;
        String name = null;
        try {
            name = result.getScanRecord() != null ? result.getScanRecord().getDeviceName() : null;
            if (name == null || name.isEmpty()) name = device.getName();
        } catch (SecurityException e) {
            Log.w(TAG, "读取广播名称缺少权限: " + e);
        }
        boolean hasFfe0 = false;
        try {
            List<ParcelUuid> uuids = result.getScanRecord() != null
                    ? result.getScanRecord().getServiceUuids() : null;
            if (uuids != null) {
                for (ParcelUuid u : uuids) {
                    if (u != null && SERVICE_UUID.equals(u.getUuid())) { hasFfe0 = true; break; }
                }
            }
        } catch (RuntimeException e) {
            Log.w(TAG, "解析广播服务失败: " + e);
        }
        final ScanEntry entry = new ScanEntry(name == null ? "" : name, address, result.getRssi(), hasFfe0);
        scanResults.put(address, entry);
        listener.onScanEntry(entry);   // 已在主线程
    }

    private void handleScanFailed(final int myScanGen, final int errorCode) {
        if (closed) return;
        deliver(new Runnable() {
            @Override public void run() {
                if (closed) return;
                if (myScanGen != scanGen) return;   // 旧扫描的失败不影响新扫描
                boolean wasScanning = scanning;
                stopScanInternal();
                if (!wasScanning) return;
                final String msg = "系统扫描失败 errorCode=" + errorCode + scanErrorHint(errorCode);
                listener.onScanFailed(msg);
                fail("扫描失败", errorCode, msg);
            }
        });
    }

    // ---------------------------------------------------------------- 连接

    /** 连接指定 MAC。回调 onLinkUp / onConnected / onDisconnected / onError。 */
    public boolean connect(String address) {
        if (closed) return false;
        if (address == null || address.trim().isEmpty()) {
            fail("连接", -1, "MAC 地址为空。");
            return false;
        }
        final String normalized = address.trim().toUpperCase(Locale.US);
        BluetoothAdapter a = adapter;
        if (a == null) {
            fail("连接", -1, "本机不支持蓝牙低功耗(BLE)。");
            return false;
        }
        String problem = permissionProblem(appContext);
        if (problem != null) {
            fail("连接", -1, problem);
            return false;
        }
        boolean enabled;
        try {
            enabled = a.isEnabled();
        } catch (SecurityException e) {
            fail("连接", -1, "缺少蓝牙权限，无法读取蓝牙开关状态：" + e);
            return false;
        } catch (RuntimeException e) {
            fail("连接", -1, "读取蓝牙开关状态失败：" + e);
            return false;
        }
        if (!enabled) {
            fail("连接", -1, "蓝牙未打开，请先打开蓝牙。");
            return false;
        }
        // 连接期间若在发送，必须明确中止旧队列：绝不允许旧队列跨连接发送。
        if (abortSend("开始新连接前中止上一批发送")) {
            deliver(new Runnable() {
                @Override public void run() {
                    listener.onSendError("已中止上一批发送：连接发生切换，旧队列不会再被发送。");
                }
            });
        }
        stopScan();
        // 旧连接的回调作废（先断开旧的，再建立新的）。
        disconnectInternal("建立新连接，已释放旧连接", false);
        final BluetoothDevice device;
        try {
            device = a.getRemoteDevice(normalized);
        } catch (IllegalArgumentException e) {
            fail("连接", -1, "MAC 地址格式非法：" + normalized);
            return false;
        } catch (SecurityException e) {
            fail("连接", -1, "缺少 BLUETOOTH_CONNECT 权限：" + e);
            return false;
        } catch (RuntimeException e) {
            fail("连接", -1, "获取设备失败：" + e);
            return false;
        }
        final int myGeneration = ++generation;
        final BluetoothGattCallback callback = new BluetoothGattCallback() {
            @Override public void onConnectionStateChange(BluetoothGatt g, int status, int newState) {
                postConnectionState(myGeneration, g, status, newState);
            }
            @Override public void onServicesDiscovered(BluetoothGatt g, int status) {
                postServicesDiscovered(myGeneration, g, status);
            }
            @Override public void onDescriptorWrite(BluetoothGatt g, BluetoothGattDescriptor descriptor, int status) {
                postDescriptorWrite(myGeneration, g, descriptor, status);
            }
            @Override public void onCharacteristicWrite(BluetoothGatt g, BluetoothGattCharacteristic c, int status) {
                postCharacteristicWrite(myGeneration, g, c, status);
            }
            @Override public void onCharacteristicChanged(BluetoothGatt g, BluetoothGattCharacteristic c) {
                if(c == null || !NOTIFY_UUID.equals(c.getUuid())) return;
                byte[] copy = copyOf(c == null ? null : c.getValue());
                postCharacteristicChanged(myGeneration, g, copy);
            }
            @TargetApi(33)
            @Override public void onCharacteristicChanged(BluetoothGatt g, BluetoothGattCharacteristic c, byte[] value) {
                if(c == null || !NOTIFY_UUID.equals(c.getUuid())) return;
                // API 33+ 带值重载：value 可能被复用，必须在回调线程内先复制。
                postCharacteristicChanged(myGeneration, g, copyOf(value));
            }
        };
        BluetoothGatt created = null;
        try {
            created = device.connectGatt(appContext, false, callback, BluetoothDevice.TRANSPORT_LE);
        } catch (SecurityException e) {
            fail("连接", -1, "缺少 BLUETOOTH_CONNECT 权限：" + e);
            return false;
        } catch (RuntimeException e) {
            created = null;
            Log.w(TAG, "connectGatt 异常: " + e);
        }
        if (created == null) {
            fail("连接", -1, "connectGatt 返回空，无法建立连接（请确认模块在广播、且旧 APP 已断开）。");
            return false;
        }
        gatt = created;
        linkUp = false;
        ready = false;
        peerAddress = normalized;
        armConnectTimeout();
        Log.i(TAG, "已发起连接 " + normalized + " gen=" + myGeneration);
        return true;
    }

    /** 主动断开，并作废所有在途操作。 */
    public void disconnect(String reason) {
        String text = reason == null ? "用户断开连接" : reason;
        abortSend(text);
        disconnectInternal(text, true);
    }

    private void disconnectInternal(String reason, boolean notify) {
        if (disconnecting) {
            Log.i(TAG, "忽略重复的断开调用：" + reason);
            return;
        }
        disconnecting = true;
        try {
            BluetoothGatt g = gatt;
            gatt = null;
            generation++;                       // 旧 gatt 的回调从此一律作废
            cancelOpTimeout();
            pendingOp = OP_NONE;
            linkUp = false;
            ready = false;
            decoder.reset();
            String who = peerAddress;
            peerAddress = null;
            if (g != null) {
                try {
                    g.disconnect();
                } catch (RuntimeException e) {
                    Log.w(TAG, "disconnect 异常: " + e);
                }
                try {
                    g.close();
                } catch (RuntimeException e) {
                    Log.w(TAG, "close 异常: " + e);
                }
            }
            if (notify) {
                final String r = (who == null ? "" : who + "：") + reason;
                deliver(new Runnable() {
                    @Override public void run() { listener.onDisconnected(r); }
                });
            }
        } finally {
            disconnecting = false;
        }
    }

    private void closeGattQuietly() {
        BluetoothGatt g = gatt;
        gatt = null;
        if (g != null) {
            try {
                g.close();
            } catch (RuntimeException e) {
                Log.w(TAG, "close 异常: " + e);
            }
        }
    }

    // ---------------------------------------------------------------- GATT 回调（先 main.post，再核对代次与 gatt）

    private void postConnectionState(final int myGeneration, final BluetoothGatt g,
                                     final int status, final int newState) {
        if (closed) return;
        main.post(new Runnable() {
            @Override public void run() {
                if (closed || myGeneration != generation || g != gatt) return;
                handleConnectionState(status, newState);
            }
        });
    }

    private void postServicesDiscovered(final int myGeneration, final BluetoothGatt g, final int status) {
        if (closed) return;
        main.post(new Runnable() {
            @Override public void run() {
                if (closed || myGeneration != generation || g != gatt) return;
                handleServicesDiscovered(status);
            }
        });
    }

    private void postDescriptorWrite(final int myGeneration, final BluetoothGatt g,
                                     final BluetoothGattDescriptor descriptor, final int status) {
        if (closed) return;
        final UUID uuid = descriptor == null ? null : descriptor.getUuid();
        main.post(new Runnable() {
            @Override public void run() {
                if (closed || myGeneration != generation || g != gatt) return;
                handleDescriptorWrite(uuid, status);
            }
        });
    }

    private void postCharacteristicWrite(final int myGeneration, final BluetoothGatt g,
                                         final BluetoothGattCharacteristic c, final int status) {
        if (closed) return;
        final UUID uuid = c == null ? null : c.getUuid();
        main.post(new Runnable() {
            @Override public void run() {
                if (closed || myGeneration != generation || g != gatt) return;
                handleCharacteristicWrite(uuid, status);
            }
        });
    }

    private void postCharacteristicChanged(final int myGeneration, final BluetoothGatt g, final byte[] value) {
        if (closed || value == null || value.length == 0) return;
        main.post(new Runnable() {
            @Override public void run() {
                if (closed || myGeneration != generation || g != gatt) return;
                listener.onNotification(value);   // value 已复制，不随 getValue 变化
            }
        });
    }

    private static byte[] copyOf(byte[] source) {
        if (source == null || source.length == 0) return null;
        if (source.length > MAX_NOTIFY_BYTES) {
            Log.w(TAG, "忽略异常长度的通知 " + source.length + " 字节");
            return null;
        }
        byte[] copy = new byte[source.length];
        System.arraycopy(source, 0, copy, 0, source.length);
        return copy;
    }

    // ---------------------------------------------------------------- 状态机处理（主线程）

    private void handleConnectionState(int status, int newState) {
        if (status != BluetoothGatt.GATT_SUCCESS) {
            pendingOp = OP_NONE;
            cancelOpTimeout();
            ready = false;
            linkUp = false;
            boolean wasSending = sending;
            if (wasSending) {
                abortSend("连接中断 status=" + status + gattStatusHint(status));
                deliver(new Runnable() {
                    @Override public void run() {
                        listener.onSendError("连接中断，发送已中止：status=" + status);
                    }
                });
            }
            closeGattQuietly();
            generation++;
            final String message = "GATT 连接失败 status=" + status + gattStatusHint(status);
            fail("连接失败", status, message);
            deliver(new Runnable() {
                @Override public void run() { listener.onDisconnected("连接失败，已断开"); }
            });
            return;
        }
        if (newState == BluetoothProfile.STATE_CONNECTED) {
            linkUp = true;
            cancelOpTimeout();
            BluetoothGatt g = gatt;
            if (g == null) {
                abortConnectFailure("服务发现", -1, "连接回调时 gatt 已失效。");
                return;
            }
            boolean ok;
            try {
                ok = g.discoverServices();
            } catch (SecurityException e) {
                abortConnectFailure("服务发现", -1, "缺少 BLUETOOTH_CONNECT 权限，discoverServices 失败：" + e);
                return;
            } catch (RuntimeException e) {
                abortConnectFailure("服务发现", -1, "discoverServices 异常：" + e);
                return;
            }
            if (!ok) {
                abortConnectFailure("服务发现", -1, "discoverServices() 同步返回 false，服务发现未能启动。");
                return;
            }
            final String addr = peerAddress;
            deliver(new Runnable() {
                @Override public void run() { listener.onLinkUp(addr); }
            });
            armDiscoverTimeout();
            return;
        }
        if (newState == BluetoothProfile.STATE_DISCONNECTED) {
            pendingOp = OP_NONE;
            cancelOpTimeout();
            ready = false;
            linkUp = false;
            boolean wasSending = sending;
            if (wasSending) {
                abortSend("设备已断开");
            }
            closeGattQuietly();
            generation++;
            final String message = wasSending
                    ? "设备已断开（status=" + status + gattStatusHint(status) + "），发送已中止。"
                    : "设备已断开（status=" + status + gattStatusHint(status) + "）。";
            fail("连接断开", status, message);
            deliver(new Runnable() {
                @Override public void run() { listener.onDisconnected(message); }
            });
        }
    }

    /** 连接阶段失败：清理 GATT 并通知断开，避免界面停在“已连上”但永远没有 READY。 */
    private void abortConnectFailure(String stage, int status, String message) {
        pendingOp = OP_NONE;
        cancelOpTimeout();
        ready = false;
        linkUp = false;
        closeGattQuietly();
        generation++;
        fail(stage, status, message);
        deliver(new Runnable() {
            @Override public void run() { listener.onDisconnected("连接未完成，已断开"); }
        });
    }

    private void handleServicesDiscovered(int status) {
        if (pendingOp != OP_DISCOVER) {
            Log.i(TAG, "忽略非在途的服务发现回调");
            return;
        }
        cancelOpTimeout();
        pendingOp = OP_NONE;
        if (status != BluetoothGatt.GATT_SUCCESS) {
            abortConnectFailure("服务发现", status, "服务发现失败 status=" + status + gattStatusHint(status));
            return;
        }
        BluetoothGatt g = gatt;
        if (g == null) {
            abortConnectFailure("服务发现", -1, "服务发现完成时连接已失效。");
            return;
        }
        BluetoothGattService service = g.getService(SERVICE_UUID);
        if (service == null) {
            abortConnectFailure("服务发现", -1, "连接成功但未找到服务 " + SERVICE_UUID
                    + "。请确认模块是 FFE0/FFE1 的 JDY 型；若旧 APP 还连着手机，请先断开旧 APP 再试。");
            return;
        }
        BluetoothGattCharacteristic ch = service.getCharacteristic(NOTIFY_UUID);
        if (ch == null) {
            abortConnectFailure("服务发现", -1, "服务内未找到特征 " + NOTIFY_UUID + "。");
            return;
        }
        int props = ch.getProperties();
        boolean canNotify = (props & BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0;
        boolean canIndicate = (props & BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0;
        boolean canWrite = (props & BluetoothGattCharacteristic.PROPERTY_WRITE) != 0;
        boolean canWriteAny = (props & (BluetoothGattCharacteristic.PROPERTY_WRITE
                | BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE)) != 0;
        resolvedWriteType = canWrite ? BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                : BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE;
        Log.i(TAG, "FFE1 属性=0x" + Integer.toHexString(props) + " canWrite=" + canWrite
                + " canWriteAny=" + canWriteAny + " notify=" + canNotify + " indicate=" + canIndicate
                + " -> " + describeWriteType());
        if (!canNotify && !canIndicate) {
            abortConnectFailure("通知", -1, "特征 FFE1 不支持 notify/indicate（属性=0x"
                    + Integer.toHexString(props) + "），无法接收回复。");
            return;
        }
        if (!canWriteAny) {
            abortConnectFailure("写", -1, "特征 FFE1 既不可写也不可无响应写（属性=0x"
                    + Integer.toHexString(props) + "）。");
            return;
        }
        BluetoothGattDescriptor cccd = ch.getDescriptor(CCCD_UUID);
        if (cccd == null) {
            abortConnectFailure("通知", -1, "特征缺少 CCCD 描述符 " + CCCD_UUID + "，无法打开通知。");
            return;
        }
        try {
            cccd.setValue(canNotify ? BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    : BluetoothGattDescriptor.ENABLE_INDICATION_VALUE);
        } catch (RuntimeException e) {
            abortConnectFailure("通知", -1, "设置 CCCD 值失败：" + e);
            return;
        }
        // 标准流程：先本地通知注册，再写 0x2902；只有写回调成功才算 READY。
        try {
            if (!g.setCharacteristicNotification(ch, true)) {
                abortConnectFailure("通知", -1, "setCharacteristicNotification 同步返回 false，本地通知注册失败。");
                return;
            }
        } catch (SecurityException e) {
            abortConnectFailure("通知", -1, "本地通知注册缺少权限：" + e);
            return;
        } catch (RuntimeException e) {
            abortConnectFailure("通知", -1, "本地通知注册异常：" + e);
            return;
        }
        boolean scheduled;
        try {
            scheduled = g.writeDescriptor(cccd);
        } catch (SecurityException e) {
            abortConnectFailure("通知", -1, "写 CCCD 缺少权限：" + e);
            return;
        } catch (RuntimeException e) {
            scheduled = false;
            Log.w(TAG, "writeDescriptor 异常: " + e);
        }
        if (!scheduled) {
            abortConnectFailure("通知", -1, "writeDescriptor(CCCD) 同步返回失败，通知未打开。");
            return;
        }
        armCccdTimeout();
    }

    private void handleDescriptorWrite(UUID descriptorUuid, int status) {
        if (pendingOp != OP_CCCD) {
            Log.i(TAG, "忽略非在途的描述符写回调");
            return;
        }
        cancelOpTimeout();
        pendingOp = OP_NONE;
        if (status != BluetoothGatt.GATT_SUCCESS) {
            abortConnectFailure("通知", status, "写 CCCD 失败 status=" + status + gattStatusHint(status)
                    + "，通知未打开，不会进入可收发状态。");
            return;
        }
        if (descriptorUuid == null || !CCCD_UUID.equals(descriptorUuid)) {
            abortConnectFailure("通知", -1, "收到的描述符写回调不是 CCCD，通知状态未知。");
            return;
        }
        ready = true;
        final String addr = peerAddress;
        final String desc = "FFE1（" + resolvedWriteTypeLabel() + "，通知已开启）";
        deliver(new Runnable() {
            @Override public void run() {
                listener.onNotifyEnabled(desc);
                listener.onConnected(addr);
            }
        });
    }

    private void handleCharacteristicWrite(UUID characteristicUuid, int status) {
        if (pendingOp != OP_WRITE) {
            Log.i(TAG, "忽略非在途的特征写回调");
            return;
        }
        if (characteristicUuid != null && !NOTIFY_UUID.equals(characteristicUuid)) {
            Log.i(TAG, "忽略非目标特征的写回调 " + characteristicUuid);
            return;
        }
        cancelOpTimeout();
        pendingOp = OP_NONE;
        if (status != BluetoothGatt.GATT_SUCCESS) {
            // 无自动重试：写状态未知时中止并断开，避免参数部分生效后被重复发送。
            abortSendAndDisconnect("第 " + queueIndex + " 帧写入失败",
                    "第 " + queueIndex + " 帧写入失败 status=" + status + gattStatusHint(status)
                            + "，不重试，发送已中止，并已断开连接。");
            return;
        }
        writtenCount = queueIndex;
        postProgress(queueTotal(), writtenCount, false, false);
        scheduleNextFrame();
    }

    /** 上层在主线程调用：把通知字节流转成 ReplyDecoder 事件。 */
    public List<ReplyDecoder.Reply> decode(byte[] data) {
        return decoder.feed(data);
    }

    // ---------------------------------------------------------------- 发送

    /** 发送单个帧（例如仅延音参数）。 */
    public boolean sendFrame(byte[] frame) {
        List<byte[]> list = new ArrayList<>(1);
        list.add(frame);
        return sendFrames(list);
    }

    /**
     * 顺序发送一批帧（完整音色 133 帧）。同一时刻只有一个 GATT 写在途，
     * 帧间隔 WRITE_SPACING_MS（>=30ms），保护模块 9600 UART。
     * 帧必须正好 12 字节且 A5/5A/XOR 正确，会被克隆后发送。
     */
    public boolean sendFrames(List<byte[]> frames) {
        return enqueue(frames,false);
    }

    /** 115200 score EVENT window only: <=8 intact frames, split into <=20-byte ATT values. */
    public boolean sendScoreWindow(List<byte[]> chunks) {
        return sendScoreWindow(chunks,false);
    }
    /** Fast writes are limited to negotiated, bounded EVENT windows by the caller. */
    public boolean sendScoreWindow(List<byte[]> chunks,boolean fastWrites) {
        return enqueue(chunks,true,false,fastWrites);
    }
    public boolean sendReliableScore(byte[] message){
        try{return enqueue(ReliableScoreProtocol.chunks(message),true,true);}
        catch(IllegalArgumentException ex){fail("发送",-1,ex.getMessage());return false;}
    }

    private long queueSpacingMs=WRITE_SPACING_MS;
    private long queueSubmitElapsed;
    private boolean queueFastScore;
    private int queueWriteType=BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT;
    private boolean enqueue(List<byte[]> frames,boolean scoreWindow) {
        return enqueue(frames,scoreWindow,false);
    }
    private boolean enqueue(List<byte[]> frames,boolean scoreWindow,boolean reliableScore) {
        return enqueue(frames,scoreWindow,reliableScore,false);
    }
    private boolean enqueue(List<byte[]> frames,boolean scoreWindow,boolean reliableScore,boolean fastWrites) {
        if (closed) {
            fail("发送", -1, "传输层已释放，无法发送。");
            return false;
        }
        if (sending) {
            fail("发送", -1, "已有发送任务在进行中，请等待完成或先取消。");
            return false;
        }
        if (frames == null || frames.isEmpty()) {
            fail("发送", -1, "没有要发送的帧。");
            return false;
        }
        if (!ready || gatt == null || !linkUp) {
            fail("发送", -1, "尚未就绪：必须先连接成功并打开通知(CCCD)后才能写帧。");
            return false;
        }
        List<byte[]> copy = new ArrayList<>(frames.size());
        java.io.ByteArrayOutputStream stream=new java.io.ByteArrayOutputStream();
        if(scoreWindow&&frames.size()>5){fail("发送",-1,"曲谱窗口分段数量超限。");return false;}
        for (int i = 0; i < frames.size(); i++) {
            byte[] f = frames.get(i);
            if (f == null || (scoreWindow ? f.length<1||f.length>20||(i<frames.size()-1&&f.length!=20) : f.length != FRAME_BYTES)) {
                fail("发送", -1, "第 " + (i + 1) + (scoreWindow ? " 段长度非法：上限20字节，非末段须20字节。" : " 帧长度非法：必须正好 " + FRAME_BYTES + " 字节。"));
                return false;
            }
            if (!scoreWindow && !isValidFrame(f)) {
                fail("发送", -1, "第 " + (i + 1) + " 帧校验失败：帧头必须是 A5 5A，末尾 XOR 必须正确。");
                return false;
            }
            byte[] cloned = f.clone();
            copy.add(cloned);
            if(scoreWindow)stream.write(cloned,0,cloned.length);
        }
        if(scoreWindow){
            byte[] bytes=stream.toByteArray();
            if(reliableScore){if(!ReliableScoreProtocol.validMessage(bytes)){fail("发送",-1,"可靠曲谱消息校验失败。");return false;}}
            else {
            if(bytes.length%FRAME_BYTES!=0||bytes.length<FRAME_BYTES||bytes.length>8*FRAME_BYTES){fail("发送",-1,"曲谱窗口必须包含1..8个完整事件帧。");return false;}
            for(int at=0;at<bytes.length;at+=FRAME_BYTES){
                byte[] frame=java.util.Arrays.copyOfRange(bytes,at,at+FRAME_BYTES);
                if(!isValidFrame(frame)||(frame[2]&255)!=0x51){fail("发送",-1,"窗口只允许校验有效的曲谱事件帧。");return false;}
            }
            }
        }
        queueSpacingMs=scoreWindow?5L:WRITE_SPACING_MS;
        queueFastScore=scoreWindow&&!reliableScore&&fastWrites;
        queueWriteType=resolvedWriteType;
        if(queueFastScore){
            BluetoothGattService service=gatt.getService(SERVICE_UUID);
            BluetoothGattCharacteristic ch=service==null?null:service.getCharacteristic(NOTIFY_UUID);
            if(ch!=null&&(ch.getProperties()&BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE)!=0)
                queueWriteType=BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE;
        }
        queue = copy;
        queueIndex = 0;
        writtenCount = 0;
        sending = true;
        postProgress(copy.size(), 0, false, false);
        Log.i(TAG, "开始发送 " + copy.size() + " 段，writeType=" + queueWriteType);
        writeOne();
        return true;
    }

    /** 取消发送：作废在途写回调并断开连接，避免污染下一批发送。 */
    public void cancelSend() {
        if (!sending) return;
        final int total = queueTotal();
        final int written = writtenCount;
        postProgress(total, written, true, true);
        // 如实上报：取消发送会主动断开连接（不是静默断开）。
        abortSendAndDisconnect("用户取消发送，已断开连接",
                "发送已取消：为保证下一批发送不受在途回调影响，连接已断开，请重新连接。");
    }

    /** 只终止发送状态，不碰连接；返回是否原本在发送。 */
    private boolean abortSend(String reason) {
        if (!sending) return false;
        Log.i(TAG, "中止发送：" + reason);
        sending = false;
        queue = null;
        queueIndex = 0;
        return true;
    }

    private void scheduleNextFrame() {
        if (!sending) return;
        if (queueIndex >= queueTotal()) {
            int total = queueTotal();
            sending = false;
            queue = null;
            // 正常完成：只上报进度（finished=true），不报错误。
            postProgress(total, writtenCount, true, false);
            return;
        }
        final int sendGeneration = generation;
        final List<byte[]> sendQueue = queue;
        long delay=queueFastScore?Math.max(0,queueSpacingMs-Math.max(0,SystemClock.elapsedRealtime()-queueSubmitElapsed)):queueSpacingMs;
        main.postDelayed(new Runnable() {
            @Override public void run() {
                if (closed || !sending || generation != sendGeneration || queue != sendQueue) return;
                writeOne();
            }
        }, delay);
    }

    private void writeOne() {
        if (closed || !sending) return;
        if (!ready || pendingOp != OP_NONE) {
            abortSendAndDisconnect("发送状态异常", "尚未就绪或仍有 GATT 操作在途，发送中止。请重新连接。");
            return;
        }
        BluetoothGatt g = gatt;
        if (g == null || !linkUp) {
            abortSendAndDisconnect("发送期间连接已断开", "发送期间连接已断开，发送已中止。");
            return;
        }
        int total = queueTotal();
        if (queueIndex >= total) {
            sending = false;
            queue = null;
            postProgress(total, writtenCount, true, false);
            return;
        }
        BluetoothGattService service = g.getService(SERVICE_UUID);
        BluetoothGattCharacteristic ch = service == null ? null : service.getCharacteristic(NOTIFY_UUID);
        if (ch == null) {
            abortSendAndDisconnect("发送期间找不到 FFE1 特征",
                    "发送期间找不到 FFE1 特征，发送已中止，并已断开连接。");
            return;
        }
        byte[] frame = queue.get(queueIndex);
        int frameNo = queueIndex + 1;
        queueIndex++;                 // 预置为「已提交」下标
        queueSubmitElapsed=SystemClock.elapsedRealtime();
        boolean withResponse = queueWriteType == BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT;
        if (Build.VERSION.SDK_INT >= 33) {
            submitApi33(g, ch, frame, withResponse, frameNo);
        } else {
            submitLegacy(g, ch, frame, withResponse, frameNo);
        }
    }

    @TargetApi(33)
    private void submitApi33(BluetoothGatt g, BluetoothGattCharacteristic ch, byte[] frame,
                             boolean withResponse, int frameNo) {
        int submitted;
        try {
            submitted = g.writeCharacteristic(ch, frame,
                    withResponse ? BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                            : BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE);
        } catch (SecurityException e) {
            abortSendAndDisconnect("第 " + frameNo + " 帧缺少权限",
                    "第 " + frameNo + " 帧写入缺少权限：" + e + "（已断开连接）");
            return;
        } catch (RuntimeException e) {
            abortSendAndDisconnect("第 " + frameNo + " 帧写入异常",
                    "第 " + frameNo + " 帧写入异常：" + e + "（已断开连接）");
            return;
        }
        afterSubmit(submitted, frameNo);
    }

    @SuppressWarnings("deprecation")
    private void submitLegacy(BluetoothGatt g, BluetoothGattCharacteristic ch, byte[] frame,
                              boolean withResponse, int frameNo) {
        boolean submitted;
        try {
            ch.setWriteType(withResponse ? BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                    : BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE);
            ch.setValue(frame);
            submitted = g.writeCharacteristic(ch);
        } catch (SecurityException e) {
            abortSendAndDisconnect("第 " + frameNo + " 帧缺少权限",
                    "第 " + frameNo + " 帧写入缺少权限：" + e + "（已断开连接）");
            return;
        } catch (RuntimeException e) {
            abortSendAndDisconnect("第 " + frameNo + " 帧写入异常",
                    "第 " + frameNo + " 帧写入异常：" + e + "（已断开连接）");
            return;
        }
        afterSubmit(submitted ? BluetoothGatt.GATT_SUCCESS : 1, frameNo);
    }

    private void afterSubmit(int submitStatus, int frameNo) {
        if (submitStatus != BluetoothGatt.GATT_SUCCESS) {
            // 同步返回失败：没有在途操作，也不会有回调。不重试，直接中止并断开。
            pendingOp = OP_NONE;
            abortSendAndDisconnect("第 " + frameNo + " 帧同步提交失败",
                    "第 " + frameNo + " 帧同步提交失败 status=" + submitStatus
                            + gattStatusHint(submitStatus) + "（GATT 忙碌或连接已失效），"
                            + "不重试，发送已中止，并已断开连接。");
            return;
        }
        if (!sending) return;
        pendingOp = OP_WRITE;
        armWriteTimeout(frameNo);
    }

    private void deliverSendError(final String message) {
        fail("发送", -1, message);
        deliver(new Runnable() {
            @Override public void run() { listener.onSendError(message); }
        });
    }

    /**
     * 中止发送并断开连接。发送过程中出现未知状态时必须断开，才能在途回调不影响下一批；
     * 断开通过 disconnectInternal(..., true) 如实上报 onDisconnected，界面不会停留在“仍连接”。
     */
    private void abortSendAndDisconnect(String reason, String sendErrorMessage) {
        boolean wasSending = abortSend(reason);
        disconnectInternal(reason, true);
        if (wasSending) deliverSendError(sendErrorMessage);
    }

    private int queueTotal() {
        List<byte[]> q = queue;
        return q == null ? writtenCount : q.size();
    }

    private void postProgress(final int total, final int written, final boolean finished, final boolean cancelled) {
        final SendProgress p = new SendProgress(total, written, queueWriteType, finished, cancelled);
        deliver(new Runnable() {
            @Override public void run() { listener.onSendProgress(p); }
        });
    }

    // ---------------------------------------------------------------- 超时

    private void armConnectTimeout() {
        armTimeout(OP_CONNECT, CONNECT_TIMEOUT_MS, new Runnable() {
            @Override public void run() {
                linkUp = false;
                ready = false;
                closeGattQuietly();
                generation++;
                fail("连接超时", -1, "连接超时：" + (CONNECT_TIMEOUT_MS / 1000)
                        + " 秒内未收到 GATT 连接回调。请确认旧 APP 已断开、模块未被其它手机连接。");
                deliver(new Runnable() {
                    @Override public void run() { listener.onDisconnected("连接超时，已断开"); }
                });
            }
        });
    }

    private void armDiscoverTimeout() {
        armTimeout(OP_DISCOVER, DISCOVER_TIMEOUT_MS, new Runnable() {
            @Override public void run() {
                abortConnectFailure("服务发现", -1,
                        "服务发现超时（" + (DISCOVER_TIMEOUT_MS / 1000) + " 秒），请重新连接。");
            }
        });
    }

    private void armCccdTimeout() {
        armTimeout(OP_CCCD, CCCD_TIMEOUT_MS, new Runnable() {
            @Override public void run() {
                abortConnectFailure("通知", -1, "写 CCCD 打开通知超时（" + (CCCD_TIMEOUT_MS / 1000)
                        + " 秒），通知未打开，不会进入可收发状态。");
            }
        });
    }

    private void armWriteTimeout(final int frameNo) {
        armTimeout(OP_WRITE, WRITE_TIMEOUT_MS, new Runnable() {
            @Override public void run() {
                // 超时后无法确认该帧状态，也不重试（回调可能已丢）：中止并断开。
                pendingOp = OP_NONE;
                abortSendAndDisconnect("第 " + frameNo + " 帧写超时",
                        "第 " + frameNo + " 帧写超时：" + WRITE_TIMEOUT_MS
                                + "ms 未收到 onCharacteristicWrite，不重试，发送已中止，并已断开连接。");
            }
        });
    }

    private void armTimeout(final int op, long delayMs, final Runnable onTimeout) {
        cancelOpTimeout();
        pendingOp = op;
        final int seq = timeoutSeq;
        opTimeout = new Runnable() {
            @Override public void run() {
                if (closed || seq != timeoutSeq) return;   // 已被新操作或回调取代
                if (pendingOp != op) return;
                pendingOp = OP_NONE;
                opTimeout = null;
                ready = false;
                Log.w(TAG, "操作超时 op=" + op);
                onTimeout.run();
            }
        };
        main.postDelayed(opTimeout, delayMs);
    }

    private void cancelOpTimeout() {
        if (opTimeout != null) {
            main.removeCallbacks(opTimeout);
            opTimeout = null;
        }
        timeoutSeq++;   // 让已排队的超时全部作废
    }

    // ---------------------------------------------------------------- 上报

    private String resolvedWriteTypeLabel() {
        return resolvedWriteType == BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                ? "带响应写" : "无响应写";
    }

    private void fail(String stage, int status, String message) {
        Log.w(TAG, "[" + stage + "] status=" + status + " " + message);
        final String s = stage;
        final int st = status;
        final String m = message;
        deliver(new Runnable() {
            @Override public void run() { listener.onError(s, st, m); }
        });
    }
}
