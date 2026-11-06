package com.gowin.instrument;
import java.util.*;
import java.util.zip.CRC32;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;

public final class BluetoothUpgradeTest {
    private static int checks;
    private static void ok(boolean b,String why){checks++;if(!b)throw new AssertionError(why);}
    private static void reject(Runnable r,String why){checks++;try{r.run();}catch(IllegalArgumentException expected){return;}throw new AssertionError(why);}
    static void le(byte[] b,int at,long v,int n){for(int i=0;i<n;i++)b[at+i]=(byte)(v>>>(8*i));}
    static void sum(byte[] b){byte x=0;for(int i=2;i<b.length-1;i++)x^=b[i];b[b.length-1]=x;}
    public static byte[] capabilityFrame(int count,int voices,int group){
        byte[] b=new byte[20];b[0]=(byte)0xa5;b[1]=0x5a;b[2]=(byte)0xf1;b[3]=1;b[4]=0x57;
        le(b,5,0x12345678L,4);le(b,9,count,2);b[11]=(byte)voices;b[12]=(byte)group;b[13]=1;le(b,14,115200,4);b[18]=1;sum(b);return b;
    }
    public static ScoreCapabilities capabilities(int count,int voices,int group){return ScoreCapabilities.decode(capabilityFrame(count,voices,group));}
    private static List<byte[]> upload(int n){
        List<byte[]> frames=new ArrayList<>();frames.add(Score.command(0x55));
        byte[] d=new byte[8];le(d,0,n,2);d[2]=1;frames.add(Protocol.packet(0x50,d));
        CRC32 crc=new CRC32();
        for(int i=0;i<n;i++){d=new byte[8];le(d,0,i,2);d[6]=(byte)(36+(i/2)%64);d[7]=(byte)(i%2==0?90:0);crc.update(d,2,6);frames.add(Protocol.packet(0x51,d));}
        d=new byte[8];le(d,0,crc.getValue(),4);le(d,4,n,2);d[6]=1;frames.add(Protocol.packet(0x52,d));return frames;
    }
    public static void main(String[] args)throws Exception {
        ScoreCapabilities caps=capabilities(8192,12,8);
        ok(caps.negotiated&&caps.maxEvents==8192&&caps.voices==12&&caps.uartBaud==115200&&caps.nonce==0x12345678L,"capabilities fields");
        ok(caps.recommendedUploadMode()==3,"138K negotiated window is the automatic fast path");
        ok(ScoreCapabilities.legacy().recommendedUploadMode()==1,"unknown baud never automatically uses 115200");
        byte[] policy=capabilityFrame(8192,16,8);le(policy,14,9600,4);sum(policy);
        ok(ScoreCapabilities.decode(policy).recommendedUploadMode()==1,"slow UART retains compatibility pacing");
        le(policy,14,115200,4);policy[13]=0;sum(policy);
        ok(ScoreCapabilities.decode(policy).recommendedUploadMode()==2,"fast UART without window uses single frames");
        policy[13]=1;policy[12]=1;sum(policy);
        ok(ScoreCapabilities.decode(policy).recommendedUploadMode()==2,"one-event groups do not imply batch support");
        policy[13]=3;policy[18]=2;sum(policy);
        ok(ScoreCapabilities.decode(policy).recommendedUploadMode()==4,"v2 is used only when explicitly advertised");
        ok(capabilities(65535,32,8).maxEvents==8192,"parser cap separate from device cap");
        for(int p:new int[]{11,12,18}){byte[] b=capabilityFrame(8192,12,8);b[p]=0;sum(b);final byte[] broken=b;reject(()->ScoreCapabilities.decode(broken),"invalid capability field "+p);}
        byte[] f=capabilityFrame(8192,12,8), ack={(byte)0xa5,0x5a,(byte)0xf0,0x55,0,(byte)0xa5};
        for(int split=0;split<=f.length;split++){
            ReplyDecoder decoder=new ReplyDecoder();List<ReplyDecoder.Reply> rs=new ArrayList<>();rs.addAll(decoder.feed(Arrays.copyOfRange(f,0,split)));rs.addAll(decoder.feed(Arrays.copyOfRange(f,split,f.length)));
            ok(rs.size()==1&&rs.get(0).capabilities.nonce==caps.nonce,"arbitrary capability split "+split);
            ok(decoder.feed(ack).size()==1,"legacy ACK after capability");
        }
        ReplyDecoder decoder=new ReplyDecoder();List<ReplyDecoder.Reply> byteReplies=new ArrayList<>();for(byte b:f)byteReplies.addAll(decoder.feed(new byte[]{b}));ok(byteReplies.size()==1,"one byte notifications");
        byte[] bad=f.clone();System.arraycopy(ack,0,bad,7,6);bad[19]^=1;
        ok(new ReplyDecoder().feed(bad).isEmpty(),"bad F1 envelope cannot replay embedded ACK");
        byte[] mixed=new byte[ack.length+f.length+ack.length];System.arraycopy(ack,0,mixed,0,ack.length);System.arraycopy(f,0,mixed,ack.length,f.length);System.arraycopy(ack,0,mixed,ack.length+f.length,ack.length);
        ok(new ReplyDecoder().feed(mixed).size()==3,"glued old/new replies");
        ok(ScoreCapabilities.le(ScoreCapabilities.query(caps.nonce),3,4)==caps.nonce,"query nonce layout");
        for(int cap:new int[]{2048,4096,8192})for(int n:new int[]{1,2048,3140,4095,4096,4097,8191,8192,8193}){
            final List<byte[]> fs=upload(n);ScoreBurstTransfer transfer=new ScoreBurstTransfer();
            if(n>cap){reject(()->transfer.start(fs,cap,8),"capacity rejection "+cap+"/"+n);continue;}
            transfer.start(fs,cap,8);int seen=0;
            while(transfer.busy()){int size=transfer.groupSize(),cmd=transfer.command();for(int i=0;i<size;i++)transfer.reply(cmd,0);ok(!transfer.canAdvance(),"ACK waits for GATT");transfer.written();ok(transfer.canAdvance(),"GATT+ACK advances");seen+=size;transfer.advance();}
            ok(seen==n+3,"full capacity byte/group count "+n);
        }
        final List<byte[]> big=upload(4096);reject(()->new ScoreTransfer().start(big,false),"legacy single-frame path still caps capacity");reject(()->new ScoreTransfer().start(big,true),"legacy window path still caps capacity");
        ScoreBurstTransfer smaller=new ScoreBurstTransfer();smaller.start(upload(20),8192,3);while(smaller.busy()){ok(smaller.groupSize()<=3,"negotiated group bound");int cmd=smaller.command();for(int i=0;i<smaller.groupSize();i++)smaller.reply(cmd,0);smaller.written();smaller.advance();}
        Score full=Score.fromMidi("Truth full",Files.readAllBytes(Paths.get(args[0])));
        ok(full.events.size()==3140&&full.peakVoices==5&&full.durationMs==212259,"actual complete Truth parser");caps.checkUpload(full);reject(()->ScoreCapabilities.legacy().checkUpload(full),"old board rejects complete Truth before BEGIN");
        int at=0;for(int part=1;part<=2;part++){Score s=Score.fromMidi("part",Files.readAllBytes(Paths.get(args[part])));for(Score.Event e:s.events){Score.Event whole=full.events.get(at++);ok(e.timeMs+(part==1?0:110745)==whole.timeMs&&e.note==whole.note&&e.velocity==whole.velocity,"parts exactly match original");}}
        ok(at==full.events.size(),"Truth original preserved");
        List<byte[]> fs=new ArrayList<>();fs.add(Score.command(0x55));fs.addAll(full.uploadFrames());StringBuilder hex=new StringBuilder();for(byte[] b:fs){for(byte v:b)hex.append(String.format(Locale.US,"%02x",v&255));hex.append('\n');}
        Files.write(Paths.get(args[3],"truth-full.hex"),hex.toString().getBytes(StandardCharsets.US_ASCII));
        StringBuilder cf=new StringBuilder();for(byte v:f)cf.append(String.format(Locale.US,"%02x",v&255)).append('\n');Files.write(Paths.get(args[3],"capability-8192.hex"),cf.toString().getBytes(StandardCharsets.US_ASCII));
        System.out.println("BLUETOOTH_UPGRADE_JAVA_OK checks="+checks+" Truth_events="+full.events.size()+" duration_ms="+full.durationMs);
    }
}
