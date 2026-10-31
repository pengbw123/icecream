package com.gowin.instrument;
import java.util.*;
import java.util.zip.CRC32;

/** Fixed 67-byte request and 32-byte CRC32 response; both coexist with v1 framing. */
public final class ReliableScoreProtocol {
    public static final int BEGIN=1,DATA=2,SEAL=3,QUERY=4,ABORT=5,BLOCK_EVENTS=8;
    private ReliableScoreProtocol(){}
    static void le(byte[] b,int at,long v,int n){for(int i=0;i<n;i++)b[at+i]=(byte)(v>>>(8*i));}
    static long le(byte[] b,int at,int n){return ScoreCapabilities.le(b,at,n);}
    static long crc(byte[] b,int at,int n){CRC32 crc=new CRC32();crc.update(b,at,n);return crc.getValue();}
    public static byte[] message(int type,long session,int start,int count,byte[] payload) {
        if(type<BEGIN||type>ABORT||session==0||start<0||start>65535||count<0||count>8||payload==null||payload.length>48)
            throw new IllegalArgumentException("可靠曲谱消息字段越界");
        byte[] b=new byte[67];b[0]=(byte)0xa5;b[1]=0x5a;b[2]=0x60;b[3]=(byte)type;
        le(b,4,session,8);le(b,12,start,2);b[14]=(byte)count;System.arraycopy(payload,0,b,15,payload.length);
        le(b,63,crc(b,2,61),4);return b;
    }
    public static byte[] begin(long session,int count,long targetCrc,long allocationNonce){
        if(count<1||count>Score.MAX_EVENTS||allocationNonce<=0||allocationNonce>0xffffffffL||targetCrc<0||targetCrc>0xffffffffL)throw new IllegalArgumentException("可靠曲谱起始参数错误");
        byte[] d=new byte[10];le(d,0,count,2);le(d,2,targetCrc,4);le(d,6,allocationNonce,4);
        return message(BEGIN,session,0,0,d);
    }
    public static boolean validMessage(byte[] b){return b!=null&&b.length==67&&(b[0]&255)==0xa5&&(b[1]&255)==0x5a&&b[2]==0x60&&le(b,63,4)==crc(b,2,61);}
    public static List<byte[]> chunks(byte[] b){
        if(!validMessage(b))throw new IllegalArgumentException("可靠消息校验错误");
        List<byte[]> out=new ArrayList<>();for(int p=0;p<b.length;p+=20)out.add(Arrays.copyOfRange(b,p,Math.min(p+20,b.length)));return out;
    }
    public static final class Reply {
        public final int type,status,next,limit,total,state,blockEvents;
        public final long session,scoreCrc;
        private Reply(byte[] b){type=b[4]&255;status=b[5]&255;session=le(b,6,8);next=(int)le(b,14,2);limit=(int)le(b,16,2);total=(int)le(b,18,2);state=b[20]&255;blockEvents=b[21]&255;scoreCrc=le(b,22,4);}
        public String label(){return "可靠曲谱 session="+Long.toHexString(session)+" 已提交="+next+"/"+total+" 可发送至="+limit+" 状态="+state;}
    }
    public static Reply decode(byte[] b){
        if(b==null||b.length!=32||(b[0]&255)!=0xa5||(b[1]&255)!=0x5a||(b[2]&255)!=0xf2||b[3]!=1||
                le(b,28,4)!=crc(b,2,26)||b[26]!=0||b[27]!=0)throw new IllegalArgumentException("可靠回复校验错误");
        Reply r=new Reply(b);
        if(r.type<1||r.type>5||r.status>6||r.session==0||r.next>r.limit||r.limit>r.total||r.state>4||r.blockEvents!=8)
            throw new IllegalArgumentException("可靠回复字段错误");
        return r;
    }
}
