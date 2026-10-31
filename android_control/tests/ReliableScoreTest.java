package com.gowin.instrument;

import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.zip.CRC32;

/** Pure Java fault-injection checks and shared UART vectors, never a radio/board test. */
public final class ReliableScoreTest {
    private static int checks;
    private static final long SESSION=0x1020304050607080L, NONCE=0x12345678L;
    private static void ok(boolean value,String why){checks++;if(!value)throw new AssertionError(why);}
    private static void reject(Runnable action,String why){checks++;try{action.run();}catch(IllegalArgumentException|IllegalStateException expected){return;}throw new AssertionError(why);}
    private static long le(byte[] b,int p,int n){return ScoreCapabilities.le(b,p,n);}
    private static void le(byte[] b,int p,long v,int n){ReliableScoreProtocol.le(b,p,v,n);}
    private static long crc(byte[] b,int p,int n){CRC32 c=new CRC32();c.update(b,p,n);return c.getValue();}
    private static String hex(byte[] bytes){StringBuilder s=new StringBuilder();for(byte b:bytes)s.append(String.format(Locale.US,"%02x",b&255));return s.toString();}
    private static Score synthetic(int n){List<Score.Event> events=new ArrayList<>();for(int i=0;i<n;i++)events.add(new Score.Event(i*10L,60+(i/2)%8,(i&1)==0?100:0));return new Score("synthetic "+n,events);}
    private static byte[] capability(){byte[] b=BluetoothUpgradeTest.capabilityFrame(8192,12,8);b[13]=3;b[18]=2;BluetoothUpgradeTest.sum(b);return b;}
    private static ScoreCapabilities caps(){return ScoreCapabilities.decode(capability());}
    static byte[] response(int kind,int status,long session,int next,int total,int state,int limit,long scoreCrc){
        byte[] b=new byte[32];b[0]=(byte)0xa5;b[1]=0x5a;b[2]=(byte)0xf2;b[3]=1;b[4]=(byte)kind;b[5]=(byte)status;
        le(b,6,session,8);le(b,14,next,2);le(b,16,limit,2);le(b,18,total,2);b[20]=(byte)state;b[21]=8;le(b,22,scoreCrc,4);le(b,28,crc(b,2,26),4);return b;
    }
    /** Independent receiver model: stores actual six-byte deltas and checks final CRC. */
    private static final class Board {
        int next,total,state;long session,expected;boolean blocked;byte[] data=new byte[8192*6];
        byte[] receive(byte[] request){
            ok(request.length==67&&le(request,63,4)==crc(request,2,61),"request wire CRC");
            int type=request[3]&255,start=(int)le(request,12,2),count=request[14]&255,status=0;long sid=le(request,4,8);
            if(type==1){
                if(state==0){ok(le(request,21,4)==NONCE,"allocation nonce");session=sid;total=(int)le(request,15,2);expected=le(request,17,4);next=0;state=1;}
                else if(sid!=session)status=4;
                else if(total!=le(request,15,2)||expected!=le(request,17,4))status=1;
            }else if(state==0||sid!=session)status=3;
            else if(type==2){
                if(blocked)status=4;
                else if(start==next){ok(count>=1&&count<=8&&next+count<=total,"block bounds");System.arraycopy(request,15,data,next*6,count*6);next+=count;}
                else if(start+count!=next)status=5;
            }else if(type==3){if(next!=total||crc(data,0,next*6)!=expected)status=1;else state=2;}
            else if(type==5){state=0;next=total=0;}
            int limit=(state==1&&!blocked)?Math.min(total,next+8):next;
            return response(type,status,sid,next,total,blocked&&state==1?3:state,limit,crc(data,0,next*6));
        }
    }
    private static ReliableScoreTransfer start(Score score){ReliableScoreTransfer t=new ReliableScoreTransfer();t.start(score,caps(),SESSION);return t;}
    private static void commit(ReliableScoreTransfer t,byte[] reply){ok(t.accept(ReliableScoreProtocol.decode(reply)),"matching reply accepted");t.written();ok(t.canAdvance(),"local completion and ACK both required");t.advance();}
    private static void step(ReliableScoreTransfer t,Board b){commit(t,b.receive(t.current()));}
    private static void finish(ReliableScoreTransfer t,Board b){int limit=10000;while(t.busy()&&--limit>0)step(t,b);ok(limit>0&&t.completed()&&b.state==2,"sealed all events");}
    private static void full(Score score){ReliableScoreTransfer t=start(score);Board b=new Board();finish(t,b);ok(t.done()==score.events.size(),"cumulative count never truncates");
        List<byte[]> v1=score.uploadFrames();for(int i=0;i<score.events.size();i++)for(int k=0;k<6;k++)ok(v1.get(i+1)[5+k]==b.data[i*6+k],"v2 matches v1 exact event delta bytes");
    }
    private static void faults(){
        Score s=synthetic(20);ReliableScoreTransfer t=start(s);Board b=new Board();
        byte[] begin=t.current(),reply=b.receive(begin);
        ok(t.accept(ReliableScoreProtocol.decode(reply))&&!t.canAdvance(),"ACK arriving before local finish cannot advance");t.written();t.advance();
        byte[] first=t.current(),firstAck=b.receive(first);t.written();t.timeout();ok(t.type()==4,"lost DATA ACK switches to QUERY");
        ok(!t.accept(ReliableScoreProtocol.decode(firstAck)),"late DATA ACK ignored during QUERY");step(t,b);ok(t.done()==8&&le(t.current(),12,2)==8,"QUERY discovers committed data without duplicate write");
        ok(!t.accept(ReliableScoreProtocol.decode(firstAck)),"previous block duplicate ACK cannot commit next block");
        byte[] second=t.current();t.written();t.timeout();step(t,b);ok(Arrays.equals(second,t.current()),"lost DATA request is retransmitted exactly after query");
        ok(!t.accept(ReliableScoreProtocol.decode(response(2,0,SESSION+1,16,20,1,20,0))),"cross-session ACK ignored");finish(t,b);
        t.pause();ok(t.canResume(),"completed score can be queried after reconnect");t.resume();ok(!t.completed()&&t.type()==4,"reconnect queries sealed session");step(t,b);ok(t.completed(),"sealed query restores completed state");
        t.abort();step(t,b);ok(t.aborted()&&!t.hasSession()&&!t.busy(),"abort frees local session only after ACK");t.start(s,caps(),SESSION+1);ok(t.session()==SESSION+1,"new song/session can begin after abort");

        t=start(s);b=new Board();b.blocked=true;step(t,b);ok(t.type()==4&&t.done()==0,"zero credit queries rather than sending data");b.blocked=false;step(t,b);ok(t.type()==2,"credit recovers from absolute query limit");finish(t,b);
        t=start(s);b=new Board();reply=b.receive(t.current());t.written();t.timeout();ok(Arrays.equals(t.current(),begin),"lost BEGIN ACK retries identical idempotent BEGIN");step(t,b);finish(t,b);
        t=start(s);b=new Board();step(t,b);t.pause();t.resume();ok(t.type()==4,"resume always queries before retransmission");step(t,b);finish(t,b);

        ReliableScoreTransfer noWrite=start(s);reject(noWrite::timeout,"GATT completion missing pauses without unsafe resend");ok(!noWrite.busy()&&noWrite.hasSession(),"GATT failure retains resumable ownership");
        ReliableScoreTransfer reset=start(s);reject(()->reset.accept(ReliableScoreProtocol.decode(response(1,3,SESSION,0,0,0,0,0))),"reset/no session stops transfer");ok(reset.canResume(),"failed reset keeps session until explicit release");reset.abort();commit(reset,response(5,3,SESSION,0,0,0,0,0));ok(!reset.hasSession(),"NO_SESSION on abort safely frees stale local session");
        ReliableScoreTransfer changed=start(s);Board changedBoard=new Board();step(changed,changedBoard);reject(()->changed.accept(ReliableScoreProtocol.decode(response(2,0,SESSION,8,20,1,16,0))),"unexpected prefix CRC stops transfer");
        ReliableScoreTransfer abandoned=start(s);Board abandonedBoard=new Board();step(abandoned,abandonedBoard);abandoned.pause();abandoned.abort();reject(()->abandoned.accept(ReliableScoreProtocol.decode(response(5,4,SESSION,0,20,3,0,0))),"busy abort never silently frees ownership");abandoned.pause();abandoned.resume();ok(abandoned.type()==5,"resume preserves abort intent");step(abandoned,abandonedBoard);ok(abandoned.aborted(),"abort resumes after busy clears");
        ReliableScoreTransfer exhausted=start(s);exhausted.written();for(int i=0;i<3;i++){exhausted.timeout();exhausted.written();}reject(exhausted::timeout,"retry count bounded");ok(!exhausted.busy(),"retry exhaustion pauses");
        ReliableScoreTransfer beginBusy=start(s);byte[] exactBegin=beginBusy.current();commit(beginBusy,response(1,4,SESSION,0,0,0,0,0x11223344L));ok(beginBusy.type()==1&&Arrays.equals(exactBegin,beginBusy.current()),"unallocated BUSY BEGIN retries BEGIN without sending data or querying a nonexistent owner");finish(beginBusy,new Board());
        ReliableScoreTransfer creditStall=start(s);Board creditBoard=new Board();creditBoard.blocked=true;for(int i=0;i<12;i++)step(creditStall,creditBoard);reject(()->step(creditStall,creditBoard),"persistent zero credit bounded");
    }
    private static void framing(){
        byte[] r=response(4,0,SESSION,0,20,1,8,0);
        for(int split=0;split<=32;split++){ReplyDecoder d=new ReplyDecoder();List<ReplyDecoder.Reply> rs=new ArrayList<>();rs.addAll(d.feed(Arrays.copyOfRange(r,0,split)));rs.addAll(d.feed(Arrays.copyOfRange(r,split,32)));ok(rs.size()==1&&rs.get(0).reliable.session==SESSION,"arbitrary reply split "+split);}
        ReplyDecoder d=new ReplyDecoder();int count=0;for(byte v:r)count+=d.feed(new byte[]{v}).size();ok(count==1,"byte-sized notifications");
        byte[] corrupt=r.clone(),legacy={(byte)0xa5,0x5a,(byte)0xf0,0x55,0,(byte)0xa5};System.arraycopy(legacy,0,corrupt,10,6);ok(new ReplyDecoder().feed(corrupt).isEmpty(),"invalid F2 cannot replay embedded v1 ACK");
        byte[] mixed=new byte[64];System.arraycopy(r,0,mixed,0,32);System.arraycopy(r,0,mixed,32,32);ok(new ReplyDecoder().feed(mixed).size()==2,"glued reliable replies");
        byte[] msg=ReliableScoreProtocol.begin(SESSION,20,0,NONCE);List<byte[]> chunks=ReliableScoreProtocol.chunks(msg);ok(chunks.size()==4&&chunks.get(0).length==20&&chunks.get(3).length==7,"67-byte frame over unchanged 20-byte ATT");
        reject(()->ReliableScoreProtocol.begin(SESSION,20,0,0x100000000L),"allocation nonce cannot truncate");reject(()->ReliableScoreProtocol.begin(SESSION,20,0x100000000L,NONCE),"target CRC cannot truncate");
    }
    private static void export(Path dir,String name,Score score)throws Exception{
        ReliableScoreTransfer t=start(score);Board b=new Board();StringBuilder req=new StringBuilder(),rep=new StringBuilder();int messages=0;
        while(t.busy()){byte[] message=t.current(),reply=b.receive(message);req.append(hex(message)).append('\n');rep.append(hex(reply)).append('\n');commit(t,reply);messages++;}
        Files.write(dir.resolve(name+"-requests.hex"),req.toString().getBytes(StandardCharsets.US_ASCII));Files.write(dir.resolve(name+"-replies.hex"),rep.toString().getBytes(StandardCharsets.US_ASCII));
        StringBuilder v1=new StringBuilder();v1.append(hex(Score.command(0x55))).append('\n');for(byte[] frame:score.uploadFrames())v1.append(hex(frame)).append('\n');Path fixture=dir.resolve(name+"-v1.hex").toAbsolutePath().normalize();Files.write(fixture,v1.toString().getBytes(StandardCharsets.US_ASCII));
        String meta="{\n  \"messages\": "+messages+",\n  \"events\": "+score.events.size()+",\n  \"durationMs\": "+score.durationMs+",\n  \"peakHeldNotes\": "+score.peakVoices+",\n  \"nonceHex\": \"12345678\",\n  \"sessionHex\": \"1020304050607080\",\n  \"crc32Hex\": \""+String.format(Locale.US,"%08x",b.expected)+"\",\n  \"requestBytes\": 67,\n  \"replyBytes\": 32,\n  \"wireOrder\": \"left-to-right transmitted bytes; little-endian numeric fields\",\n  \"v1Fixture\": \""+fixture.toString().replace('\\','/')+"\"\n}\n";
        Files.write(dir.resolve(name+"-metadata.json"),meta.getBytes(StandardCharsets.UTF_8));System.out.println("V2_FIXTURE "+name+" messages="+messages+" events="+score.events.size()+" crc32="+String.format(Locale.US,"%08x",b.expected));
    }
    public static void main(String[] args)throws Exception{
        framing();faults();for(int n:new int[]{2,2048,4096,8192})full(synthetic(n));Score truth=Score.fromMidi("Truth complete",Files.readAllBytes(Paths.get(args[0])));ok(truth.events.size()==3140,"actual Truth is complete 3140 events");full(truth);
        Path dir=Paths.get(args[1]);Files.createDirectories(dir);export(dir,"short",synthetic(20));export(dir,"truth",truth);StringBuilder cap=new StringBuilder();for(byte v:capability())cap.append(String.format(Locale.US,"%02x\n",v&255));Files.write(dir.resolve("capability-v2.hex"),cap.toString().getBytes(StandardCharsets.US_ASCII));
        System.out.println("RELIABLE_V2_JAVA_OK checks="+checks+" actual_Truth_events="+truth.events.size());
    }
}
