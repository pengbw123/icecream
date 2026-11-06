package com.gowin.instrument;

/** 138K phone FM commands, executed by the board's own parameter logic. */
public final class FmPhoneProtocol {
    private FmPhoneProtocol() {}
    public static final int COMMAND=0x78;
    public static byte[] request(int group,int selector,int row,int value,int token,boolean read,boolean force) {
        if(group<1||group>8||selector<0||selector>5||row<0||row>13||value<0||value>127||token<1||token>65535)
            throw new IllegalArgumentException("音色命令参数越界");
        int flags=(read?1:0)|(force?2:0);
        byte[] data={(byte)group,(byte)selector,(byte)row,(byte)value,
                     (byte)token,(byte)(token>>>8),(byte)flags,(byte)0xd9};
        return Protocol.packet(COMMAND,data);
    }
    public static final class Reply {
        public final int status,token,value;
        Reply(int status,int token,int value){this.status=status;this.token=token;this.value=value;}
        public String label(){
            switch(status){
                case 0:return "板端已处理并回读";
                case 1:return "参数无效或不支持";
                case 2:return "切换音色会覆盖未保存的修改";
                case 3:return "板端读写超时或未确认";
                case 4:return "板端实际值与请求不一致";
                default:return "未知状态 "+status;
            }
        }
    }
    public static Reply decode(byte[] frame) {
        if(frame==null||frame.length!=9||(frame[0]&255)!=0xa5||(frame[1]&255)!=0x5a||
                (frame[2]&255)!=0xf4||(frame[3]&255)!=COMMAND)
            throw new IllegalArgumentException("音色回复帧格式错误");
        int check=0;for(int i=2;i<8;i++)check^=frame[i]&255;
        if(check!=(frame[8]&255))throw new IllegalArgumentException("音色回复校验错误");
        int token=(frame[5]&255)|((frame[6]&255)<<8);
        if(token==0)throw new IllegalArgumentException("音色回复序号无效");
        return new Reply(frame[4]&255,token,frame[7]&255);
    }
}
