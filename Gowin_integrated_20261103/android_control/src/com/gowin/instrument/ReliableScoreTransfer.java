package com.gowin.instrument;
import java.util.*;
import java.util.zip.CRC32;

/** One bounded block in flight. Timeout DATA -> QUERY -> resend only uncommitted data. */
public final class ReliableScoreTransfer {
    private Score score;
    private long session;
    private byte[] begin,pending;
    private byte[][] events;
    private long[] prefixCrc;
    private int committed,sentHigh,pendingEnd,type,retries,stalls;
    private boolean busy,written,completed,aborting,aborted;
    private ReliableScoreProtocol.Reply reply;
    private final Set<Integer> boundaries=new HashSet<>();
    public boolean busy(){return busy;}
    public boolean hasSession(){return session!=0;}
    // A sealed score can also be queried after reconnect to restore the Play UI.
    public boolean canResume(){return hasSession()&&!busy;}
    public boolean completed(){return completed;}
    public boolean aborted(){return aborted;}
    public int done(){return committed;}
    public int total(){return score==null?0:score.events.size();}
    public int type(){return type;}
    public long session(){return session;}
    public Score score(){return score;}
    public int retries(){return retries;}
    public void start(Score score,ScoreCapabilities caps,long session){
        if(score.isMapped())throw new IllegalArgumentException("实体键映射请使用逐帧或窗口上传");
        if(busy||hasSession())throw new IllegalStateException("请先释放此前可靠会话");
        if(!caps.reliableSupported()||session==0)throw new IllegalArgumentException("板端未协商可靠v2");
        caps.checkUpload(score);this.score=score;this.session=session;
        events=new byte[score.events.size()][];prefixCrc=new long[events.length+1];CRC32 crc=new CRC32();long previous=0;
        for(int i=0;i<events.length;i++){Score.Event e=score.events.get(i);byte[] d=new byte[6];ReliableScoreProtocol.le(d,0,e.timeMs-previous,4);d[4]=(byte)e.note;d[5]=(byte)e.velocity;events[i]=d;crc.update(d);prefixCrc[i+1]=crc.getValue();previous=e.timeMs;}
        begin=ReliableScoreProtocol.begin(session,events.length,crc.getValue(),caps.nonce);
        committed=sentHigh=0;retries=stalls=0;completed=aborting=aborted=false;boundaries.clear();boundaries.add(0);busy=true;
        setPending(ReliableScoreProtocol.BEGIN,begin,0);
    }
    private void setPending(int kind,byte[] bytes,int end){type=kind;pending=bytes.clone();pendingEnd=end;written=false;reply=null;}
    private void query(){setPending(ReliableScoreProtocol.QUERY,ReliableScoreProtocol.message(ReliableScoreProtocol.QUERY,session,0,0,new byte[0]),committed);}
    public byte[] current(){if(!busy)throw new IllegalStateException("没有在途可靠消息");return pending.clone();}
    public void written(){if(busy)written=true;}
    public boolean accept(ReliableScoreProtocol.Reply r){
        if(!busy||r.session!=session||r.type!=type)return false;
        if(type==ReliableScoreProtocol.ABORT){
            if(r.status!=0&&r.status!=3)throw new IllegalArgumentException("释放可靠会话被拒绝，状态"+r.status+"；请先停止当前指引");
            reply=r;return true;
        }
        if(r.status==3){pause();throw new IllegalArgumentException("板端已复位或会话失效，请重新上传");}
        if(r.status!=0&&r.status!=4&&r.status!=5){pause();throw new IllegalArgumentException("可靠消息被板端拒绝，状态"+r.status);}
        // BEGIN can be rejected while the previous v1 playback/flush still owns
        // the backend. No new session was allocated, so retry BEGIN, never DATA.
        if(type==ReliableScoreProtocol.BEGIN&&r.status==4&&r.state==0&&r.next==0&&r.limit==0&&(r.total==0||r.total==total())){reply=r;return true;}
        if(r.next<committed)return false; // A late cumulative ACK never moves the cursor backwards.
        if(r.total!=total()||r.next>sentHigh||!boundaries.contains(r.next)||r.scoreCrc!=prefixCrc[r.next]||r.limit>Math.min(total(),r.next+8)){
            pause();throw new IllegalArgumentException("板端提交位置/CRC与本次曲谱不符，停止续传");
        }
        if(type==ReliableScoreProtocol.DATA&&r.status==0&&r.next!=pendingEnd)return false; // Duplicate previous-block ACK.
        if(type==ReliableScoreProtocol.SEAL&&r.status==0&&(r.next!=total()||r.state!=2)){
            pause();throw new IllegalArgumentException("板端未确认曲谱封存");
        }
        if(r.state==4){pause();throw new IllegalArgumentException("板端提交失败，请释放会话后重新上传");}
        if(r.status==0&&r.state==0){pause();throw new IllegalArgumentException("板端没有持有本次会话，请释放会话后重新上传");}
        // A success may replace an earlier BUSY/NACK while local writes finish.
        if(reply==null||reply.status!=0||r.status==0)reply=r;
        return true;
    }
    public boolean canAdvance(){return busy&&written&&reply!=null;}
    public void advance(){
        if(!canAdvance())throw new IllegalStateException("尚未同时收到本地写完成和累计回复");
        ReliableScoreProtocol.Reply r=reply;
        if(type==ReliableScoreProtocol.ABORT){busy=false;session=0;aborted=true;aborting=false;completed=false;return;}
        if(type==ReliableScoreProtocol.BEGIN&&r.status==4&&r.state==0){if(++stalls>12){pause();throw new IllegalArgumentException("板端持续忙，起始会话尚未分配；请停止当前指引后重试");}setPending(ReliableScoreProtocol.BEGIN,begin,0);return;}
        if(r.next>committed){committed=r.next;retries=stalls=0;}
        if(r.status!=0){if(++stalls>12){pause();throw new IllegalArgumentException("板端持续忙，已暂停可靠上传");}query();return;}
        if(r.state==2){if(committed!=total()){pause();throw new IllegalArgumentException("封存数量不符");}completed=true;busy=false;return;}
        if(committed==total()){setPending(ReliableScoreProtocol.SEAL,ReliableScoreProtocol.message(ReliableScoreProtocol.SEAL,session,total(),0,new byte[0]),total());return;}
        int n=Math.min(8,Math.min(total()-committed,r.limit-committed));
        if(n==0){if(++stalls>12){pause();throw new IllegalArgumentException("板端持续无可用credit，已暂停");}query();return;}
        byte[] data=new byte[n*6];for(int i=0;i<n;i++)System.arraycopy(events[committed+i],0,data,i*6,6);
        pendingEnd=committed+n;sentHigh=Math.max(sentHigh,pendingEnd);boundaries.add(pendingEnd);
        setPending(ReliableScoreProtocol.DATA,ReliableScoreProtocol.message(ReliableScoreProtocol.DATA,session,committed,n,data),pendingEnd);
    }
    public void timeout(){
        if(!busy)return;
        if(!written){pause();throw new IllegalArgumentException("本地GATT写未完成，需重连后查询续传");}
        if(++retries>3){pause();throw new IllegalArgumentException("可靠查询/重传超过3次，已暂停；可重连后继续");}
        if(type==ReliableScoreProtocol.DATA)query();else setPending(type,pending,pendingEnd);
    }
    public void pause(){busy=false;written=false;reply=null;}
    public void resume(){if(!canResume())throw new IllegalStateException("没有可继续的可靠上传");busy=true;completed=false;retries=stalls=0;if(aborting)setPending(ReliableScoreProtocol.ABORT,ReliableScoreProtocol.message(ReliableScoreProtocol.ABORT,session,0,0,new byte[0]),committed);else query();}
    public void abort(){if(busy||!hasSession())throw new IllegalStateException("没有可释放的可靠会话");busy=true;aborting=true;aborted=false;retries=0;setPending(ReliableScoreProtocol.ABORT,ReliableScoreProtocol.message(ReliableScoreProtocol.ABORT,session,0,0,new byte[0]),committed);}
    public String waitingSummary(){return "v2 session="+Long.toHexString(session)+" type="+type+" committed="+committed+"/"+total()+" GATT="+(written?"complete":"pending")+" retry="+retries;}
}
