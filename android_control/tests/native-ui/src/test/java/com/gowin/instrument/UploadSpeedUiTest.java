package com.gowin.instrument;

import android.app.Activity;
import android.bluetooth.*;
import android.os.Looper;
import android.os.SystemClock;
import android.widget.*;
import java.io.ByteArrayOutputStream;
import java.lang.reflect.*;
import java.nio.file.*;
import java.time.Duration;
import java.util.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.*;
import org.robolectric.shadow.api.Shadow;
import static org.junit.Assert.*;

/** Real transport queue, controllable Android GATT callbacks; no physical BLE claims. */
@RunWith(RobolectricTestRunner.class)
@Config(manifest=Config.NONE,sdk=35,shadows=UploadSpeedUiTest.CaptureGatt.class)
@LooperMode(LooperMode.Mode.PAUSED)
public class UploadSpeedUiTest {
    @Implements(BluetoothGatt.class)
    public static class CaptureGatt {
        BluetoothGattService service;
        final List<byte[]> bytes=new ArrayList<>();
        final List<Integer> types=new ArrayList<>();
        final List<Long> times=new ArrayList<>();
        int submitStatus;
        @Implementation protected BluetoothGattService getService(UUID id){return service!=null&&service.getUuid().equals(id)?service:null;}
        @Implementation protected void disconnect(){}
        @Implementation protected void close(){}
        @Implementation protected boolean requestConnectionPriority(int value){return true;}
        @Implementation(minSdk=33) protected int writeCharacteristic(BluetoothGattCharacteristic c,byte[] value,int type){record(value,type);return submitStatus;}
        @Implementation protected boolean writeCharacteristic(BluetoothGattCharacteristic c){record(c.getValue(),c.getWriteType());return true;}
        private void record(byte[] value,int type){bytes.add(value.clone());types.add(type);times.add(SystemClock.elapsedRealtime());}
    }
    private static final class Peer implements AutoCloseable {
        final ActivityController<NativeUiTest.DarkActivity> controller=Robolectric.buildActivity(NativeUiTest.DarkActivity.class).setup();
        final List<BleTransport.SendProgress> progress=new ArrayList<>();
        final BleTransport transport;final CaptureGatt capture;ScorePanel panel;
        Peer(boolean noResponse)throws Exception{
            BleTransport.Listener listener=(BleTransport.Listener)Proxy.newProxyInstance(BleTransport.Listener.class.getClassLoader(),new Class<?>[]{BleTransport.Listener.class},(p,m,a)->{
                if(m.getName().equals("onSendProgress")){BleTransport.SendProgress value=(BleTransport.SendProgress)a[0];progress.add(value);if(panel!=null)panel.onProgress(value);}return null;
            });
            transport=new BleTransport(controller.get(),listener);
            BluetoothGatt gatt=Shadow.newInstanceOf(BluetoothGatt.class);
            capture=Shadow.extract(gatt);capture.service=new BluetoothGattService(BleTransport.SERVICE_UUID,BluetoothGattService.SERVICE_TYPE_PRIMARY);
            capture.service.addCharacteristic(new BluetoothGattCharacteristic(BleTransport.NOTIFY_UUID,BluetoothGattCharacteristic.PROPERTY_WRITE|BluetoothGattCharacteristic.PROPERTY_NOTIFY|(noResponse?BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE:0),BluetoothGattCharacteristic.PERMISSION_WRITE));
            set(transport,"gatt",gatt);set(transport,"ready",true);set(transport,"linkUp",true);
        }
        void completeWrite()throws Exception{call(transport,"handleCharacteristicWrite",new Class<?>[]{UUID.class,int.class},BleTransport.NOTIFY_UUID,0);idle();}
        public void close(){if(panel!=null)panel.close();transport.close();controller.pause().stop().destroy();}
    }
    @Test public void negotiatedAutoUploadsRealTruthPartIn200GroupsWithExactBytes()throws Exception{
        try(Peer peer=new Peer(true)){
            peer.panel=new ScorePanel(peer.controller.get(),new ScorePanel.Host(){public BleTransport transport(){return peer.transport;}public boolean legacyEnabled(){return false;}public boolean scoreEnabled(){return true;}public void log(String s){}public void refresh(){}});
            byte[] midi;try(java.util.zip.ZipFile apk=new java.util.zip.ZipFile(System.getProperty("qa.apk"))){try(java.io.InputStream input=apk.getInputStream(apk.getEntry("assets/scores/the_truth_that_you_leave_part2.mid"))){midi=input.readAllBytes();}}
            Score score=Score.fromMidi("Truth part 2",midi);
            assertEquals(1574,score.events.size());set(peer.panel,"score",score);set(peer.panel,"capable",true);set(peer.panel,"capabilitiesChecked",true);set(peer.panel,"capabilities",caps());peer.panel.refresh();
            assertEquals(5,((Spinner)field(peer.panel,"mode")).getSelectedItemPosition());((Button)field(peer.panel,"upload")).performClick();idle();
            assertEquals(3,field(peer.panel,"uploadMode"));ScoreTransfer transfer=(ScoreTransfer)field(peer.panel,"transfer");int groups=0;
            while(transfer.busy()){
                assertTrue("upload stalled: "+transfer.waitingSummary(),groups<201);
                int cmd=transfer.command(),count=transfer.groupSize(),done=transfer.done();
                assertTrue(transfer.windowed());assertTrue(count<=8);assertTrue(peer.transport.isSending());
                // Both callback orders must work; neither local-only nor ACK-only may advance.
                if(groups%2==0){for(int a=0;a<count;a++)peer.panel.onReply(new ReplyDecoder.Reply(cmd,0));assertEquals(done,transfer.done());}
                int callbacks=0;
                while(transfer.done()==done&&peer.transport.isSending()){
                    assertTrue("GATT stalled: "+transfer.waitingSummary(),callbacks++<8);
                    assertEquals(4,field(peer.transport,"pendingOp"));
                    peer.completeWrite();
                    if(transfer.done()==done&&peer.transport.isSending()&&(Integer)field(peer.transport,"pendingOp")==0)idleFor(5);
                }
                if(groups%2!=0){assertEquals(done,transfer.done());for(int a=0;a<count;a++)peer.panel.onReply(new ReplyDecoder.Reply(cmd,0));}
                idleFor(40);groups++;
                assertTrue("group did not advance: "+transfer.waitingSummary(),!transfer.busy()||transfer.done()>done);
            }
            assertEquals(200,groups);assertEquals(987,peer.capture.bytes.size());assertEquals(Boolean.TRUE,field(peer.panel,"loaded"));
            ByteArrayOutputStream actual=new ByteArrayOutputStream(),expected=new ByteArrayOutputStream();
            for(int i=0;i<peer.capture.bytes.size();i++){actual.write(peer.capture.bytes.get(i));assertEquals(i<2||i==986?BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT:BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE,(int)peer.capture.types.get(i));}
            expected.write(Score.command(0x55));for(byte[] f:score.uploadFrames())expected.write(f);assertArrayEquals(expected.toByteArray(),actual.toByteArray());
            StringBuilder fixture=new StringBuilder();byte[] stream=actual.toByteArray();for(int at=0;at<stream.length;at+=12){for(int k=11;k>=0;k--)fixture.append(String.format(Locale.US,"%02x",stream[at+k]&255));fixture.append('\n');}
            Path output=Paths.get(System.getProperty("qa.screens"));Files.createDirectories(output);
            Files.write(output.resolve("truth-part2-packets.mem"),fixture.toString().getBytes(java.nio.charset.StandardCharsets.US_ASCII));
            assertTrue(((Button)field(peer.panel,"play")).isEnabled());assertTrue(((TextView)field(peer.panel,"status")).getText().toString().contains("蓝牙无响应写"));
            // A normal control after the fast queue returns to the normal ATT type.
            assertTrue(peer.transport.sendFrame(Score.command(0x55)));assertEquals(BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,(int)peer.capture.types.get(987));peer.completeWrite();
        }
    }
    @Test public void windowsArePacedAndNeverSubmitTwoGattWritesAtOnce()throws Exception{
        try(Peer peer=new Peer(true)){
            assertTrue(peer.transport.sendScoreWindow(chunks(),true));assertEquals(1,peer.capture.bytes.size());idleFor(100);assertEquals(1,peer.capture.bytes.size());
            peer.completeWrite();idle();assertEquals("late completion adds no 5ms sleep",2,peer.capture.bytes.size());
            idleFor(2);peer.completeWrite();idleFor(2);assertEquals(2,peer.capture.bytes.size());idleFor(1);assertEquals(3,peer.capture.bytes.size());
            while(peer.transport.isSending()){peer.completeWrite();idleFor(5);}
            for(int i=1;i<peer.capture.times.size();i++)assertTrue(peer.capture.times.get(i)-peer.capture.times.get(i-1)>=5);
            assertTrue(peer.progress.get(peer.progress.size()-1).finished);assertFalse(peer.progress.get(peer.progress.size()-1).ackedByPeer());
        }
    }
    @Test public void characteristicWithoutNoResponseUsesNormalWrites()throws Exception{fallback();}
    @Test public void legacyWriterPreservesSelectedWriteType()throws Exception{
        try(Peer peer=new Peer(true)){
            BluetoothGatt gatt=(BluetoothGatt)field(peer.transport,"gatt");BluetoothGattCharacteristic ch=peer.capture.service.getCharacteristic(BleTransport.NOTIFY_UUID);
            call(peer.transport,"submitLegacy",new Class<?>[]{BluetoothGatt.class,BluetoothGattCharacteristic.class,byte[].class,boolean.class,int.class},gatt,ch,Score.command(0x55),false,1);
            assertEquals(BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE,(int)peer.capture.types.get(0));assertArrayEquals(Score.command(0x55),peer.capture.bytes.get(0));
        }
    }
    @Test public void missingAckCannotUnlockSealOrPlay()throws Exception{
        ScoreTransfer transfer=new ScoreTransfer();List<byte[]> frames=new ArrayList<>();frames.add(Score.command(0x55));frames.addAll(tiny().uploadFrames());transfer.start(frames,true,caps());
        for(int controls=0;controls<2;controls++){transfer.reply(transfer.command(),0);transfer.written();transfer.advance();}
        transfer.written();for(int n=0;n<7;n++)transfer.reply(0x51,0);assertFalse(transfer.canAdvance());assertEquals(0x51,transfer.command());transfer.cancel();assertFalse(transfer.reply(0x51,0));
    }
    @Test public void failedSubmissionErrorCallbackAndMissingCallbackAbortFastQueue()throws Exception{
        try(Peer peer=new Peer(true)){peer.capture.submitStatus=201;peer.transport.sendScoreWindow(chunks(),true);idle();assertFalse(peer.transport.isReady());assertFalse(peer.transport.isSending());}
        try(Peer peer=new Peer(true)){assertTrue(peer.transport.sendScoreWindow(chunks(),true));call(peer.transport,"handleCharacteristicWrite",new Class<?>[]{UUID.class,int.class},BleTransport.NOTIFY_UUID,133);idle();assertFalse(peer.transport.isReady());assertFalse(peer.transport.isSending());assertEquals(1,peer.capture.bytes.size());}
        try(Peer peer=new Peer(true)){assertTrue(peer.transport.sendScoreWindow(chunks(),true));idleFor(BleTransport.WRITE_TIMEOUT_MS+1);assertFalse(peer.transport.isReady());assertFalse(peer.transport.isSending());assertEquals(1,peer.capture.bytes.size());}
    }
    private static void fallback()throws Exception{try(Peer peer=new Peer(false)){assertTrue(peer.transport.sendScoreWindow(chunks(),true));while(peer.transport.isSending()){peer.completeWrite();idleFor(5);}for(int type:peer.capture.types)assertEquals(BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,type);assertTrue(peer.progress.get(peer.progress.size()-1).ackedByPeer());}}
    private static Score tiny(){List<Score.Event> events=new ArrayList<>();for(int i=0;i<8;i++)events.add(new Score.Event(i*10,60,i%2==0?90:0));return new Score("tiny",events);}
    private static List<byte[]> chunks(){List<byte[]> frames=new ArrayList<>();frames.add(Score.command(0x55));frames.addAll(tiny().uploadFrames());ScoreTransfer t=new ScoreTransfer();t.start(frames,true,caps());for(int i=0;i<2;i++){t.written();t.reply(t.command(),0);t.advance();}return t.chunks();}
    private static ScoreCapabilities caps(){byte[] b={(byte)0xA5,0x5A,(byte)0xF1,1,0x57,123,0,0,0,0,32,16,8,1,0,(byte)0xC2,1,0,1,0};for(int i=2;i<19;i++)b[19]^=b[i];return ScoreCapabilities.decode(b);}
    private static Object field(Object object,String name)throws Exception{Field f=object.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(object);}
    private static void set(Object object,String name,Object value)throws Exception{Field f=object.getClass().getDeclaredField(name);f.setAccessible(true);f.set(object,value);}
    private static Object call(Object object,String name,Class<?>[] types,Object... values)throws Exception{Method m=object.getClass().getDeclaredMethod(name,types);m.setAccessible(true);return m.invoke(object,values);}
    private static void idle(){Shadows.shadowOf(Looper.getMainLooper()).idle();}
    private static void idleFor(long ms){Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(ms));}
}
