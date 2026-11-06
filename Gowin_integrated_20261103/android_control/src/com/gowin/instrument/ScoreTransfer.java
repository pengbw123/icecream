package com.gowin.instrument;

import java.util.*;

/** Legacy single-frame or opt-in bounded EVENT window; final board CRC is unchanged. */
public final class ScoreTransfer {
    private final ScoreBurstTransfer burst=new ScoreBurstTransfer();
    private boolean windowed;
    private List<byte[]> frames=Collections.emptyList();private int index;private boolean busy,written,acked;
    public void start(List<byte[]> input){start(input,false);}
    public void start(List<byte[]> input,boolean window){
        start(input,window,ScoreCapabilities.legacy());
    }
    public void start(List<byte[]> input,boolean window,ScoreCapabilities capabilities){
        if(busy()||input==null||input.isEmpty())throw new IllegalStateException("曲谱传输状态错误");
        for(byte[] f:input){if(f==null||f.length!=12)throw new IllegalArgumentException("曲谱帧格式错误");if((f[2]&255)==0x50&&(ScoreCapabilities.le(f,3,2)<1||ScoreCapabilities.le(f,3,2)>capabilities.maxEvents))throw new IllegalArgumentException("曲谱超出当前板端容量");if((f[2]&255)==0x50&&(f[5]&255)==2&&!capabilities.keyPlanSupported())throw new IllegalArgumentException("板端不支持实体键映射");}
        if(window){if(!capabilities.windowSupported())throw new IllegalArgumentException("板端不支持窗口");burst.start(input,capabilities.maxEvents,capabilities.groupEvents);windowed=true;return;}
        windowed=false;frames=new ArrayList<byte[]>();for(byte[] f:input)frames.add(f.clone());index=0;busy=true;written=false;acked=false;
    }
    public boolean windowed(){return windowed;}
    public int groupSize(){return windowed?burst.groupSize():1;}
    public List<byte[]> chunks(){return windowed?burst.chunks():Collections.singletonList(current());}
    public boolean busy(){return windowed?burst.busy():busy;}
    public int done(){return windowed?burst.done():index;}
    public int total(){return windowed?burst.total():frames.size();}
    public boolean isWritten(){return windowed?burst.isWritten():written;}
    /** Diagnostic snapshot only: ACK count is not an event identity. */
    public String waitingSummary(){
        if(!busy())return "idle";
        return "cmd=0x"+Integer.toHexString(command())+" frames="+done()+"/"+total()
            +" group="+groupSize()+" GATT="+((windowed?burst.isWritten():written)?"complete":"pending")
            +" ACK="+(windowed?burst.ackCount():(acked?1:0))+"/"+groupSize();
    }
    public byte[] current(){if(windowed){if(burst.groupSize()!=1)throw new IllegalStateException("事件窗口请使用chunks");return burst.chunks().get(0);}if(!busy)throw new IllegalStateException("没有在途曲谱帧");return frames.get(index).clone();}
    public int command(){return windowed?burst.command():current()[2]&255;}
    public void written(){if(windowed){if(burst.busy())burst.written();}else if(busy)written=true;}
    public boolean reply(int cmd,int status){if(windowed)return burst.reply(cmd,status);if(!busy||command()!=cmd)return false;if(status!=0){cancel();throw new IllegalArgumentException("板端拒绝命令0x"+Integer.toHexString(cmd)+" 状态"+status);}if(acked){cancel();throw new IllegalArgumentException("重复板端回复，需重连后重传");}acked=true;return true;}
    public boolean canAdvance(){return windowed?burst.canAdvance():busy&&written&&acked;}
    public void advance(){if(windowed){burst.advance();return;}if(!canAdvance())throw new IllegalStateException("尚未同时收到写完成和板端ACK");index++;written=acked=false;if(index==frames.size())busy=false;}
    public void cancel(){burst.cancel();windowed=false;busy=false;written=acked=false;}
}
