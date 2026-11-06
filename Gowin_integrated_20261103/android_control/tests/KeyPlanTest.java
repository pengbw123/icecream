package com.gowin.instrument;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.zip.CRC32;

public final class KeyPlanTest {
    static int checks;
    static void ok(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    static void reject(byte[] file,String message){checks++;try{KeyPlan.fromMidi("bad",file,48);}catch(IllegalArgumentException e){return;}throw new AssertionError(message);}
    static byte[] midi(int[][] tracks)throws Exception{
        ByteArrayOutputStream out=new ByteArrayOutputStream();DataOutputStream d=new DataOutputStream(out);
        d.writeBytes("MThd");d.writeInt(6);d.writeShort(tracks.length==1?0:1);d.writeShort(tracks.length);d.writeShort(480);
        for(int[] t:tracks){d.writeBytes("MTrk");d.writeInt(t.length);for(int x:t)d.writeByte(x);}return out.toByteArray();
    }
    static long le(byte[] b,int p,int n){long v=0;for(int i=0;i<n;i++)v|=(long)(b[p+i]&255)<<(8*i);return v;}
    public static void main(String[] args)throws Exception{
        byte[] unison=midi(new int[][]{
            {0,0x90,67,100,0x83,0x60,0x80,67,13,0,0xff,0x2f,0},
            {0,0x90,67,70,0x87,0x40,0x80,67,71,0,0xff,0x2f,0}});
        KeyPlan.Result result=KeyPlan.fromMidi("unison",unison,48);Score s=result.score;
        Score legacy=Score.fromMidi("unison",unison);ok(legacy.fidelityIssue!=null&&legacy.fidelityIssue.contains("重叠"),"legacy parser flags unsafe original overlap");
        ok(result.pairedNotes==2&&result.sameChannelOverlaps==1&&s.events.size()==4&&s.peakVoices==2,"two same-channel track instances");
        ok(result.releaseVelocities==2,"nonzero release velocities disclosed");
        ok(s.events.get(0).note!=s.events.get(1).note&&s.events.get(0).targetNote==67&&s.events.get(1).targetNote==67,"distinct physical keys for same pitch");
        ok(s.events.get(2).note==s.events.get(0).note&&s.events.get(2).timeMs==500&&s.events.get(3).timeMs==1000,"independent releases");
        List<byte[]> frames=s.uploadFrames();ok(frames.get(0)[5]==2&&(frames.get(0)[6]&255)==48,"mapped begin version and first key");
        CRC32 crc=new CRC32();for(int i=1;i<frames.size()-1;i++){byte[] f=frames.get(i);crc.update(f,5,6);long word=le(f,5,4);ok((word>>>20)==s.events.get(i-1).note-48&&(f[9]&255)==67,"mapped event payload");}
        ok(le(frames.get(frames.size()-1),3,4)==crc.getValue()&&frames.get(frames.size()-1)[9]==2,"mapped seal CRC/version");
        byte[] cap={(byte)0xa5,0x5a,(byte)0xf1,1,0x57,1,0,0,0,0,0x20,32,8,5,0,(byte)0xc2,1,0,1,0};
        for(int i=2;i<19;i++)cap[19]^=cap[i];
        ScoreCapabilities mappedCaps=ScoreCapabilities.decode(cap);ok(mappedCaps.keyPlanSupported(),"capability flag accepted");
        checks++;try{ScoreCapabilities.legacy().checkUpload(s);throw new AssertionError("legacy must reject mapped upload");}catch(IllegalArgumentException expected){}
        mappedCaps.checkUpload(s);List<byte[]> send=new ArrayList<byte[]>();send.add(Score.command(0x55));send.addAll(frames);
        ScoreTransfer single=new ScoreTransfer();single.start(send,false,mappedCaps);ok(single.busy(),"mapped single-frame transfer accepted");
        ScoreTransfer batch=new ScoreTransfer();batch.start(send,true,mappedCaps);ok(batch.busy(),"mapped batch validated");
        checks++;try{new ScoreTransfer().start(send,false,ScoreCapabilities.legacy());throw new AssertionError("legacy transport accepted mapped frames");}catch(IllegalArgumentException expected){}
        Score shifted=s.transposed(2);ok(shifted.events.get(0).targetNote==69&&shifted.events.get(0).note==s.events.get(0).note,"transpose sounds, never shifts physical key");
        Score part=s.prefix(2);for(Score.Event e:part.events)ok(e.targetNote==67,"prefix retains target on closes");
        reject(midi(new int[][]{{0,0x90,60,80,0,0x90,60,90,0x83,0x60,0x80,60,0,0,0x80,60,0,0,0xff,0x2f,0}}),"same-track overlap");
        reject(midi(new int[][]{{0,0x90,60,80,0,0xb0,64,127,0x83,0x60,0x80,60,0,0,0xff,0x2f,0}}),"sustain unsupported");
        reject(midi(new int[][]{{0,0x99,60,80,0x83,0x60,0x89,60,0,0,0xff,0x2f,0}}),"drum unsupported");
        reject(midi(new int[][]{{0,0x80,60,0,0,0xff,0x2f,0}}),"orphan off");
        reject(midi(new int[][]{{0,0x90,60,80,0,0xff,0x2f,0}}),"unclosed on");
        int[] crowded=new int[26*8+4];int at=0;
        for(int i=0;i<26;i++){crowded[at++]=0;crowded[at++]=0x90;crowded[at++]=40+i;crowded[at++]=80;}
        for(int i=0;i<26;i++){crowded[at++]=0;crowded[at++]=0x80;crowded[at++]=40+i;crowded[at++]=0;}
        crowded[at++]=0;crowded[at++]=0xff;crowded[at++]=0x2f;crowded[at]=0;
        reject(midi(new int[][]{crowded}),"26 simultaneous notes");
        KeyPlan.Result zero=KeyPlan.fromMidi("zero",midi(new int[][]{{0,0x90,60,80,0,0x80,60,0,0,0xff,0x2f,0}}),48);
        ok(zero.shiftedEvents==1&&zero.score.events.get(1).timeMs==1,"zero duration disclosed and shifted by 1 ms");
        if(args.length>0){
            KeyPlan.Result real=KeyPlan.fromMidi("huahai",Files.readAllBytes(Paths.get(args[0])),48);
            ok(Score.fromMidi("huahai",Files.readAllBytes(Paths.get(args[0]))).fidelityIssue!=null,"Huahai cannot be silently uploaded with legacy parser");
            ok(real.pairedNotes==845&&real.score.events.size()==1690&&real.sameChannelOverlaps==7&&real.score.peakVoices==5&&real.shiftedEvents==0&&real.releaseVelocities==845,"original file track audit: "+real.pairedNotes+","+real.score.events.size()+","+real.sameChannelOverlaps+","+real.score.peakVoices+","+real.shiftedEvents+","+real.releaseVelocities);
            if(args.length>1){List<String> lines=new ArrayList<String>();lines.add("ms,physical,target,velocity");for(Score.Event e:real.score.events)lines.add(e.timeMs+","+e.note+","+e.targetNote+","+e.velocity);Files.write(Paths.get(args[1]),lines,StandardCharsets.UTF_8);}
        }
        System.out.println("KEY_PLAN_TEST_OK checks="+checks);
    }
}
