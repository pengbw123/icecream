package com.gowin.instrument;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
/** Export the exact app uploader frames for the independent RTL byte-path test. */
public final class ScoreFixture {
    public static void main(String[] args)throws Exception {
        Path out=Paths.get(args[0]);Files.createDirectories(out);
        List<Score.Event> shortEvents=new ArrayList<Score.Event>();
        for(int i=0;i<10;i++){
            shortEvents.add(new Score.Event(i*20,60+i%8,100));
            shortEvents.add(new Score.Event(i*20+10,60+i%8,0));
        }
        export(out.resolve("window-short.hex"),new Score("window short",shortEvents));
        for(int i=1;i<args.length;i++){
            Path input=Paths.get(args[i]);Score s=Score.fromMidi(input.getFileName().toString(),Files.readAllBytes(input));
            export(out.resolve(input.getFileName().toString()+".hex"),s);
        }
    }
    private static void export(Path dest,Score s)throws Exception{
            List<byte[]> frames=new ArrayList<byte[]>();frames.add(Score.command(0x55));frames.addAll(s.uploadFrames());
            StringBuilder text=new StringBuilder();for(byte[] frame:frames){for(byte b:frame)text.append(String.format(Locale.US,"%02x",b&255));text.append('\n');}
            Files.write(dest,text.toString().getBytes(StandardCharsets.US_ASCII));
            System.out.println(dest+" frames="+frames.size()+" events="+s.events.size());
    }
}
