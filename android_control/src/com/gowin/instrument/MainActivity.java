package com.gowin.instrument;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.bluetooth.BluetoothAdapter;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * 高云 FPGA 乐器调试界面（纯程序化 UI，无 res 依赖，无 AndroidX，无外部库）。
 *
 * 重要边界：
 *  - 手机解析曲谱并下载事件；音频由配套 FPGA 硬件合成，未实现录音回传。
 *  - 不会自动发送任何帧（包括 AT），必须用户点击。
 *  - 发送进度只表示「本地写出」，不代表 FPGA 已确认；0x42 只是完成标记，不是原子提交。
 *  - 权限永远先于蓝牙 API 检查；未授权时不会调用任何蓝牙 API，界面不崩溃。
 */
public class MainActivity extends Activity implements BleTransport.Listener {

    // ---------------------------------------------------------------- 常量

    private static final String PREFS = "gowin_instrument";
    private static final String KEY_PRESET_JSON = "preset_json";
    private static final String KEY_ANCHOR = "anchor_index";
    private static final int REQ_PERMISSION = 1001;
    private static final int REQ_ENABLE_BT = 1002;
    private static final int REQ_IMPORT_JSON = 1003;
    private static final int REQ_EXPORT_JSON = 1004;
    private static final int REQ_EXPORT_LED_MAP = 1005;
    private static final String KEY_PENDING_LED_CSV = "pending_led_map_csv";
    private static final String JSON_MIME = "application/json";
    private static final String JSON_NAME = "gowin_tone.json";
    /** 导入 JSON 的最大字节数：128 KiB。不申请任何存储权限。 */
    private static final int MAX_JSON_BYTES = 128 * 1024;
    private static final int MAX_LOG_CHARS = 20000;
    private static final int MAX_HEX_CHARS = 12000;
    private static final int MAX_REPLY_LINES = 100;
    private static final String[] ADSR_LABELS = {
            "起音 attack：0.1..60000 ms",
            "衰减 decay：0.1..60000 ms",
            "延音 sustain：0..1",
            "释音 release：0.1..60000 ms"};

    // ---------------------------------------------------------------- 状态

    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final List<String> deviceLines = new ArrayList<>();
    private final List<String> deviceAddresses = new ArrayList<>();
    private final LinkedHashMapHolder scanMap = new LinkedHashMapHolder();

    private Preset preset = new Preset();
    private int anchorIndex;
    private BleTransport ble;
    private ScorePanel scorePanel;
    private OnlineScorePanel onlineScorePanel;
    private OnlineCatalogPanel onlineCatalogPanel;
    private boolean activityAlive = true;
    /** 预设是否已成功载入（未载入前禁用发送/保存/导入导出，避免零值被误当默认值发送）。 */
    private boolean presetReady;
    private int uiEpoch;              // 丢弃过期的异步 UI 更新
    private int presetEpoch;          // 丢弃过期的预设载入结果（导入/内置载入会递增）
    private int editRevision;         // Also reject asynchronous loads after visible edits.
    private int prefsWriteToken;
    private String pendingLedMapCsv;

    private ArrayAdapter<String> deviceAdapter;
    private final List<String> logLines = new ArrayList<>();
    private final List<String> replyLines = new ArrayList<>();
    private int ackCount;
    private int lastSentFrames;
    private final StringBuilder hexBuffer = new StringBuilder();
    private boolean diagnosticsScheduled;
    private final Runnable diagnosticsRefresh = new Runnable() {
        public void run() { diagnosticsScheduled=false; if(!activityAlive)return; refreshHex();refreshReplies();refreshLog(); }
    };

    // ---------------------------------------------------------------- 视图

    private ScrollView scroll;
    private View contentRoot;
    private AppNavigation navigation;
    private TextView tvBtState;
    private TextView tvLinkState;
    private TextView tvReadyState;
    private TextView tvWriteType;
    private Button btnScan;
    private Button btnConnectManual;
    private Button btnDisconnect;
    private Button btnSendSustain;
    private Button btnSendTone;
    private Button btnCancelSend;
    private Button btnSaveLocal;
    private Button btnLoadLocal;
    private Button btnImport;
    private Button btnExport;
    private ProgressBar progress;
    private TextView tvProgress;
    private Spinner spAnchor;
    private Spinner spControlProfile;
    private boolean legacyProfile;
    private EditText etName;
    private EditText etMac;
    private TextView tvHex;
    private TextView tvReplies;
    private TextView tvAck;
    private TextView tvLog;

    private EditorRow[] adsrRows;
    private EditorRow[] ampRows;
    private EditorRow[] decRows;
    private LinearLayout harmonicBox;
    private AdsrView adsrView;

    // ---------------------------------------------------------------- 生命周期

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        legacyProfile=getSharedPreferences(PREFS,MODE_PRIVATE).getBoolean("legacy_control_profile",false);
        if(savedInstanceState!=null)pendingLedMapCsv=savedInstanceState.getString(KEY_PENDING_LED_CSV);
        ble = new BleTransport(this, this);
        buildUi();
        navigation.restore(savedInstanceState);
        applyWindowInsets();
        loadPresetFromPrefsOrAssets(savedInstanceState);
        ble.emitAdapterState();
        refreshButtons();
    }

    @Override protected void onResume() {
        super.onResume();
        activityAlive = true;
        if (ble != null) ble.emitAdapterState();
        refreshButtons();
    }

    @Override public void onBackPressed(){if(navigation!=null&&navigation.back())return;super.onBackPressed();}

    @Override protected void onDestroy() {
        activityAlive = false;
        uiEpoch++;
        main.removeCallbacksAndMessages(null);   // 关掉本界面自己的 Handler 任务
        if (ble != null) {
            ble.close();          // 释放 GATT / 扫描 / 传输层 Handler 任务
            ble = null;
        }
        if (scorePanel != null) scorePanel.close();
        if (onlineScorePanel != null) onlineScorePanel.close();
        if (onlineCatalogPanel != null) onlineCatalogPanel.close();
        io.shutdownNow();
        super.onDestroy();
    }

    private void applyWindowInsets() {
        if (contentRoot == null) return;
        contentRoot.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener() {
            @Override public WindowInsets onApplyWindowInsets(View v, WindowInsets insets) {
                int top;
                int bottom;
                int left;
                int right;
                if (Build.VERSION.SDK_INT >= 30) {
                    android.graphics.Insets bars = insets.getInsets(
                            WindowInsets.Type.systemBars() | WindowInsets.Type.ime());
                    top = bars.top;
                    bottom = bars.bottom;
                    left = bars.left;
                    right = bars.right;
                } else {
                    top = insets.getSystemWindowInsetTop();
                    bottom = insets.getSystemWindowInsetBottom();
                    left = insets.getSystemWindowInsetLeft();
                    right = insets.getSystemWindowInsetRight();
                }
                v.setPadding(left, top, right, bottom);
                return insets;
            }
        });
        // 深色界面：状态栏/导航栏随底色，系统图标切为浅色。
        getWindow().setStatusBarColor(UiTheme.BG);
        getWindow().setNavigationBarColor(UiTheme.BG);
        if (Build.VERSION.SDK_INT >= 30) {
            android.view.WindowInsetsController controller = getWindow().getInsetsController();
            if (controller != null) {
                controller.setSystemBarsAppearance(0,
                        android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                                | android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS);
            }
        } else {
            getWindow().getDecorView().setSystemUiVisibility(0);
        }
        contentRoot.requestApplyInsets();
    }

    // ---------------------------------------------------------------- 界面搭建

    private void buildUi() {
        scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        contentRoot = root;
        scroll.addView(root, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        final List<Integer> pageMap = new ArrayList<>();

        // ============================================================ 连接页
        LinearLayout welcome = new LinearLayout(this);
        welcome.setOrientation(LinearLayout.VERTICAL);
        welcome.setPadding(dp(2), dp(8), dp(2), dp(12));
        welcome.addView(UiTheme.eyebrow(this, "无线连接  /  JDY-23"));
        TextView greeting = UiTheme.heading(this, "连接乐器，\n开始今天的练习。");
        greeting.setTextSize(28);
        greeting.setPadding(0, dp(8), 0, dp(10));
        welcome.addView(greeting);
        welcome.addView(UiTheme.caption(this, "把设置留给手机，把演奏交给你。"));
        page(root, pageMap, welcome, 0);
        // —— 设备面板：状态、扫描、设备列表、断开 ——
        LinearLayout deviceCard = UiTheme.card(this);
        deviceCard.addView(UiTheme.section(this, "附近的乐器"));
        tvLinkState = UiTheme.caption(this, "尚未连接设备");
        deviceCard.addView(tvLinkState);
        tvReadyState = UiTheme.caption(this, "可通信：否（连接并打开通知后才能收发）");
        tvBtState = UiTheme.caption(this, "");
        deviceCard.addView(UiTheme.caption(this,
                "开始扫描后，在列表中选择 JDY-23。"));
        LinearLayout profileCard=UiTheme.card(this);
        profileCard.addView(UiTheme.section(this,"连接用途"));
        spControlProfile=new Spinner(this);UiTheme.spinner(spControlProfile);
        spControlProfile.setAdapter(UiTheme.spinnerAdapter(this,new String[]{"138K · 跟灯与自动演奏","曲谱 / 加法音色（配套固件）"}));
        spControlProfile.setSelection(legacyProfile?1:0);profileCard.addView(spControlProfile);
        UiTheme.space(profileCard,8);
        profileCard.addView(UiTheme.caption(this,"138K新版支持等键跟灯和MIDI自动演奏；曲谱需先检测接口。FM音色和总音量仍在乐器屏幕调整。用途须与配套固件匹配。"));
        spControlProfile.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener(){
            public void onItemSelected(android.widget.AdapterView<?> parent,View view,int position,long id){
                boolean next=position==1;if(next==legacyProfile)return;
                if((ble!=null&&ble.isSending())||(scorePanel!=null&&!scorePanel.canLoadDownloaded())){
                    spControlProfile.setSelection(legacyProfile?1:0);toast("请先停止演奏并等待当前任务结束，再切换用途。");return;
                }
                legacyProfile=next;getSharedPreferences(PREFS,MODE_PRIVATE).edit().putBoolean("legacy_control_profile",next).apply();
                appendLog("连接用途："+(next?"曲谱 / 加法音色，需要配套固件":"138K内置《晴天》灯带指引"));
                if(btnSendTone!=null)refreshButtons();
            }
            public void onNothingSelected(android.widget.AdapterView<?> parent){}
        });
        btnScan = button("开始扫描", new View.OnClickListener() {
            @Override public void onClick(View v) {
                if (ble != null && ble.isScanning()) ble.stopScan();
                else ensurePermissionsAndScan(true);
            }
        });
        deviceCard.addView(btnScan, new LinearLayout.LayoutParams(-1, -2));
        FrameLayout listFrame = new FrameLayout(this);
        ListView list = new ListView(this);
        deviceAdapter = UiTheme.listAdapter(this, deviceLines);
        list.setAdapter(deviceAdapter);
        UiTheme.list(list);
        listFrame.addView(list, new FrameLayout.LayoutParams(-1, -1));
        TextView listEmpty = UiTheme.caption(this, "等待发现你的乐器\n扫描约需 10 秒，请保持模块处于广播状态。");
        listEmpty.setGravity(Gravity.CENTER);
        listEmpty.setPadding(dp(16), dp(16), dp(16), dp(16));
        listFrame.addView(listEmpty);
        list.setEmptyView(listEmpty);
        list.setOnItemClickListener(new android.widget.AdapterView.OnItemClickListener() {
            @Override public void onItemClick(android.widget.AdapterView<?> parent, View view, int position, long id) {
                if (position < 0 || position >= deviceAddresses.size()) return;
                String address = deviceAddresses.get(position);
                appendLog("点击设备 " + address + "，开始连接");
                connectTo(address);
            }
        });
        LinearLayout.LayoutParams listParams = new LinearLayout.LayoutParams(-1, dp(136));
        listParams.topMargin = dp(8);
        deviceCard.addView(listFrame, listParams);
        btnDisconnect = button("断开连接", new View.OnClickListener() {
            @Override public void onClick(View v) {
                if (ble != null) {
                    ble.cancelSend();
                    ble.disconnect("用户点击断开");
                }
                appendLog("用户主动断开连接");
            }
        });
        UiTheme.ghost(btnDisconnect);
        deviceCard.addView(btnDisconnect, new LinearLayout.LayoutParams(-1, -2));
        page(root, pageMap, deviceCard, 0);
        page(root, pageMap, profileCard, 0);

        // —— 高级选项：手动地址、权限与系统设置 ——
        LinearLayout advancedCard = UiTheme.card(this);
        LinearLayout advancedBox = new LinearLayout(this);
        advancedBox.setOrientation(LinearLayout.VERTICAL);
        advancedBox.addView(tvBtState);
        advancedBox.addView(UiTheme.caption(this,
                "列表没有设备时，手动输入 MAC 地址连接（Android 12+ 可能给出随机化地址，以列表显示的地址为准）。"));
        LinearLayout macRow = row();
        etMac = input("AA:BB:CC:DD:EE:FF");
        macRow.addView(etMac, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        btnConnectManual = button("连接", new View.OnClickListener() {
            @Override public void onClick(View v) { connectTo(etMac.getText().toString()); }
        });
        LinearLayout.LayoutParams macBtnParams = new LinearLayout.LayoutParams(-2, -2);
        macBtnParams.leftMargin = dp(8);
        macRow.addView(btnConnectManual, macBtnParams);
        advancedBox.addView(macRow);
        LinearLayout permRow = row();
        permRow.addView(button("检查/申请权限", new View.OnClickListener() {
            @Override public void onClick(View v) { ensurePermissionsAndScan(false); }
        }));
        permRow.addView(button("系统蓝牙设置", new View.OnClickListener() {
            @Override public void onClick(View v) { openBluetoothSettings(); }
        }));
        shareRow(permRow);
        advancedBox.addView(permRow);
        advancedBox.addView(UiTheme.caption(this,
                "Android 12+ 需授予「附近的设备」权限；Android 11 及以下需授予「位置信息」并在系统设置里打开定位开关（本 APP 不会替你改开关）。"));
        collapsible(advancedCard, "高级选项 · 手动地址 / 权限", advancedBox, false);
        page(root, pageMap, advancedCard, 0);

        // —— 诊断明细：READY、写类型等技术细节 ——
        LinearLayout connectDiagCard = UiTheme.card(this);
        LinearLayout connectDiagBox = new LinearLayout(this);
        connectDiagBox.setOrientation(LinearLayout.VERTICAL);
        connectDiagBox.addView(tvReadyState);
        tvWriteType = UiTheme.caption(this, "写类型：未知（连接后确定）");
        connectDiagBox.addView(tvWriteType);
        connectDiagBox.addView(UiTheme.caption(this,
                "READY 表示 GATT 已连接、服务发现(FFE0)完成、且通知(0x2902 CCCD)写成功；READY=否时所有发送按钮保持禁用。扫描不使用服务 UUID 过滤，因为有些 JDY 模块广播里没有 FFE0。"));
        collapsible(connectDiagCard, "诊断明细 · READY / 写类型", connectDiagBox, false);
        page(root, pageMap, connectDiagCard, 0);

        // ============================================================ 曲谱页
        scorePanel = new ScorePanel(this, new ScorePanel.Host() {
            public BleTransport transport() { return ble; }
            public void log(String message) { appendLog(message); }
            public void refresh() { refreshButtons(); }
            public boolean legacyEnabled(){return legacyProfile;}
            public boolean scoreEnabled(){return true;}
            public boolean tutorialEnabled(){return !legacyProfile;}
            public void exportLedMap(String csv){startLedMapExport(csv);}
        });
        page(root, pageMap, scorePanel, 1);
        onlineScorePanel = new OnlineScorePanel(this, new OnlineScorePanel.Host() {
            public boolean canLoad() { return scorePanel != null && scorePanel.canLoadDownloaded(); }
            public boolean load(String name, byte[] bytes) { boolean loaded=scorePanel != null && scorePanel.loadDownloaded(name, bytes);if(loaded&&navigation!=null)navigation.show(1,scorePanel);return loaded; }
            public void log(String message) { appendLog(message); if(onlineCatalogPanel!=null)onlineCatalogPanel.refresh(); }
        });
        onlineCatalogPanel = new OnlineCatalogPanel(this,new OnlineCatalogPanel.Host(){
            public boolean canSelect(){return onlineScorePanel!=null&&onlineScorePanel.canSelectCatalog();}
            public boolean select(ScoreCatalog.Entry entry){boolean accepted=onlineScorePanel!=null&&onlineScorePanel.selectFromCatalog(entry);if(accepted&&navigation!=null)navigation.show(1,onlineScorePanel);return accepted;}
            public void log(String message){appendLog(message);}
        });
        scorePanel.addLegacySource(onlineCatalogPanel);
        scorePanel.addLegacySource(onlineScorePanel);
        LinearLayout webCard = UiTheme.card(this);
        webCard.addView(UiTheme.section(this, "人人钢琴 · 网页曲库"));
        webCard.addView(UiTheme.caption(this, "在 App 内登录自己的会员、选曲并下载到手机；载入曲谱后，仍需配套曲谱固件才能上传 FPGA。"));
        Button websiteScores=new Button(this);websiteScores.setText("打开人人钢琴 · App 内浏览下载");
        websiteScores.setOnClickListener(new View.OnClickListener(){public void onClick(View view){
            if(scorePanel==null||!scorePanel.canLoadDownloaded()){
                toast("请先结束传输并停止演奏，再进入网页曲库。");return;
            }
            try{startActivityForResult(new Intent(MainActivity.this,WebsiteScoreActivity.class),WebsiteScoreActivity.REQUEST);}
            catch(RuntimeException ex){appendLog("无法打开网页曲库。");}
        }});
        UiTheme.button(websiteScores, false);
        webCard.addView(websiteScores, new LinearLayout.LayoutParams(-1, -2));
        scorePanel.addLegacySource(webCard);

        // ============================================================ 音色页
        // —— 当前音色：名称、锚点、发送到乐器 ——
        LinearLayout toneCard = UiTheme.card(this);
        toneCard.addView(UiTheme.eyebrow(this, "离线编辑  /  加法合成"));
        toneCard.addView(UiTheme.section(this, "当前音色"));
        toneCard.addView(UiTheme.caption(this,
                "当前138K的FM音色在板载界面调整。本页可编辑加法预设，发送需配套固件。"));
        toneCard.addView(UiTheme.caption(this,"音色名称"));
        etName = input("音色名");
        trackEdits(etName);
        toneCard.addView(etName, new LinearLayout.LayoutParams(-1,-2));
        LinearLayout anchorRow = row();
        anchorRow.addView(label("锚点"));
        spAnchor = new Spinner(this);
        UiTheme.spinner(spAnchor);
        spAnchor.setAdapter(UiTheme.spinnerAdapter(this, Protocol.ANCHORS));
        spAnchor.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(android.widget.AdapterView<?> parent, View view, int position, long id) {
                if (position == anchorIndex) return;
                if (!presetReady) return;
                String problem = tryApplyEditorsToModel();
                if (problem != null) {
                    // 非法编辑：不丢输入，也不切换锚点。
                    toast("当前锚点参数非法，未切换：" + problem);
                    appendLog("锚点切换被拒绝：" + problem);
                    spAnchor.setSelection(anchorIndex, false);
                    return;
                }
                anchorIndex = position;
                fillHarmonicEditor();
                appendLog("已切换到锚点 " + Protocol.ANCHORS[anchorIndex]);
            }
            @Override public void onNothingSelected(android.widget.AdapterView<?> parent) { }
        });
        anchorRow.addView(spAnchor, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        toneCard.addView(anchorRow);
        btnSendTone = button("发送音色到乐器", new View.OnClickListener() {
            @Override public void onClick(View v) { sendFullTone(); }
        });
        UiTheme.button(btnSendTone, UiTheme.Style.PRIMARY);
        LinearLayout.LayoutParams sendToneParams = new LinearLayout.LayoutParams(-1, -2);
        sendToneParams.topMargin = dp(4);
        toneCard.addView(btnSendTone, sendToneParams);
        LinearLayout sendRow = row();
        btnSendSustain = button("仅发送延音参数", new View.OnClickListener() {
            @Override public void onClick(View v) { sendSustainOnly(); }
        });
        btnCancelSend = button("取消发送", new View.OnClickListener() {
            @Override public void onClick(View v) {
                if (ble != null) ble.cancelSend();
                appendLog("用户取消发送");
            }
        });
        UiTheme.danger(btnCancelSend);
        sendRow.addView(btnSendSustain);
        sendRow.addView(btnCancelSend);
        shareRow(sendRow);
        toneCard.addView(sendRow);
        progress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progress.setMax(1);
        progress.setProgress(0);
        UiTheme.progress(progress);
        toneCard.addView(progress, new LinearLayout.LayoutParams(-1, -2));
        tvProgress = UiTheme.caption(this, "发送进度：0/0（本地写出）");
        toneCard.addView(tvProgress);
        toneCard.addView(UiTheme.caption(this,
                "本地发送进度不代表板端确认，回复详情见日志。"));
        page(root, pageMap, toneCard, 2);

        // —— ADSR 包络：示意曲线 + 四段参数 ——
        LinearLayout adsrCard = UiTheme.card(this);
        adsrCard.addView(UiTheme.section(this, "包络 · ADSR"));
        adsrCard.addView(UiTheme.caption(this,
                "曲线随编辑变化；非法输入会提示，保留原值。"));
        adsrView = new AdsrView();
        LinearLayout.LayoutParams adsrParams = new LinearLayout.LayoutParams(-1, dp(120));
        adsrParams.topMargin = dp(4);
        adsrParams.bottomMargin = dp(8);
        adsrCard.addView(adsrView, adsrParams);
        adsrRows = new EditorRow[4];
        for (int i = 0; i < 4; i++) {
            EditorRow r = paramRow(ADSR_LABELS[i]);
            adsrRows[i] = r;
            adsrCard.addView(r.view);
            r.edit.addTextChangedListener(new android.text.TextWatcher() {
                public void beforeTextChanged(CharSequence s, int start, int count, int after) { }
                public void onTextChanged(CharSequence s, int start, int before, int count) { if (adsrView != null) adsrView.invalidate(); }
                public void afterTextChanged(android.text.Editable text) { }
            });
        }
        page(root, pageMap, adsrCard, 2);

        // —— 16 路谐波：折叠的高级编辑 ——
        LinearLayout harmonicCard = UiTheme.card(this);
        harmonicBox = new LinearLayout(this);
        harmonicBox.setOrientation(LinearLayout.VERTICAL);
        harmonicBox.addView(UiTheme.caption(this,
                "每路含幅度 0..1 与衰减 0..120000 ms，全部保留精度、单位与校验。"));
        buildHarmonicRows();
        collapsible(harmonicCard, "16 路谐波 · 幅度 / 衰减", harmonicBox, false);
        page(root, pageMap, harmonicCard, 2);

        // —— 预设管理：本机保存/恢复与 JSON 导入导出 ——
        LinearLayout presetCard = UiTheme.card(this);
        presetCard.addView(UiTheme.section(this, "预设管理"));
        LinearLayout ioRow = row();
        btnSaveLocal = button("保存到本机", new View.OnClickListener() {
            @Override public void onClick(View v) { savePresetToPrefs(false); }
        });
        btnLoadLocal = button("从本机恢复", new View.OnClickListener() {
            @Override public void onClick(View v) { loadPresetFromPrefsOrAssets(null); }
        });
        ioRow.addView(btnSaveLocal);
        ioRow.addView(btnLoadLocal);
        shareRow(ioRow);
        presetCard.addView(ioRow);
        LinearLayout safRow = row();
        btnImport = button("导入音色 JSON", new View.OnClickListener() {
            @Override public void onClick(View v) { startImport(); }
        });
        btnExport = button("导出音色 JSON", new View.OnClickListener() {
            @Override public void onClick(View v) { startExport(); }
        });
        safRow.addView(btnImport);
        safRow.addView(btnExport);
        shareRow(safRow);
        presetCard.addView(safRow);
        LinearLayout presetRow = row();
        presetRow.addView(button("载入内置钢琴预设", new View.OnClickListener() {
            @Override public void onClick(View v) { loadAssetPreset(); }
        }));
        shareRow(presetRow);
        presetCard.addView(presetRow);
        presetCard.addView(UiTheme.caption(this,
                "保存与恢复只作用于手机。JSON 导入/导出通过系统文件选择器，最大128 KiB。"));
        page(root, pageMap, presetCard, 2);

        // ============================================================ 日志页
        // —— 最近结果与日志正文 ——
        LinearLayout logCard = UiTheme.card(this);
        logCard.addView(UiTheme.section(this, "最近结果与日志"));
        tvAck = UiTheme.body(this, "ACK 计数：0");
        logCard.addView(tvAck);
        logCard.addView(UiTheme.caption(this,
                "记录连接、传输与指引命令。ACK表示收到回复，灯带效果仍需看实物。"));
        tvLog = UiTheme.mono(this, "日志：");
        logCard.addView(tvLog, new LinearLayout.LayoutParams(-1, -2));
        LinearLayout logRow = row();
        logRow.addView(button("清空显示", new View.OnClickListener() {
            @Override public void onClick(View v) {
                hexBuffer.setLength(0);
                replyLines.clear();
                logLines.clear();
                ackCount = 0;
                refreshHex();
                refreshReplies();
                refreshLog();
            }
        }));
        logRow.addView(button("使用说明 / 测试指引", new View.OnClickListener() {
            @Override public void onClick(View v) { showHelp(); }
        }));
        shareRow(logRow);
        logCard.addView(logRow);
        page(root, pageMap, logCard, 3);

        // —— 原始诊断：HEX 与回复解码（默认收起）——
        LinearLayout rawCard = UiTheme.card(this);
        LinearLayout rawBox = new LinearLayout(this);
        rawBox.setOrientation(LinearLayout.VERTICAL);
        tvReplies = UiTheme.mono(this, "ReplyDecoder 解码：");
        rawBox.addView(tvReplies, new LinearLayout.LayoutParams(-1, -2));
        View hexGap = new View(this);
        rawBox.addView(hexGap, new LinearLayout.LayoutParams(-1, dp(8)));
        tvHex = UiTheme.mono(this, "HEX：");
        rawBox.addView(tvHex, new LinearLayout.LayoutParams(-1, -2));
        collapsible(rawCard, "诊断明细 · 原始 HEX / 回复解码", rawBox, false);
        page(root, pageMap, rawCard, 3);

        UiTheme.button(btnScan, UiTheme.Style.PRIMARY);
        navigation = new AppNavigation(this, root, scroll, toInts(pageMap));
        contentRoot = navigation.shell;
        setContentView(contentRoot);
    }

    /** 把视图挂到根布局并记录所属页码（0 连接 / 1 曲谱 / 2 音色 / 3 日志）。 */
    private static void page(LinearLayout root, List<Integer> map, View v, int p) {
        root.addView(v);
        map.add(p);
    }
    private static int[] toInts(List<Integer> list) {
        int[] a = new int[list.size()];
        for (int i = 0; i < a.length; i++) a[i] = list.get(i);
        return a;
    }

    /** 折叠区：14sp 标题 + ▸/▾ 指示，整行 48dp 可点；内容默认收起。 */
    private void collapsible(LinearLayout card, String title, final View content, boolean expanded) {
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setMinimumHeight(dp(48));
        TextView label = new TextView(this);
        label.setText(title);
        label.setTextColor(UiTheme.TEXT);
        label.setTextSize(14);
        label.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        header.addView(label, new LinearLayout.LayoutParams(0, -2, 1f));
        final TextView chevron = new TextView(this);
        chevron.setTextSize(14);
        chevron.setTextColor(UiTheme.MUTED);
        header.addView(chevron);
        card.addView(header);
        card.addView(content);
        content.setVisibility(expanded ? View.VISIBLE : View.GONE);
        chevron.setText(expanded ? "▾" : "▸");
        header.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                boolean open = content.getVisibility() != View.VISIBLE;
                content.setVisibility(open ? View.VISIBLE : View.GONE);
                chevron.setText(open ? "▾" : "▸");
            }
        });
    }

    /** ADSR 包络示意：按当前输入值绘制，非法输入回退为模型值；纯展示，不参与校验与提交。 */
    private final class AdsrView extends View {
        private final android.graphics.Paint line = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        private final android.graphics.Paint grid = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        private final android.graphics.Paint fill = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        private final android.graphics.Paint dots = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        AdsrView() {
            super(MainActivity.this);
            line.setColor(UiTheme.PRIMARY);
            line.setStyle(android.graphics.Paint.Style.STROKE);
            line.setStrokeWidth(dp(2));
            line.setStrokeCap(android.graphics.Paint.Cap.ROUND);
            line.setStrokeJoin(android.graphics.Paint.Join.ROUND);
            grid.setColor(UiTheme.OUTLINE);
            grid.setStyle(android.graphics.Paint.Style.STROKE);
            grid.setStrokeWidth(1f);
            fill.setColor(0x22D8AD66);
            fill.setStyle(android.graphics.Paint.Style.FILL);
            dots.setColor(UiTheme.PRIMARY);
            dots.setStyle(android.graphics.Paint.Style.FILL);
        }
        @Override protected void onDraw(android.graphics.Canvas canvas) {
            double[] v = adsrValues();
            double a = v[0], d = v[1], s = v[2], r = v[3];
            double hold = Math.max(a + d + r, 1) * 0.35;
            double total = a + d + hold + r;
            float x0 = dp(8), x1 = getWidth() - dp(8);
            float y0 = dp(10), y1 = getHeight() - dp(14);
            if (x1 <= x0 || y1 <= y0) return;
            canvas.drawLine(x0, y1, x1, y1, grid);
            float xa = x0 + (float) ((x1 - x0) * a / total);
            float xd = xa + (float) ((x1 - x0) * d / total);
            float xh = xd + (float) ((x1 - x0) * hold / total);
            float xr = xh + (float) ((x1 - x0) * r / total);
            float ys = y1 - (float) ((y1 - y0) * s);
            android.graphics.Path p = new android.graphics.Path();
            p.moveTo(x0, y1);
            p.lineTo(xa, y0);
            p.lineTo(xd, ys);
            p.lineTo(xh, ys);
            p.lineTo(xr, y1);
            android.graphics.Path f = new android.graphics.Path(p);
            f.lineTo(x0, y1);
            f.close();
            canvas.drawPath(f, fill);
            canvas.drawPath(p, line);
            canvas.drawCircle(xa, y0, dp(3), dots);
            canvas.drawCircle(xd, ys, dp(3), dots);
            canvas.drawCircle(xh, ys, dp(3), dots);
        }
    }

    /** 读取四个 ADSR 输入框；非法或越界的项回退为当前模型值。 */
    private double[] adsrValues() {
        double[] v = {
                preset == null ? 30 : preset.attack,
                preset == null ? 500 : preset.decay,
                preset == null ? 0.18 : preset.sustain,
                preset == null ? 800 : preset.release};
        if (adsrRows != null) {
            for (int i = 0; i < 4; i++) {
                Double parsed = parse(adsrRows[i].edit.getText().toString());
                if (parsed != null && inRange(i, parsed)) v[i] = parsed;
            }
        }
        return v;
    }

    /** 谐波编辑：每项一块，标签在上，下面两列等宽输入。 */
    private void buildHarmonicRows() {
        harmonicBox.removeAllViews();
        ampRows = new EditorRow[16];
        decRows = new EditorRow[16];
        for (int h = 0; h < 16; h++) {
            LinearLayout block = new LinearLayout(this);
            block.setOrientation(LinearLayout.VERTICAL);
            block.setPadding(0, dp(3), 0, dp(3));
            block.addView(label("谐波 H" + (h + 1)));
            LinearLayout line = row();
            EditorRow amp = weightedEditor("幅度 0..1");
            EditorRow dec = weightedEditor("衰减 ms");
            ampRows[h] = amp;
            decRows[h] = dec;
            line.addView(amp.view, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            line.addView(dec.view, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            block.addView(line);
            harmonicBox.addView(block);
        }
    }

    private void fillHarmonicEditor() {
        if (preset == null || ampRows == null || decRows == null) return;
        for (int h = 0; h < 16; h++) {
            ampRows[h].edit.setText(num(preset.amplitudes[anchorIndex][h]));
            decRows[h].edit.setText(num(preset.decayMs[anchorIndex][h]));
            mark(ampRows[h], true);
            mark(decRows[h], true);
        }
    }

    private void pushModelToUi() {
        etName.setText(preset.name);
        adsrRows[0].edit.setText(num(preset.attack));
        adsrRows[1].edit.setText(num(preset.decay));
        adsrRows[2].edit.setText(num(preset.sustain));
        adsrRows[3].edit.setText(num(preset.release));
        fillHarmonicEditor();
        for (EditorRow r : adsrRows) mark(r, true);
        if (adsrView != null) adsrView.invalidate();
    }

    // ---------------------------------------------------------------- 预设载入/保存

    private void loadPresetFromPrefsOrAssets(Bundle savedInstanceState) {
        final int epoch = ++uiEpoch;
        final int presetToken = ++presetEpoch;
        final int edits = editRevision;
        final boolean haveSaved = savedInstanceState != null;
        final String savedJson = haveSaved ? savedInstanceState.getString(KEY_PRESET_JSON) : null;
        final int savedAnchor = haveSaved ? savedInstanceState.getInt(KEY_ANCHOR, 0) : -1;
        io.execute(new Runnable() {
            @Override public void run() {
                Preset loaded = null;
                String note = null;
                if (savedJson != null) {
                    try {
                        loaded = PresetJson.parse(savedJson);
                        note = "已从上次界面状态恢复参数。";
                    } catch (Exception e) {
                        note = "上次界面状态无效，改用已保存/内置预设：" + e.getMessage();
                    }
                }
                if (loaded == null) loaded = loadFromPrefsSync();
                if (loaded == null) loaded = loadFromAssetsSync();
                if (loaded == null) {
                    note = "内置预设与已保存预设都不可用：参数区保持未初始化，"
                            + "发送/保存/导入导出保持禁用，请点「载入内置钢琴预设」重试。";
                }
                final Preset result = loaded;
                final String message = note;
                final int anchor = savedAnchor >= 0 ? savedAnchor : readAnchorPref();
                main.post(new Runnable() {
                    @Override public void run() {
                        if (!activityAlive || epoch != uiEpoch) return;
                        // 期间已经发生导入或内置载入（presetEpoch 变了）：不要用初始结果覆盖。
                        if (presetEpoch != presetToken) return;
                        if (editRevision != edits) { appendLog("参数已有新编辑，未用迟到的载入结果覆盖。"); return; }
                        if (result == null) {
                            appendLog(message);
                            refreshButtons();
                            return;
                        }
                        preset = result;
                        anchorIndex = Math.max(0, Math.min(3, anchor));
                        spAnchor.setSelection(anchorIndex, false);
                        pushModelToUi();
                        presetReady = true;
                        if (message != null) appendLog(message);
                        appendLog("已载入音色：" + preset.name);
                        refreshButtons();
                    }
                });
            }
        });
    }

    private Preset loadFromPrefsSync() {
        try {
            SharedPreferences sp = getSharedPreferences(PREFS, MODE_PRIVATE);
            String json = sp.getString(KEY_PRESET_JSON, null);
            if (json == null || json.isEmpty()) return null;
            return PresetJson.parse(json);
        } catch (Exception e) {
            main.post(logRunnable("读取已保存预设失败：" + e.getMessage()));
            return null;
        }
    }

    private Preset loadFromAssetsSync() {
        InputStream in = null;
        try {
            in = getAssets().open("default_preset.json");
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            return PresetJson.parse(new String(out.toByteArray(), Charset.forName("UTF-8")));
        } catch (Exception e) {
            main.post(logRunnable("从 assets 载入预设失败：" + e.getMessage()));
            return null;
        } finally {
            closeQuietly(in);
        }
    }

    /** 载入内置钢琴预设（也作为「恢复出厂默认」，因为全零参数会静音）。 */
    private void loadAssetPreset() {
        final int epoch = ++uiEpoch;
        final int presetToken = ++presetEpoch;
        final int edits = editRevision;
        io.execute(new Runnable() {
            @Override public void run() {
                final Preset p = loadFromAssetsSync();
                main.post(new Runnable() {
                    @Override public void run() {
                        if (!activityAlive || epoch != uiEpoch) return;
                        if (presetEpoch != presetToken) return;   // 已被更新的载入/导入取代
                        if (editRevision != edits) { appendLog("参数已有新编辑，未用迟到的内置预设覆盖。"); return; }
                        if (p == null) {
                            toast("内置预设载入失败，详见日志");
                            return;
                        }
                        preset = p;
                        presetReady = true;
                        pushModelToUi();
                        appendLog("已载入内置钢琴预设");
                        refreshButtons();
                    }
                });
            }
        });
    }

    private void savePresetToPrefs(final boolean silent) {
        if (!presetReady) {
            toast("预设尚未载入，暂时不能保存");
            return;
        }
        String problem = tryApplyEditorsToModel();
        if (problem != null) {
            toast("保存失败，参数非法：" + problem);
            return;
        }
        try {
            preset.validate();
            final String json = PresetJson.stringify(preset);
            final int token = ++prefsWriteToken;
            io.execute(new Runnable() {
                @Override public void run() {
                    try {
                        SharedPreferences.Editor ed = getSharedPreferences(PREFS, MODE_PRIVATE).edit();
                        ed.putString(KEY_PRESET_JSON, json);
                        ed.putInt(KEY_ANCHOR, anchorIndex);
                        ed.apply();
                        main.post(new Runnable() {
                            @Override public void run() {
                                if (!activityAlive) return;
                                if (token == prefsWriteToken && !silent) toast("已保存到本机");
                                appendLog("预设已保存到本机 SharedPreferences（" + json.length() + " 字符）");
                            }
                        });
                    } catch (RuntimeException e) {
                        main.post(logRunnable("保存失败：" + e));
                    }
                }
            });
        } catch (Exception e) {
            toast("保存失败：" + e.getMessage());
        }
    }

    private int readAnchorPref() {
        try {
            return getSharedPreferences(PREFS, MODE_PRIVATE).getInt(KEY_ANCHOR, 0);
        } catch (RuntimeException e) {
            return 0;
        }
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        if(navigation!=null)navigation.save(outState);
        if(pendingLedMapCsv!=null)outState.putString(KEY_PENDING_LED_CSV,pendingLedMapCsv);
        try {
            if (preset != null && presetReady) {
                tryApplyEditorsToModel();
                outState.putString(KEY_PRESET_JSON, PresetJson.stringify(preset));
                outState.putInt(KEY_ANCHOR, anchorIndex);
            }
        } catch (Exception e) {
            appendLog("界面状态保存失败（忽略）：" + e.getMessage());
        }
    }

    // ---------------------------------------------------------------- SAF 导入/导出

    private void startImport() {
        if (!presetReady) {
            toast("预设尚未载入，暂时不能导入");
            return;
        }
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        intent.putExtra(Intent.EXTRA_MIME_TYPES,
                new String[]{JSON_MIME, "text/plain", "application/octet-stream"});
        try {
            startActivityForResult(intent, REQ_IMPORT_JSON);
        } catch (RuntimeException e) {
            toast("无法打开文件选择器：" + e.getMessage());
        }
    }

    private void startExport() {
        if (!presetReady) {
            toast("预设尚未载入，暂时不能导出");
            return;
        }
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType(JSON_MIME);
        intent.putExtra(Intent.EXTRA_TITLE, JSON_NAME);
        try {
            startActivityForResult(intent, REQ_EXPORT_JSON);
        } catch (RuntimeException e) {
            toast("无法打开文件选择器：" + e.getMessage());
        }
    }

    private void startLedMapExport(String csv){
        if(pendingLedMapCsv!=null){toast("请先完成或取消上一次灯位导出");return;}
        pendingLedMapCsv=csv;
        Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);intent.setType("text/csv");
        intent.putExtra(Intent.EXTRA_TITLE,"gowin_25key_led_map.csv");
        try{startActivityForResult(intent,REQ_EXPORT_LED_MAP);}
        catch(RuntimeException ex){pendingLedMapCsv=null;appendLog("无法打开灯位导出："+ex.getMessage());toast("无法打开文件选择器，可先复制明细");}
    }

    private void writeLedMap(final Uri uri,final String csv){
        io.execute(new Runnable(){public void run(){
            String error=null;
            try(OutputStream output=getContentResolver().openOutputStream(uri,"wt")){
                if(output==null)throw new IOException("无法打开输出文件");
                output.write(("\ufeff"+csv).getBytes(Charset.forName("UTF-8")));output.flush();
            }catch(Exception ex){error=ex.getMessage();}
            final String problem=error;
            main.post(new Runnable(){public void run(){if(!activityAlive)return;
                appendLog(problem==null?"25键灯位CSV已导出；未校准键留空，数据未发送到FPGA。":"灯位CSV导出失败："+problem);
                toast(problem==null?"灯位明细已导出":"灯位明细导出失败");
            }});
        }});
    }

    private void handleImport(final Uri uri) {
        // 导入是用户主动操作，完成后必须覆盖模型；presetEpoch 递增可作废所有在途的初始载入。
        final int epoch = ++uiEpoch;
        final int presetToken = ++presetEpoch;
        final int edits = editRevision;
        io.execute(new Runnable() {
            @Override public void run() {
                String text = null;
                String error = null;
                InputStream in = null;
                try {
                    in = getContentResolver().openInputStream(uri);
                    if (in == null) throw new IOException("无法打开输入流");
                    byte[] data = new byte[MAX_JSON_BYTES + 1];
                    int total = 0;
                    while (total < data.length) {
                        int n = in.read(data, total, data.length - total);
                        if (n <= 0) break;
                        total += n;
                    }
                    if (total > MAX_JSON_BYTES) {
                        error = "文件超过 128 KiB，已拒绝导入。";
                    } else {
                        text = new String(data, 0, total, Charset.forName("UTF-8"));
                        if (text.startsWith("\ufeff")) text = text.substring(1);
                    }
                } catch (Exception e) {
                    error = "读取失败：" + e.getMessage();
                } finally {
                    closeQuietly(in);
                }
                final String t = text;
                final String err = error;
                main.post(new Runnable() {
                    @Override public void run() {
                        if (!activityAlive) return;
                        if (epoch != uiEpoch || presetToken != presetEpoch) return;   // 期间又有更新的载入/导入
                        if (editRevision != edits) { appendLog("参数已有新编辑，导入结果未覆盖；可重新导入。"); return; }
                        if (err != null) {
                            appendLog("导入失败：" + err);
                            toast("导入失败：" + err);
                            return;
                        }
                        // 先在临时副本上验证，失败不动模型。
                        try {
                            Preset parsed = PresetJson.parse(t);
                            parsed.validate();
                            preset = parsed;
                            presetReady = true;
                            pushModelToUi();
                            appendLog("导入成功：" + preset.name);
                            toast("导入成功");
                            refreshButtons();
                        } catch (Exception e) {
                            appendLog("导入的 JSON 非法，模型未改变：" + e.getMessage());
                            toast("导入的 JSON 非法，模型未改变");
                        }
                    }
                });
            }
        });
    }

    private void handleExport(final Uri uri) {
        if (!presetReady) {
            toast("预设尚未载入，暂时不能导出");
            return;
        }
        String problem = tryApplyEditorsToModel();
        final String json;
        if (problem != null) {
            toast("导出失败，参数非法：" + problem);
            return;
        }
        try {
            preset.validate();
            json = PresetJson.stringify(preset);
        } catch (Exception e) {
            toast("导出失败：" + e.getMessage());
            return;
        }
        if (json.getBytes(Charset.forName("UTF-8")).length > MAX_JSON_BYTES) {
            toast("导出内容超过 128 KiB，已取消");
            return;
        }
        final int epoch = uiEpoch;
        io.execute(new Runnable() {
            @Override public void run() {
                String error = null;
                OutputStream out = null;
                try {
                    out = getContentResolver().openOutputStream(uri, "wt");
                    if (out == null) throw new IOException("无法打开输出流");
                    out.write(json.getBytes(Charset.forName("UTF-8")));
                    out.flush();
                } catch (Exception e) {
                    error = "写入失败：" + e.getMessage();
                } finally {
                    if (out != null) {
                        try { out.close(); } catch (IOException ignore) { }
                    }
                }
                final String err = error;
                main.post(new Runnable() {
                    @Override public void run() {
                        if (!activityAlive || epoch != uiEpoch) return;
                        if (err != null) {
                            appendLog("导出失败：" + err);
                            toast("导出失败：" + err);
                        } else {
                            appendLog("导出成功：" + preset.name);
                            toast("导出成功");
                        }
                    }
                });
            }
        });
    }

    // ---------------------------------------------------------------- 权限与蓝牙开关

    /**
     * 权限检查永远先于任何蓝牙 API。未授权时只申请权限，不做任何蓝牙调用。
     * thenScan=true 表示权限齐全后自动开始扫描。
     */
    private void ensurePermissionsAndScan(boolean thenScan) {
        List<String> missing = new ArrayList<>();
        if (Build.VERSION.SDK_INT >= 31) {
            if (!hasPermission("android.permission.BLUETOOTH_SCAN")) missing.add("android.permission.BLUETOOTH_SCAN");
            if (!hasPermission("android.permission.BLUETOOTH_CONNECT")) missing.add("android.permission.BLUETOOTH_CONNECT");
            appendLog("说明：Android 12+ 的蓝牙权限是「附近的设备」，授予后才能扫描和连接。");
        } else {
            if (!hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)) missing.add(Manifest.permission.ACCESS_FINE_LOCATION);
            appendLog("说明：Android 11 及以下扫描 BLE 必须授予「位置信息」权限，"
                    + "并且要打开系统定位开关，否则扫描不到设备（本 APP 不会替你改开关）。");
        }
        if (!missing.isEmpty()) {
            toast("请授予权限：" + missing);
            try {
                requestPermissions(missing.toArray(new String[0]), REQ_PERMISSION);
            } catch (RuntimeException e) {
                appendLog("申请权限失败：" + e);
            }
            return;
        }
        if (thenScan) startScanNow();
    }

    private boolean hasPermission(String permission) {
        try {
            return checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED;
        } catch (RuntimeException e) {
            return false;
        }
    }

    private void startScanNow() {
        BluetoothAdapter adapter = BleTransport.adapterOf(this);
        if (adapter == null) {
            toast("本机不支持 BLE");
            return;
        }
        if (!isAdapterEnabled(adapter)) {
            appendLog("蓝牙未打开，已请求系统打开蓝牙；打开后请再点一次扫描。");
            requestEnableBluetooth();
            return;
        }
        String problem = BleTransport.permissionProblem(this);
        if (problem != null) {
            appendLog(problem);
            toast(problem);
            ensurePermissionsAndScan(false);
            return;
        }
        String hint = BleTransport.locationSwitchHint(this);
        if (hint != null) appendLog(hint);
        if (ble != null) ble.startScan();
    }

    /** 读蓝牙开关必须 catch：未授权时 isEnabled() 会抛 SecurityException。 */
    private boolean isAdapterEnabled(BluetoothAdapter adapter) {
        try {
            return adapter.isEnabled();
        } catch (SecurityException e) {
            appendLog("缺少蓝牙权限，无法读取蓝牙开关状态：" + e);
            return false;
        } catch (RuntimeException e) {
            appendLog("读取蓝牙开关状态失败：" + e);
            return false;
        }
    }

    /** 蓝牙关闭时用系统 ACTION_REQUEST_ENABLE；绝不自己改开关。 */
    private void requestEnableBluetooth() {
        try {
            Intent intent = new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE);
            startActivityForResult(intent, REQ_ENABLE_BT);
        } catch (RuntimeException e) {
            toast("无法请求打开蓝牙：" + e.getMessage());
            appendLog("ACTION_REQUEST_ENABLE 失败：" + e);
        }
    }

    private void openBluetoothSettings() {
        try {
            startActivity(new Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS));
        } catch (RuntimeException e) {
            toast("无法打开蓝牙设置：" + e.getMessage());
        }
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != REQ_PERMISSION) return;
        boolean allGranted = grantResults != null && grantResults.length > 0;
        if (grantResults != null) {
            for (int r : grantResults) if (r != PackageManager.PERMISSION_GRANTED) allGranted = false;
        }
        if (allGranted) {
            appendLog("权限已授予。");
            startScanNow();
        } else {
            String problem = BleTransport.permissionProblem(this);
            appendLog("权限被拒绝，无法扫描或连接。"
                    + (problem == null ? "" : problem)
                    + " 可在「系统设置 -> 应用 -> 权限」里手动补授。");
            toast("权限被拒绝，无法扫描；请到系统设置里补授权限");
            if (ble != null) ble.emitAdapterState();
            refreshButtons();
        }
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if(requestCode==REQ_EXPORT_LED_MAP){
            String snapshot=pendingLedMapCsv;pendingLedMapCsv=null;
            if(resultCode!=RESULT_OK){appendLog("已取消灯位CSV导出");return;}
            if(data==null||data.getData()==null||snapshot==null){appendLog("灯位导出内容已失效，请重新打开灯位明细后导出。");return;}
            writeLedMap(data.getData(),snapshot);return;
        }
        if(requestCode==WebsiteScoreActivity.REQUEST){
            if(resultCode==RESULT_OK&&data!=null)loadWebsiteScore(data);
            return;
        }
        if (scorePanel != null && scorePanel.activityResult(requestCode, resultCode, data)) return;
        if (onlineScorePanel != null && onlineScorePanel.activityResult(requestCode, resultCode, data)) return;
        if (requestCode == REQ_ENABLE_BT) {
            // 只认 RESULT_OK；不读可能不存在的 boolean EXTRA_STATE。
            boolean granted = BleTransport.isEnableResultOk(resultCode);
            appendLog(granted ? "用户已同意打开蓝牙" : "用户未打开蓝牙（resultCode=" + resultCode + "）");
            if (granted) {
                ensurePermissionsAndScan(true);
            } else {
                appendLog("蓝牙仍处于关闭状态，无法扫描或连接。");
            }
            if (ble != null) ble.emitAdapterState();
            return;
        }
        if (resultCode != RESULT_OK || data == null) return;
        Uri uri = data.getData();
        if (uri == null) return;
        if (requestCode == REQ_IMPORT_JSON) handleImport(uri);
        else if (requestCode == REQ_EXPORT_JSON) handleExport(uri);
    }

    private void loadWebsiteScore(Intent result){
        final String cache=result.getStringExtra(WebsiteScoreActivity.EXTRA_TOKEN);
        final String name=WebMidiDownload.displayName(result.getStringExtra(WebsiteScoreActivity.EXTRA_NAME));
        final int generation=uiEpoch;
        if(scorePanel==null||!scorePanel.canLoadDownloaded()){appendLog("当前曲谱区忙，请稍后从网页曲库读取最近下载。");return;}
        io.execute(new Runnable(){public void run(){try{
            final byte[] bytes=WebMidiDownload.readCached(getFilesDir(),cache);
            main.post(new Runnable(){public void run(){if(!activityAlive||generation!=uiEpoch)return;
                if(scorePanel!=null&&scorePanel.loadDownloaded(name,bytes)){
                    appendLog("已将网站下载的MIDI载入曲谱区："+name+"，尚未发送蓝牙。");
                    if(navigation!=null)navigation.show(1,scorePanel);
                }else appendLog("曲谱区当前忙，下载保留，可从网页曲库读取最近下载。");
            }});
        }catch(Exception ex){main.post(new Runnable(){public void run(){if(activityAlive&&generation==uiEpoch)appendLog("网站下载缓存读取失败，请返回网页曲库重新下载。");}});}}});
    }

    private void connectTo(String address) {
        if (address == null || address.trim().isEmpty()) {
            toast("请先选择设备或输入地址");
            return;
        }
        BluetoothAdapter adapter = BleTransport.adapterOf(this);
        if (adapter == null) {
            toast("本机不支持 BLE");
            return;
        }
        // 权限先于任何蓝牙 API（isEnabled 在未授权时会抛 SecurityException）。
        String problem = BleTransport.permissionProblem(this);
        if (problem != null) {
            toast(problem);
            appendLog(problem);
            ensurePermissionsAndScan(false);
            return;
        }
        if (!isAdapterEnabled(adapter)) {
            appendLog("蓝牙未打开，已请求系统打开蓝牙；打开后请再点一次连接。");
            requestEnableBluetooth();
            return;
        }
        if (ble == null) return;
        ble.connect(address.trim());
    }

    // ---------------------------------------------------------------- 发送

    private void sendSustainOnly() {
        if(!legacyProfile){toast("当前用途为138K灯带指引，加法延音参数不会发送。");return;}
        if (!presetReady) {
            toast("预设尚未载入完成，请稍候再发送");
            return;
        }
        String problem = tryApplyEditorsToModel();
        if (problem != null) {
            toast("参数非法，未发送：" + problem);
            return;
        }
        try {
            preset.validate();
            byte[] frame = Protocol.sustain(preset.sustain);
            appendLog("发送单帧 延音参数 proto=" + Protocol.hex(frame));
            if (ble == null) return;
            ble.sendFrame(frame);
        } catch (IllegalArgumentException e) {
            toast("延音参数非法：" + e.getMessage());
        } catch (RuntimeException e) {
            toast("发送失败：" + e);
        }
    }

    private void sendFullTone() {
        if(!legacyProfile){toast("当前用途为138K灯带指引，FM音色请在板载界面调整。");return;}
        if (!presetReady) {
            toast("预设尚未载入完成，请稍候再发送");
            return;
        }
        String problem = tryApplyEditorsToModel();
        if (problem != null) {
            toast("参数非法，未发送：" + problem);
            return;
        }
        final Preset snapshot = preset.copy();
        try {
            snapshot.validate();
            final List<byte[]> frames = Protocol.frames(snapshot);
            if (frames.size() != BleTransport.FULL_TONE_FRAMES) {
                appendLog("注意：帧数为 " + frames.size() + "，与预期的 "
                        + BleTransport.FULL_TONE_FRAMES + " 不一致");
            }
            appendLog("发送完整音色，共 " + frames.size() + " 帧（每帧 " + BleTransport.FRAME_BYTES
                    + " 字节，间隔 " + BleTransport.WRITE_SPACING_MS + "ms）");
            if (ble == null) return;
            ble.sendFrames(frames);
        } catch (IllegalArgumentException e) {
            toast("参数非法，未发送：" + e.getMessage());
        } catch (RuntimeException e) {
            toast("发送失败：" + e);
        }
    }

    // ---------------------------------------------------------------- 参数编辑

    private static final class EditorRow {
        final LinearLayout view;
        final EditText edit;
        final TextView hint;
        final String hintText;
        EditorRow(LinearLayout view, EditText edit, TextView hint, String hintText) {
            this.view = view;
            this.edit = edit;
            this.hint = hint;
            this.hintText = hintText;
        }
    }

    /** ADSR 行：标签在上、输入占满整行宽度（窄屏不被裁掉）。 */
    private EditorRow paramRow(String labelText) {
        LinearLayout block = new LinearLayout(this);
        block.setOrientation(LinearLayout.VERTICAL);
        block.setPadding(0, dp(3), 0, dp(3));
        TextView title = label(labelText);
        title.setMinHeight(0);
        title.setPadding(0, 0, 0, dp(6));
        block.addView(title);
        EditorRow r = editor("");
        block.addView(r.edit, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        block.addView(r.hint);
        return new EditorRow(block, r.edit, r.hint, r.hintText);
    }

    /** 谐波列：标签在上、输入 MATCH_PARENT。 */
    private EditorRow weightedEditor(String caption) {
        LinearLayout block = new LinearLayout(this);
        block.setOrientation(LinearLayout.VERTICAL);
        block.setPadding(dp(2), 0, dp(2), 0);
        TextView captionView = label(caption);
        captionView.setMinHeight(0);
        block.addView(captionView);
        EditorRow r = editor("");
        block.addView(r.edit, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        block.addView(r.hint);
        return new EditorRow(block, r.edit, r.hint, r.hintText);
    }

    private EditorRow editor(String unit) {
        EditText edit = new EditText(this);
        edit.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        edit.setSingleLine(true);
        UiTheme.input(edit);
        trackEdits(edit);
        TextView hint = new TextView(this);
        hint.setText(unit);
        hint.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        hint.setTextColor(UiTheme.FAINT);
        hint.setVisibility(unit.isEmpty() ? View.GONE : View.VISIBLE);
        LinearLayout holder = new LinearLayout(this);
        holder.setOrientation(LinearLayout.VERTICAL);
        // Leave children unattached: each caller attaches them exactly once.
        return new EditorRow(holder, edit, hint, unit);
    }

    private void mark(EditorRow r, boolean ok) {
        r.edit.setTextColor(ok ? UiTheme.TEXT : UiTheme.DANGER);
        r.hint.setText(ok ? r.hintText : "! 非法，请修正后重试");
        r.hint.setTextColor(ok ? UiTheme.FAINT : UiTheme.DANGER);
        r.hint.setVisibility(ok && r.hintText.isEmpty() ? View.GONE : View.VISIBLE);
    }

    /** 在临时副本上验证并提交；返回 null 表示成功，否则返回第一条错误说明。 */
    private String tryApplyEditorsToModel() {
        if (preset == null || adsrRows == null || ampRows == null || decRows == null) return null;
        if (!presetReady) return "预设尚未载入完成";
        Preset temp = preset.copy();
        String firstError = null;
        String name = etName.getText().toString().trim();
        if (!name.isEmpty()) temp.name = name;

        double[] adsr = new double[4];
        String[] adsrNames = {"起音", "衰减", "延音", "释音"};
        for (int i = 0; i < 4; i++) {
            Double value = parse(adsrRows[i].edit.getText().toString());
            boolean ok = value != null && inRange(i, value);
            adsr[i] = ok ? value : 0;
            mark(adsrRows[i], ok);
            if (!ok && firstError == null) firstError = adsrNames[i] + " 必须是 " + adsrRange(i) + " 的数字";
        }
        double[] amp = new double[16];
        double[] dec = new double[16];
        for (int h = 0; h < 16; h++) {
            Double a = parse(ampRows[h].edit.getText().toString());
            boolean okA = a != null && a >= 0 && a <= 1;
            amp[h] = okA ? a : 0;
            mark(ampRows[h], okA);
            if (!okA && firstError == null) firstError = "H" + (h + 1) + " 幅度必须是 0..1 的数字";

            Double d = parse(decRows[h].edit.getText().toString());
            boolean okD = d != null && d >= 0 && d <= 120000;
            dec[h] = okD ? d : 0;
            mark(decRows[h], okD);
            if (!okD && firstError == null) firstError = "H" + (h + 1) + " 衰减必须是 0..120000 ms 的数字";
        }
        if (firstError != null) return firstError;   // 有非法输入：模型完全不动

        temp.attack = adsr[0];
        temp.decay = adsr[1];
        temp.sustain = adsr[2];
        temp.release = adsr[3];
        for (int h = 0; h < 16; h++) {
            temp.amplitudes[anchorIndex][h] = amp[h];
            temp.decayMs[anchorIndex][h] = dec[h];
        }
        try {
            temp.validate();
        } catch (IllegalArgumentException e) {
            return e.getMessage();
        }
        preset = temp;   // 验证通过后一次性提交，失败不改模型
        return null;
    }

    private static boolean inRange(int adsrIndex, double value) {
        switch (adsrIndex) {
            case 2: return value >= 0 && value <= 1;
            default: return value >= 0.1 && value <= 60000;
        }
    }

    private static String adsrRange(int adsrIndex) {
        return adsrIndex == 2 ? "0..1" : "0.1..60000ms";
    }

    private static Double parse(String text) {
        if (text == null) return null;
        String t = text.trim();
        if (t.isEmpty() || t.startsWith("+")) return null;
        try {
            double v = Double.parseDouble(t);
            if (Double.isNaN(v) || Double.isInfinite(v)) return null;
            return v;
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /** 整数值显示成整数，其余用 Double.toString 保留导入的原始精度。 */
    private static String num(double value) {
        if (!Double.isNaN(value) && !Double.isInfinite(value)
                && value == Math.rint(value) && Math.abs(value) < 1e15) {
            return Long.toString((long) value);
        }
        return Double.toString(value);
    }

    // ---------------------------------------------------------------- BleTransport.Listener

    @Override public void onBluetoothState(final boolean enabled, final boolean bleSupported) {
        runOnMain(new Runnable() {
            @Override public void run() {
                if (tvBtState == null) return;
                if (enabled) {
                    tvBtState.setText("本机 BLE：" + (bleSupported ? "支持" : "不支持") + "；蓝牙开关：已打开");
                } else {
                    tvBtState.setText("本机 BLE：" + (bleSupported ? "支持" : "不支持")
                            + "；蓝牙开关：已关闭或未授权（可在「高级选项」里申请权限/打开系统设置）");
                }
                refreshButtons();
            }
        });
    }

    @Override public void onScanStarted() {
        runOnMain(new Runnable() {
            @Override public void run() {
                deviceLines.clear();
                deviceAddresses.clear();
                scanMap.clear();
                if (deviceAdapter != null) deviceAdapter.notifyDataSetChanged();
                btnScan.setText("停止扫描（10 秒后自动停止）");
                appendLog("开始扫描，10 秒后自动停止");
                refreshButtons();
            }
        });
    }

    @Override public void onScanEntry(final BleTransport.ScanEntry entry) {
        runOnMain(new Runnable() {
            @Override public void run() {
                ScanRow previous = scanMap.get(entry.address);
                if (previous == null) {
                    scanMap.put(entry.address, new ScanRow(entry.address, entry.rssi, entry.name, entry.hasFfe0));
                } else {
                    previous.rssi = entry.rssi;
                    if (entry.name != null && !entry.name.isEmpty()) previous.name = entry.name;
                    previous.hasFfe0 = previous.hasFfe0 || entry.hasFfe0;
                }
                rebuildDeviceList();
            }
        });
    }

    @Override public void onScanFinished(final int count) {
        runOnMain(new Runnable() {
            @Override public void run() {
                if (btnScan == null) return;
                btnScan.setText("开始扫描");
                appendLog("扫描结束，共 " + count + " 个设备");
                if (count == 0) {
                    appendLog("没有扫描到任何设备：请确认模块在广播、旧 APP 已断开、"
                            + "Android 11 及以下已打开系统定位开关。");
                }
                refreshButtons();
            }
        });
    }

    @Override public void onScanFailed(final String message) {
        runOnMain(new Runnable() {
            @Override public void run() {
                if (btnScan == null) return;
                btnScan.setText("开始扫描");
                appendLog("扫描失败：" + message);
                refreshButtons();
            }
        });
    }

    @Override public void onLinkUp(final String address) {
        runOnMain(new Runnable() {
            @Override public void run() {
                if (tvLinkState == null) return;
                tvLinkState.setText("蓝牙链路：已连接 " + (address == null ? "" : address) + "（服务发现中…）");
                tvReadyState.setText("可通信：否（正在打开通知…）");
                appendLog("GATT 链路已连上，开始服务发现");
                refreshButtons();
            }
        });
    }

    @Override public void onConnected(final String address) {
        runOnMain(new Runnable() {
            @Override public void run() {
                if (tvLinkState == null) return;
                tvLinkState.setText("蓝牙链路：连接成功 " + (address == null ? "" : address));
                tvReadyState.setText("可通信：是（可以收发）");
                if (ble != null) tvWriteType.setText("写类型：" + ble.describeWriteType());
                appendLog("READY：连接成功且通知已打开，可以收发");
                refreshButtons();
            }
        });
    }

    @Override public void onNotifyEnabled(final String characteristicDescription) {
        runOnMain(new Runnable() {
            @Override public void run() {
                appendLog("通知已开启：" + characteristicDescription);
            }
        });
    }

    @Override public void onDisconnected(final String reason) {
        runOnMain(new Runnable() {
            @Override public void run() {
                if (tvLinkState == null) return;
                tvLinkState.setText("蓝牙链路：未连接");
                tvReadyState.setText("可通信：否（连接并打开通知后才能收发）");
                tvWriteType.setText("写类型：未知（连接后确定）");
                appendLog("已断开：" + reason);
                if (scorePanel != null) scorePanel.disconnected();
                stopProgressAnimation();
                refreshButtons();
            }
        });
    }

    @Override public void onError(final String stage, final int status, final String message) {
        runOnMain(new Runnable() {
            @Override public void run() {
                appendLog("错误[" + stage + "] status=" + status + " " + message);
                toast(stage + "失败：status=" + status);
                refreshButtons();
            }
        });
    }

    @Override public void onNotification(byte[] data) {
        // 已在主线程
        hexBuffer.append(Protocol.hex(data)).append(' ');
        if (hexBuffer.length() > MAX_HEX_CHARS) {
            int cut = hexBuffer.length() - MAX_HEX_CHARS / 2;
            hexBuffer.delete(0, cut);
            hexBuffer.insert(0, "[…截断…] ");
        }
        refreshDiagnosticsSoon();
        try {
            if (ble == null) return;
            List<ReplyDecoder.Reply> replies = ble.decode(data);
            for (ReplyDecoder.Reply r : replies) {
                if (scorePanel != null) scorePanel.onReply(r);
                ackCount++;
                String line = "cmd=0x" + String.format(Locale.US, "%02X", r.command)
                        + " status=" + r.status + " " + r.label();
                replyLines.add(line);
                appendLog("回复 " + line);
                if (r.command == 0x42) {
                    appendLog("收到 0x42 完成标记：这只是一个标记，不是原子提交的证明。");
                }
            }
            while (replyLines.size() > MAX_REPLY_LINES) replyLines.remove(0);
            refreshDiagnosticsSoon();
        } catch (RuntimeException e) {
            appendLog("解码回复异常：" + e);
        }
    }

    @Override public void onSendProgress(final BleTransport.SendProgress info) {
        runOnMain(new Runnable() {
            @Override public void run() {
                if (progress == null) return;
                boolean scoreOwned=scorePanel!=null&&scorePanel.busy();
                if (scorePanel != null) scorePanel.onProgress(info);
                lastSentFrames = info.written;
                if(scoreOwned){refreshButtons();return;}
                progress.setMax(Math.max(1, info.total));
                progress.setProgress(info.written);
                StringBuilder sb = new StringBuilder();
                sb.append("发送进度：").append(info.written).append('/').append(info.total);
                sb.append("（仅本地写出，不是 FPGA 确认）");
                if (info.finished) sb.append(info.cancelled ? " ｜ 已取消" : " ｜ 发送完毕");
                sb.append(" ｜ 写类型：").append(info.writeTypeLabel());
                if (!info.ackedByPeer()) sb.append("，只有本地提交");
                tvProgress.setText(sb.toString());
                if (info.finished) {
                    stopProgressAnimation();
                    appendLog("发送" + (info.cancelled ? "取消" : "完成")
                            + "：" + info.written + "/" + info.total);
                }
                refreshButtons();
            }
        });
    }

    private void stopProgressAnimation() {
        // No estimates: progress is updated only by actual write callbacks.
    }

    @Override public void onSendError(final String message) {
        runOnMain(new Runnable() {
            @Override public void run() {
                appendLog("发送错误：" + message);
                if (scorePanel != null) scorePanel.sendError(message);
                toast("发送已停止：" + message);
                stopProgressAnimation();
                refreshButtons();
            }
        });
    }

    // ---------------------------------------------------------------- 显示刷新

    private void refreshButtons() {
        if (btnScan == null) return;
        boolean sending = (ble != null && ble.isSending()) || (scorePanel != null && scorePanel.busy());
        boolean ready = ble != null && ble.isReady();
        boolean scanning = ble != null && ble.isScanning();
        if(navigation!=null)navigation.status(ready,scanning,sending);
        btnScan.setText(scanning ? "停止扫描" : "开始扫描");
        btnScan.setEnabled(!sending);
        spControlProfile.setEnabled(!sending&&(scorePanel==null||scorePanel.canLoadDownloaded()));
        btnSendSustain.setEnabled(legacyProfile && presetReady && ready && !sending);
        btnSendTone.setEnabled(legacyProfile && presetReady && ready && !sending);
        btnCancelSend.setEnabled(ble != null && ble.isSending() && (scorePanel == null || !scorePanel.busy()));
        btnDisconnect.setEnabled(ble != null && (ble.isLinkUp() || sending));
        btnConnectManual.setEnabled(ble != null && !sending);
        btnSaveLocal.setEnabled(presetReady);
        btnImport.setEnabled(presetReady);
        btnExport.setEnabled(presetReady);
        btnLoadLocal.setEnabled(ble != null && !sending && !scanning);
        if (scorePanel != null) scorePanel.refresh();
        if (onlineScorePanel != null) onlineScorePanel.refresh();
        if (onlineCatalogPanel != null) onlineCatalogPanel.refresh();
    }

    private void rebuildDeviceList() {
        List<ScanRow> rows = new ArrayList<>(scanMap.values());
        Collections.sort(rows, new Comparator<ScanRow>() {
            @Override public int compare(ScanRow a, ScanRow b) {
                return Integer.compare(b.rssi, a.rssi);
            }
        });
        deviceLines.clear();
        deviceAddresses.clear();
        for (ScanRow r : rows) {
            deviceLines.add(r.rssi + "dBm   " + r.address
                    + (r.name == null || r.name.isEmpty() ? "" : "   " + r.name)
                    + (r.hasFfe0 ? "   [FFE0]" : ""));
            deviceAddresses.add(r.address);
        }
        deviceAdapter.notifyDataSetChanged();
    }

    private void refreshHex() {
        if (tvHex == null) return;
        tvHex.setText("HEX：" + (hexBuffer.length() == 0 ? "（尚未收到数据）" : hexBuffer.toString()));
    }

    private void refreshReplies() {
        if (tvReplies == null) return;
        StringBuilder sb = new StringBuilder("ReplyDecoder 解码（最近 " + replyLines.size() + " 条）：");
        if (replyLines.isEmpty()) sb.append("（无）");
        else for (String line : replyLines) sb.append('\n').append(line);
        tvReplies.setText(sb.toString());
        tvAck.setText("ACK 计数：" + ackCount + "  ｜ 最近一次发送写出帧数：" + lastSentFrames
                + "（计数无法逐帧对应，协议无序号）");
    }

    private void appendLog(String message) {
        if (message == null || tvLog == null) return;
        long t = android.os.SystemClock.elapsedRealtime();
        String line = String.format(Locale.US, "[%02d:%02d:%02d.%03d] ", t / 3600000L, (t / 60000L) % 60, (t / 1000L) % 60, t % 1000L) + message;
        logLines.add(line);
        while (logLines.size() > 300) logLines.remove(0);
        refreshDiagnosticsSoon();
    }

    /** Data is recorded immediately; expensive TextView relayout is coalesced during score uploads. */
    private void refreshDiagnosticsSoon() {
        if(!activityAlive)return;
        if(scorePanel==null||!scorePanel.uploading()) {
            main.removeCallbacks(diagnosticsRefresh);diagnosticsScheduled=false;
            refreshHex();refreshReplies();refreshLog();return;
        }
        if(!diagnosticsScheduled){diagnosticsScheduled=true;main.postDelayed(diagnosticsRefresh,200);}
    }

    private void refreshLog() {
        StringBuilder sb = new StringBuilder();
        for (String line : logLines) {
            sb.append(line).append('\n');
        }
        if (sb.length() > MAX_LOG_CHARS) {
            sb.delete(0, sb.length() - MAX_LOG_CHARS);
            sb.insert(0, "[…日志已截断…]\n");
        }
        tvLog.setText("日志：\n" + sb);
    }

    private Runnable logRunnable(final String message) {
        return new Runnable() {
            @Override public void run() {
                if (!activityAlive) return;
                appendLog(message);
            }
        };
    }

    /** 回调统一入口：界面已销毁直接丢弃；非主线程转主线程。 */
    private void runOnMain(Runnable r) {
        if (!activityAlive) return;
        if (Looper.myLooper() == Looper.getMainLooper()) r.run();
        else main.post(r);
    }

    // ---------------------------------------------------------------- 小工具

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    /** 输入标签：13sp 暖白、垂直居中、与输入框同高对齐。 */
    private TextView label(String text) {
        TextView tv = new TextView(this);
        tv.setText(text);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        tv.setTextColor(UiTheme.MUTED);
        tv.setGravity(Gravity.CENTER_VERTICAL);
        tv.setMinHeight(dp(48));
        tv.setPadding(0, 0, dp(12), 0);
        return tv;
    }

    private EditText input(String hint) {
        EditText et = new EditText(this);
        et.setHint(hint);
        et.setSingleLine(true);
        UiTheme.input(et);
        return et;
    }

    private void trackEdits(EditText edit) {
        edit.addTextChangedListener(new android.text.TextWatcher() {
            public void beforeTextChanged(CharSequence s,int start,int count,int after) {}
            public void onTextChanged(CharSequence s,int start,int before,int count) { editRevision++; }
            public void afterTextChanged(android.text.Editable text) {}
        });
    }

    private Button button(String text, View.OnClickListener click) {
        Button b = new Button(this);
        b.setText(text);
        b.setOnClickListener(click);
        UiTheme.button(b, false);
        return b;
    }

    private LinearLayout row() {
        LinearLayout line = new LinearLayout(this);
        line.setOrientation(LinearLayout.HORIZONTAL);
        line.setGravity(Gravity.CENTER_VERTICAL);
        line.setPadding(0, dp(2), 0, dp(2));
        return line;
    }

    /** 让一行里的按钮平分宽度，避免长中文按钮被挤出屏幕。 */
    private void shareRow(LinearLayout row) {
        row.setGravity(Gravity.FILL_VERTICAL);
        int count = row.getChildCount();
        for (int i = 0; i < count; i++) {
            View child = row.getChildAt(i);
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.MATCH_PARENT, 1f);
            if (i > 0) params.setMarginStart(dp(6));
            child.setLayoutParams(params);
        }
    }

    private void toast(String message) {
        try {
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
        } catch (RuntimeException e) {
            appendLog("提示：" + message);
        }
    }

    private static void closeQuietly(java.io.Closeable c) {
        if (c != null) {
            try { c.close(); } catch (IOException ignore) { }
        }
    }

    private void showHelp() {
        String text = "使用与测试指引\n\n"
                + "1) 先把旧厂家 APP 的连接断开，确保同一时刻只有本 APP 连接模块。\n"
                + "2) 权限：Android 12+ 授予「附近的设备」(BLUETOOTH_SCAN/CONNECT)；"
                + "Android 11 及以下授予「位置信息」并打开系统定位开关"
                + "（本 APP 不会替你改开关）。被拒绝时请到系统设置里手动补授。\n"
                + "3) 点「开始扫描」，10 秒内列表会显示 RSSI/地址/名称；列表没有时可用手动输入地址连接\n"
                + "   （Android 12+ 某些机型给出的可能是随机化地址，请直接使用列表里显示的地址字符串）。\n"
                + "4) 连接流程：GATT 连接 -> 服务发现(FFE0) -> 打开通知（本地注册 + 写 0x2902 CCCD）。"
                + "只有 CCCD 写成功才会显示 READY=是；任何一步失败都会断开并写明原因。\n"
                + "5) 可收发后才允许发送：单帧「仅发送延音参数」或「发送完整音色(133 帧)」。\n"
                + "6) 进度条只表示手机本地写出；无响应写时没有 ATT 响应，更不能当作 FPGA 已确认。\n"
                + "7) 发送失败或取消会主动断开连接（避免在途回调影响下一批），需要重新连接。\n"
                + "8) 发送不自动重试：写状态未知时直接中止，避免参数部分生效后被重复发送。\n\n"
                + "138K《晴天》跟灯：曲谱已内置。连接后到曲谱页检查138K指引接口，展开灯带校准，给包含黑键在内的25个琴键各选一颗灯。保存到手机后，写入全部灯位或点开始；开始前有4拍预备。板上S0开始、S1停止，S4复位。灯位写入只在本次供电期间有效。\n\n"
                + "其他MIDI曲谱：展开MIDI上传区，先确认配套曲谱固件，连接READY后检测接口，载入MIDI、上传并等待CRC校验通过，再开始演奏。"
                + "曲谱每帧同时等待本地写完成和板端接受；取消/超时后需重连并从头上传。手机不生成音频。"
                + "当前138K蓝牙指引口不提供此MIDI上传或加法音色控制，FM音色用板载界面调整。录音回传未实现。\n\n"
                + "回复：收到的是 a5 5a f0 cmd status xor 六字节回复，本 APP 用 ReplyDecoder 解码。"
                + "ACK 计数只是收到的条数，协议没有序号，不能逐帧对应。0x42 只是完成标记。\n\n"
                + "参数：先在临时副本上验证再提交；切换锚点前会先校验，非法输入不会被丢弃。"
                + "「载入内置钢琴预设」只替换手机中的音色（全零参数会静音，本 APP 不把零值当默认）。"
                + "JSON 导入/导出走系统文件选择器，上限 128 KiB，不申请存储权限。";
        new AlertDialog.Builder(this)
                .setTitle("说明")
                .setMessage(text)
                .setPositiveButton("知道了", null)
                .show();
    }

    // ---------------------------------------------------------------- 扫描行模型

    private static final class ScanRow {
        final String address;
        int rssi;
        String name;
        boolean hasFfe0;
        ScanRow(String address, int rssi, String name, boolean hasFfe0) {
            this.address = address;
            this.rssi = rssi;
            this.name = name == null ? "" : name;
            this.hasFfe0 = hasFfe0;
        }
    }

    /** 简单的地址->行的映射容器。 */
    private static final class LinkedHashMapHolder {
        private final java.util.LinkedHashMap<String, ScanRow> map = new java.util.LinkedHashMap<>();
        void clear() { map.clear(); }
        ScanRow get(String address) { return map.get(address); }
        void put(String address, ScanRow row) {
            ScanRow old = map.get(address);
            if (old != null) {
                old.rssi = row.rssi;
                if (row.name != null && !row.name.isEmpty()) old.name = row.name;
                old.hasFfe0 = old.hasFfe0 || row.hasFfe0;
            } else {
                map.put(address, row);
            }
        }
        java.util.Collection<ScanRow> values() { return map.values(); }
    }
}
