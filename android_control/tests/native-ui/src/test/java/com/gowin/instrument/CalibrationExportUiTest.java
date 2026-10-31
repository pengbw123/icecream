package com.gowin.instrument;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.net.Uri;
import android.os.Bundle;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.widget.*;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.Collections;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import org.robolectric.annotation.LooperMode;
import org.robolectric.shadows.ShadowAlertDialog;
import static org.junit.Assert.*;

@RunWith(org.robolectric.RobolectricTestRunner.class)
@Config(manifest=Config.NONE,sdk=35)
@LooperMode(LooperMode.Mode.PAUSED)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class CalibrationExportUiTest {
    private static final int[] REAL={45,43,41,40,7,38,36,34,32,30,28,27,25,23,21,6,16,14,11,8,9,60,5,4,1};
    @Test public void mappingDialogFitsLargeTextAndLandscape()throws Exception{
        for(int[] size:new int[][]{{320,640,200},{800,360,150}}){
            RuntimeEnvironment.setQualifiers("w"+size[0]+"dp-h"+size[1]+"dp-xhdpi");RuntimeEnvironment.setFontScale(size[2]/100f);
            ActivityController<NativeUiTest.DarkActivity> controller=Robolectric.buildActivity(NativeUiTest.DarkActivity.class).setup();TutorialPanel panel=null;
            try{
                Activity activity=controller.get();panel=new TutorialPanel(activity,new TutorialPanel.Host(){public BleTransport transport(){return null;}public boolean otherBusy(){return false;}public void log(String s){}public void refresh(){}});
                System.arraycopy(REAL,0,(int[])field(panel,"keyIndices"),0,25);panel.refresh();((Button)field(panel,"detailsButton")).performClick();Shadows.shadowOf(Looper.getMainLooper()).idle();
                AlertDialog dialog=ShadowAlertDialog.getLatestAlertDialog();View view=dialog.getWindow().getDecorView();
                view.measure(View.MeasureSpec.makeMeasureSpec(UiTheme.dp(view,size[0]-24),View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(UiTheme.dp(view,size[1]-48),View.MeasureSpec.AT_MOST));
                view.layout(0,0,view.getMeasuredWidth(),view.getMeasuredHeight());fits(view);
                for(int id:new int[]{AlertDialog.BUTTON_POSITIVE,AlertDialog.BUTTON_NEGATIVE,AlertDialog.BUTTON_NEUTRAL}){
                    Button b=dialog.getButton(id);assertTrue(b.getWidth()>0);assertTrue(b.getHeight()>0);
                    android.graphics.Rect box=new android.graphics.Rect();b.getDrawingRect(box);((ViewGroup)view).offsetDescendantRectToMyCoords(b,box);
                    assertTrue("dialog action below screen",box.bottom<=view.getHeight());
                }
                Bitmap bitmap=Bitmap.createBitmap(view.getWidth(),view.getHeight(),Bitmap.Config.ARGB_8888);view.draw(new Canvas(bitmap));
                try(FileOutputStream output=new FileOutputStream(new File(System.getProperty("qa.screens"),"led-map-dialog-"+size[0]+"-font"+size[2]+".png"))){assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG,100,output));}bitmap.recycle();dialog.dismiss();
            }finally{if(panel!=null)panel.close();controller.pause().stop().destroy();}
        }
    }
    @Test public void partialExportIsOfflineAndNeverInventsMappings()throws Exception{
        ActivityController<NativeUiTest.DarkActivity> controller=Robolectric.buildActivity(NativeUiTest.DarkActivity.class).setup();
        TutorialPanel panel=null;
        try{
            Activity activity=controller.get();final String[] exported={null};
            panel=new TutorialPanel(activity,new TutorialPanel.Host(){
                public BleTransport transport(){return null;}public boolean otherBusy(){return false;}
                public void log(String text){}public void refresh(){}public void exportLedMap(String csv){exported[0]=csv;}
            });panel.refresh();
            assertFalse(((Button)field(panel,"copyButton")).isEnabled());
            ((EditText)field(panel,"scanIndex")).setText("45");button(panel,"保存当前灯位到所选键（手机）").performClick();
            ((Button)field(panel,"detailsButton")).performClick();
            AlertDialog dialog=ShadowAlertDialog.getLatestAlertDialog();assertTrue(dialog.isShowing());
            dialog.getButton(AlertDialog.BUTTON_NEUTRAL).performClick();
            Shadows.shadowOf(Looper.getMainLooper()).idle();
            String csv=((ClipboardManager)activity.getSystemService(Context.CLIPBOARD_SERVICE)).getPrimaryClip().getItemAt(0).getText().toString();
            assertEquals(26,csv.split("\r\n").length);assertTrue(csv.contains("1,48,45,46,手机已保存\r\n"));
            assertTrue(csv.contains("2,49,,,未校准\r\n"));assertTrue(csv.contains("25,72,,,未校准\r\n"));
            assertFalse(panel.busy());assertFalse(((Button)field(panel,"copyButton")).isEnabled());
            ((Button)field(panel,"detailsButton")).performClick();ShadowAlertDialog.getLatestAlertDialog().getButton(AlertDialog.BUTTON_POSITIVE).performClick();
            Shadows.shadowOf(Looper.getMainLooper()).idle();
            assertEquals(csv,exported[0]);
        }finally{if(panel!=null)panel.close();controller.pause().stop().destroy();}
    }
    @Test public void key22ReportsDuplicateNearbyThenExportsItsActualValue()throws Exception{
        ActivityController<NativeUiTest.DarkActivity> controller=Robolectric.buildActivity(NativeUiTest.DarkActivity.class).setup();TutorialPanel panel=null;
        try{
            Activity activity=controller.get();panel=new TutorialPanel(activity,new TutorialPanel.Host(){
                public BleTransport transport(){return null;}public boolean otherBusy(){return false;}public void log(String text){}public void refresh(){}
            });panel.refresh();int[] values=(int[])field(panel,"keyIndices");
            System.arraycopy(REAL,0,values,0,25);values[21]=-1;
            ((Spinner)field(panel,"key")).setSelection(21);((EditText)field(panel,"scanIndex")).setText("9");
            button(panel,"保存当前灯位到所选键（手机）").performClick();
            assertEquals(-1,values[21]);TextView feedback=(TextView)field(panel,"calibrationFeedback");
            assertTrue(feedback.getText().toString().contains("第21键"));assertEquals(UiTheme.DANGER,feedback.getCurrentTextColor());
            ((EditText)field(panel,"scanIndex")).setText("60");button(panel,"保存当前灯位到所选键（手机）").performClick();
            assertEquals(60,values[21]);assertTrue(feedback.getText().toString().contains("第22键"));
            ((Button)field(panel,"detailsButton")).performClick();ShadowAlertDialog.getLatestAlertDialog().getButton(AlertDialog.BUTTON_NEUTRAL).performClick();
            Shadows.shadowOf(Looper.getMainLooper()).idle();
            String csv=((ClipboardManager)activity.getSystemService(Context.CLIPBOARD_SERVICE)).getPrimaryClip().getItemAt(0).getText().toString();
            assertTrue(csv.contains("22,69,60,61,手机已保存\r\n"));assertTrue(((Button)field(panel,"copyButton")).isEnabled());
        }finally{if(panel!=null)panel.close();controller.pause().stop().destroy();}
    }
    @Test public void fileExportKeepsSnapshotAcrossRotationAndUsesUtf8Bom()throws Exception{
        ActivityController<NativeUiTest.PreviewActivity> controller=Robolectric.buildActivity(NativeUiTest.PreviewActivity.class).setup();
        try{
            MainActivity activity=controller.get();Method begin=MainActivity.class.getDeclaredMethod("startLedMapExport",String.class);begin.setAccessible(true);
            String csv="琴键序号,MIDI编号,灯珠编号\r\n22,69,60\r\n";begin.invoke(activity,csv);
            org.robolectric.shadows.ShadowActivity.IntentForResult request=Shadows.shadowOf(activity).getNextStartedActivityForResult();
            assertEquals(Intent.ACTION_CREATE_DOCUMENT,request.intent.getAction());assertEquals("text/csv",request.intent.getType());assertEquals(1005,request.requestCode);
            assertEquals("gowin_25key_led_map.csv",request.intent.getStringExtra(Intent.EXTRA_TITLE));
            controller.recreate();activity=controller.get();assertEquals(csv,field(activity,"pendingLedMapCsv"));
            File destination=new File(System.getProperty("qa.screens"),"saved-led-map.csv");
            activity.onActivityResult(1005,Activity.RESULT_OK,new Intent().setData(Uri.fromFile(destination)));
            for(int i=0;i<200&&(!destination.isFile()||destination.length()==0);i++){Thread.sleep(5);Shadows.shadowOf(Looper.getMainLooper()).idle();}
            byte[] bytes=Files.readAllBytes(destination.toPath());assertArrayEquals(new byte[]{(byte)0xEF,(byte)0xBB,(byte)0xBF},Arrays.copyOf(bytes,3));
            assertEquals(csv,new String(bytes,3,bytes.length-3,StandardCharsets.UTF_8));assertNull(field(activity,"pendingLedMapCsv"));
            begin.invoke(activity,csv);activity.onActivityResult(1005,Activity.RESULT_CANCELED,null);assertNull(field(activity,"pendingLedMapCsv"));
        }finally{controller.pause().stop().destroy();}
    }
    @Test public void scoreProbeUnlocks138kUploadWithoutEnablingToneOrVolume()throws Exception{
        ActivityController<NativeUiTest.DarkActivity> controller=Robolectric.buildActivity(NativeUiTest.DarkActivity.class).setup();
        BleTransport peer=null;ScorePanel panel=null;
        try{
            Activity activity=controller.get();BleTransport.Listener listener=(BleTransport.Listener)Proxy.newProxyInstance(BleTransport.Listener.class.getClassLoader(),new Class<?>[]{BleTransport.Listener.class},(p,m,a)->null);
            peer=new BleTransport(activity,listener);set(peer,"ready",true);final BleTransport transport=peer;
            panel=new ScorePanel(activity,new ScorePanel.Host(){public BleTransport transport(){return transport;}public boolean legacyEnabled(){return false;}public boolean scoreEnabled(){return true;}public void log(String s){}public void refresh(){}});
            set(panel,"score",new Score("fixture",Arrays.asList(new Score.Event(0,60,80),new Score.Event(50,60,0))));panel.refresh();
            assertTrue(((Button)field(panel,"probe")).isEnabled());assertFalse(((Button)field(panel,"upload")).isEnabled());
            // Inject the already-isolated detection completion; no fake GATT is used.
            set(panel,"capable",true);set(panel,"operation",0x57);set(panel,"capabilityNonce",123L);
            ScoreTransfer transfer=(ScoreTransfer)field(panel,"transfer");transfer.start(Collections.singletonList(ScoreCapabilities.query(123)));
            byte[] cap={(byte)0xA5,0x5A,(byte)0xF1,1,0x57,123,0,0,0,0,32,16,8,1,0,(byte)0xC2,1,0,1,0};
            for(int i=2;i<19;i++)cap[19]^=cap[i];
            panel.onReply(new ReplyDecoder.Reply(ScoreCapabilities.decode(cap)));assertTrue(panel.busy());
            panel.onProgress(new BleTransport.SendProgress(1,1,2,true,false));Shadows.shadowOf(Looper.getMainLooper()).idle();
            assertFalse(panel.busy());assertTrue(((Button)field(panel,"upload")).isEnabled());
            assertFalse(((Button)field(panel,"volumeApply")).isEnabled());assertEquals(5,((Spinner)field(panel,"mode")).getSelectedItemPosition());
            set(panel,"loaded",true);set(panel,"operation",0x53);transfer.start(Collections.singletonList(Score.command(0x53)));
            panel.onReply(new ReplyDecoder.Reply(0x53,1));assertTrue(panel.busy());assertTrue(peer.isReady());
            panel.onProgress(new BleTransport.SendProgress(1,1,2,true,false));assertFalse(panel.busy());assertTrue(peer.isReady());assertTrue((Boolean)field(panel,"loaded"));
            assertTrue(((TextView)field(panel,"status")).getText().toString().contains("先停止跟灯练习"));
        }finally{if(panel!=null)panel.close();if(peer!=null)peer.close();controller.pause().stop().destroy();}
    }
    @Test public void modeRefusalWaitsForLocalWriteAndKeepsSavedKeys()throws Exception{
        ActivityController<NativeUiTest.DarkActivity> controller=Robolectric.buildActivity(NativeUiTest.DarkActivity.class).setup();BleTransport peer=null;TutorialPanel panel=null;
        try{
            BleTransport.Listener listener=(BleTransport.Listener)Proxy.newProxyInstance(BleTransport.Listener.class.getClassLoader(),new Class<?>[]{BleTransport.Listener.class},(p,m,a)->null);
            peer=new BleTransport(controller.get(),listener);set(peer,"ready",true);final BleTransport transport=peer;
            panel=new TutorialPanel(controller.get(),new TutorialPanel.Host(){public BleTransport transport(){return transport;}public boolean otherBusy(){return false;}public void log(String text){}public void refresh(){}});
            int[] values=(int[])field(panel,"keyIndices");System.arraycopy(REAL,0,values,0,25);
            ScoreTransfer transfer=(ScoreTransfer)field(panel,"transfer");transfer.start(Collections.singletonList(TutorialProtocol.mode(true)));panel.refresh();
            panel.onReply(new ReplyDecoder.Reply(0x76,1));assertTrue(panel.busy());assertTrue(peer.isReady());
            panel.onProgress(new BleTransport.SendProgress(1,1,2,true,false));assertFalse(panel.busy());assertTrue(peer.isReady());
            assertArrayEquals(REAL,values);assertTrue(((TextView)field(panel,"status")).getText().toString().contains("配套的等键练习版"));
        }finally{if(panel!=null)panel.close();if(peer!=null)peer.close();controller.pause().stop().destroy();}
    }
    private static Object field(Object target,String name)throws Exception{Class<?> type=target.getClass();while(type!=null){try{Field value=type.getDeclaredField(name);value.setAccessible(true);return value.get(target);}catch(NoSuchFieldException ex){type=type.getSuperclass();}}throw new NoSuchFieldException(name);}
    private static void set(Object target,String name,Object value)throws Exception{Field member=target.getClass().getDeclaredField(name);member.setAccessible(true);member.set(target,value);}
    private static Button button(View root,String label){if(root instanceof Button&&label.contentEquals(((Button)root).getText()))return (Button)root;if(root instanceof ViewGroup){ViewGroup g=(ViewGroup)root;for(int i=0;i<g.getChildCount();i++){Button found=button(g.getChildAt(i),label);if(found!=null)return found;}}return null;}
    private static void fits(View root){if(root.getVisibility()!=View.VISIBLE)return;if(root instanceof TextView){TextView text=(TextView)root;if(text.getLayout()!=null&&!text.isSingleLine())assertTrue("clipped dialog text: "+text.getText(),text.getLayout().getHeight()<=text.getHeight()-text.getTotalPaddingTop()-text.getTotalPaddingBottom()+1);}if(root instanceof ViewGroup){ViewGroup g=(ViewGroup)root;for(int i=0;i<g.getChildCount();i++)fits(g.getChildAt(i));}}
}
