package com.gowin.instrument;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.os.Looper;
import android.view.View;
import android.widget.*;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.Collections;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import org.robolectric.annotation.LooperMode;
import static org.junit.Assert.*;

/** Android runtime/layout fixtures, never a real GATT connection or board test. */
@RunWith(RobolectricTestRunner.class)
@Config(manifest=Config.NONE,sdk=35)
@LooperMode(LooperMode.Mode.PAUSED)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class AppAdaptationUiTest {
    @Test public void tabTextAndIndicatorShareCenterAcrossSizes() throws Exception {
        int[][] cases={{320,480,200},{360,800,100},{412,915,130},{800,360,150}};
        for(int[] sample:cases){
            RuntimeEnvironment.setQualifiers("w"+sample[0]+"dp-h"+sample[1]+"dp-xhdpi");
            RuntimeEnvironment.setFontScale(sample[2]/100f);
            ActivityController<NativeUiTest.DarkActivity> controller=Robolectric.buildActivity(NativeUiTest.DarkActivity.class).setup();
            try{
                Activity activity=controller.get();ScrollView scroll=new ScrollView(activity);
                LinearLayout body=new LinearLayout(activity);body.setOrientation(1);scroll.addView(body);
                for(int i=0;i<4;i++){TextView text=UiTheme.body(activity,"页面"+i);text.setMinimumHeight(UiTheme.dp(text,1800));body.addView(text);}
                AppNavigation nav=new AppNavigation(activity,body,scroll,new int[]{0,1,2,3});activity.setContentView(nav.shell);
                for(int page=0;page<4;page++){
                    nav.show(page,null);measure(nav.shell,sample[0],sample[1]);
                    Object[] tabs=(Object[])field(nav,"tabs");
                    int baseline=-1;
                    for(int tabIndex=0;tabIndex<4;tabIndex++){
                        Object tab=tabs[tabIndex];View indicator=(View)field(tab,"indicator");TextView label=(TextView)field(tab,"label");View target=(View)field(tab,"view");
                        assertTrue(target.getWidth()>0);assertTrue(target.getHeight()>=UiTheme.dp(target,48));
                        assertEquals(tabIndex==page,target.isSelected());assertNotNull(label.getLayout());assertEquals(1,label.getLineCount());
                        float lineCenter=label.getLeft()+label.getTotalPaddingLeft()+(label.getLayout().getLineLeft(0)+label.getLayout().getLineRight(0))/2f;
                        float indicatorCenter=indicator.getLeft()+indicator.getWidth()/2f;
                        assertEquals("tab line/text center: "+label.getText(),indicatorCenter,lineCenter,1.0f);
                        int next=label.getTop()+label.getBaseline();if(baseline<0)baseline=next;else assertEquals("tab baselines",baseline,next);
                    }
                    assertTrue("short display must retain scrollable content",scroll.getHeight()>=UiTheme.dp(scroll,80));
                    save(nav.shell,"nav-"+sample[0]+"x"+sample[1]+"-font"+sample[2]+"-tab"+page);
                }
            }finally{controller.pause().stop().destroy();}
        }
    }

    @Test public void calibrationRequiresSavingKeysAndLocksPendingCommands() throws Exception {
        RuntimeEnvironment.setQualifiers("w360dp-h800dp-xhdpi");RuntimeEnvironment.setFontScale(1.3f);
        ActivityController<NativeUiTest.DarkActivity> controller=Robolectric.buildActivity(NativeUiTest.DarkActivity.class).setup();
        BleTransport peer=null;ScorePanel score=null;
        try{
            Activity activity=controller.get();peer=transport(activity);final BleTransport transport=peer;
            score=new ScorePanel(activity,new ScorePanel.Host(){public BleTransport transport(){return transport;}public void log(String text){}public void refresh(){}});
            TutorialPanel guide=(TutorialPanel)field(score,"tutorial");score.refresh();
            assertFalse(((Button)field(guide,"startButton")).isEnabled());
            EditText scan=(EditText)field(guide,"scanIndex");scan.setText("3");
            int[] indices=(int[])field(guide,"keyIndices");assertEquals("typing a scan number must not set key1",-1,indices[0]);
            Button saveKey=button(guide,"保存当前灯位到所选键（手机）");saveKey.performClick();assertEquals(3,indices[0]);
            ((Spinner)field(guide,"key")).setSelection(1);saveKey.performClick();assertEquals("a duplicate pixel cannot be saved",-1,indices[1]);
            assertTrue(((TextView)field(guide,"status")).getText().toString().contains("此灯已用于第1键"));
            for(int i=1;i<25;i++){((Spinner)field(guide,"key")).setSelection(i);scan.setText(String.valueOf(3+i*2));saveKey.performClick();}
            score.refresh();assertTrue(((Button)field(guide,"startButton")).isEnabled());assertTrue(((Button)field(guide,"writeMappingButton")).isEnabled());
            assertTrue(((TextView)field(guide,"calibrationSummary")).getText().toString().contains("25/25"));
            ((EditText)field(guide,"ledCount")).setText("161");assertFalse(((Button)field(guide,"startButton")).isEnabled());
            assertTrue(((TextView)field(guide,"calibrationSummary")).getText().toString().contains("160"));
            ((EditText)field(guide,"ledCount")).setText("160");((EditText)field(guide,"firstNote")).setText("104");
            assertFalse(((Button)field(guide,"startButton")).isEnabled());((EditText)field(guide,"firstNote")).setText("48");
            ScoreTransfer transfer=(ScoreTransfer)field(guide,"transfer");transfer.start(Collections.singletonList(TutorialProtocol.probe()));set(guide,"completedMessage","probe fixture");score.refresh();
            for(String field:new String[]{"ledCount","firstNote","scanIndex","transpose","beatIndex","key","speed"})assertFalse(field+" editable in flight",((View)field(guide,field)).isEnabled());
            assertFalse("legacy cancel cannot cancel tutorial ownership",((Button)field(score,"cancel")).isEnabled());
            score.onReply(new ReplyDecoder.Reply(0x75,1));assertTrue("NACK must retain local write ownership",guide.busy());assertTrue(peer.isReady());
            score.onReply(new ReplyDecoder.Reply(0x75,0));assertTrue(guide.busy());
            score.onProgress(new BleTransport.SendProgress(1,1,2,true,false));assertFalse(guide.busy());assertTrue(peer.isReady());assertTrue(scan.isEnabled());
            assertTrue(((TextView)field(guide,"status")).getText().toString().contains("被拒绝"));
        }finally{if(score!=null)score.close();if(peer!=null)peer.close();controller.pause().stop().destroy();}
    }

    @Test public void tempoPresetsShowExactBpmAndLockUntilBothCallbacks() throws Exception {
        int[][] cases={{320,640,200},{360,800,100},{800,360,150}};
        for(int[] sample:cases){
            RuntimeEnvironment.setQualifiers("w"+sample[0]+"dp-h"+sample[1]+"dp-xhdpi");RuntimeEnvironment.setFontScale(sample[2]/100f);
            ActivityController<NativeUiTest.DarkActivity> controller=Robolectric.buildActivity(NativeUiTest.DarkActivity.class).setup();
            TutorialPanel guide=null;
            try{
                Activity activity=controller.get();
                guide=new TutorialPanel(activity,new TutorialPanel.Host(){
                    public BleTransport transport(){return null;}public boolean otherBusy(){return false;}
                    public void log(String text){}public void refresh(){}
                });guide.refresh();
                ScrollView scroll=new ScrollView(activity);LinearLayout body=new LinearLayout(activity);body.setOrientation(1);
                body.setPadding(UiTheme.dp(body,20),0,UiTheme.dp(body,20),0);body.setBackgroundColor(UiTheme.BG);
                body.addView(guide,new LinearLayout.LayoutParams(-1,-2));scroll.addView(body);activity.setContentView(scroll);
                int[] rates={50,75,100,150};String[] bpm={"75","112.5","150","225"};
                for(int i=0;i<rates.length;i++){
                    Button preset=button(guide,rates[i]+"%");assertTrue("offline tempo editing",preset.isEnabled());preset.performClick();
                    measure(scroll,sample[0],sample[1]);fits(body);
                    TextView number=(TextView)field(guide,"speedLabel");
                    assertEquals(bpm[i],number.getText().toString());assertEquals("decimal BPM must fit on one line",1,number.getLineCount());
                    assertEquals(rates[i]-50,((SeekBar)field(guide,"speed")).getProgress());assertTrue(preset.isSelected());
                    assertFalse("preset selection must not initiate a transfer",guide.busy());
                    Bitmap buttonImage=Bitmap.createBitmap(preset.getWidth(),preset.getHeight(),Bitmap.Config.ARGB_8888);
                    preset.draw(new Canvas(buttonImage));
                    int fill=buttonImage.getPixel(UiTheme.dp(preset,12),preset.getHeight()/2);
                    double inkLuma=luminance(preset.getCurrentTextColor()),fillLuma=luminance(fill);
                    assertTrue("selected preset must retain readable contrast",(Math.max(inkLuma,fillLuma)+.05)/(Math.min(inkLuma,fillLuma)+.05)>=4.5);
                    buttonImage.recycle();
                    if(i==0)save(body,"tempo-"+sample[0]+"-font"+sample[2]+"-75-percent");
                }
                ScoreTransfer transfer=(ScoreTransfer)field(guide,"transfer");transfer.start(Collections.singletonList(TutorialProtocol.probe()));set(guide,"completedMessage","fixture accepted");guide.refresh();
                for(int rate:rates)assertFalse("preset locked in flight",button(guide,rate+"%").isEnabled());
                guide.onReply(new ReplyDecoder.Reply(0x75,0));assertTrue("ACK alone cannot unlock presets",guide.busy());
                for(int rate:rates)assertFalse(button(guide,rate+"%").isEnabled());
                guide.onProgress(new BleTransport.SendProgress(1,1,2,true,false));assertFalse(guide.busy());
                for(int rate:rates)assertTrue(button(guide,rate+"%").isEnabled());
            }finally{if(guide!=null)guide.close();controller.pause().stop().destroy();}
        }
    }

    @Test public void current138kProfileBlocksLegacyWritesAndKeepsToneProgressSeparate() throws Exception {
        RuntimeEnvironment.setQualifiers("w360dp-h800dp-xhdpi");RuntimeEnvironment.setFontScale(1f);
        ActivityController<NativeUiTest.PreviewActivity> controller=Robolectric.buildActivity(NativeUiTest.PreviewActivity.class).setup();
        try{
            MainActivity activity=controller.get();awaitPreset(activity);
            BleTransport peer=(BleTransport)field(activity,"ble");set(peer,"ready",true);
            invoke(activity,"refreshButtons");ScorePanel score=(ScorePanel)field(activity,"scorePanel");TutorialPanel guide=(TutorialPanel)field(score,"tutorial");
            assertFalse((Boolean)field(activity,"legacyProfile"));assertFalse(((Button)field(activity,"btnSendTone")).isEnabled());
            assertTrue("138K may probe score support",((Button)field(score,"probe")).isEnabled());assertFalse(((Button)field(score,"upload")).isEnabled());assertFalse(((Button)field(score,"volumeApply")).isEnabled());
            assertTrue(button(guide,"检查138K指引接口").isEnabled());
            assertEquals(View.GONE,((View)field(score,"legacyContent")).getVisibility());
            TextView toneProgress=(TextView)field(activity,"tvProgress");String before=toneProgress.getText().toString();
            ScoreTransfer transfer=(ScoreTransfer)field(guide,"transfer");transfer.start(Collections.singletonList(TutorialProtocol.probe()));set(guide,"completedMessage","probe accepted fixture");
            invoke(activity,"refreshButtons");assertFalse(((Spinner)field(activity,"spControlProfile")).isEnabled());
            activity.onSendProgress(new BleTransport.SendProgress(1,1,2,true,false));assertTrue(guide.busy());
            assertEquals("guide progress must not overwrite tone progress",before,toneProgress.getText().toString());
            score.onReply(new ReplyDecoder.Reply(0x75,0));assertFalse(guide.busy());invoke(activity,"refreshButtons");
            Spinner profile=(Spinner)field(activity,"spControlProfile");profile.setSelection(1);Shadows.shadowOf(Looper.getMainLooper()).idle();invoke(activity,"refreshButtons");
            assertTrue((Boolean)field(activity,"legacyProfile"));assertTrue(((Button)field(activity,"btnSendTone")).isEnabled());assertTrue(((Button)field(score,"probe")).isEnabled());
            assertFalse(button(guide,"检查138K指引接口").isEnabled());
            profile.setSelection(0);Shadows.shadowOf(Looper.getMainLooper()).idle();invoke(activity,"refreshButtons");
            assertFalse((Boolean)field(activity,"legacyProfile"));assertTrue(button(guide,"检查138K指引接口").isEnabled());
        }finally{controller.pause().stop().destroy();}
    }

    @Test public void volumeRefusalWaitsForItsOwnWriteAndKeepsLoadedScore() throws Exception {
        ActivityController<NativeUiTest.DarkActivity> controller=Robolectric.buildActivity(NativeUiTest.DarkActivity.class).setup();
        BleTransport peer=null;ScorePanel score=null;
        try{
            peer=transport(controller.get());final BleTransport transport=peer;
            score=new ScorePanel(controller.get(),new ScorePanel.Host(){public BleTransport transport(){return transport;}public void log(String text){}public void refresh(){}});
            set(score,"loaded",true);set(score,"capable",true);set(score,"operation",0x56);
            ScoreTransfer transfer=(ScoreTransfer)field(score,"transfer");transfer.start(Collections.singletonList(Score.volume(60)));score.refresh();
            score.onReply(new ReplyDecoder.Reply(0x56,1));assertTrue(score.busy());assertTrue(peer.isReady());
            score.onReply(new ReplyDecoder.Reply(0x56,0));assertTrue(score.busy());
            score.onProgress(new BleTransport.SendProgress(1,1,2,true,false));assertFalse(score.busy());assertTrue(peer.isReady());assertTrue((Boolean)field(score,"loaded"));
        }finally{if(score!=null)score.close();if(peer!=null)peer.close();controller.pause().stop().destroy();}
    }

    @Test public void actualPagesAndExpandedCalibrationFitSmallAndLargeText() throws Exception {
        int[][] cases={{320,640,150},{412,915,130},{800,360,100}};
        for(int[] sample:cases){
            RuntimeEnvironment.setQualifiers("w"+sample[0]+"dp-h"+sample[1]+"dp-xhdpi");RuntimeEnvironment.setFontScale(sample[2]/100f);
            ActivityController<NativeUiTest.PreviewActivity> controller=Robolectric.buildActivity(NativeUiTest.PreviewActivity.class).setup();
            try{
                MainActivity activity=controller.get();awaitPreset(activity);AppNavigation nav=(AppNavigation)field(activity,"navigation");
                for(int page=0;page<4;page++){
                    nav.show(page,null);measure(nav.shell,sample[0],sample[1]);fits(nav.shell);
                    save(nav.shell,"actual-"+sample[0]+"x"+sample[1]+"-font"+sample[2]+"-page"+page);
                }
                nav.show(1,null);ScorePanel score=(ScorePanel)field(activity,"scorePanel");TutorialPanel guide=(TutorialPanel)field(score,"tutorial");
                button(guide,"展开灯带校准").performClick();measure(nav.shell,sample[0],sample[1]);fits(nav.shell);
                LinearLayout page=((LinearLayout[])field(nav,"pages"))[1];save(page,"calibration-full-"+sample[0]+"-font"+sample[2]);
                score.setLegacyExpanded(true);measure(nav.shell,sample[0],sample[1]);fits(nav.shell);
                ScrollView scroll=(ScrollView)field(nav,"scroll");scroll.setSmoothScrollingEnabled(false);scroll.fullScroll(View.FOCUS_DOWN);measure(nav.shell,sample[0],sample[1]);
                assertTrue("expanded legacy content remains reachable; content="+scroll.getChildAt(0).getHeight()+", viewport="+scroll.getHeight(),scroll.getScrollY()>0);
                save(nav.shell,"legacy-bottom-"+sample[0]+"-font"+sample[2]);
            }finally{controller.pause().stop().destroy();}
        }
    }

    private static void awaitPreset(MainActivity activity)throws Exception{
        for(int i=0;i<200&&!((Boolean)field(activity,"presetReady"));i++){Thread.sleep(10);Shadows.shadowOf(Looper.getMainLooper()).idle();}
        assertTrue((Boolean)field(activity,"presetReady"));
    }
    private static double luminance(int color){
        double result=0;double[] weights={.2126,.7152,.0722};
        for(int i=0;i<3;i++){double channel=((color>>(16-i*8))&255)/255.0;result+=weights[i]*(channel<=.04045?channel/12.92:Math.pow((channel+.055)/1.055,2.4));}
        return result;
    }
    private static BleTransport transport(Activity activity)throws Exception{
        BleTransport.Listener listener=(BleTransport.Listener)Proxy.newProxyInstance(BleTransport.Listener.class.getClassLoader(),new Class<?>[]{BleTransport.Listener.class},(proxy,method,args)->null);
        BleTransport peer=new BleTransport(activity,listener);set(peer,"ready",true);return peer;
    }
    private static Field member(Object target,String name)throws Exception{Class<?> type=target.getClass();while(type!=null){try{Field field=type.getDeclaredField(name);field.setAccessible(true);return field;}catch(NoSuchFieldException ex){type=type.getSuperclass();}}throw new NoSuchFieldException(name);}
    private static Object field(Object target,String name)throws Exception{return member(target,name).get(target);}
    private static void set(Object target,String name,Object value)throws Exception{member(target,name).set(target,value);}
    private static void invoke(MainActivity target,String name)throws Exception{Method method=MainActivity.class.getDeclaredMethod(name);method.setAccessible(true);method.invoke(target);}
    private static Button button(View view,String label){if(view instanceof Button&&label.contentEquals(((Button)view).getText()))return (Button)view;if(view instanceof android.view.ViewGroup){android.view.ViewGroup group=(android.view.ViewGroup)view;for(int i=0;i<group.getChildCount();i++){Button found=button(group.getChildAt(i),label);if(found!=null)return found;}}return null;}
    private static void measure(View view,int widthDp,int heightDp){int width=UiTheme.dp(view,widthDp),height=UiTheme.dp(view,heightDp);for(int i=0;i<2;i++){view.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(height,View.MeasureSpec.EXACTLY));view.layout(0,0,view.getMeasuredWidth(),view.getMeasuredHeight());Shadows.shadowOf(Looper.getMainLooper()).idle();}}
    private static void fits(View view){if(view.getVisibility()!=View.VISIBLE)return;if(view instanceof TextView){TextView text=(TextView)view;if(text.getLayout()!=null&&!text.isSingleLine())assertTrue("clipped text: "+text.getText(),text.getLayout().getHeight()<=text.getHeight()-text.getTotalPaddingTop()-text.getTotalPaddingBottom()+1);}if(view instanceof android.view.ViewGroup){android.view.ViewGroup group=(android.view.ViewGroup)view;for(int i=0;i<group.getChildCount();i++)fits(group.getChildAt(i));}}
    private static void save(View view,String name)throws Exception{File folder=new File(System.getProperty("qa.screens"));folder.mkdirs();assertTrue(view.getWidth()>0&&view.getHeight()>0);Bitmap bitmap=Bitmap.createBitmap(view.getWidth(),view.getHeight(),Bitmap.Config.ARGB_8888);view.draw(new Canvas(bitmap));try(FileOutputStream output=new FileOutputStream(new File(folder,name+".png"))){assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG,100,output));}bitmap.recycle();}
}
