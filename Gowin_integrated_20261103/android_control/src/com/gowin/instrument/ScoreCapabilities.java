package com.gowin.instrument;

/** Read-only 0x57 negotiation. Missing/unsupported capabilities always use the old limits. */
public final class ScoreCapabilities {
    public static final int LEGACY_EVENTS=2048, LEGACY_VOICES=8;
    public final boolean negotiated;
    public final long nonce, uartBaud;
    public final int deviceEvents, maxEvents, voices, groupEvents, flags, scoreVersion;

    private ScoreCapabilities(boolean negotiated,long nonce,int capacity,int voices,int group,int flags,long baud,int version) {
        this.negotiated=negotiated;this.nonce=nonce;deviceEvents=capacity;
        maxEvents=Math.min(Score.MAX_EVENTS,capacity);this.voices=voices;
        groupEvents=group;this.flags=flags;uartBaud=baud;scoreVersion=version;
    }
    public static ScoreCapabilities legacy() {
        return new ScoreCapabilities(false,0,LEGACY_EVENTS,LEGACY_VOICES,8,1,0,1);
    }
    static long le(byte[] b,int p,int n){long v=0;for(int i=0;i<n;i++)v|=(long)(b[p+i]&255)<<(8*i);return v;}
    public static byte[] query(long nonce) {
        if(nonce<=0 || nonce>0xffffffffL)throw new IllegalArgumentException("能力查询标识越界");
        byte[] d=new byte[8];for(int i=0;i<4;i++)d[i]=(byte)(nonce>>>(8*i));
        return Protocol.packet(0x57,d);
    }
    public static ScoreCapabilities decode(byte[] b) {
        if(b==null || b.length!=20 || (b[0]&255)!=0xa5 || (b[1]&255)!=0x5a ||
                (b[2]&255)!=0xf1 || b[3]!=1 || (b[4]&255)!=0x57)
            throw new IllegalArgumentException("能力回复格式错误");
        int xor=0;for(int i=2;i<20;i++)xor^=b[i]&255;
        int capacity=(int)le(b,9,2), voices=b[11]&255, group=b[12]&255, flags=b[13]&255, version=b[18]&255;
        long nonce=le(b,5,4), baud=le(b,14,4);
        if(xor!=0 || nonce==0 || capacity<1 || voices<1 || voices>128 || group<1 || group>8 ||
                (flags&~7)!=0 || (version!=1&&version!=2) || ((flags&2)!=0&&version!=2) || baud==0)
            throw new IllegalArgumentException("能力回复字段错误");
        return new ScoreCapabilities(true,nonce,capacity,voices,group,flags,baud,version);
    }
    public boolean windowSupported(){return (flags&1)!=0;}
    public boolean reliableSupported(){return negotiated&&(flags&2)!=0&&scoreVersion==2;}
    public boolean keyPlanSupported(){return negotiated&&(flags&4)!=0;}
    /** Select only speeds explicitly advertised by the current board. */
    public int recommendedUploadMode(){
        if(reliableSupported())return 4;
        if(negotiated&&uartBaud>=115200)return windowSupported()&&groupEvents>1?3:2;
        return 1;
    }
    public void checkUpload(Score score) {
        if(score.isMapped()&&!keyPlanSupported())throw new IllegalArgumentException("板端未声明一键多音映射能力；请使用配套 FPGA，旧版不能接收此曲谱。");
        if(score.events.size()>maxEvents)throw new IllegalArgumentException("当前板端上限 "+maxEvents+" 事件，曲目需要 "+score.events.size()+"；请使用分段曲目或检测已升级板端");
        if(score.peakVoices>voices)throw new IllegalArgumentException("当前板端 "+voices+" 声部，曲目最多按住 "+score.peakVoices+" 个音符；释音尾声还会占用声部");
    }
    public String description(){return (negotiated?"已协商":"旧协议回退")+"：最多"+maxEvents+"事件 · "+voices+"声部"+(reliableSupported()?" · 可靠v2":"")+(negotiated?" · UART "+uartBaud:"");}
}
