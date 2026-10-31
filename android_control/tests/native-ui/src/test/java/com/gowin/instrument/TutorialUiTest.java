package com.gowin.instrument;

import android.app.Activity;
import android.content.ClipboardManager;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.os.Bundle;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.widget.*;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Proxy;
import java.util.Collections;
import java.util.Arrays;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import org.robolectric.annotation.LooperMode;
import static org.junit.Assert.*;

@RunWith(org.robolectric.RobolectricTestRunner.class)
@Config(manifest=Config.NONE,sdk=35)
@LooperMode(LooperMode.Mode.PAUSED)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class TutorialUiTest {
    public static class Preview extends Activity {
        @Override public void onCreate(Bundle state){setTheme(android.R.style.Theme_Material_NoActionBar);super.onCreate(state);}
    }
    private TutorialPanel panel(Activity activity){return new TutorialPanel(activity,new TutorialPanel.Host(){
        public BleTransport transport(){return null;}public boolean otherBusy(){return false;}
        public void log(String text){}public void refresh(){}
    });}
    @Test public void controlsFitAndCalibrationPersistsOffline() throws Exception {
        RuntimeEnvironment.setQualifiers("w360dp-h800dp-xhdpi");RuntimeEnvironment.setFontScale(1.3f);
        ActivityController<Preview> controller=Robolectric.buildActivity(Preview.class).setup();
        try {
            Preview activity=controller.get();TutorialPanel panel=panel(activity);panel.refresh();
            ScrollView scroll=new ScrollView(activity);LinearLayout root=new LinearLayout(activity);root.setOrientation(1);
            root.setPadding(32,28,32,48);root.setBackgroundColor(UiTheme.BG);root.addView(panel);scroll.addView(root);activity.setContentView(scroll);
            measure(scroll);fits(root);save(root,"sunny-collapsed-360-font1.3");
            assertFalse(button(panel,"开始练习").isEnabled());
            button(panel,"展开灯带校准").performClick();measure(scroll);fits(root);
            assertTrue(button(panel,"保存当前灯位到所选键（手机）").isEnabled());
            ((EditText)field(panel,"beatIndex")).setText("159");
            for(int i=0;i<25;i++){
                ((Spinner)field(panel,"key")).setSelection(i);
                ((EditText)field(panel,"scanIndex")).setText(String.valueOf(i*2));
                button(panel,"保存当前灯位到所选键（手机）").performClick();
            }
            button(panel,"复制校准JSON（用于下次编入FPGA）").performClick();
            ClipboardManager clipboard=(ClipboardManager)activity.getSystemService(Context.CLIPBOARD_SERVICE);
            String json=clipboard.getPrimaryClip().getItemAt(0).getText().toString();
            assertTrue(json.contains("\"48\":0")&&json.contains("\"72\":48")&&json.contains("\"beat_led\":159"));
            assertTrue(json.contains("\"speed_percent\":100,\"count_in_beats\":4,\"transpose\":-2"));
            measure(scroll);fits(root);save(root,"sunny-calibration-360-font1.3");
            panel.close();TutorialPanel again=panel(activity);
            int[] indices=(int[])field(again,"keyIndices");for(int i=0;i<25;i++)assertEquals(i*2,indices[i]);
            assertEquals("159",((EditText)field(again,"beatIndex")).getText().toString());again.close();
        }finally{controller.pause().stop().destroy();}
    }
    @Test public void ackAndWriteCompletionStayIsolatedFromLegacyScore() throws Exception {
        ActivityController<Preview> controller=Robolectric.buildActivity(Preview.class).setup();
        BleTransport transport=null;ScorePanel score=null;
        try {
            BleTransport.Listener listener=(BleTransport.Listener)Proxy.newProxyInstance(BleTransport.Listener.class.getClassLoader(),new Class<?>[]{BleTransport.Listener.class},(proxy,method,args)->null);
            transport=new BleTransport(controller.get(),listener);set(transport,"ready",true);final BleTransport peer=transport;
            score=new ScorePanel(controller.get(),new ScorePanel.Host(){public BleTransport transport(){return peer;}public void log(String text){}public void refresh(){}});
            set(score,"loaded",true);set(score,"capable",true);
            TutorialPanel guide=(TutorialPanel)field(score,"tutorial");
            ScoreTransfer transfer=(ScoreTransfer)field(guide,"transfer");
            transfer.start(Collections.singletonList(TutorialProtocol.start()));set(guide,"completedMessage","Fixture accepted");score.refresh();
            assertTrue(score.busy());assertFalse(((Button)field(score,"upload")).isEnabled());
            score.onReply(new ReplyDecoder.Reply(0x50,0));assertTrue(guide.busy());
            score.onReply(new ReplyDecoder.Reply(0x70,0));assertTrue("ACK alone cannot complete",guide.busy());
            score.onProgress(new BleTransport.SendProgress(1,1,2,true,false));
            assertFalse(guide.busy());assertEquals("Fixture accepted",((TextView)field(guide,"status")).getText().toString());
            assertTrue((Boolean)field(score,"loaded"));assertFalse((Boolean)field(score,"started"));
            assertTrue(((Button)field(score,"play")).isEnabled());
        }finally{if(score!=null)score.close();if(transport!=null)transport.close();controller.pause().stop().destroy();}
    }
    @Test public void rejectedLegacyProbeKeepsConnectionForTutorial() throws Exception {
        for(int operation:new int[]{0x55,0x52})for(boolean written:new boolean[]{false,true}){
            ActivityController<Preview> controller=Robolectric.buildActivity(Preview.class).setup();
            BleTransport transport=null;ScorePanel score=null;
            try{
                BleTransport.Listener listener=(BleTransport.Listener)Proxy.newProxyInstance(BleTransport.Listener.class.getClassLoader(),new Class<?>[]{BleTransport.Listener.class},(proxy,method,args)->null);
                transport=new BleTransport(controller.get(),listener);set(transport,"ready",true);final BleTransport peer=transport;
                score=new ScorePanel(controller.get(),new ScorePanel.Host(){public BleTransport transport(){return peer;}public void log(String text){}public void refresh(){}});
                ScoreTransfer legacy=(ScoreTransfer)field(score,"transfer");
                Score fixture=new Score("probe fixture",Arrays.asList(new Score.Event(0,60,90),new Score.Event(10,60,0)));
                legacy.start(operation==0x55?Collections.singletonList(Score.command(0x55)):
                    Arrays.asList(Score.command(0x55),fixture.uploadFrames().get(0)));
                set(score,"operation",operation);set(score,"uploadAfterProbe",true);set(score,"capable",true);set(score,"loaded",true);
                if(written)legacy.written();
                score.refresh(); // Match begin(): reserve the shared UI before callbacks.
                score.onReply(new ReplyDecoder.Reply(0x55,1));
                assertTrue("valid preflight refusal must keep BLE ready",transport.isReady());
                if(!written){
                    assertTrue("keep the shared frame slot until local completion",score.busy());
                    TutorialPanel waitingGuide=(TutorialPanel)field(score,"tutorial");
                    assertFalse(button(waitingGuide,"检查138K指引接口").isEnabled());
                    score.onReply(new ReplyDecoder.Reply(0x55,0));
                    assertTrue("a late positive ACK cannot override the refusal",score.busy());
                    score.onProgress(new BleTransport.SendProgress(1,1,2,true,false));
                }
                assertFalse(score.busy());assertFalse((Boolean)field(score,"capable"));assertFalse((Boolean)field(score,"loaded"));
                assertFalse((Boolean)field(score,"uploadAfterProbe"));
                assertTrue(((TextView)field(score,"status")).getText().toString().contains("跟灯练习"));
                // A completion callback arriving after the refusal must not send BEGIN.
                score.onProgress(new BleTransport.SendProgress(1,1,2,true,false));
                Shadows.shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(500));
                assertTrue(transport.isReady());assertFalse(score.busy());
                TutorialPanel guide=(TutorialPanel)field(score,"tutorial");
                assertTrue(button(guide,"检查138K指引接口").isEnabled());
                ScoreTransfer guideTransfer=(ScoreTransfer)field(guide,"transfer");
                guideTransfer.start(Collections.singletonList(TutorialProtocol.probe()));set(guide,"completedMessage","Tutorial probe accepted");
                score.onReply(new ReplyDecoder.Reply(0x55,1));
                assertTrue("a stale legacy refusal cannot cancel tutorial control",guide.busy());
                score.onReply(new ReplyDecoder.Reply(0x75,0));
                assertTrue("tutorial ACK still requires local completion",guide.busy());
                score.onProgress(new BleTransport.SendProgress(1,1,2,true,false));
                assertFalse(guide.busy());assertTrue(transport.isReady());
                assertEquals("Tutorial probe accepted",((TextView)field(guide,"status")).getText().toString());
            }finally{if(score!=null)score.close();if(transport!=null)transport.close();controller.pause().stop().destroy();}
        }
    }
    @Test public void staleProbeRefusalIsIgnoredAndEventErrorsStillDisconnect() throws Exception {
        ActivityController<Preview> controller=Robolectric.buildActivity(Preview.class).setup();
        BleTransport transport=null;ScorePanel score=null;
        try{
            BleTransport.Listener listener=(BleTransport.Listener)Proxy.newProxyInstance(BleTransport.Listener.class.getClassLoader(),new Class<?>[]{BleTransport.Listener.class},(proxy,method,args)->null);
            transport=new BleTransport(controller.get(),listener);set(transport,"ready",true);final BleTransport peer=transport;
            score=new ScorePanel(controller.get(),new ScorePanel.Host(){public BleTransport transport(){return peer;}public void log(String text){}public void refresh(){}});
            ScoreTransfer legacy=(ScoreTransfer)field(score,"transfer");
            legacy.start(Collections.singletonList(Score.command(0x51)));set(score,"operation",0x52);
            score.onReply(new ReplyDecoder.Reply(0x55,1));
            assertTrue(transport.isReady());assertTrue(legacy.busy());assertEquals(0x51,legacy.command());
            score.onReply(new ReplyDecoder.Reply(0x51,1));
            assertFalse("an event rejection still requires recovery",transport.isReady());assertFalse(score.busy());
            set(transport,"ready",true);legacy.start(Collections.singletonList(Score.command(0x55)));set(score,"operation",0x55);
            score.onReply(new ReplyDecoder.Reply(0x55,2));
            assertFalse("a checksum error is not a clean interface refusal",transport.isReady());assertFalse(score.busy());
        }finally{if(score!=null)score.close();if(transport!=null)transport.close();controller.pause().stop().destroy();}
    }
    private static Object field(Object target,String name)throws Exception{Field value=target.getClass().getDeclaredField(name);value.setAccessible(true);return value.get(target);}
    private static void set(Object target,String name,Object value)throws Exception{Field member=target.getClass().getDeclaredField(name);member.setAccessible(true);member.set(target,value);}
    private static Button button(View root,String label){
        if(root instanceof Button&&((Button)root).getText().toString().equals(label))return (Button)root;
        if(root instanceof ViewGroup){ViewGroup group=(ViewGroup)root;for(int i=0;i<group.getChildCount();i++){Button found=button(group.getChildAt(i),label);if(found!=null)return found;}}
        return null;
    }
    private static void measure(View view){view.measure(View.MeasureSpec.makeMeasureSpec(UiTheme.dp(view,360),View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(UiTheme.dp(view,800),View.MeasureSpec.EXACTLY));view.layout(0,0,view.getMeasuredWidth(),view.getMeasuredHeight());Shadows.shadowOf(Looper.getMainLooper()).idle();}
    private static void fits(View view){
        if(view.getVisibility()!=View.VISIBLE)return;
        if(view instanceof TextView){TextView text=(TextView)view;if(text.getLayout()!=null&&!text.isSingleLine())assertTrue("Clipped text: "+text.getText(),text.getLayout().getHeight()<=text.getHeight()-text.getTotalPaddingTop()-text.getTotalPaddingBottom()+1);}
        if(view instanceof ViewGroup){ViewGroup group=(ViewGroup)view;for(int i=0;i<group.getChildCount();i++)fits(group.getChildAt(i));}
    }
    private static void save(View root,String name)throws Exception{
        File directory=new File(System.getProperty("qa.screens"));directory.mkdirs();
        Bitmap bitmap=Bitmap.createBitmap(root.getWidth(),root.getHeight(),Bitmap.Config.ARGB_8888);root.draw(new Canvas(bitmap));
        try(FileOutputStream file=new FileOutputStream(new File(directory,name+".png"))){assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG,100,file));}bitmap.recycle();
    }
}
