package com.gowin.instrument;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.graphics.drawable.StateListDrawable;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.ProgressBar;
import android.widget.SeekBar;
import android.widget.Spinner;
import android.widget.TextView;

import java.util.List;

/**
 * 乐器练习室：暖白底色、深绿强调；全部视觉由项目自身绘制。
 * 只有视觉样式：纯程序化 Drawable，无 res/Material/AndroidX 依赖，不涉及任何通信行为。
 */
final class UiTheme {
    // ---------------------------------------------------------------- 色板
    static final int BG = 0xFFF5F5F0;
    static final int PANEL = 0xFFFFFFFF;
    static final int RAISED = 0xFFEEF2EC;
    static final int TEXT = 0xFF202F29;
    static final int MUTED = 0xFF66756D;
    static final int FAINT = 0xFF7D8A82;
    static final int PRIMARY = 0xFF25634D;
    static final int ON_PRIMARY = 0xFFFFFFFF;
    static final int OUTLINE = 0xFFE0E6DD;
    static final int SUCCESS = 0xFF25634D;
    static final int WARNING = 0xFF966321;
    static final int DANGER = 0xFFB0473F;
    static final int HERO = 0xFFE3EDDF;
    static final int ACCENT = 0xFFD5A359;
    private static final int RIPPLE = 0x1A25634D;
    private static final int DISABLED_FILL = 0xFFEBEEE8;
    private static final int MONO_BG = 0xFFF2F4F0;

    enum Style { PRIMARY, SECONDARY, DANGER, GHOST }

    private UiTheme() { }

    // ---------------------------------------------------------------- 度量
    static int dp(View v, int n) { return dp(v.getContext(), n); }
    static int dp(Context c, int n) { return Math.round(n * c.getResources().getDisplayMetrics().density); }

    // ---------------------------------------------------------------- 形状
    static GradientDrawable round(View v, int color, int radiusDp) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(dp(v, radiusDp));
        return d;
    }
    static GradientDrawable dot(View v, int color) {
        GradientDrawable d = new GradientDrawable();
        d.setShape(GradientDrawable.OVAL);
        d.setColor(color);
        int s = dp(v, 8);
        d.setSize(s, s);
        return d;
    }
    static View divider(Context c) {
        View v = new View(c);
        v.setBackgroundColor(OUTLINE);
        v.setLayoutParams(new LinearLayout.LayoutParams(-1, 1));
        return v;
    }

    // ---------------------------------------------------------------- 卡片
    /** 区块卡片：圆角面板 + 1dp 描边 + 16dp 内边距；卡片间距由 gap() 统一处理。 */
    static LinearLayout card(Context c) {
        LinearLayout card = new LinearLayout(c);
        card.setOrientation(LinearLayout.VERTICAL);
        GradientDrawable bg = round(card, PANEL, 18);
        bg.setStroke(dp(c,1),OUTLINE);
        card.setBackground(bg);
        card.setPadding(dp(c, 18), dp(c, 18), dp(c, 18), dp(c, 18));
        return card;
    }
    static void gap(View v) {
        ViewGroup.LayoutParams raw = v.getLayoutParams();
        if (raw instanceof ViewGroup.MarginLayoutParams) {
            ViewGroup.MarginLayoutParams p = (ViewGroup.MarginLayoutParams) raw;
            p.bottomMargin = dp(v, 12);
            v.setLayoutParams(p);
        }
    }

    // ---------------------------------------------------------------- 文字
    static TextView heading(Context c, String text) { TextView t = new TextView(c); t.setText(text); heading(t); return t; }
    static void heading(TextView t) {
        t.setTextColor(TEXT);
        t.setTextSize(20);
        t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        if (android.os.Build.VERSION.SDK_INT >= 28) t.setAccessibilityHeading(true);
    }
    static TextView section(Context c, String text) { TextView t = new TextView(c); t.setText(text); section(t); return t; }
    static void section(TextView t) {
        t.setTextColor(TEXT);
        t.setTextSize(16);
        t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        t.setPadding(0, 0, 0, dp(t, 8));
        if (android.os.Build.VERSION.SDK_INT >= 28) t.setAccessibilityHeading(true);
    }
    static TextView body(Context c, String text) { TextView t = new TextView(c); t.setText(text); body(t); return t; }
    static void body(TextView t) { t.setTextColor(TEXT); t.setTextSize(16); t.setLineSpacing(dp(t, 2), 1f); }
    static TextView caption(Context c, String text) { TextView t = new TextView(c); t.setText(text); caption(t); return t; }
    static TextView eyebrow(Context c, String text) {
        TextView t = caption(c, text);
        t.setTextColor(PRIMARY);
        t.setTextSize(11);
        t.setLetterSpacing(0.04f);
        t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return t;
    }
    static LinearLayout row(Context c) {
        LinearLayout row = new LinearLayout(c);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        return row;
    }
    static void space(LinearLayout parent, int height) {
        parent.addView(new View(parent.getContext()), new LinearLayout.LayoutParams(1, dp(parent, height)));
    }
    static void caption(TextView t) {
        t.setTextColor(MUTED);
        t.setTextSize(13);
        t.setLineSpacing(dp(t, 2), 1f);
        t.setPadding(0, dp(t, 2), 0, dp(t, 2));
    }
    static TextView mono(Context c, String text) { TextView t = new TextView(c); t.setText(text); mono(t); return t; }
    static void mono(TextView t) {
        t.setTextColor(TEXT);
        t.setTextSize(13);
        t.setTypeface(Typeface.MONOSPACE);
        t.setTextIsSelectable(true);
        t.setBackground(round(t, MONO_BG, 10));
        t.setPadding(dp(t, 12), dp(t, 10), dp(t, 12), dp(t, 10));
    }

    // ---------------------------------------------------------------- 按钮
    static void button(Button b, boolean primary) { button(b, primary ? Style.PRIMARY : Style.SECONDARY); }
    static void danger(Button b) { button(b, Style.DANGER); }
    static void ghost(Button b) { button(b, Style.GHOST); }
    static void button(Button b, Style s) {
        b.setAllCaps(false);
        b.setTextSize(14);
        b.setMinHeight(dp(b, 48));
        b.setMinimumHeight(dp(b, 48));
        b.setMinWidth(dp(b, 48));
        b.setPadding(dp(b, 16), dp(b, 10), dp(b, 16), dp(b, 10));
        b.setStateListAnimator(null);
        b.setElevation(0);
        GradientDrawable def = round(b, fill(s, false), 12);
        int stroke = stroke(s);
        if (stroke != 0) def.setStroke(dp(b, 1), stroke);
        GradientDrawable pressed = round(b, fill(s, true), 12);
        if (stroke != 0) pressed.setStroke(dp(b, 1), stroke);
        GradientDrawable focused = round(b, fill(s, false), 12);
        focused.setStroke(dp(b, 2), s == Style.PRIMARY ? TEXT : PRIMARY);
        StateListDrawable states = new StateListDrawable();
        states.addState(new int[]{-android.R.attr.state_enabled}, round(b, DISABLED_FILL, 12));
        states.addState(new int[]{android.R.attr.state_pressed}, pressed);
        states.addState(new int[]{android.R.attr.state_focused}, focused);
        states.addState(new int[]{}, def);
        b.setBackground(new RippleDrawable(ColorStateList.valueOf(RIPPLE), states, null));
        b.setBackgroundTintList(null);
        b.setTextColor(new ColorStateList(
                new int[][]{new int[]{-android.R.attr.state_enabled}, new int[]{}},
                new int[]{FAINT, ink(s)}));
    }
    /** A persistent state selector keeps the background and ink in sync on taps. */
    static void segment(Button b) {
        button(b, Style.SECONDARY);
        StateListDrawable states = new StateListDrawable();
        states.addState(new int[]{-android.R.attr.state_enabled}, round(b, DISABLED_FILL, 12));
        GradientDrawable selectedFocus = round(b, PRIMARY, 12);
        selectedFocus.setStroke(dp(b, 2), TEXT);
        states.addState(new int[]{android.R.attr.state_selected, android.R.attr.state_focused}, selectedFocus);
        states.addState(new int[]{android.R.attr.state_selected}, round(b, PRIMARY, 12));
        GradientDrawable focus = round(b, RAISED, 12);focus.setStroke(dp(b, 2), PRIMARY);
        states.addState(new int[]{android.R.attr.state_focused}, focus);
        states.addState(new int[]{}, round(b, RAISED, 12));
        b.setBackground(new RippleDrawable(ColorStateList.valueOf(RIPPLE), states, null));
        b.setBackgroundTintList(null);
        b.setTextColor(new ColorStateList(new int[][]{
                new int[]{-android.R.attr.state_enabled}, new int[]{android.R.attr.state_selected}, new int[]{}},
                new int[]{FAINT, ON_PRIMARY, TEXT}));
    }
    private static int fill(Style s, boolean pressed) {
        switch (s) {
            case PRIMARY: return pressed ? 0xFF194C3A : PRIMARY;
            case DANGER: return pressed ? 0xFFF3DCD7 : 0xFFFCF0ED;
            case GHOST: return pressed ? RAISED : 0x00000000;
            default: return pressed ? 0xFFE0E9DD : RAISED;
        }
    }
    private static int stroke(Style s) {
        switch (s) {
            case SECONDARY: return OUTLINE;
            case DANGER: return 0;
            default: return 0;
        }
    }
    private static int ink(Style s) {
        switch (s) {
            case PRIMARY: return ON_PRIMARY;
            case DANGER: return DANGER;
            case GHOST: return MUTED;
            default: return TEXT;
        }
    }

    // ---------------------------------------------------------------- 输入与选择
    static void input(EditText e) {
        e.setTextColor(TEXT);
        e.setHintTextColor(FAINT);
        e.setTextSize(16);
        e.setMinHeight(dp(e, 48));
        e.setPadding(dp(e, 14), dp(e, 10), dp(e, 14), dp(e, 10));
        GradientDrawable def = round(e, RAISED, 12);
        def.setStroke(dp(e, 1), OUTLINE);
        GradientDrawable focused = round(e, RAISED, 12);
        focused.setStroke(dp(e, 1), PRIMARY);
        StateListDrawable states = new StateListDrawable();
        states.addState(new int[]{android.R.attr.state_focused}, focused);
        states.addState(new int[]{}, def);
        e.setBackground(states);
    }
    static void spinner(Spinner s) {
        s.setMinimumHeight(dp(s, 48));
        GradientDrawable def = round(s, RAISED, 12);
        def.setStroke(dp(s, 1), OUTLINE);
        s.setBackground(def);
        s.setPadding(dp(s, 12), 0, dp(s, 4), 0);
        GradientDrawable popup = round(s, PANEL, 12);
        popup.setStroke(dp(s, 1), OUTLINE);
        s.setPopupBackgroundDrawable(popup);
    }
    /** Spinner 显示与下拉统一深色行样式。 */
    static ArrayAdapter<String> spinnerAdapter(Context c, String[] items) {
        return new ArrayAdapter<String>(c, 0, items) {
            @Override public View getView(int position, View convertView, ViewGroup parent) {
                LinearLayout row = new LinearLayout(parent.getContext());
                row.setOrientation(LinearLayout.HORIZONTAL);
                row.setGravity(Gravity.CENTER_VERTICAL);
                TextView t = base(parent);
                t.setTextSize(15);
                t.setText(getItem(position));
                row.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
                TextView arrow = new TextView(parent.getContext());
                arrow.setText("▾");
                arrow.setTextColor(MUTED);
                arrow.setTextSize(14);
                arrow.setPadding(0, 0, dp(parent.getContext(), 10), 0);
                row.addView(arrow, new LinearLayout.LayoutParams(-2, -2));
                return row;
            }
            @Override public View getDropDownView(int position, View convertView, ViewGroup parent) {
                TextView t = base(parent);
                t.setTextSize(14);
                t.setMinHeight(dp(parent.getContext(), 48));
                t.setSingleLine(false);
                t.setMaxLines(3);
                t.setText(getItem(position));
                return t;
            }
            private TextView base(ViewGroup parent) {
                TextView t = new TextView(parent.getContext());
                t.setTextColor(TEXT);
                t.setSingleLine(true);
                t.setEllipsize(android.text.TextUtils.TruncateAt.END);
                t.setGravity(Gravity.CENTER_VERTICAL);
                t.setPadding(dp(parent.getContext(), 12), dp(parent.getContext(), 10), dp(parent.getContext(), 12), dp(parent.getContext(), 10));
                return t;
            }
        };
    }
    /** 扫描设备列表：深色行容器、细分隔线、空列表提示由调用方 setEmptyView。 */
    static void list(ListView l) {
        l.setDivider(new ColorDrawable(OUTLINE));
        l.setDividerHeight(1);
        l.setSelector(new ColorDrawable(0x1925634D));
        l.setCacheColorHint(0x00000000);
        l.setBackground(round(l, RAISED, 12));
        l.setClipToOutline(true);
    }
    static ArrayAdapter<String> listAdapter(Context c, List<String> data) {
        return new ArrayAdapter<String>(c, 0, data) {
            @Override public View getView(int position, View convertView, ViewGroup parent) {
                TextView t = new TextView(parent.getContext());
                t.setText(getItem(position));
                t.setTextColor(TEXT);
                t.setTextSize(14);
                t.setMaxLines(2);
                t.setEllipsize(android.text.TextUtils.TruncateAt.END);
                t.setGravity(Gravity.CENTER_VERTICAL);
                t.setMinHeight(dp(parent.getContext(), 48));
                t.setPadding(dp(parent.getContext(), 14), dp(parent.getContext(), 12), dp(parent.getContext(), 14), dp(parent.getContext(), 12));
                return t;
            }
        };
    }

    // ---------------------------------------------------------------- 进度与滑块
    static void progress(ProgressBar p) {
        p.setProgressTintList(ColorStateList.valueOf(PRIMARY));
        p.setProgressBackgroundTintList(ColorStateList.valueOf(RAISED));
    }
    static void seek(SeekBar s) {
        s.setMinimumHeight(dp(s, 48));
        s.setProgressTintList(ColorStateList.valueOf(PRIMARY));
        s.setThumbTintList(ColorStateList.valueOf(PRIMARY));
        s.setProgressBackgroundTintList(ColorStateList.valueOf(RAISED));
    }

    static void systemBars(android.app.Activity activity){
        // Construct the decor before asking Android 11+ for its controller.
        activity.getWindow().getDecorView();
        activity.getWindow().setStatusBarColor(BG);
        activity.getWindow().setNavigationBarColor(BG);
        if(android.os.Build.VERSION.SDK_INT>=30){
            android.view.WindowInsetsController bars=activity.getWindow().getInsetsController();
            if(bars!=null)bars.setSystemBarsAppearance(android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS|android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
                android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS|android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS);
        }else{
            int flags=android.view.View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
            if(android.os.Build.VERSION.SDK_INT>=26)flags|=android.view.View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
            activity.getWindow().getDecorView().setSystemUiVisibility(flags);
        }
    }

    static void compactDetail(final TextView view,final String title,int lines){
        view.setMaxLines(lines);view.setEllipsize(android.text.TextUtils.TruncateAt.END);
        view.setOnClickListener(new View.OnClickListener(){public void onClick(View v){
            new android.app.AlertDialog.Builder(view.getContext()).setTitle(title).setMessage(view.getText()).setPositiveButton("关闭",null).show();
        }});
    }
}
