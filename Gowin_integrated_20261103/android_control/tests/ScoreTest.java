package com.gowin.instrument;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.zip.CRC32;

public final class ScoreTest {
    static int checks;
    static void ok(boolean b,String s){checks++;if(!b)throw new AssertionError(s);}
    static void reject(Runnable r,String s){checks++;try{r.run();}catch(IllegalArgumentException e){return;}throw new AssertionError(s);}
    static byte[] midi(byte[] track){byte[] header={77,84,104,100,0,0,0,6,0,0,0,1,1,(byte)0xe0,77,84,114,107,0,0,0,0};int n=track.length;for(int i=0;i<4;i++)header[18+i]=(byte)(n>>>(24-8*i));byte[] out=Arrays.copyOf(header,header.length+n);System.arraycopy(track,0,out,header.length,n);return out;}
    static byte[] track(int... ints){byte[] b=new byte[ints.length];for(int i=0;i<ints.length;i++)b[i]=(byte)ints[i];return midi(b);}
    static long le(byte[] b,int p,int n){long v=0;for(int i=0;i<n;i++)v|=(long)(b[p+i]&255)<<(8*i);return v;}
    public static void main(String[] args)throws Exception{
        final byte[] simple=track(0,0x90,60,80,0x83,0x60,0x80,60,0,0,0xff,0x2f,0);
        Score s=Score.fromMidi("test",simple);ok(s.events.size()==2&&s.events.get(1).timeMs==500&&s.peakVoices==1,"PPQ default tempo");
        Score run=Score.fromMidi("running",track(0,0x90,60,80,0,64,80,0x83,0x60,60,0,0,64,0,0,0xff,0x2f,0));ok(run.peakVoices==2&&run.events.size()==4,"running status chord");
        Score tempo=Score.fromMidi("tempo",track(0,0xff,0x51,3,0x0f,0x42,0x40,0,0x90,60,80,0x83,0x60,0x80,60,0,0,0xff,0x2f,0));ok(tempo.durationMs==1000,"tempo application");
        ok(s.firstBeatMs==500&&tempo.firstBeatMs==1000,"initial quarter-note tempo for count-in");
        Score pedal=Score.fromMidi("pedal",track(0,0x90,60,80,0,0xb0,64,127,0x83,0x60,0x80,60,0,0x83,0x60,0xb0,64,0,0,0xff,0x2f,0));ok(pedal.events.size()==2&&pedal.durationMs==1000,"baked sustain");
        Score merged=Score.fromMidi("merge",track(0,0x90,60,80,0,0x91,60,90,0x83,0x60,0x80,60,0,0x83,0x60,0x81,60,0,0,0xff,0x2f,0));ok(merged.events.size()==2&&merged.durationMs==1000,"same note channel union");
        Score closed=Score.fromMidi("closure",track(0,0x90,60,80,0x83,0x60,0xff,0x2f,0));ok(closed.events.size()==2&&closed.durationMs==500,"close dangling note at end");
        List<Score.Event> chord=new ArrayList<Score.Event>();
        chord.add(new Score.Event(0,60,80));chord.add(new Score.Event(0,64,90));
        chord.add(new Score.Event(100,60,0));chord.add(new Score.Event(100,67,100));
        chord.add(new Score.Event(400,67,0));chord.add(new Score.Event(500,64,0));
        chord.add(new Score.Event(600,62,80));chord.add(new Score.Event(700,62,0));
        final Score source=new Score("chord",chord),half=source.prefix(2),quarter=source.prefix(4),eighth=source.prefix(8);
        ok(source.prefix(1)==source,"full is unchanged");
        ok(half.events.size()==6&&half.durationMs==400&&half.peakVoices==2,"half closes both held notes at boundary");
        ok(half.events.get(4).note==64&&half.events.get(4).velocity==0&&half.events.get(5).note==67&&half.events.get(5).velocity==0,"close only active notes");
        ok(quarter.events.size()==4&&quarter.durationMs==100&&quarter.peakVoices==2,"quarter retains initial chord and closes it");
        ok(eighth.events.size()==4&&eighth.peakVoices==2,"never split first simultaneous chord");
        ok(source.events.size()==8&&source.durationMs==700,"segment never mutates original");

        boolean[] allowed=new boolean[128];allowed[60]=true;allowed[67]=true;
        Score playable=source.onlyPitches(allowed);
        ok(playable.events.size()==4&&playable.events.get(0).note==60&&playable.events.get(1).timeMs==100&&
            playable.events.get(2).note==67&&playable.events.get(3).timeMs==400,"filter keeps complete note pairs and original timing");
        ok(playable.peakVoices==1&&playable.firstBeatMs==source.firstBeatMs&&source.events.size()==8,"filter leaves source and tempo unchanged");
        boolean[] all=new boolean[128];Arrays.fill(all,true);ok(source.onlyPitches(all)==source,"filter all pitches preserves original");
        reject(new Runnable(){public void run(){source.onlyPitches(new boolean[128]);}},"reject empty practice");
        reject(new Runnable(){public void run(){source.onlyPitches(new boolean[12]);}},"reject invalid map");

        Score shifted=half.transposed(-2);ok(shifted.minNote==58&&shifted.maxNote==65&&shifted.firstBeatMs==half.firstBeatMs,"explicit transpose preserves timing and tempo");
        ok(source.minNote==60&&source.events.get(0).note==60,"transpose preserves original score");
        reject(new Runnable(){public void run(){source.transposed(25);}},"reject excessive transpose");
        byte[] practice=tempo.practiceCommand(75,true);ok((practice[2]&255)==0x5a&&(practice[3]&255)==75&&(practice[4]&255)==1&&(practice[5]&255)==4&&le(practice,6,2)==1000&&practice[8]=='G'&&practice[9]=='P'&&practice[10]=='1',"practice command includes speed, wait mode and tempo");
        reject(new Runnable(){public void run(){source.prefix(3);}},"reject unknown ratio");
        List<Score.Event> flat=new ArrayList<Score.Event>();for(int i=0;i<8;i++){flat.add(new Score.Event(0,60,80));flat.add(new Score.Event(0,60,0));}
        Score dense=new Score("same timestamp",flat);ok(dense.prefix(8)==dense,"all simultaneous events retained as complete score");
        List<Score.Event> longEvents=new ArrayList<Score.Event>();for(int i=0;i<4096;i++)longEvents.add(new Score.Event(i*10,60,i%2==0?80:0));
        Score longScore=new Score("long",longEvents);ScoreCapabilities.legacy().checkUpload(longScore.prefix(2));
        reject(new Runnable(){public void run(){ScoreCapabilities.legacy().checkUpload(longScore);}},"capacity applies to the selected segment");
        for(int divisor:new int[]{2,4,8}){
            Score part=longScore.prefix(divisor);ok(part.events.size()<=4096/divisor+2,"ratio actually reduces events");
            List<byte[]> partFrames=part.uploadFrames();ok(le(partFrames.get(0),3,2)==part.events.size(),"begin count matches segment");
            CRC32 partCrc=new CRC32();for(int i=1;i<partFrames.size()-1;i++)partCrc.update(partFrames.get(i),5,6);
            ok(le(partFrames.get(partFrames.size()-1),3,4)==partCrc.getValue(),"segment CRC covers emitted events and closures");
        }
        reject(new Runnable(){public void run(){Score.fromMidi("bad",new byte[]{1,2});}},"truncated header");
        reject(new Runnable(){public void run(){Score.fromMidi("bad",track(0,60,80));}},"invalid running");
        final byte[] smpte=simple.clone();smpte[12]=(byte)0xe7;reject(new Runnable(){public void run(){Score.fromMidi("bad",smpte);}},"reject SMPTE");
        reject(new Runnable(){public void run(){Score.fromMidi("drum",track(0,0x99,60,80,0x83,0x60,0x89,60,0));}},"drum-only unsupported");
        final List<Score.Event> crowded=new ArrayList<Score.Event>();for(int n=0;n<9;n++)crowded.add(new Score.Event(0,60+n,90));for(int n=0;n<9;n++)crowded.add(new Score.Event(500,60+n,0));final Score nine=new Score("nine",crowded);ok(nine.peakVoices==9,"parser independent of device voices");reject(new Runnable(){public void run(){ScoreCapabilities.legacy().checkUpload(nine);}},"legacy polyphony limit");
        List<byte[]> frames=s.uploadFrames();ok(frames.size()==4&&le(frames.get(0),3,2)==2&&frames.get(0)[5]==1,"begin count/version");
        ok(le(frames.get(2),3,2)==1&&le(frames.get(2),5,4)==500&&frames.get(2)[10]==0,"event LE layout");
        CRC32 crc=new CRC32();for(int i=1;i<frames.size()-1;i++)crc.update(frames.get(i),5,6);ok(le(frames.get(3),3,4)==crc.getValue(),"seal CRC");
        byte[] vector="123456789".getBytes("US-ASCII");CRC32 known=new CRC32();known.update(vector);ok(known.getValue()==0xcbf43926L,"CRC IEEE vector");
        for(byte[] f:frames){int x=0;for(int i=2;i<12;i++)x^=f[i]&255;ok(f.length==12&&x==0,"packet XOR");}
        ScoreTransfer t=new ScoreTransfer();t.start(frames);ok(!t.reply(0x12,0),"ignore unrelated ACK");t.reply(0x50,0);ok(!t.canAdvance(),"ACK before local completion waits");t.written();ok(t.canAdvance(),"both required");t.advance();t.written();ok(!t.canAdvance(),"write alone insufficient");t.reply(0x51,0);t.advance();ok(t.done()==2&&t.busy(),"ordered transfer");t.cancel();ok(!t.busy(),"cancel");
        t.start(frames);try{t.reply(0x50,1);throw new AssertionError("board rejection");}catch(IllegalArgumentException e){ok(!t.busy(),"board rejection aborts");}
        ok(UploadPacing.delayAfterReady(true,100,112)==18,"fast protects 30ms start spacing");
        ok(UploadPacing.delayAfterReady(true,100,130)==0,"ACK at spacing boundary adds no wait");
        ok(UploadPacing.delayAfterReady(true,100,220)==0,"slow ACK incurs no redundant wait");
        ok(UploadPacing.delayAfterReady(false,100,220)==40,"compat retains after-ACK wait");
        ok(UploadPacing.delayAfterReady(true,100,90)==30,"clock regression protects spacing");
        ok(UploadPacing.delayAfterReady(2,100,102)==3,"115200 mode protects 5ms start spacing");
        ok(UploadPacing.delayAfterReady(2,100,120)==0,"115200 slow ACK never gains extra delay");
        ok(UploadPacing.delayAfterReady(0,100,102)==28,"9600 selection preserves 30ms");
        ok(UploadPacing.delayAfterReady(1,100,120)==40,"compat selection preserves 40ms");
        reject(new Runnable(){public void run(){UploadPacing.delayAfterReady(3,0,0);}},"invalid pacing mode");
        long fastTime=0,compatTime=0;
        for(int i=0;i<100;i++){
            long readyDelay=(i%3==0)?12:(i%3==1?30:90);
            long next=readyDelay+UploadPacing.delayAfterReady(true,fastTime,fastTime+readyDelay);
            ok(next>=30&&next>=readyDelay,"simulated ACK pacing never early");
            fastTime+=next;compatTime+=readyDelay+UploadPacing.delayAfterReady(false,compatTime,compatTime+readyDelay);
        }
        ok(compatTime-fastTime==3388,"100-frame mixed ACK simulation saves redundant waits");
        for(int value:new int[]{0,64,127}){byte[] v=Score.volume(value);ok((v[2]&255)==0x56&&(v[3]&255)==value,"volume command layout");int xor=0;for(int i=2;i<12;i++)xor^=v[i]&255;ok(xor==0&&le(v,4,7)==0,"volume XOR/reserved bytes");}
        reject(new Runnable(){public void run(){Score.volume(128);}},"volume overflow");
        reject(new Runnable(){public void run(){Score.volume(-1);}},"negative volume");
        for(String path:args){Score real=Score.fromMidi(Paths.get(path).getFileName().toString(),Files.readAllBytes(Paths.get(path)));ok(real.events.size()<=Score.MAX_EVENTS&&real.peakVoices<=128,"builtin parses");
            if(real.name.equals("twinkle_25key_c4.mid")){ok(real.events.size()==84&&real.minNote==60&&real.maxNote==69&&real.peakVoices==1,"25-key demo is a complete single-note melody in C4..A4");
                Set<Integer> pitch=new TreeSet<Integer>();for(Score.Event e:real.events)if(e.velocity>0)pitch.add(e.note);
                ok(pitch.equals(new TreeSet<Integer>(Arrays.asList(60,62,64,65,67,69))),"demo uses exactly the saved 25-key pitches");}
            System.out.println(real.name+" events="+real.events.size()+" duration_ms="+real.durationMs+" peak="+real.peakVoices+" range="+real.minNote+".."+real.maxNote);}
        System.out.println("SCORE_TEST_OK checks="+checks);
    }
}
