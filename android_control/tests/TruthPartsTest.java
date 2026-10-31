package com.gowin.instrument;
import java.nio.file.*;
import java.util.*;

/** Compare release parser output against the original MIDI's exported full schedule. */
public final class TruthPartsTest {
    public static void main(String[] args)throws Exception{
        List<String> original=Files.readAllLines(Paths.get(args[0]));int at=1;
        for(int part=1;part<=2;part++){
            Score s=Score.fromMidi("part"+part,Files.readAllBytes(Paths.get(args[part])));
            if(s.events.size()!=(part==1?1566:1574)||s.peakVoices!=5)throw new AssertionError("part capacity/polyphony");
            long offset=part==1?0:110745;
            for(Score.Event event:s.events){String actual=(event.timeMs+offset)+","+event.note+","+event.velocity;
                if(!actual.equals(original.get(at++)))throw new AssertionError("changed note/time/velocity at "+(at-1));}
            List<byte[]> frames=s.uploadFrames();if(frames.size()!=s.events.size()+2)throw new AssertionError("upload framing");
        }
        if(at!=original.size()||at!=3141)throw new AssertionError("lost or added events");
        System.out.println("TRUTH_PARTS_PASS original 3140 events preserved exactly, release parser and upload limits accepted");
    }
}
