package com.gowin.instrument;
import java.util.*;
public final class TutorialProtocolTest {
    private static int checks;
    private static void check(boolean condition){checks++;if(!condition)throw new AssertionError("Tutorial check "+checks);}
    private static void invalid(Runnable action){try{action.run();throw new AssertionError("Invalid request accepted");}catch(IllegalArgumentException expected){checks++;}}
    private static void frame(byte[] value,int command){
        check(value.length==12&&value[0]==(byte)0xa5&&value[1]==0x5a&&(value[2]&255)==command);
        check(value[7]==0x47&&value[8]==0x55&&value[9]==0x49&&value[10]==0x44);
        int sum=0;for(int i=2;i<11;i++)sum^=value[i]&255;check((value[11]&255)==sum);
        ReplyDecoder decoder=new ReplyDecoder();byte[] ack={(byte)0xa5,0x5a,(byte)0xf0,(byte)command,0,(byte)(0xf0^command)};
        for(int split=0;split<=6;split++){
            decoder.reset();List<ReplyDecoder.Reply> replies=new ArrayList<>();
            replies.addAll(decoder.feed(Arrays.copyOfRange(ack,0,split)));
            replies.addAll(decoder.feed(Arrays.copyOfRange(ack,split,6)));
            check(replies.size()==1&&replies.get(0).command==command&&replies.get(0).status==0);
        }
    }
    public static void main(String[] args){
        frame(TutorialProtocol.start(),0x70);frame(TutorialProtocol.stop(),0x70);frame(TutorialProtocol.probe(),0x75);
        frame(TutorialProtocol.mode(true),0x76);frame(TutorialProtocol.mode(false),0x76);
        frame(TutorialProtocol.calibrationComplete(),0x77);check(TutorialProtocol.calibrationComplete()[3]==0&&TutorialProtocol.calibrationComplete()[4]==0&&TutorialProtocol.calibrationComplete()[5]==0&&TutorialProtocol.calibrationComplete()[6]==0);
        check(TutorialProtocol.mode(true)[3]==1&&TutorialProtocol.mode(false)[3]==0);
        check(TutorialProtocol.start()[3]==1&&TutorialProtocol.stop()[3]==0);
        for(int index=0;index<256;index++){
            byte[] scan=TutorialProtocol.scan(true,index);frame(scan,0x71);check((scan[4]&255)==index&&scan[5]==0);
            for(int kind=0;kind<=2;kind++)for(int note=0;note<128;note++){
                byte[] map=TutorialProtocol.mapping(index,kind,note);
                check((map[3]&255)==index&&map[4]==0&&(map[5]&255)==kind&&(map[6]&255)==note);
            }
        }
        for(int speed=50;speed<=150;speed++)for(int transpose=-24;transpose<=24;transpose++){
            byte[] value=TutorialProtocol.settings(speed,4,transpose);
            check((value[3]&255)==speed&&value[4]==4&&value[5]==(byte)transpose&&value[6]==0);
        }
        int[] keys=new int[25];for(int i=0;i<25;i++)keys[i]=i*2;
        List<byte[]> profile=TutorialProtocol.profile(160,48,keys,159);
        check(profile.size()==27&&(profile.get(0)[2]&255)==0x73);
        check((profile.get(25)[3]&255)==48&&(profile.get(25)[6]&255)==72);
        check((profile.get(26)[5]&255)==2);
        keys[24]=0;invalid(()->TutorialProtocol.profile(160,48,keys,-1));keys[24]=48;
        invalid(()->TutorialProtocol.profile(160,48,keys,2));
        keys[24]=-1;invalid(()->TutorialProtocol.profile(160,48,keys,-1));keys[24]=48;
        invalid(()->TutorialProtocol.settings(49,4,-2));invalid(()->TutorialProtocol.settings(151,4,-2));
        invalid(()->TutorialProtocol.settings(100,9,-2));invalid(()->TutorialProtocol.settings(100,4,25));
        invalid(()->TutorialProtocol.scan(true,256));invalid(()->TutorialProtocol.mapping(0,3,60));
        TutorialProtocol.checkRange(48,-2);TutorialProtocol.checkRange(60,10);
        invalid(()->TutorialProtocol.checkRange(48,0));
        // An unrelated ACK or local completion alone cannot advance a command.
        ScoreTransfer transfer=new ScoreTransfer();transfer.start(Arrays.asList(TutorialProtocol.probe(),TutorialProtocol.start()));
        check(!transfer.reply(0x50,0));transfer.written();check(!transfer.canAdvance());
        check(transfer.reply(0x75,0)&&transfer.canAdvance());transfer.advance();
        check(transfer.reply(0x70,0)&&!transfer.canAdvance());transfer.written();check(transfer.canAdvance());transfer.advance();
        check(!transfer.busy());
        System.out.println("TUTORIAL_PROTOCOL_OK checks="+checks);
    }
}
