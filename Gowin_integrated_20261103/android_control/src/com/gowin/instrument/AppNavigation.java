package com.gowin.instrument;

import android.app.Activity;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * 四页导航：紧凑页标题、真实蓝牙状态与带图标的底栏。
 * 各页编辑器与传输状态在切换间保持存活；滚动位置、焦点与键盘处理语义保持不变。
 */
final class AppNavigation {
    final LinearLayout shell;
    private final ScrollView scroll;
    private final LinearLayout[] pages = new LinearLayout[4];
    private final Tab[] tabs = new Tab[4];
    private final int[] positions = new int[4];
    private final TextView title;
    private final TextView status;
    private final View statusDot;
    private int selected = -1, revision;
    private final String[] names = {"连接", "曲谱", "音色", "设置"};
    private final String[] titles = {"我的乐器", "曲谱与练习", "音色", "设置"};

    /** pageOfChild[i] 给出 original 第 i 个子视图归属的页码，替代旧的区间切分。 */
    AppNavigation(Activity activity, LinearLayout original, ScrollView scroll, int[] pageOfChild) {
        this.scroll = scroll;
        int count = original.getChildCount();
        View[] views = new View[count];
        for (int i = 0; i < count; i++) views[i] = original.getChildAt(i);
        original.removeAllViews();
        original.setPadding(0, 0, 0, 0);
        final LinearLayout body = original;
        scroll.setBackgroundColor(UiTheme.BG);
        scroll.addOnLayoutChangeListener(new View.OnLayoutChangeListener() {
            public void onLayoutChange(View v, int l, int t, int r, int b, int ol, int ot, int or, int ob) {
                if (r - l == or - ol) return;
                body.setLayoutParams(new FrameLayout.LayoutParams(Math.min(r - l, UiTheme.dp(body, 720)), -2, Gravity.CENTER_HORIZONTAL));
            }
        });
        for (int i = 0; i < pages.length; i++) {
            pages[i] = new LinearLayout(activity);
            pages[i].setOrientation(LinearLayout.VERTICAL);
            pages[i].setPadding(UiTheme.dp(original, 18), UiTheme.dp(original, 4), UiTheme.dp(original, 18), UiTheme.dp(original, 24));
            original.addView(pages[i], new LinearLayout.LayoutParams(-1, -2));
        }
        for (int i = 0; i < count; i++) {
            int page = i < pageOfChild.length ? pageOfChild[i] : 0;
            add(Math.max(0, Math.min(pages.length - 1, page)), views[i]);
        }

        shell = new LinearLayout(activity);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setFocusableInTouchMode(true);
        shell.setBackgroundColor(UiTheme.BG);

        // ---- 顶部品牌栏：品牌 + 页名 + 真实连接状态 ----
        LinearLayout bar = new LinearLayout(activity);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(UiTheme.dp(bar, 20), UiTheme.dp(bar, 12), UiTheme.dp(bar, 20), UiTheme.dp(bar, 18));
        LinearLayout identity = new LinearLayout(activity);
        identity.setOrientation(LinearLayout.VERTICAL);
        TextView brand = new TextView(activity);
        brand.setText("高云乐器");
        brand.setTextColor(UiTheme.MUTED);
        brand.setTextSize(11);
        brand.setLetterSpacing(0.06f);
        identity.addView(brand);
        title = new TextView(activity);
        title.setTextColor(UiTheme.TEXT);
        title.setTextSize(25);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setPadding(0, UiTheme.dp(title, 2), 0, 0);
        if (android.os.Build.VERSION.SDK_INT >= 28) title.setAccessibilityHeading(true);
        identity.addView(title);
        bar.addView(identity, new LinearLayout.LayoutParams(0, -2, 1));
        LinearLayout statusRow = new LinearLayout(activity);
        statusRow.setOrientation(LinearLayout.HORIZONTAL);
        statusRow.setGravity(Gravity.CENTER_VERTICAL);
        statusRow.setPadding(UiTheme.dp(bar, 10), UiTheme.dp(bar, 7), UiTheme.dp(bar, 10), UiTheme.dp(bar, 7));
        statusRow.setBackground(UiTheme.round(statusRow, UiTheme.PANEL, 24));
        statusRow.setMinimumHeight(UiTheme.dp(bar, 48));
        statusRow.setFocusable(true);
        statusRow.setOnClickListener(new View.OnClickListener() {
            public void onClick(View view) { show(0, null); }
        });
        statusDot = new View(activity);
        statusRow.addView(statusDot, new LinearLayout.LayoutParams(UiTheme.dp(statusRow, 6), UiTheme.dp(statusRow, 6)));
        status = new TextView(activity);
        status.setTextSize(11);
        status.setTextColor(UiTheme.MUTED);
        status.setPadding(UiTheme.dp(status, 6), 0, 0, 0);
        status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        statusRow.addView(status, new LinearLayout.LayoutParams(-2, -2));
        bar.addView(statusRow);
        shell.addView(bar);
        shell.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        shell.addView(UiTheme.divider(activity));

        // ---- 底部标签栏 ----
        LinearLayout nav = new LinearLayout(activity);
        nav.setOrientation(LinearLayout.HORIZONTAL);
        nav.setPadding(UiTheme.dp(nav, 12), UiTheme.dp(nav, 8), UiTheme.dp(nav, 12), UiTheme.dp(nav, 8));
        nav.setBackgroundColor(UiTheme.PANEL);
        for (int i = 0; i < 4; i++) {
            final int index = i;
            Tab tab = new Tab(activity, names[i], i);
            tabs[i] = tab;
            LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(0, -2, 1);
            p.setMargins(UiTheme.dp(nav, 4), 0, UiTheme.dp(nav, 4), 0);
            nav.addView(tab.view, p);
            tab.view.setOnClickListener(new View.OnClickListener() {
                public void onClick(View v) { show(index, null); }
            });
        }
        shell.addView(nav);
        show(0, null);
        status(false, false, false);
    }

    private void add(int page, View view) { pages[page].addView(view); UiTheme.gap(view); }

    void show(int index, final View anchor) {
        if (index < 0 || index >= pages.length) return;
        if (index == selected && anchor == null && pages[index].getVisibility() == View.VISIBLE) return;
        if (selected >= 0) positions[selected] = scroll.getScrollY();
        selected = index;
        // 收起隐藏页的键盘与焦点，避免它把滚动拉回旧页。
        View focused = shell.findFocus();
        if (focused != null) {
            android.view.inputmethod.InputMethodManager ime = (android.view.inputmethod.InputMethodManager) shell.getContext().getSystemService(android.content.Context.INPUT_METHOD_SERVICE);
            if (ime != null) ime.hideSoftInputFromWindow(focused.getWindowToken(), 0);
            focused.clearFocus();
        }
        for (int i = 0; i < 4; i++) {
            pages[i].setVisibility(i == index ? View.VISIBLE : View.GONE);
            tabs[i].setSelected(i == index);
        }
        title.setText(titles[index]);
        shell.requestFocus();
        final int generation = ++revision, position = positions[index];
        scroll.post(new Runnable() { public void run() {
            if (generation != revision) return;
            int target=position;
            if(anchor!=null){
                android.graphics.Rect rect=new android.graphics.Rect(0,0,anchor.getWidth(),anchor.getHeight());
                ((android.view.ViewGroup)scroll.getChildAt(0)).offsetDescendantRectToMyCoords(anchor,rect);
                target=rect.top;
            }
            scroll.scrollTo(0,target);
        } });
    }

    /** 顶栏真实状态：已连接/正在传输/扫描中/未连接；不掺技术细节。 */
    void status(boolean ready, boolean scanning, boolean sending) {
        String message;
        int color;
        if (ready && sending) { message = "传输中"; color = UiTheme.PRIMARY; }
        else if (ready) { message = "已连接"; color = UiTheme.SUCCESS; }
        else if (scanning) { message = "扫描中"; color = UiTheme.PRIMARY; }
        else { message = "未连接"; color = UiTheme.FAINT; }
        if (!message.contentEquals(status.getText())) status.setText(message);
        ((View)status.getParent()).setContentDescription("蓝牙状态：" + message + "。点击查看连接。");
        statusDot.setBackground(UiTheme.dot(statusDot, color));
    }

    boolean back() { if (selected == 0) return false; show(0, null); return true; }
    void save(Bundle out) {
        positions[selected] = scroll.getScrollY();
        out.putInt("navigation_page", selected);
        out.putIntArray("navigation_scroll", positions);
    }
    void restore(Bundle state) {
        if (state == null) return;
        int[] p = state.getIntArray("navigation_scroll");
        if (p != null && p.length == 4) System.arraycopy(p, 0, positions, 0, 4);
        int next = state.getInt("navigation_page", 0);
        selected = -1;
        show(next >= 0 && next < 4 ? next : 0, null);
    }

    /** 统一48dp图标胶囊与居中文字，触点最小64dp，随系统字体自然增高。 */
    private static final class Tab {
        final LinearLayout view;
        private final View indicator;
        private final TextView label;
        Tab(Activity activity, String name, int kind) {
            view = new LinearLayout(activity);
            view.setOrientation(LinearLayout.VERTICAL);
            view.setGravity(Gravity.CENTER_HORIZONTAL);
            view.setMinimumHeight(UiTheme.dp(view, 64));
            view.setFocusable(true);
            view.setContentDescription(name + "页");
            indicator = new InstrumentGraphics.Icon(activity, kind);
            view.addView(indicator, new LinearLayout.LayoutParams(UiTheme.dp(view, 48), UiTheme.dp(view, 28)));
            label = new TextView(activity);
            label.setText(name);
            label.setTextSize(11);
            label.setGravity(Gravity.CENTER);
            label.setPadding(0, UiTheme.dp(label, 4), 0, UiTheme.dp(label, 2));
            view.addView(label, new LinearLayout.LayoutParams(-1, -2));
            setSelected(false);
        }
        void setSelected(boolean on) {
            view.setSelected(on);
            indicator.setBackground(UiTheme.round(indicator, on ? UiTheme.HERO : 0x00000000, 20));
            ((InstrumentGraphics.Icon)indicator).color(on ? UiTheme.PRIMARY : UiTheme.MUTED);
            label.setTextColor(on ? UiTheme.PRIMARY : UiTheme.MUTED);
            label.setTypeface(Typeface.DEFAULT, on ? Typeface.BOLD : Typeface.NORMAL);
        }
    }
}
