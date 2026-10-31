package com.gowin.instrument;

import android.app.Activity;
import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.os.Bundle;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Proxy;
import java.util.Arrays;
import java.util.zip.CRC32;
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

/** Desktop Android runtime checks; no real Bluetooth, network actions or board access. */
@RunWith(RobolectricTestRunner.class)
@Config(manifest=Config.NONE, sdk=35)
@LooperMode(LooperMode.Mode.PAUSED)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class NativeUiTest {
    public static class DarkActivity extends Activity {
        @Override public void onCreate(Bundle state) {
            setTheme(android.R.style.Theme_Material_NoActionBar);
            super.onCreate(state);
        }
    }

    public static class PreviewActivity extends MainActivity {
        @Override protected void onCreate(Bundle state) {
            setTheme(android.R.style.Theme_Material_NoActionBar);
            try {
                AssetManager.class.getDeclaredMethod("addAssetPath",String.class)
                    .invoke(getAssets(),System.getProperty("qa.apk","E:/gaoyun111111/android_control/outputs/Gowin-JDY23-Android-v0.4.6-r1.apk"));
            }catch(Exception exception){throw new IllegalStateException("Cannot load built APK assets",exception);}
            super.onCreate(state);
        }
    }

    @Test public void actualFourPagesOpenAndPreserveToneInput() throws Exception {
        RuntimeEnvironment.setQualifiers("w360dp-h800dp-xhdpi");
        ActivityController<PreviewActivity> controller=Robolectric.buildActivity(PreviewActivity.class).setup();
        try {
            PreviewActivity activity=controller.get();
            for(int i=0;i<200&&!((Boolean)mainField(activity,"presetReady"));i++){
                Thread.sleep(10);Shadows.shadowOf(Looper.getMainLooper()).idle();
            }
            assertTrue("default preset from built APK failed to load",(Boolean)mainField(activity,"presetReady"));
            AppNavigation nav=(AppNavigation)mainField(activity,"navigation");
            for(int page=0;page<4;page++){
                nav.show(page,null);measure(nav.shell,360,800);assertTextFits(nav.shell);
                save(nav.shell,"app-page-"+page+"-360",nav.shell.getHeight());
            }
            android.widget.EditText name=(android.widget.EditText)mainField(activity,"etName");
            nav.show(2,null);name.setText("保留编辑值");nav.show(1,null);nav.show(2,null);
            assertEquals("保留编辑值",name.getText().toString());
            activity.onDisconnected("UI runtime disconnect fixture");
            assertFalse(((Button)mainField(activity,"btnSendTone")).isEnabled());
        }finally{controller.pause().stop().destroy();}
    }

    @Test public void scoreControlsFitSmallPhoneAndLargeFont() throws Exception {
        scoreCase(360, 1.0f);
        scoreCase(412, 1.3f);
    }

    private void scoreCase(int widthDp, float scale) throws Exception {
        RuntimeEnvironment.setQualifiers("w"+widthDp+"dp-h800dp-xhdpi");
        RuntimeEnvironment.setFontScale(scale);
        ActivityController<DarkActivity> controller=Robolectric.buildActivity(DarkActivity.class).setup();
        try {
            DarkActivity activity=controller.get();
            ScorePanel panel=new ScorePanel(activity,new ScorePanel.Host(){
                public BleTransport transport(){return null;}
                public void log(String text){}
                public void refresh(){}
            });
            panel.setLegacyExpanded(true);
            LinearLayout root=new LinearLayout(activity);root.setOrientation(LinearLayout.VERTICAL);
            root.setPadding(UiTheme.dp(root,16),UiTheme.dp(root,14),UiTheme.dp(root,16),UiTheme.dp(root,24));
            root.setBackgroundColor(UiTheme.BG);root.addView(panel,new LinearLayout.LayoutParams(-1,-2));
            android.widget.ScrollView viewport=new android.widget.ScrollView(activity);
            viewport.addView(root);
            activity.setContentView(viewport);
            measure(viewport,widthDp,800);
            int before=root.getMeasuredHeight();
            for(int i=0;i<panel.getChildCount();i++){
                View card=panel.getChildAt(i);
                assertTrue("card gap missing",((ViewGroup.MarginLayoutParams)card.getLayoutParams()).bottomMargin>=UiTheme.dp(card,12));
            }
            SeekBar volume=(SeekBar)field(panel,"volumeBar");
            assertTrue("volume touch target too small",volume.getHeight()>=UiTheme.dp(volume,48));
            Button upload=(Button)field(panel,"upload"),play=(Button)field(panel,"play"),stop=(Button)field(panel,"stop");
            assertFalse(upload.isEnabled());assertFalse(play.isEnabled());assertFalse(stop.isEnabled());
            Button apply=(Button)field(panel,"volumeApply"),mute=(Button)field(panel,"volumeMute"),restore=(Button)field(panel,"volumeRestore");
            assertTrue("primary volume action should use full width",apply.getWidth()>mute.getWidth());
            assertTrue(mute.getWidth()>0&&restore.getWidth()>0);
            assertTextFits(root);
            save(root,"score-"+widthDp+"-font"+scale,before);
            volume.setProgress(16);
            assertEquals(16,volume.getProgress());
            assertFalse("choosing volume must not make sending available",apply.isEnabled());
            panel.close();
        }finally{controller.pause().stop().destroy();}
    }

    @Test public void navigationKeepsEditorsAndHandlesBack() throws Exception {
        RuntimeEnvironment.setQualifiers("w360dp-h800dp-xhdpi");
        ActivityController<DarkActivity> controller=Robolectric.buildActivity(DarkActivity.class).setup();
        try {
            DarkActivity activity=controller.get();
            android.widget.ScrollView scroll=new android.widget.ScrollView(activity);
            LinearLayout body=new LinearLayout(activity);body.setOrientation(LinearLayout.VERTICAL);scroll.addView(body);
            TextView[] content=new TextView[4];
            for(int i=0;i<4;i++){content[i]=UiTheme.body(activity,"页面 "+i);body.addView(content[i]);}
            AppNavigation nav=new AppNavigation(activity,body,scroll,new int[]{0,1,2,3});
            activity.setContentView(nav.shell);measure(nav.shell,360,800);
            nav.show(2,null);content[2].setText("未发送的编辑值");
            nav.show(1,null);nav.show(2,null);
            assertEquals("未发送的编辑值",content[2].getText().toString());
            assertEquals(View.VISIBLE,((View)content[2].getParent()).getVisibility());
            assertTrue(nav.back());assertFalse(nav.back());
            Bundle saved=new Bundle();nav.show(3,null);nav.save(saved);nav.show(0,null);nav.restore(saved);
            assertEquals(3,saved.getInt("navigation_page"));
            nav.status(true,false,true);Shadows.shadowOf(Looper.getMainLooper()).idle();
            measure(nav.shell,360,800);assertTextFits(nav.shell);
            save(nav.shell,"navigation-360",nav.shell.getHeight());
        }finally{controller.pause().stop().destroy();}
    }

    @Test public void sealedScoreReconnectAndPeerRestriction() throws Exception {
        ActivityController<DarkActivity> controller=Robolectric.buildActivity(DarkActivity.class).setup();
        BleTransport transport=null;ScorePanel panel=null;
        try {
            transport=transport(controller.get());final BleTransport peer=transport;
            panel=new ScorePanel(controller.get(),new ScorePanel.Host(){public BleTransport transport(){return peer;}public void log(String text){}public void refresh(){}});
            Score score=new Score("retained song",Arrays.asList(new Score.Event(0,60,90),new Score.Event(10,60,0)));
            ReliableScoreTransfer transfer=(ReliableScoreTransfer)field(panel,"reliable");long session=0x1020304050607080L;
            transfer.start(score,testCapabilities(),session);
            byte[] eventBytes=new byte[12];eventBytes[4]=60;eventBytes[5]=90;eventBytes[6]=10;eventBytes[10]=60;
            CRC32 crc=new CRC32();crc.update(eventBytes);long value=crc.getValue();
            finishLocal(transfer,reply(1,0,session,0,2,1,2,0));finishLocal(transfer,reply(2,0,session,2,2,1,2,value));finishLocal(transfer,reply(3,0,session,2,2,2,2,value));
            set(panel,"score",score);set(panel,"loaded",true);set(panel,"capable",true);set(panel,"reliablePeer","AA:BB:CC:DD:EE:01");panel.refresh();
            assertTrue(((Button)field(panel,"play")).isEnabled());panel.disconnected();assertFalse(((Button)field(panel,"play")).isEnabled());
            set(transport,"peerAddress","AA:BB:CC:DD:EE:02");panel.refresh();assertFalse("another device cannot resume",((Button)field(panel,"resumeReliable")).isEnabled());assertFalse(((Button)field(panel,"releaseReliable")).isEnabled());
            set(transport,"peerAddress","AA:BB:CC:DD:EE:01");panel.refresh();assertTrue(((Button)field(panel,"resumeReliable")).isEnabled());
            transfer.resume();set(panel,"operation",0x52);panel.onReply(new ReplyDecoder.Reply(ReliableScoreProtocol.decode(reply(4,0,session,2,2,2,2,value))));
            assertFalse("valid ACK alone cannot enable Play",((Boolean)field(panel,"loaded")));panel.onProgress(new BleTransport.SendProgress(4,4,2,true,false));Shadows.shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(450));
            assertTrue("sealed query restores Play after reconnect",((Boolean)field(panel,"loaded")));assertTrue(((Button)field(panel,"play")).isEnabled());
            Score next=new Score("next song",Arrays.asList(new Score.Event(0,64,70),new Score.Event(20,64,0)));set(panel,"score",next);
            transfer.abort();set(panel,"operation",0x65);panel.onReply(new ReplyDecoder.Reply(ReliableScoreProtocol.decode(reply(5,0,session,0,0,0,0,0))));panel.onProgress(new BleTransport.SendProgress(4,4,2,true,false));Shadows.shadowOf(Looper.getMainLooper()).idle();
            assertFalse(transfer.hasSession());assertSame("releasing prior session must retain newly parsed song",next,field(panel,"score"));assertFalse(((Boolean)field(panel,"loaded")));
        }finally{if(panel!=null)panel.close();if(transport!=null)transport.close();controller.pause().stop().destroy();}
    }

    @Test public void recoveryQueryRequiresOwnF2AndLocalCompletion() throws Exception {
        ActivityController<DarkActivity> controller=Robolectric.buildActivity(DarkActivity.class).setup();BleTransport transport=null;ScorePanel panel=null;
        try {
            transport=transport(controller.get());final BleTransport peer=transport;
            panel=new ScorePanel(controller.get(),new ScorePanel.Host(){public BleTransport transport(){return peer;}public void log(String text){}public void refresh(){}});
            set(panel,"recovering",true);set(panel,"recoverySession",123L);set(panel,"operation",0x64);panel.refresh();assertTrue(panel.busy());assertFalse(((Button)field(panel,"probe")).isEnabled());
            panel.onReply(new ReplyDecoder.Reply(ReliableScoreProtocol.decode(reply(4,3,124,0,0,0,0,0))));assertNull(field(panel,"recoveryReply"));
            panel.onReply(new ReplyDecoder.Reply(0x55,0));assertNull(field(panel,"recoveryReply"));
            panel.onReply(new ReplyDecoder.Reply(ReliableScoreProtocol.decode(reply(4,3,123,0,0,0,0,0))));assertTrue("F2 alone is insufficient",panel.busy());
            panel.onProgress(new BleTransport.SendProgress(4,4,2,true,false));assertFalse(panel.busy());assertFalse((Boolean)field(panel,"loaded"));assertTrue(((Button)field(panel,"probe")).isEnabled());assertFalse(((Button)field(panel,"play")).isEnabled());
            assertTrue(((TextView)field(panel,"status")).getText().toString().contains("不表示曲谱上传成功"));
        }finally{if(panel!=null)panel.close();if(transport!=null)transport.close();controller.pause().stop().destroy();}
    }

    private static BleTransport transport(Activity activity)throws Exception {
        BleTransport.Listener listener=(BleTransport.Listener)Proxy.newProxyInstance(BleTransport.Listener.class.getClassLoader(),new Class<?>[]{BleTransport.Listener.class},(proxy,method,args)->null);
        BleTransport t=new BleTransport(activity,listener);set(t,"ready",true);set(t,"peerAddress","AA:BB:CC:DD:EE:01");return t;
    }
    private static void set(Object target,String name,Object value)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);f.set(target,value);}
    private static ScoreCapabilities testCapabilities(){byte[] b=new byte[20];b[0]=(byte)0xa5;b[1]=0x5a;b[2]=(byte)0xf1;b[3]=1;b[4]=0x57;ReliableScoreProtocol.le(b,5,0x12345678,4);ReliableScoreProtocol.le(b,9,8192,2);b[11]=12;b[12]=8;b[13]=3;ReliableScoreProtocol.le(b,14,115200,4);b[18]=2;for(int i=2;i<19;i++)b[19]^=b[i];return ScoreCapabilities.decode(b);}
    private static byte[] reply(int kind,int status,long session,int next,int total,int state,int limit,long scoreCrc){
        byte[] b=new byte[32];b[0]=(byte)0xa5;b[1]=0x5a;b[2]=(byte)0xf2;b[3]=1;b[4]=(byte)kind;b[5]=(byte)status;ReliableScoreProtocol.le(b,6,session,8);ReliableScoreProtocol.le(b,14,next,2);ReliableScoreProtocol.le(b,16,limit,2);ReliableScoreProtocol.le(b,18,total,2);b[20]=(byte)state;b[21]=8;ReliableScoreProtocol.le(b,22,scoreCrc,4);ReliableScoreProtocol.le(b,28,ReliableScoreProtocol.crc(b,2,26),4);return b;
    }
    private static void finishLocal(ReliableScoreTransfer t,byte[] reply){t.written();assertTrue(t.accept(ReliableScoreProtocol.decode(reply)));t.advance();}

    private static Object field(Object target,String name)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(target);}
    private static Object mainField(Object target,String name)throws Exception{Field f=MainActivity.class.getDeclaredField(name);f.setAccessible(true);return f.get(target);}
    private static void measure(View view,int widthDp,int heightDp){
        int width=UiTheme.dp(view,widthDp),height=UiTheme.dp(view,heightDp);
        view.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(height,View.MeasureSpec.EXACTLY));
        view.layout(0,0,view.getMeasuredWidth(),view.getMeasuredHeight());
        Shadows.shadowOf(Looper.getMainLooper()).idle();
    }
    private static void assertTextFits(View view){
        if(view.getVisibility()!=View.VISIBLE)return;
        if(view instanceof TextView){TextView text=(TextView)view;
            if(text.getLayout()!=null&&!text.isSingleLine())assertTrue("text height clipped: "+text.getText(),text.getLayout().getHeight()<=text.getHeight()-text.getTotalPaddingTop()-text.getTotalPaddingBottom()+1);
        }
        if(view instanceof ViewGroup){ViewGroup group=(ViewGroup)view;for(int i=0;i<group.getChildCount();i++)assertTextFits(group.getChildAt(i));}
    }
    private static void save(View root,String name,int height)throws Exception{
        File dir=new File(System.getProperty("qa.screens"));dir.mkdirs();
        Bitmap bitmap=Bitmap.createBitmap(root.getWidth(),Math.min(height,root.getHeight()),Bitmap.Config.ARGB_8888);
        root.draw(new Canvas(bitmap));
        try(FileOutputStream output=new FileOutputStream(new File(dir,name+".png"))){assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG,100,output));}
        bitmap.recycle();
    }
}

