package com.gowin.instrument;
import java.util.*;
public final class FmPhoneProtocolTest {
    private static void check(boolean ok,String s){if(!ok)throw new AssertionError(s);}
    private static byte[] reply(int status,int token,int value){byte[] b={(byte)0xa5,0x5a,(byte)0xf4,0x78,(byte)status,(byte)token,(byte)(token>>>8),(byte)value,0};for(int i=2;i<8;i++)b[8]^=b[i];return b;}
    private static void invalid(Runnable r){boolean failed=false;try{r.run();}catch(IllegalArgumentException ex){failed=true;}check(failed,"expected invalid");}
    public static void main(String[] args){
        byte[] q=FmPhoneProtocol.request(3,5,7,99,0x5aa5,false,true);
        check(q.length==12&&(q[2]&255)==0x78&&(q[7]&255)==0xa5&&(q[8]&255)==0x5a&&(q[9]&255)==2,"request format");
        int x=0;for(int i=2;i<11;i++)x^=q[i]&255;check(x==(q[11]&255),"request XOR");
        invalid(()->FmPhoneProtocol.request(1,0,0,1,0,false,false));invalid(()->FmPhoneProtocol.request(9,0,0,1,1,false,false));
        byte[] packet=reply(0,0x5aa5,42);ReplyDecoder decoder=new ReplyDecoder();List<ReplyDecoder.Reply> got=new ArrayList<>();
        for(byte b:packet)got.addAll(decoder.feed(new byte[]{b}));
        check(got.size()==1&&got.get(0).phone.token==0x5aa5&&got.get(0).phone.value==42,"split or embedded header");
        packet[8]^=1;check(decoder.feed(packet).isEmpty(),"bad XOR must be rejected");
        byte[] f0={(byte)0xa5,0x5a,(byte)0xf0,0x55,0,(byte)(0xf0^0x55)};
        got=decoder.feed(f0);check(got.size()==1&&got.get(0).phone==null&&got.get(0).command==0x55,"legacy response");
        check(FmPresetNames.NAMES.length==128,"preset count");
        check(FmToneSpec.protocolSelector(3,0)==5&&FmToneSpec.protocolSelector(3,5)==0,"operator numbering");
        check(FmToneSpec.parameters(2,0)[3].raw(-24)==0&&FmToneSpec.parameters(2,0)[3].display(48)==24,"transpose mapping");
        check(FmToneSpec.parameters(3,0)[3].raw(-7)==0&&FmToneSpec.parameters(3,0)[3].display(14)==7,"detune mapping");
        for(int e=0;e<6;e++){FmToneSpec.Param[] pp=FmToneSpec.parameters(7,e);for(FmToneSpec.Param p:pp)check(p.row!=2||e<2,"unsupported effect type");}
        System.out.println("PASS FM request/reply framing, legacy ACK, parameter mapping, 128 presets");
    }
}
