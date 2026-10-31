package com.gowin.instrument;

import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.List;

public final class ProtocolTest {
    private static int checks=0;
    private static void check(boolean ok,String name){checks++;if(!ok)throw new AssertionError(name);}
    private static void invalid(Runnable r){boolean failed=false;try{r.run();}catch(IllegalArgumentException e){failed=true;}check(failed,"invalid input accepted");}
    public static void main(String[] args)throws Exception {
        check(Protocol.hex(Protocol.sustain(0.5)).equals("A5 5A 12 00 80 00 00 00 00 00 00 92"),"Q16 even rounding");
        check(Protocol.decayQ24(0)==0,"disabled decay");
        check(Protocol.decayQ24(120000)>=1,"minimum coefficient");
        invalid(()->Protocol.amplitude(4,0,0.5));invalid(()->Protocol.amplitude(0,16,0.5));
        invalid(()->Protocol.sustain(Double.NaN));invalid(()->Protocol.sustain(Double.POSITIVE_INFINITY));
        invalid(()->Protocol.timing(0x10,0));invalid(()->Protocol.timing(0x42,100));
        invalid(()->Protocol.harmonicDecay(0,0,-1));invalid(()->Protocol.harmonicDecay(0,0,120001));
        invalid(()->Protocol.packet(0x100,new byte[8]));
        Preset p=new Preset();for(int a=0;a<4;a++)for(int h=0;h<16;h++){p.amplitudes[a][h]=((a*16+h)%11)/10.0;p.decayMs[a][h]=(a*16+h)*1100.0;}
        List<byte[]> frames=Protocol.frames(p);check(frames.size()==133,"preset frame count");
        byte[] actual=new byte[1596];for(int i=0;i<133;i++)System.arraycopy(frames.get(i),0,actual,i*12,12);
        check(Arrays.equals(actual,Files.readAllBytes(Paths.get(args[0]))),"Python/Java 133-frame parity");
        ReplyDecoder decoder=new ReplyDecoder(); byte[] ack={(byte)0xa5,0x5a,(byte)0xf0,0x12,0,(byte)0xe2};
        for(int split=0;split<=6;split++){decoder.reset();check(decoder.feed(Arrays.copyOfRange(ack,0,split)).size()+(decoder.feed(Arrays.copyOfRange(ack,split,6))).size()==1,"fragmented ACK");}
        byte[] noisy={1,(byte)0xa5,0x5a,(byte)0xf0,0x12,0,0,(byte)0xa5,0x5a,(byte)0xf0,0x12,0,(byte)0xe2,(byte)0xa5,0x5a,(byte)0xf0,0x40,2,(byte)0xb2};
        decoder.reset();List<ReplyDecoder.Reply> replies=decoder.feed(noisy);
        check(replies.size()==2&&replies.get(0).status==0&&replies.get(1).status==2,"noise corrupt checksum multiple frames");
        decoder.reset();byte[] flood=new byte[100000];decoder.feed(flood);check(decoder.feed(ack).size()==1,"bounded noise recovery");
        System.out.println("PROTOCOL_TEST_OK checks="+checks+" Python parity=133 frames");
    }
}
