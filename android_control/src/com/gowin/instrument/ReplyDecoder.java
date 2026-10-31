package com.gowin.instrument;

import java.util.ArrayList;
import java.util.List;

/** Streaming resynchronization: notification boundaries are not UART frame boundaries. */
public final class ReplyDecoder {
    private final ArrayList<Byte> buffer=new ArrayList<>();
    public static final class Reply {
        public final int command,status;
        public final ScoreCapabilities capabilities;
        public final ReliableScoreProtocol.Reply reliable;
        public Reply(int command,int status){this.command=command;this.status=status;capabilities=null;reliable=null;}
        public Reply(ScoreCapabilities capabilities){command=0x57;status=0;this.capabilities=capabilities;reliable=null;}
        public Reply(ReliableScoreProtocol.Reply reliable){command=0x60;status=reliable.status;this.reliable=reliable;capabilities=null;}
        public String label(){if(capabilities!=null)return capabilities.description();if(reliable!=null)return reliable.label();String[] names={command==0x56?"音量事件已排队":(command>=0x50&&command<=0x55?"曲谱命令已接受":"参数命令已接受"),"不支持的命令或非法参数/曲谱状态","数据包校验错误","帧内超时","内部译码器超时"};return status>=0&&status<names.length?names[status]:"未知状态 "+status;}
    }
    public void reset(){buffer.clear();}
    public List<Reply> feed(byte[] data) {
        List<Reply> replies=new ArrayList<>();
        for(byte b:data){buffer.add(b);drain(replies);}return replies;
    }
    private void drain(List<Reply> out) {
        while(buffer.size()>=3) {
            if((buffer.get(0)&255)!=0xa5||(buffer.get(1)&255)!=0x5a){buffer.remove(0);continue;}
            int type=buffer.get(2)&255;
            if(type==0xf2){
                if(buffer.size()<32)return;
                byte[] frame=new byte[32];for(int i=0;i<32;i++)frame[i]=buffer.get(i);
                try {out.add(new Reply(ReliableScoreProtocol.decode(frame)));}catch(IllegalArgumentException ignored){}
                for(int i=0;i<32;i++)buffer.remove(0);continue;
            }
            if(type==0xf1){
                if(buffer.size()<20)return;
                byte[] frame=new byte[20];for(int i=0;i<20;i++)frame[i]=buffer.get(i);
                try {out.add(new Reply(ScoreCapabilities.decode(frame)));}
                catch(IllegalArgumentException ignored) { /* Consume the whole recognized F1 envelope. */ }
                for(int i=0;i<20;i++)buffer.remove(0);
                continue;
            }
            if(type!=0xf0){buffer.remove(0);continue;}
            if(buffer.size()<6)return;
            int cmd=buffer.get(3)&255,st=buffer.get(4)&255,check=buffer.get(5)&255;
            if(check!=(0xf0^cmd^st)){buffer.remove(0);continue;}
            out.add(new Reply(cmd,st));for(int i=0;i<6;i++)buffer.remove(0);
        }
    }
}
