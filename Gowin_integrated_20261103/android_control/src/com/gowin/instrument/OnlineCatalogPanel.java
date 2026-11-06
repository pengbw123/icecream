package com.gowin.instrument;

import android.app.Activity;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.inputmethod.InputMethodManager;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.Spinner;
import android.widget.TextView;

import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * 「在线搜索曲库」面板：在 APP 内直接联网搜索 Mutopia 完整曲库，用户不需要知道也不需要填写网址。
 *
 * 边界（与 Root 的分工）：
 *  - 联网与 HTML 解析全部在 ScoreCatalog.fetch(...)；本组件只调用它，不含任何网络/解析实现。
 *  - 本组件不下载 MIDI、不知道下载目录、不写文件；点「选择并下载」只调用 Host.select(entry)，
 *    由 Root 负责真实下载、容量检查与提示。
 *  - 不嵌 WebView、不打开浏览器、不需要填写网址。
 *  - 构造器不联网、不自动下载、不发蓝牙；只有用户点「联网浏览 / 搜索」才发起请求。
 *  - 请求在 singleThreadExecutor，所有界面更新回主线程 Handler；generation + CancelToken 丢弃迟到回调。
 *  - 下载 Metadata 不阻塞曲谱上传：busy 只锁本面板，host.canSelect() 只控制「选择并下载」是否可用。
 *  - 不假定 Entry 已满足 FPGA 容量：结果统一提示下载后检查事件数/复音，超限由 Root 说明原因。
 */
public final class OnlineCatalogPanel extends LinearLayout {

    public interface Host {
        /** 曲谱区/上传当前是否允许接受一次新的下载；false 时列表只展示，不能点「选择并下载」。 */
        boolean canSelect();
        /** 把选中的曲库条目录交给 Root 开始下载：返回 true 表示已接受并开始下载。 */
        boolean select(ScoreCatalog.Entry entry);
        void log(String message);
    }

    private static final String[] CATEGORIES = {"钢琴（推荐）", "全部乐器"};
    private static final int MAX_ITEMS = 10;

    private final Activity activity;
    private final Host host;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();

    private final EditText keyword;
    private final Spinner category;
    private final Button browse;
    private final Button prev;
    private final Button next;
    private final Button cancel;
    private final TextView pageText;
    private final TextView status;
    private final LinearLayout list;

    private boolean loading;      // 是否已有在途请求
    private boolean closed;       // close() 之后一律不再回调
    private int generation;       // 请求代次：取消/关闭/新请求都让旧回调失效
    private ScoreDownload.CancelToken token;

    private ScoreCatalog.Page page;   // 最近一次成功的页（失败时保留）
    private String pageKeyword;       // 该页使用的查询关键词（快照，翻页只认它）
    private boolean pagePiano;        // 该页使用的乐器分类（快照）
    private List<ScoreCatalog.Entry> shown;   // 当前列表里已显示的条目（Selection 状态用）

    public OnlineCatalogPanel(Activity activity, Host host) {
        super(activity);
        this.activity = activity;
        this.host = host;
        setOrientation(VERTICAL);
        setPadding(dp(8), dp(4), dp(8), dp(4));

        LinearLayout searchCard=UiTheme.card(activity);
        searchCard.addView(UiTheme.section(activity,"在线搜索曲库"));
        searchCard.addView(UiTheme.caption(activity,"搜索英文标题或作者，常见中文曲名自动对应。选曲下载到手机后，载入并上传到乐器即可开始 LED 灯光指引。"));

        keyword = new EditText(activity);
        keyword.setSingleLine(true);
        keyword.setSaveEnabled(false);
        keyword.setHint("搜索：Elise / Bach / Minuet，或 致爱丽丝 / 巴赫 / 小步舞曲");
        UiTheme.input(keyword);
        searchCard.addView(keyword, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        searchCard.addView(UiTheme.caption(activity,"分类"));

        category = new Spinner(activity);
        category.setAdapter(UiTheme.spinnerAdapter(activity, CATEGORIES));
        UiTheme.spinner(category);
        searchCard.addView(category, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        browse = new Button(activity);
        browse.setText("联网浏览 / 搜索");
        UiTheme.button(browse, UiTheme.Style.PRIMARY);
        prev = new Button(activity);
        prev.setText("上一页");
        UiTheme.button(prev, UiTheme.Style.SECONDARY);
        next = new Button(activity);
        next.setText("下一页");
        UiTheme.button(next, UiTheme.Style.SECONDARY);
        cancel = new Button(activity);
        cancel.setText("取消");
        UiTheme.button(cancel, UiTheme.Style.GHOST);
        final LinearLayout actions = new LinearLayout(activity);
        actions.setOrientation(HORIZONTAL);
        actions.addView(browse, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 3f));
        actions.addView(cancel, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        LinearLayout.LayoutParams actionsLp=new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        actionsLp.topMargin=dp(10);
        searchCard.addView(actions,actionsLp);
        final LinearLayout pages = new LinearLayout(activity);
        pages.setOrientation(HORIZONTAL);
        pages.addView(prev,new LinearLayout.LayoutParams(0,LinearLayout.LayoutParams.WRAP_CONTENT,1f));
        pages.addView(next,new LinearLayout.LayoutParams(0,LinearLayout.LayoutParams.WRAP_CONTENT,1f));
        searchCard.addView(pages);

        pageText = UiTheme.caption(activity,"");
        searchCard.addView(pageText);

        status = UiTheme.caption(activity,"");
        status.setTextIsSelectable(true);
        searchCard.addView(status);
        addView(searchCard);UiTheme.gap(searchCard);

        list = new LinearLayout(activity);
        list.setOrientation(VERTICAL);
        addView(list, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        LinearLayout footCard=UiTheme.card(activity);
        footCard.addView(UiTheme.caption(activity,"每页最多10条。下载后可解析最多8192事件；上传时按检测到的板端容量和声部数检查，旧板保持2048事件、8声部上限。"));
        addView(footCard);UiTheme.gap(footCard);

        // 监听器在全部 final 控件构造器赋值之后才挂。
        browse.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { startSearch(); }
        });
        prev.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { startOffset(currentOffset() - MAX_ITEMS); }
        });
        next.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { startOffset(currentOffset() + MAX_ITEMS); }
        });
        cancel.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { cancelLoad(); }
        });
        category.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                if (closed || loading) return;
                setStatus(CATEGORIES[selectedCategory()].equals(CATEGORIES[0])
                        ? "已选择「钢琴（推荐）」：搜索更精准；点「联网浏览 / 搜索」再联网。"
                        : "已选择「全部乐器」：覆盖整个曲库；点「联网浏览 / 搜索」再联网。旧页面保留，可继续翻页。");
                refresh();
            }
            public void onNothingSelected(AdapterView<?> parent) { }
        });

        showPage();
        refresh();
    }

    // ------------------------------------------------------------ 对外接口

    /** 重新计算按钮可用状态；只读 Host.canSelect()，不联网、不下载。Root 可随时调用。 */
    public void refresh() {
        if (!onMainThread()) {
            main.post(new Runnable() { public void run() { refresh(); } });
            return;
        }
        if (closed) return;
        final boolean idle = !loading;
        final boolean canSelect = host != null && shown != null && !shown.isEmpty() && hostCanSelect();
        keyword.setEnabled(idle);
        category.setEnabled(idle);
        browse.setEnabled(idle);
        cancel.setEnabled(!idle);
        final boolean first = page == null || page.offset <= 0;
        prev.setEnabled(idle && !first);
        next.setEnabled(idle && hasNext());
        for (int i = 0; i < list.getChildCount(); i++) {
            final View child = list.getChildAt(i);
            if (child instanceof Button) child.setEnabled(idle && canSelect);
        }
    }

    /** 取消在途请求、停止 worker、移除主线程回调；迟到结果全部忽略。不改 Activity、不发蓝牙。 */
    public void close() {
        if (closed) return;
        closed = true;
        generation++;
        final ScoreDownload.CancelToken current = token;
        token = null;
        loading = false;
        if (current != null) {
            try { current.cancel(); } catch (RuntimeException ignore) { }
        }
        main.removeCallbacksAndMessages(null);
        worker.shutdownNow();
    }

    // ------------------------------------------------------------ 动作

    private void startSearch() {
        if (closed || loading) return;
        hideKeyboard();
        load(keyword.getText().toString(), selectedCategory() == 0, 0);
    }

    private void startOffset(int offset) {
        if (closed || loading) return;
        if (page == null) { setStatus("还没有成功加载过曲库页，请先点「联网浏览 / 搜索」。"); refresh(); return; }
        if (offset < 0 || offset % MAX_ITEMS != 0) { setStatus("页码无效，已忽略这次翻页。"); refresh(); return; }
        // 翻页沿用当前成功页的关键词/分类快照，不读取可能已被改动的搜索框。
        load(pageKeyword == null ? "" : pageKeyword, pagePiano, offset);
    }

    private void load(String rawKeyword, boolean piano, int offset) {
        if (closed || loading) return;
        final String key = rawKeyword == null ? "" : rawKeyword.trim();
        final int request = ++generation;
        final ScoreDownload.CancelToken requestToken = new ScoreDownload.CancelToken();
        token = requestToken;
        loading = true;
        setStatus("正在联网加载 "
                + (key.isEmpty() ? "全部曲目" : "「" + shortText(key, 40) + "」")
                + "（第 " + (offset / MAX_ITEMS + 1) + " 页，分类 " + CATEGORIES[piano ? 0 : 1]
                + "），可点「取消」停止。");
        refresh();
        worker.execute(new Runnable() {
            public void run() {
                ScoreCatalog.Page result = null;
                String error = null;
                try {
                    result = ScoreCatalog.fetch(key, piano, offset, requestToken);
                } catch (Exception ex) {
                    error = describe(ex);
                } catch (Throwable t) {
                    // 兜底：核心若抛出非 Exception，也必须解锁界面而不是卡在加载中。
                    error = describe(t);
                }
                final ScoreCatalog.Page loaded = result;
                final String failure = error;
                main.post(new Runnable() {
                    public void run() {
                        if (closed || generation != request) return;
                        loading = false;
                        token = null;
                        final List<ScoreCatalog.Entry> entries = loaded == null ? null : loaded.entries;
                        if (loaded == null || entries == null) {
                            // 失败：保留上一次成功的页与它的查询快照，界面不空转、不锁死。
                            setStatus("加载失败：" + failure + networkHint(failure) + "；已保留上一次成功的结果，可重试或翻回旧页。");
                            hostLog("曲库加载失败（" + key + " / offset " + offset + "）：" + failure);
                        } else if (entries.isEmpty()) {
                            page = loaded;
                            pageKeyword = key;
                            pagePiano = piano;
                            shown = entries;
                            renderList(entries);
                            setStatus("未找到匹配曲目：换个关键词，或把分类切到「全部乐器」再搜一次。"
                                    + (loaded.hasNext ? "服务器提示后面还有内容，可点「下一页」继续。" : ""));
                            hostLog("曲库无结果（" + key + " / offset " + offset + "）");
                        } else {
                            page = loaded;
                            pageKeyword = key;
                            pagePiano = piano;
                            shown = entries;
                            renderList(entries);
                            setStatus("已加载 " + entries.size() + " 条（第 " + (offset / MAX_ITEMS + 1) + " 页，分类 "
                                    + CATEGORIES[piano ? 0 : 1] + "）。点「选择并下载」，完成后载入曲谱区。"
                                    + (loaded.hasNext ? "" : "已是最后一页。"));
                            hostLog("曲库加载成功（" + key + " / offset " + offset + "）：" + entries.size() + " 条");
                        }
                        showPage();
                        refresh();
                    }
                });
            }
        });
    }

    private void cancelLoad() {
        if (closed || !loading) return;
        generation++;                 // 在途回调立刻作废
        final ScoreDownload.CancelToken current = token;
        token = null;
        loading = false;
        if (current != null) {
            try { current.cancel(); } catch (RuntimeException ignore) { }
        }
        // 取消只放弃这次请求：旧的成功页与旧查询快照仍然可用，可以继续翻页或重新搜索。
        setStatus("已取消本次联网请求；界面已解锁，上一次成功的结果仍然保留。");
        hostLog("用户取消曲库加载");
        refresh();
    }

    private void renderList(List<ScoreCatalog.Entry> entries) {
        list.removeAllViews();
        if (entries == null || entries.isEmpty()) {
            // 列表为空时下一页仍由服务器 hasNext 决定；按钮可用性在 refresh() 里单独处理。
            final TextView empty = UiTheme.caption(activity, page != null && page.hasNext
                    ? "本页没有可下载条目（未找到）；服务器提示后面还有内容，可点「下一页」。"
                    : "未找到可下载条目；请换关键词或切换分类。");
            list.addView(empty);
            return;
        }
        final boolean canSelect = hostCanSelect();
        for (int i = 0; i < entries.size(); i++) {
            final ScoreCatalog.Entry entry = entries.get(i);
            final Button item = new Button(activity);
            UiTheme.button(item, UiTheme.Style.SECONDARY);
            item.setGravity(android.view.Gravity.START | android.view.Gravity.CENTER_VERTICAL);
            item.setText(itemLabel(entry));
            item.setOnClickListener(new View.OnClickListener() {
                public void onClick(View v) { choose(entry); }
            });
            item.setEnabled(canSelect);   // Host.refresh() → refresh() 会再按最新状态刷新
            LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            lp.bottomMargin=dp(8);
            list.addView(item, lp);
        }
    }

    private void choose(ScoreCatalog.Entry entry) {
        if (closed || entry == null) return;
        if (loading) { setStatus("正在联网加载，请等这一页出来再选曲目。"); refresh(); return; }
        if (!hostCanSelect()) { setStatus("当前不能开始新的下载（可能在下载或上传中），请稍后再点；本次没有改动任何东西。"); refresh(); return; }
        boolean accepted = false;
        try {
            accepted = host.select(entry);
        } catch (RuntimeException ex) {
            setStatus("开始下载时出错：" + describe(ex) + "，请重试。");
            hostLog("选择曲目异常：" + describe(ex));
            refresh();
            return;
        }
        if (accepted) {
            setStatus("正在下载《" + shortText(entry.name, 40) + "》，请在下方查看结果。");
            hostLog("选择并下载：" + entry.name);
        } else {
            setStatus("当前正在下载或保存，请稍后再选择。");
        }
        refresh();
    }

    // ------------------------------------------------------------ 状态与工具

    private void showPage() {
        if (page == null) {
            pageText.setText("尚未加载：点「联网浏览 / 搜索」开始。每页最多 " + MAX_ITEMS + " 条。");
            return;
        }
        final int count = page.entries == null ? 0 : page.entries.size();
        final String range = count == 0 ? "0 条" : "第 " + (page.offset + 1) + "–" + (page.offset + count) + " 条";
        pageText.setText("第 " + (page.offset / MAX_ITEMS + 1) + " 页：" + range
                + "；下一页：" + (hasNext() ? "可用" : "不可用"));
    }

    /** 没有成功页时一律不可翻页；条目为空但服务器 hasNext=true 时仍然允许下一页。 */
    private boolean hasNext() {
        return page != null && page.hasNext;
    }

    private int currentOffset() {
        return page == null ? 0 : page.offset;
    }

    private int selectedCategory() {
        final int position = category.getSelectedItemPosition();
        return position == 1 ? 1 : 0;
    }

    private boolean hostCanSelect() {
        if (host == null) return false;
        try { return host.canSelect(); } catch (RuntimeException ex) { return false; }
    }

    private void hostLog(String message) {
        if (host == null) return;
        try { host.log(message); } catch (RuntimeException ignore) { }
    }

    private void setStatus(String message) {
        status.setText(message);
    }

    private static String itemLabel(ScoreCatalog.Entry entry) {
        final String name = entry.name == null || entry.name.trim().isEmpty() ? "未命名曲目" : entry.name.trim();
        final String composer = entry.composer == null || entry.composer.trim().isEmpty() ? "未知作者" : entry.composer.trim();
        final String instrument = entry.instrument == null || entry.instrument.trim().isEmpty() ? "未知乐器" : entry.instrument.trim();
        final String license = entry.license == null || entry.license.trim().isEmpty() ? "许可未标注" : entry.license.trim();
        return shortText(name, 80) + "\n" + shortText(composer, 50) + " · " + shortText(instrument, 50)
                + "\n" + shortText(license, 60) + "\n选择并下载";
    }

    private static String shortText(String text, int max) {
        if (text == null) return "";
        final String clean = text.replace('\n', ' ').trim();
        return clean.length() <= max ? clean : clean.substring(0, max) + "…";
    }

    private static String networkHint(String failure) {
        final String text = failure == null ? "" : failure.toLowerCase(java.util.Locale.US);
        if (text.contains("unknownhost") || text.contains("connect") || text.contains("socket")
                || text.contains("timeout") || text.contains("network") || text.contains("unreachable")) {
            return "（请检查手机网络后重试）";
        }
        return "";
    }

    private boolean onMainThread() {
        return Looper.myLooper() == Looper.getMainLooper();
    }

    private void hideKeyboard() {
        try {
            final Object service = activity.getSystemService(Activity.INPUT_METHOD_SERVICE);
            if (service instanceof InputMethodManager) {
                ((InputMethodManager) service).hideSoftInputFromWindow(keyword.getWindowToken(), 0);
            }
        } catch (RuntimeException ignore) { }
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private static String describe(Throwable ex) {
        if (ex == null) return "未知错误";
        if (ex instanceof InterruptedIOException) return "请求已取消";
        if (ex instanceof IOException && ex.getMessage() != null && ex.getMessage().contains("取消")) return ex.getMessage();
        final String message = ex.getMessage();
        final String type = ex.getClass().getSimpleName();
        if (message == null || message.trim().isEmpty()) return type;
        return type + "：" + message;
    }
}
