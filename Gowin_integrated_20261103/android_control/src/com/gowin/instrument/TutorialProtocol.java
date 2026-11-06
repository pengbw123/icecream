package com.gowin.instrument;

import java.util.ArrayList;
import java.util.List;

/** Dedicated 138K tutorial control. No FM parameters or legacy score upload. */
public final class TutorialProtocol {
    private TutorialProtocol() {}
    private static byte[] frame(int command,int d0,int d1,int d2,int d3){
        byte[] data={(byte)0xa5,0x5a,(byte)command,(byte)d0,(byte)d1,(byte)d2,(byte)d3,0x47,0x55,0x49,0x44,0};
        int check=0;for(int i=2;i<11;i++)check^=data[i]&255;data[11]=(byte)check;return data;
    }
    public static byte[] probe(){return frame(0x75,0,0,0,0);}
    public static byte[] start(){return frame(0x70,1,0,0,0);}
    public static byte[] stop(){return frame(0x70,0,0,0,0);}
    public static byte[] mode(boolean waitForKey){return frame(0x76,waitForKey?1:0,0,0,0);}
    public static byte[] scan(boolean enabled,int index){
        if(index<0||index>=256)throw new IllegalArgumentException("灯珠编号需为0..255，并小于实际灯数");
        return frame(0x71,enabled?1:0,index&255,index>>>8,0);
    }
    public static byte[] mapping(int index,int kind,int note){
        if(index<0||index>=256||kind<0||kind>2||note<0||note>127)throw new IllegalArgumentException("灯位映射超出范围");
        return frame(0x72,index&255,index>>>8,kind,note);
    }
    public static byte[] clear(){return frame(0x73,0,0,0,0);}
    public static byte[] calibrationComplete(){return frame(0x77,0,0,0,0);}
    public static byte[] settings(int speed,int countIn,int transpose){
        if(speed<50||speed>150||countIn<0||countIn>8||transpose< -24||transpose>24)
            throw new IllegalArgumentException("速度50..150%，预备拍0..8，移调-24..24");
        return frame(0x74,speed,countIn,transpose,0);
    }
    public static List<byte[]> profile(int ledCount,int firstNote,int[] indices,int beatIndex){
        if(ledCount<25||ledCount>256||firstNote<0||firstNote>103||indices==null||indices.length!=25)
            throw new IllegalArgumentException("请填写25键灯位及正确的灯数/MIDI范围");
        boolean[] used=new boolean[ledCount];
        List<byte[]> result=new ArrayList<>();result.add(clear());
        for(int key=0;key<25;key++){
            int index=indices[key];if(index<0||index>=ledCount||used[index])
                throw new IllegalArgumentException("第"+(key+1)+"键灯位未设、重复或越界；请先逐灯校准");
            used[index]=true;result.add(mapping(index,1,firstNote+key));
        }
        if(beatIndex>=0){
            if(beatIndex>=ledCount||used[beatIndex])throw new IllegalArgumentException("节拍灯越界或占用了琴键灯位");
            result.add(mapping(beatIndex,2,0));
        }else if(beatIndex!= -1)throw new IllegalArgumentException("不设节拍灯时填写-1");
        return result;
    }
    public static void checkRange(int firstNote,int transpose){
        if(55+transpose<firstNote||74+transpose>firstNote+24)
            throw new IllegalArgumentException("移调后的曲谱音域"+(55+transpose)+".."+(74+transpose)+"超出这25键，请先调整移调或键盘八度");
    }
}
