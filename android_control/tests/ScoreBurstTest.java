package com.gowin.instrument;

import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Window assembly, completion ordering, corruption and real-score regression. */
public final class ScoreBurstTest {
    private static int checks;
    private interface Action{void run();}
    private static void ok(boolean value,String why){checks++;if(!value)throw new AssertionError(why);}
    private static void reject(Action action,String why){checks++;try{action.run();}catch(IllegalArgumentException|IllegalStateException expected){return;}throw new AssertionError(why);}
    private static List<byte[]> frames(Score s){List<byte[]> f=new ArrayList<byte[]>();f.add(Score.command(0x55));f.addAll(s.uploadFrames());return f;}
    private static List<byte[]> cloneFrames(List<byte[]> src){List<byte[]> f=new ArrayList<byte[]>();for(byte[] b:src)f.add(b.clone());return f;}
    private static void sum(byte[] f){byte xor=f[2];for(int i=3;i<11;i++)xor^=f[i];f[11]=xor;}
    private static List<byte[]> changed(List<byte[]> src,int frame,int at,int value){List<byte[]> f=cloneFrames(src);f.get(frame)[at]=(byte)value;sum(f.get(frame));return f;}
    private static Score tiny(int notes){List<Score.Event> e=new ArrayList<Score.Event>();for(int i=0;i<notes;i++){e.add(new Score.Event(i*20,60,100));e.add(new Score.Event(i*20+10,60,0));}return new Score("tiny",e);}
    private static byte[] flatten(List<byte[]> values)throws IOException{ByteArrayOutputStream o=new ByteArrayOutputStream();for(byte[] b:values)o.write(b);return o.toByteArray();}
    private static void run(Score score)throws Exception{
        List<byte[]> f=frames(score);ScoreTransfer transfer=new ScoreTransfer();transfer.start(f,true,BluetoothUpgradeTest.capabilities(8192,12,8));
        int groups=0,writes=0;ByteArrayOutputStream all=new ByteArrayOutputStream();
        while(transfer.busy()){
            int size=transfer.groupSize(),cmd=transfer.command();List<byte[]> chunks=transfer.chunks();
            ok(size>=1&&size<=8,"bounded group");ok(cmd==0x51||size==1,"control isolated");
            for(byte[] chunk:chunks){ok(chunk.length>=1&&chunk.length<=20,"ATT default payload fits");all.write(chunk);writes++;}
            reject(()->transfer.advance(),"no advance without write/ACK");
            if(groups%2==0){transfer.written();ok(!transfer.canAdvance(),"local alone not ACK");}
            ok(!transfer.reply(0x99,0),"unrelated reply ignored");
            for(int a=0;a<size;a++){ok(transfer.reply(cmd,0),"ACK accepted");if(a<size-1)ok(!transfer.canAdvance(),"partial group no advance");}
            if(groups%2!=0){ok(!transfer.canAdvance(),"ACK alone not local");transfer.written();}
            ok(transfer.canAdvance(),"both ready");int before=transfer.done();transfer.advance();ok(transfer.done()==before+size,"advance by frames, not writes");groups++;
        }
        ok(transfer.done()==f.size()&&transfer.total()==f.size(),"complete correct total");
        ok(Arrays.equals(all.toByteArray(),flatten(f)),"no reordered/dropped/padded stream bytes");
        ok(writes<f.size(),"fewer GATT writes");
        ok(groups==3+(score.events.size()+7)/8,"eight-event groups plus three controls");
        System.out.println("BURST_SCORE_OK title="+score.name+" events="+score.events.size()+" frames="+f.size()+" groups="+groups+" ATT_writes="+writes);
    }
    public static void main(String[] args)throws Exception{
        for(String path:args){Score s=Score.fromMidi(Paths.get(path).getFileName().toString(),Files.readAllBytes(Paths.get(path)));run(s);}
        run(tiny(5));run(tiny(1024));
        final List<byte[]> f=frames(tiny(5));final ScoreBurstTransfer b=new ScoreBurstTransfer();
        reject(()->b.chunks(),"chunks when idle");reject(()->b.advance(),"advance idle");
        reject(()->b.start(Collections.<byte[]>emptyList()),"empty upload");
        reject(()->b.start(changed(f,0,0,0)),"bad header");
        final List<byte[]> badXor=cloneFrames(f);badXor.get(2)[11]^=1;reject(()->b.start(badXor),"bad XOR");
        reject(()->b.start(changed(f,0,3,1)),"probe reserved");
        reject(()->b.start(changed(f,1,3,0)),"zero begin count");
        reject(()->b.start(changed(f,1,3,9)),"exact count required");
        reject(()->b.start(changed(f,1,5,2)),"begin version");
        reject(()->b.start(changed(f,1,6,1)),"begin reserved");
        reject(()->b.start(changed(f,2,2,0x50)),"only EVENT body");
        reject(()->b.start(changed(f,2,3,1)),"event index order");
        reject(()->b.start(changed(f,2,8,255)),"delta max");
        reject(()->b.start(changed(f,2,9,128)),"note range");
        reject(()->b.start(changed(f,2,10,128)),"velocity range");
        reject(()->b.start(changed(f,f.size()-1,3,0)),"seal CRC");
        reject(()->b.start(changed(f,f.size()-1,7,1)),"seal count");
        reject(()->b.start(changed(f,f.size()-1,9,2)),"seal version");
        reject(()->b.start(changed(f,f.size()-1,10,1)),"seal reserved");
        ok(!b.busy(),"failed validation never starts");
        b.start(f);reject(()->b.start(f),"cannot replace active");f.get(0)[0]=0;
        ok((b.chunks().get(0)[0]&255)==0xA5,"input cloned");byte[] c=b.chunks().get(0);c[0]=0;
        ok((b.chunks().get(0)[0]&255)==0xA5,"output cloned");
        b.reply(0x55,0);reject(()->b.reply(0x55,0),"extra matching ACK aborts");ok(!b.busy(),"overflow cancels");
        b.start(frames(tiny(5)));reject(()->b.reply(0x55,1),"error aborts");ok(!b.busy(),"error cancels");
        b.start(frames(tiny(5)));b.cancel();ok(!b.reply(0x55,0)&&!b.canAdvance(),"cancel ignores late ACK");
        reject(()->b.advance(),"cancel cannot advance");
        // A facade can switch back to legacy after cancellation or completion.
        ScoreTransfer facade=new ScoreTransfer();facade.start(frames(tiny(5)),true);facade.cancel();facade.start(Collections.singletonList(Score.command(0x56)));facade.reply(0x56,0);facade.written();facade.advance();ok(!facade.busy()&&!facade.windowed(),"legacy volume unaffected");
        ok(facade.waitingSummary().equals("idle"),"idle diagnostic");
        facade.start(frames(tiny(5)),true);
        ok(facade.waitingSummary().contains("GATT=pending ACK=0/1"),"initial wait diagnostic");
        facade.reply(0x55,0);
        ok(facade.waitingSummary().contains("GATT=pending ACK=1/1"),"ACK-before-write diagnostic");
        facade.written();facade.advance();facade.written();facade.reply(0x50,0);facade.advance();
        facade.written();facade.reply(0x51,0);
        ok(facade.waitingSummary().contains("group=8 GATT=complete ACK=1/8"),"partial window diagnostic");
        facade.cancel();ok(facade.waitingSummary().equals("idle"),"cancel diagnostic cleared");
        System.out.println("BURST_TEST_OK checks="+checks);
    }
}
