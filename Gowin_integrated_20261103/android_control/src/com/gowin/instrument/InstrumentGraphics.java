package com.gowin.instrument;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.view.View;

/** Project-drawn vector marks and a preview of the phone's saved calibration. */
final class InstrumentGraphics {
    private InstrumentGraphics() { }

    static final class Icon extends View {
        private final Paint pen = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final int kind;
        private int color = UiTheme.MUTED;
        Icon(Context c, int kind) {
            super(c); this.kind = kind;
            setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        }
        void color(int value) { color = value; invalidate(); }
        @Override protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            canvas.save();
            float size = Math.min(getWidth(), getHeight()) * .72f;
            canvas.translate((getWidth() - size) / 2f, (getHeight() - size) / 2f);
            canvas.scale(size / 24f, size / 24f);
            pen.setColor(color); pen.setStrokeWidth(1.65f);
            pen.setStrokeCap(Paint.Cap.ROUND); pen.setStrokeJoin(Paint.Join.ROUND);
            pen.setStyle(Paint.Style.STROKE);
            if (kind == 0) {
                Path p = new Path(); p.moveTo(7, 7); p.lineTo(17, 16);
                p.lineTo(12, 21); p.lineTo(12, 3); p.lineTo(17, 8); p.lineTo(7, 17);
                canvas.drawPath(p, pen);
            } else if (kind == 1) {
                canvas.drawRoundRect(new RectF(3, 4, 21, 20), 2, 2, pen);
                canvas.drawLine(9, 5, 9, 19, pen); canvas.drawLine(15, 5, 15, 19, pen);
                pen.setStyle(Paint.Style.FILL);
                canvas.drawRoundRect(new RectF(7.2f, 4, 10.8f, 12), .7f, .7f, pen);
                canvas.drawRoundRect(new RectF(13.2f, 4, 16.8f, 12), .7f, .7f, pen);
            } else if (kind == 2) {
                for (int i = 0; i < 3; i++) {
                    float x = 5 + i * 7, y = i == 1 ? 15 : 8;
                    canvas.drawLine(x, 3, x, y - 3, pen); canvas.drawLine(x, y + 3, x, 21, pen);
                    canvas.drawRoundRect(new RectF(x - 2.5f, y - 2.5f, x + 2.5f, y + 2.5f), 1, 1, pen);
                }
            } else if (kind == 3) {
                Path gear=new Path();
                for(int i=0;i<24;i++){
                    double a=Math.PI*2*i/24-Math.PI/2;
                    float radius=(i%4==0||i%4==3)?10f:8f;
                    float x=12+(float)Math.cos(a)*radius,y=12+(float)Math.sin(a)*radius;
                    if(i==0)gear.moveTo(x,y);else gear.lineTo(x,y);
                }gear.close();canvas.drawPath(gear,pen);canvas.drawCircle(12,12,3.1f,pen);
            } else if(kind==5){
                pen.setStyle(Paint.Style.FILL);
                for(int i=0;i<3;i++)canvas.drawRoundRect(new RectF(4+i*5.4f,5,8+i*5.4f,20),1.5f,1.5f,pen);
                pen.setColor(UiTheme.ACCENT);canvas.drawCircle(18,3.2f,2,pen);
            } else {
                pen.setStyle(Paint.Style.FILL);
                for (int i = 0; i < 5; i++) {
                    float h = new float[]{8, 15, 21, 13, 6}[i];
                    canvas.drawRoundRect(new RectF(2 + i * 4.5f, 12 - h / 2, 4.5f + i * 4.5f, 12 + h / 2), 1.2f, 1.2f, pen);
                }
            }
            canvas.restore();
        }
    }

    /** Static local map. It never simulates a live FPGA beat, note or LED reply. */
    static final class PianoMap extends View {
        private final Paint pen = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final int[] map = new int[25];
        private int first = 48, selected = -1, count = 160;
        PianoMap(Context c) { super(c); setFocusable(true); }
        void update(int firstNote, int[] indices, int selectedKey, int ledCount) {
            first = firstNote; selected = selectedKey; count = ledCount;
            System.arraycopy(indices, 0, map, 0, 25);
            int done = 0; for (int index : map) if (index >= 0 && index < count) done++;
            setContentDescription("手机灯位预览，已保存" + done + "/25键；预览不代表实物灯光。" );
            invalidate();
        }
        private boolean black(int i) {
            int note = ((first + i) % 12 + 12) % 12;
            return note == 1 || note == 3 || note == 6 || note == 8 || note == 10;
        }
        @Override protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            int whites = 0; for (int i = 0; i < 25; i++) if (!black(i)) whites++;
            float w = getWidth() / (float)whites, h = getHeight() - UiTheme.dp(this, 2);
            int white = 0;
            for (int i = 0; i < 25; i++) if (!black(i)) {
                key(canvas, i, white * w + 1, 1, (white + 1) * w - 1, h, false); white++;
            }
            white = 0;
            for (int i = 0; i < 25; i++) {
                if (black(i)) {
                    // Edge black keys remain visible for every possible first MIDI note.
                    float x = Math.max(w * .28f, Math.min(getWidth() - w * .28f, white * w));
                    key(canvas, i, x - w * .28f, 0, x + w * .28f, h * .62f, true);
                } else white++;
            }
        }
        private void key(Canvas c, int i, float l, float t, float r, float b, boolean black) {
            pen.setStyle(Paint.Style.FILL);
            pen.setColor(black ? 0xFF293E32 : 0xFFF7F8F2);
            c.drawRoundRect(new RectF(l, t, r, b), UiTheme.dp(this, 2), UiTheme.dp(this, 2), pen);
            if (map[i] >= 0 && map[i] < count) {
                pen.setColor(black ? 0xFFC6DCC5 : UiTheme.PRIMARY);
                c.drawCircle((l + r) / 2, b - UiTheme.dp(this, 8), UiTheme.dp(this, 2), pen);
            }
            if (i == selected) {
                pen.setColor(UiTheme.WARNING); pen.setStrokeWidth(UiTheme.dp(this, 2)); pen.setStyle(Paint.Style.STROKE);
                c.drawRoundRect(new RectF(l + 1, t + 1, r - 1, b - 1), UiTheme.dp(this, 2), UiTheme.dp(this, 2), pen);
            }
        }
    }
}
