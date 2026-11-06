package com.gowin.instrument;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
/** Export App-generated frames for a user-supplied MIDI; input is read-only. */
public final class KeyPlanFullFixture {
    public static void main(String[] args)throws Exception{
        Score score=KeyPlan.fromMidi("用户曲谱",Files.readAllBytes(Paths.get(args[0])),48).score;
        Path output=Paths.get(args[1]);if(Files.exists(output))throw new IllegalArgumentException("fixture already exists");
        List<String> lines=new ArrayList<String>();
        for(byte[] f:score.uploadFrames()){StringBuilder s=new StringBuilder();for(int i=f.length-1;i>=0;i--)s.append(String.format(Locale.US,"%02x",f[i]&255));lines.add(s.toString());}
        Files.write(output,lines,StandardCharsets.US_ASCII);
        System.out.println("FULL_APP_KEY_PLAN_FIXTURE notes="+score.events.size()/2+" events="+score.events.size()+" frames="+lines.size());
    }
}
