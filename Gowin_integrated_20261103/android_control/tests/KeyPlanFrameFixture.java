package com.gowin.instrument;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
/** Actual App-generated v2 key-plan frames used by the RTL integration test. */
public final class KeyPlanFrameFixture {
    public static void main(String[] args)throws Exception{
        byte[] file=KeyPlanTest.midi(new int[][]{
            {0,0x90,67,100,0x83,0x60,0x80,67,0,0,0x90,72,100,0x83,0x60,0x80,72,0,0,0xff,0x2f,0},
            {0,0x90,67,70,0x87,0x40,0x80,67,0,0,0xff,0x2f,0}});
        Score score=KeyPlan.fromMidi("unison and next",file,48).score;
        List<byte[]> frames=new ArrayList<byte[]>();frames.add(Score.command(0x55));frames.addAll(score.uploadFrames());
        frames.add(score.practiceCommand(100,true));frames.add(Score.command(0x54));
        List<String> lines=new ArrayList<String>();
        for(byte[] f:frames){StringBuilder s=new StringBuilder();for(int i=f.length-1;i>=0;i--)s.append(String.format(Locale.US,"%02x",f[i]&255));lines.add(s.toString());}
        Path out=Paths.get(args[0]);if(Files.exists(out))throw new IllegalArgumentException("refusing to overwrite fixture");
        Files.write(out,lines,StandardCharsets.US_ASCII);
        System.out.println("APP_KEY_PLAN_FIXTURE frames="+frames.size()+" first="+score.mappedFirstKey+" firstKeys="+score.events.get(0).note+","+score.events.get(1).note+" nextKey="+score.events.get(3).note);
    }
}
