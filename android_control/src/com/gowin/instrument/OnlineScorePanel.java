package com.gowin.instrument;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.View;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.Spinner;
import android.widget.TextView;

import java.io.File;
import java.io.IOException;
import java.io.OutputStream;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * 「在线 MIDI 曲库」增量面板：独立 LinearLayout 组件，不改动蓝牙音色与曲谱逻辑。
 *
 * 边界：
 *  - 联网请求、SHA-256 校验、缓存读写的实现全部在 ScoreDownload；本面板只做界面与线程切换。
 *  - 每次「下载 MIDI」都真实访问网络；只有「读取已下载缓存」才离线读缓存。
 *  - 「载入到曲谱区」只调用 Host.load(...)：不发蓝牙、不自动上传、不自动演奏。
 *  - 初始化不联网、不下载、不载入、不发蓝牙；不申请存储权限（另存走 SAF）。
 *  - 下载、读缓存、SAF 写盘都在 Executor 线程；所有界面更新都回到主线程 Handler。
 *  - 曲名只用于显示与另存建议文件名，不参与缓存路径；缓存目录固定为 filesDir/online-midi。
 *  - 用 request generation(epoch)+token 丢弃过期回调：取消、切换条目、关闭后旧回调都不能污染新任务。
 */
public final class OnlineScorePanel extends LinearLayout {
    /** 另存 MIDI 的请求码；与 ScorePanel.IMPORT_MIDI=1010 区分，不使用 1010/1001..1004。 */
    public static final int EXPORT_MIDI = 1011;

    public interface Host {
        boolean canLoad();
        boolean load(String name, byte[] bytes);
        void log(String message);
    }

    /** 固定曲库条目：URL 与 SHA-256 都是常量，仅用于显示与下载参数。 */
    private static final class Entry {
        final String label;
        final String name;
        final String url;
        final String sha256;
        final String page;
        final String license;
        Entry(String label, String name, String url, String sha256, String page) {
            this(label,name,url,sha256,page,"Public Domain");
        }
        Entry(String label, String name, String url, String sha256, String page,String license) {
            this.label = label;
            this.name = name;
            this.url = url;
            this.sha256 = sha256;
            this.page = page;
            this.license = license;
        }
    }

    /** 首版曲库 2 条：Mutopia Project，来源页面标注 Public Domain。 */
    private static final Entry[] LIBRARY = {
            new Entry("欢乐颂 · 四部合声（Mutopia · Public Domain）", "欢乐颂 · 四部合声",
                    "https://www.mutopiaproject.org/ftp/BeethovenLv/ode/ode.mid",
                    "FB1604C08C865B275B464D74E5A7C526FF1A8ACCCDF9853CB92F0778DAAED14B",
                    "https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=528"),
            new Entry("致爱丽丝（Mutopia · Public Domain）", "致爱丽丝",
                    "https://www.mutopiaproject.org/ftp/BeethovenLv/WoO59/fur_Elise_WoO59/fur_Elise_WoO59.mid",
                    "1C12C21C7BBF4CF163896732672648A69D497636059837ABD153C71ABE50215A",
                    "https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=931")
    };
    /** 第三个条目：自定义 HTTPS MIDI 直链（不固定 SHA-256）。 */
    private static final int REMOTE_INDEX = LIBRARY.length;
    private static final int CUSTOM_INDEX = LIBRARY.length+1;
    private Entry remoteEntry;

    private final Activity activity;
    private final Host host;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    /** 缓存目录；目录里的文件命名、写入与校验全部由 ScoreDownload 负责。 */
    private final File cacheDir;

    private final Spinner songs;
    private final TextView sourceLine;
    private final TextView customHint;
    private final TextView progressText;
    private final TextView resultLine;
    private final TextView status;
    private final EditText customName;
    private final EditText customUrl;
    private final Button download;
    private final Button loadCache;
    private final Button cancel;
    private final Button loadButton;
    private final Button saveButton;
    private final Button pageButton;
    private final ProgressBar progress;

    private boolean busy;        // 下载或离线读取进行中
    private boolean saving;      // SAF 另存写盘进行中
    private boolean closed;      // close() 之后一切回调作废
    private int epoch;           // 下载/读取的 request generation
    private int saveEpoch;       // 另存的 request generation
    private ScoreDownload.CancelToken cancelToken;
    private ScoreDownload.Result result;
    private String resultName;
    private byte[] pendingSaveBytes;   // 请求另存时的 byte[] 快照
    private String pendingSaveName;    // 请求另存时的命名

    public OnlineScorePanel(Activity activity, Host host) {
        super(activity);
        this.activity = activity;
        this.host = host;
        this.cacheDir = new File(activity.getFilesDir(), "online-midi");
        android.content.SharedPreferences recent=activity.getSharedPreferences("online_scores",0);
        if(!recent.getString("remote_url","").isEmpty())remoteEntry=new Entry(recent.getString("remote_label","在线曲目"),recent.getString("remote_name","在线曲目"),recent.getString("remote_url",""),null,recent.getString("remote_page",""),recent.getString("remote_license",""));
        setOrientation(VERTICAL);

        LinearLayout pickCard=card();
        pickCard.addView(section("曲目下载与保存（手机下载 → 曲谱区）"));
        pickCard.addView(caption("在在线曲库选择歌曲后，下载到手机并检查，再载入曲谱区上传。这里也提供两首已验证的常用曲目。"));
        pickCard.addView(caption("当前曲目（可在上方在线曲库选择）"));

        songs = new Spinner(activity);
        final String[] items = new String[LIBRARY.length + 2];
        for (int i = 0; i < LIBRARY.length; i++) items[i] = LIBRARY[i].label;
        items[CUSTOM_INDEX] = "自定义 HTTPS MIDI 直链";
        items[REMOTE_INDEX] = "在线曲库选中的歌曲";
        songs.setAdapter(UiTheme.spinnerAdapter(activity, items));
        UiTheme.spinner(songs);
        pickCard.addView(songs);

        sourceLine = caption("");
        pickCard.addView(sourceLine);

        customName = new EditText(activity);
        customName.setSingleLine(true);
        customName.setHint("自定义曲名（仅显示与另存建议，不参与缓存路径）");
        UiTheme.input(customName);
        pickCard.addView(customName);

        customUrl = new EditText(activity);
        customUrl.setSingleLine(true);
        customUrl.setHint("https://…/song.mid（只接受 HTTPS 的 .mid 直链）");
        UiTheme.input(customUrl);
        pickCard.addView(customUrl);
        customName.setText(activity.getSharedPreferences("online_scores",0).getString("name",""));
        customUrl.setText(activity.getSharedPreferences("online_scores",0).getString("url",""));

        customHint = caption("自定义条目不固定 SHA-256，但核心仍会严格解析 SMF 并执行大小/事件上限；"
                + "本面板只接受 .mid/.midi 直链，不下载网页、PDF、MP3，也不做音频转谱。");
        pickCard.addView(customHint);
        addCard(pickCard);

        LinearLayout fetchCard=card();
        fetchCard.addView(section("获取 MIDI"));
        download = makeButton("下载 MIDI", new Runnable() { public void run() { startDownload(); } });
        UiTheme.button(download, UiTheme.Style.PRIMARY);
        loadCache = makeButton("读取已下载缓存", new Runnable() { public void run() { startLoadCache(); } });
        UiTheme.button(loadCache, UiTheme.Style.SECONDARY);
        cancel = makeButton("取消", new Runnable() { public void run() { cancelTask(); } });
        UiTheme.button(cancel, UiTheme.Style.GHOST);
        fetchCard.addView(download,new LinearLayout.LayoutParams(-1,-2));
        LinearLayout fetchRow=row();
        fetchRow.addView(loadCache,weighted());fetchRow.addView(cancel,weighted());
        fetchCard.addView(fetchRow);

        progress = new ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal);
        progress.setMax(100);
        progress.setProgress(0);
        UiTheme.progress(progress);
        LinearLayout.LayoutParams progLp=new LinearLayout.LayoutParams(-1,-2);progLp.topMargin=dp(10);
        fetchCard.addView(progress,progLp);

        progressText = caption("进度条只表示手机下载文件的进度，与 FPGA 上传无关。");
        fetchCard.addView(progressText);
        addCard(fetchCard);

        LinearLayout resultCard=card();
        resultCard.addView(section("结果"));
        resultLine = body("尚无结果：请先下载或读取缓存。");
        resultCard.addView(resultLine);

        status = caption("选择曲目后点「下载 MIDI」（真实联网）或「读取已下载缓存」（离线）。初始化不会自动联网。");
        resultCard.addView(status);

        loadButton = makeButton("载入到曲谱区", new Runnable() { public void run() { loadToScorePanel(); } });
        UiTheme.button(loadButton, UiTheme.Style.PRIMARY);
        saveButton = makeButton("另存 MIDI 到手机", new Runnable() { public void run() { startSave(); } });
        UiTheme.button(saveButton, UiTheme.Style.SECONDARY);
        pageButton = makeButton("浏览来源网页", new Runnable() { public void run() { openSourcePage(); } });
        UiTheme.button(pageButton, UiTheme.Style.GHOST);
        resultCard.addView(loadButton,new LinearLayout.LayoutParams(-1,-2));
        LinearLayout resultRow=row();
        resultRow.addView(saveButton,weighted());resultRow.addView(pageButton,weighted());
        LinearLayout.LayoutParams rowLp=new LinearLayout.LayoutParams(-1,-2);rowLp.topMargin=dp(10);
        resultCard.addView(resultRow,rowLp);

        resultCard.addView(caption("缓存放在应用私有目录 online-midi：下载成功后保留，重启 APP 仍可离线读取；卸载 APP 会清除。"
                + "另存用系统文件选择器（可存到 Download 目录），不申请存储权限；取消保存不会改动任何文件。"));
        addCard(resultCard);

        // 监听器最后挂：此时所有 final 字段都已在构造器里直接赋值。
        songs.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                if (closed) return;
                // A posted Spinner callback after Choose-and-download must not clear that task/result.
                if(position==REMOTE_INDEX){updateEntryUi();refresh();return;}
                dropResult();
                updateEntryUi();
                if (isCustomSelected()) {
                    setStatus("自定义条目：请填写曲名与 HTTPS 直链，再点「下载 MIDI」（不会自动联网）。");
                } else {
                    setStatus("已选择：" + selectedEntry().name
                            + "。点「下载 MIDI」真实联网，或点「读取已下载缓存」离线打开；本面板不会自动联网。");
                }
                refresh();
            }
            public void onNothingSelected(AdapterView<?> parent) { }
        });

        final TextWatcher targetWatcher = new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int start, int count, int after) { }
            public void onTextChanged(CharSequence s, int start, int before, int count) { }
            public void afterTextChanged(Editable s) {
                if (closed || result == null) return;
                // 网址变了：旧结果不能当成新曲继续载入/另存。
                dropResult();
                setStatus("曲名或网址已改动，请重新下载或读取缓存。");
                refresh();
            }
        };
        customUrl.addTextChangedListener(targetWatcher);
        customName.addTextChangedListener(targetWatcher);

        refresh();
    }

    // ------------------------------------------------------------ 对外接口

    public boolean canSelectCatalog(){return !closed&&!busy&&!saving;}
    public boolean selectFromCatalog(ScoreCatalog.Entry entry){
        if(!canSelectCatalog()||entry==null)return false;
        remoteEntry=new Entry(entry.name+" · "+entry.composer,entry.name,entry.url,null,entry.page,entry.license);
        activity.getSharedPreferences("online_scores",0).edit().putString("remote_label",remoteEntry.label).putString("remote_name",entry.name).putString("remote_url",entry.url).putString("remote_page",entry.page).putString("remote_license",entry.license).apply();
        songs.setSelection(REMOTE_INDEX);dropResult();updateEntryUi();startDownload();return true;
    }

    /** 重新计算按钮可用状态。只读 Host.canLoad()，不联网、不下载、不载入。 */
    public void refresh() {
        final boolean idle = !closed && !busy && !saving;
        final boolean custom = isCustomSelected();
        final boolean haveResult = !closed && hasResult();
        songs.setEnabled(idle);
        download.setEnabled(idle);
        loadCache.setEnabled(idle);
        customName.setEnabled(idle && custom);
        customUrl.setEnabled(idle && custom);
        cancel.setEnabled(!closed && busy);
        loadButton.setEnabled(idle && haveResult && canLoad());
        saveButton.setEnabled(idle && haveResult);
        pageButton.setEnabled(idle && pageUrl() != null);
        updateEntryUi();
    }

    /** 只认自己的请求码；其他请求码返回 false，交回 Activity 自己处理。 */
    public boolean activityResult(int request, int result, Intent data) {
        if (request != EXPORT_MIDI) return false;
        if (closed) return true;
        final byte[] bytes = pendingSaveBytes;
        final String name = pendingSaveName;
        pendingSaveBytes = null;
        pendingSaveName = null;
        final Uri uri = (result == Activity.RESULT_OK && data != null) ? data.getData() : null;
        if (uri == null) {
            setStatus("已取消另存：没有写入任何文件，缓存与曲谱区都没有改动。");
            refresh();
            return true;
        }
        if (bytes == null || bytes.length == 0) {
            setStatus("这次另存的内容已失效（结果被替换或面板已重建），未写入任何文件。");
            refresh();
            return true;
        }
        final String fileName = fileNameBase(name) + ".mid";
        final int token = ++saveEpoch;
        saving = true;
        setStatus("正在写入 " + fileName + " …（后台线程写 SAF，不申请存储权限）");
        refresh();
        worker.execute(new Runnable() { public void run() {
            String error = null;
            try (OutputStream out = activity.getContentResolver().openOutputStream(uri, "wt")) {
                if (out == null) throw new IOException("系统未提供输出流");
                out.write(bytes);
                out.flush();
            } catch (Exception ex) {
                error = describe(ex);
            }
            final String failure = error;
            main.post(new Runnable() { public void run() {
                if (closed || saveEpoch != token) return;
                saving = false;
                if (failure == null) {
                    setStatus("已另存 " + fileName + "（" + size(bytes.length) + "）。缓存仍保留，可继续离线读取。");
                    host.log("在线曲库：另存成功 " + fileName);
                } else {
                    setStatus("另存失败：" + failure + "；缓存与曲谱区都没有改动。");
                    host.log("在线曲库：另存失败 " + failure);
                }
                refresh();
            }});
        }});
        return true;
    }

    /** 关闭面板：取消网络、移除 Handler 任务、停止 Executor、让过期回调全部作废；不动 Activity、不动蓝牙。 */
    public void close() {
        if (closed) return;
        closed = true;
        epoch++;           // 在途下载/读取的回调整体作废
        saveEpoch++;       // 在途另存的回调作废
        final ScoreDownload.CancelToken token = cancelToken;
        cancelToken = null;
        if (token != null) {
            try { token.cancel(); } catch (RuntimeException ignore) { }
        }
        busy = false;
        saving = false;
        pendingSaveBytes = null;
        pendingSaveName = null;
        main.removeCallbacksAndMessages(null);
        worker.shutdownNow();
    }

    // ------------------------------------------------------------ 动作

    private void startDownload() {
        if (closed || busy || saving) return;
        final String[] target = resolveTarget();
        if (target == null) return;
        final String name = target[0];
        final String url = target[1];
        final String sha256 = target[2];
        final int token = ++epoch;
        final ScoreDownload.CancelToken request = new ScoreDownload.CancelToken();
        cancelToken = request;
        busy = true;
        dropResult();
        setStatus("正在下载 " + name + "：每次都真实访问网络，不用本地缓存顶替；不会打开浏览器。");
        progress.setIndeterminate(true);
        progressText.setText("正在连接并下载（只表示手机下载，与 FPGA 上传无关）…");
        host.log("在线曲库：开始下载 " + name);
        refresh();
        worker.execute(new Runnable() { public void run() {
            ensureCacheDir();
            try {
                final ScoreDownload.Result r = ScoreDownload.download(name, url, sha256, cacheDir, request, progressReporter(token));
                postSuccess(token, r, name, false);
            } catch (Exception ex) {
                postFailure(token, name, describe(ex), false);
            } catch (Throwable t) {
                // 兜底：核心若抛出非 Exception（或声明更宽的 throws），也必须解锁界面而不是卡在下载中。
                postFailure(token, name, describe(t), false);
            }
        }});
    }

    private void startLoadCache() {
        if (closed || busy || saving) return;
        final String[] target = resolveTarget();
        if (target == null) return;
        final String name = target[0];
        final String url = target[1];
        final String sha256 = target[2];
        final int token = ++epoch;
        cancelToken = null;   // loadCached 没有 CancelToken：取消只放弃等待，不删缓存
        busy = true;
        dropResult();
        setStatus("正在读取本地缓存（离线，不联网）：" + name);
        progress.setIndeterminate(true);
        progressText.setText("离线读取中（不访问网络）…");
        host.log("在线曲库：读取离线缓存 " + name);
        refresh();
        worker.execute(new Runnable() { public void run() {
            try {
                final ScoreDownload.Result r = ScoreDownload.loadCached(name, url, sha256, cacheDir);
                postSuccess(token, r, name, true);
            } catch (Exception ex) {
                // loadCached 的 IOException（无缓存/缓存损坏）也走这里：只报错，不联网、不删缓存。
                postFailure(token, name, describe(ex), true);
            } catch (Throwable t) {
                postFailure(token, name, describe(t), true);
            }
        }});
    }

    private void cancelTask() {
        if (closed || !busy) return;
        epoch++;                       // 旧回调立刻作废
        final ScoreDownload.CancelToken token = cancelToken;
        cancelToken = null;
        busy = false;
        if (token != null) {
            try { token.cancel(); } catch (RuntimeException ignore) { }
        }
        progress.setIndeterminate(false);
        progress.setProgress(0);
        if (token != null) {
            progressText.setText("已取消下载：进度条只表示手机下载，取消后不再更新界面。");
            setStatus("已取消本次网络请求；之前完整下载过的缓存仍保留，可用「读取已下载缓存」离线载入。");
            host.log("在线曲库：用户取消下载");
        } else {
            progressText.setText("已放弃等待这次离线读取的结果。");
            setStatus("已停止等待本地读取结果；缓存内容不受影响。");
            host.log("在线曲库：用户放弃离线读取");
        }
        refresh();
    }

    private void loadToScorePanel() {
        if (closed || busy || saving) return;
        final byte[] bytes = currentBytes();
        if (bytes == null || bytes.length == 0) {
            setStatus("还没有可用结果，请先「下载 MIDI」或「读取已下载缓存」。");
            refresh();
            return;
        }
        if (!canLoad()) {
            setStatus("曲谱区当前不能载入（可能正在上传/演奏或尚未就绪）；已刷新可用状态。");
            refresh();
            return;
        }
        final String name = resultName == null || resultName.isEmpty() ? "在线曲目" : resultName;
        boolean ok = false;
        try {
            ok = host.load(name, bytes);
        } catch (RuntimeException ex) {
            setStatus("载入到曲谱区失败：" + ex.getMessage() + "；未发送任何蓝牙帧。");
            host.log("在线曲库：载入异常 " + ex);
            refresh();
            return;
        }
        setStatus(ok
                ? "已把 " + name + " 交给曲谱区解析；上传与演奏请在曲谱区完成，本面板不发送蓝牙，也不自动上传。"
                : "曲谱区拒绝载入（可能正忙或曲谱不合法），未发送任何蓝牙帧。");
        host.log("在线曲库：载入到曲谱区 " + name + " → " + ok);
        refresh();
    }

    private void startSave() {
        if (closed || busy || saving) return;
        final byte[] bytes = currentBytes();
        if (bytes == null || bytes.length == 0) {
            setStatus("还没有可另存的结果，请先下载或读取缓存。");
            return;
        }
        final String name = resultName == null || resultName.isEmpty() ? "在线曲目" : resultName;
        pendingSaveBytes = bytes.clone();
        pendingSaveName = name;
        final Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("audio/midi");
        intent.putExtra(Intent.EXTRA_TITLE, fileNameBase(name) + ".mid");
        try {
            activity.startActivityForResult(intent, EXPORT_MIDI);
            setStatus("请在系统文件选择器里选择保存位置（例如 Download 目录）；取消不会改动任何文件。");
        } catch (RuntimeException ex) {
            pendingSaveBytes = null;
            pendingSaveName = null;
            setStatus("无法打开保存对话框：" + ex.getMessage());
            host.log("在线曲库：ACTION_CREATE_DOCUMENT 失败 " + ex);
        }
    }

    private void openSourcePage() {
        if (closed) return;
        final String url = pageUrl();
        if (url == null) {
            setStatus("自定义直链没有内置来源页面；请自行确认来源与版权。");
            return;
        }
        final Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
        try {
            activity.startActivity(intent);
            setStatus("已打开曲目来源和许可详情。");
        } catch (RuntimeException ex) {
            setStatus("没有可用的浏览器打开来源网页：" + ex.getMessage());
            host.log("在线曲库：打开来源网页失败 " + ex);
        }
    }

    // ------------------------------------------------------------ 结果与回调

    private void postSuccess(final int token, final ScoreDownload.Result r, final String name, final boolean fromCache) {
        postIfCurrent(token, new Runnable() { public void run() {
            busy = false;
            cancelToken = null;
            progress.setIndeterminate(false);
            progress.setProgress(0);
            if (r == null || r.bytes == null || r.bytes.length == 0) {
                progressText.setText("未取得可用字节，进度已重置。");
                setStatus((fromCache ? "读取缓存失败：" : "下载失败：") + "核心没有返回可用的 MIDI 字节（可能校验或解析未通过）。");
                host.log("在线曲库：无可用字节 " + name);
            } else {
                progressText.setText(fromCache
                        ? "已从本地缓存读取，未联网（进度只表示手机下载）。"
                        : "下载完成：文件已保存在手机缓存（进度只表示手机下载，与 FPGA 上传无关）。");
                accept(r, name, fromCache);
            }
            refresh();
        }});
    }

    private void postFailure(final int token, final String name, final String reason, final boolean fromCache) {
        postIfCurrent(token, new Runnable() { public void run() {
            busy = false;
            cancelToken = null;
            progress.setIndeterminate(false);
            progress.setProgress(0);
            progressText.setText((fromCache ? "离线读取失败" : "下载失败") + "，进度已重置（进度只表示手机下载）。");
            setStatus(fromCache
                    ? "读取缓存失败：" + reason + "。本地可能还没有完整缓存，请先联网「下载 MIDI」。"
                    : "下载失败：" + reason + "。没有改动已有缓存；请检查网络后重试（失败也可能是 SHA-256 校验或 SMF 解析未通过）。");
            host.log("在线曲库：" + (fromCache ? "读取缓存失败 " : "下载失败 ") + name + "：" + reason);
            refresh();
        }});
    }

    /** 主线程回调闸门：面板已关闭或已有更新任务时，旧回调直接丢弃。 */
    private void postIfCurrent(final int token, final Runnable action) {
        main.post(new Runnable() { public void run() {
            if (closed || epoch != token) return;
            action.run();
        }});
    }

    /** 手机下载进度回调；进度条只表示手机下载，与 FPGA 上传无关。 */
    private ScoreDownload.Progress progressReporter(final int token) {
        return new ScoreDownload.Progress() {
            private int lastPercent = -1;
            private long lastReported = -1;
            public void update(final int received, final long total) {
                final int percent = total > 0 ? (int) Math.min(100L, (long) received * 100L / total) : -1;
                if (percent >= 0) {
                    if (percent == lastPercent) return;
                    lastPercent = percent;
                } else {
                    if (received - lastReported < 65536L) return;   // 未知总长时按 ~64 KiB 节流
                    lastReported = received;
                }
                postIfCurrent(token, new Runnable() { public void run() {
                    if (percent >= 0) {
                        progress.setIndeterminate(false);
                        progress.setProgress(percent);
                        progressText.setText("下载进度 " + percent + "%（" + size(received) + " / " + size(total)
                                + "）——只表示手机下载，与 FPGA 上传无关。");
                    } else {
                        progress.setIndeterminate(true);
                        progressText.setText("已下载 " + size(received) + "（服务器未给出总长度）——只表示手机下载。");
                    }
                }});
            }
        };
    }

    private void accept(final ScoreDownload.Result r, final String name, final boolean fromCache) {
        result = r;
        resultName = name;
        final Score score = r.score;
        final StringBuilder text = new StringBuilder();
        text.append(fromCache ? "离线缓存：" : "下载完成：").append(name).append('\n');
        if (score != null) {
            text.append(score.events == null ? 0 : score.events.size()).append(" 事件；")
                    .append(String.format(Locale.US, "%.1f", score.durationMs / 1000.0)).append(" 秒；峰值复音 ")
                    .append(score.peakVoices).append("；音域 MIDI ").append(score.minNote).append("..").append(score.maxNote)
                    .append('\n');
        } else {
            text.append("核心未返回解析统计；\n");
        }
        text.append("文件 ").append(r.bytes.length).append(" 字节（").append(size(r.bytes.length)).append("）")
                .append(r.file != null ? "；已保留本地缓存，可离线读取" : "；核心未报告缓存文件");
        resultLine.setText(text.toString());
        setStatus("结果已就绪。点「载入到曲谱区」只把曲谱交给曲谱区解析（不发送蓝牙）；点「另存 MIDI 到手机」用系统文件选择器保存。");
        host.log("在线曲库：" + (fromCache ? "离线读取成功 " : "下载成功 ") + name + "（" + r.bytes.length + " 字节）");
    }

    // ------------------------------------------------------------ 状态与工具

    private void dropResult() {
        result = null;
        resultName = null;
        resultLine.setText("尚无结果：请先下载或读取缓存。");
        progress.setIndeterminate(false);
        progress.setProgress(0);
    }

    private int selectedIndex() {
        final int position = songs.getSelectedItemPosition();
        return position < 0 || position > CUSTOM_INDEX ? 0 : position;
    }

    private boolean isCustomSelected() {
        return selectedIndex() == CUSTOM_INDEX;
    }

    /** 内置条目返回 Entry，自定义条目返回 null。 */
    private Entry selectedEntry() {
        final int index = selectedIndex();
        return index==CUSTOM_INDEX?null:index==REMOTE_INDEX?remoteEntry:LIBRARY[index];
    }

    private String pageUrl() {
        final Entry entry = selectedEntry();
        return entry == null ? null : entry.page;
    }

    /** {显示名, 直链, 期望SHA-256或null}；不合法时在界面上说明原因并返回 null。 */
    private String[] resolveTarget() {
        final Entry entry = selectedEntry();
        if (entry != null) return new String[]{entry.name, entry.url, entry.sha256};
        if(selectedIndex()==REMOTE_INDEX){setStatus("请先在上方在线曲库选择歌曲。");return null;}
        final String raw = customUrl.getText().toString().trim();
        final String problem = urlProblem(raw);
        if (problem != null) {
            setStatus("自定义地址不可用：" + problem);
            return null;
        }
        final String name=customNameText();
        activity.getSharedPreferences("online_scores",0).edit().putString("name",name).putString("url",raw).apply();
        return new String[]{name, raw, null};
    }

    private void updateEntryUi() {
        final boolean custom = isCustomSelected();
        final int visibility = custom ? VISIBLE : GONE;
        customName.setVisibility(visibility);
        customUrl.setVisibility(visibility);
        customHint.setVisibility(visibility);
        final Entry entry = selectedEntry();
        sourceLine.setText(entry == null
                ? (custom ? "来源：自定义 HTTPS MIDI 直链。" : "尚未选择在线曲目，请在上方曲库选择。")
                : "来源：Mutopia Project · "+entry.label+"\n"+entry.license+" · " + entry.page);
    }

    private boolean canLoad() {
        if (host == null) return false;
        try {
            return host.canLoad();
        } catch (RuntimeException ex) {
            return false;
        }
    }

    private boolean hasResult() {
        return result != null && result.bytes != null && result.bytes.length > 0;
    }

    private byte[] currentBytes() {
        return result == null ? null : result.bytes;
    }

    private void setStatus(String message) {
        status.setText(message);
    }

    private int dp(int v){return Math.round(v*getResources().getDisplayMetrics().density);}
    private LinearLayout card(){return UiTheme.card(activity);}
    private void addCard(View v){addView(v);UiTheme.gap(v);}
    private TextView section(String t){return UiTheme.section(activity,t);}
    private TextView caption(String t){return UiTheme.caption(activity,t);}
    private TextView body(String t){return UiTheme.body(activity,t);}
    private LinearLayout row(){LinearLayout r=new LinearLayout(activity);r.setOrientation(HORIZONTAL);return r;}
    private LinearLayout.LayoutParams weighted(){LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(0,-2,1f);p.setMarginStart(dp(4));p.setMarginEnd(dp(4));return p;}
    private Button makeButton(String label, final Runnable action) {
        final Button b = new Button(activity);
        b.setText(label);
        b.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { action.run(); } });
        return b;
    }
    private LinearLayout buttonRow(Button... buttons) {
        final LinearLayout r = new LinearLayout(activity);
        r.setOrientation(HORIZONTAL);
        for (int i = 0; i < buttons.length; i++) {
            r.addView(buttons[i], weighted());
        }
        return r;
    }

    /** 自检：只保证缓存目录存在；缓存内容、命名与校验全部由 ScoreDownload 负责。 */
    private void ensureCacheDir() {
        try {
            if (!cacheDir.isDirectory()) cacheDir.mkdirs();
        } catch (RuntimeException ignore) { }
    }

    /** 只接受 HTTPS 的 .mid/.midi 直链；是否为合法 SMF 由核心严格解析。 */
    private static String urlProblem(String raw) {
        if (raw == null || raw.isEmpty()) return "请先填写 HTTPS 直链";
        if (raw.length() > 2048) return "地址过长";
        if (!raw.regionMatches(true, 0, "https://", 0, 8)) return "只接受 https:// 开头的直链";
        final Uri uri;
        try {
            uri = Uri.parse(raw);
        } catch (RuntimeException ex) {
            return "地址无法解析";
        }
        if (uri == null) return "地址无法解析";
        final String hostName = uri.getHost();
        if (hostName == null || hostName.isEmpty()) return "地址缺少主机名";
        final String path = uri.getPath();
        if (path == null || !(path.toLowerCase(Locale.US).endsWith(".mid") || path.toLowerCase(Locale.US).endsWith(".midi"))) {
            return "只接受 .mid / .midi 直链，不下载网页、PDF 或 MP3";
        }
        try { ScoreDownload.httpsUrl(raw); } catch (IOException ex) { return ex.getMessage(); }
        return null;
    }

    /** 自定义曲名：优先用输入框，其次从直链末段推断；仅作显示，不参与缓存路径。 */
    private String customNameText() {
        final String typed = cleanName(customName.getText().toString());
        if (!typed.isEmpty()) return typed;
        try {
            final String path = Uri.parse(customUrl.getText().toString().trim()).getPath();
            if (path != null) {
                final int slash = path.lastIndexOf('/');
                String last = slash >= 0 ? path.substring(slash + 1) : path;
                final int dot = last.lastIndexOf('.');
                if (dot > 0) last = last.substring(0, dot);
                last = cleanName(last);
                if (!last.isEmpty()) return last;
            }
        } catch (RuntimeException ignore) { }
        return "自定义曲目";
    }

    private static String cleanName(String raw) {
        final String text = raw == null ? "" : raw.trim();
        final StringBuilder sb = new StringBuilder();
        for (int i = 0; i < text.length() && sb.length() < 60; i++) {
            final char c = text.charAt(i);
            if (c < ' ' || c == 0x7f || c == '/' || c == '\\') continue;
            sb.append(c);
        }
        return sb.toString().trim();
    }

    /** 另存建议文件名；名称本来就不用于缓存路径，这里再去掉文件名非法字符。 */
    private static String fileNameBase(String name) {
        final String base = cleanName(name);
        final StringBuilder sb = new StringBuilder();
        for (int i = 0; i < base.length(); i++) {
            final char c = base.charAt(i);
            if (c == ':' || c == '*' || c == '?' || c == '"' || c == '<' || c == '>' || c == '|') continue;
            sb.append(c);
        }
        final String text = sb.toString().trim();
        return text.isEmpty() ? "online_score" : text;
    }

    private static String size(long bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024L * 1024L) return String.format(Locale.US, "%.1f KiB", bytes / 1024.0);
        return String.format(Locale.US, "%.2f MiB", bytes / (1024.0 * 1024.0));
    }

    private static String describe(Throwable ex) {
        if (ex == null) return "未知错误";
        final String message = ex.getMessage();
        final String type = ex.getClass().getSimpleName();
        if (message == null || message.trim().isEmpty()) return type;
        return type + "：" + message;
    }
}
