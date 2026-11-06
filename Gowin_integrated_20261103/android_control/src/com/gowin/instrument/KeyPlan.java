package com.gowin.instrument;

import java.util.*;

/**
 * Converts SMF tracks into a physical-key score. Each note-off is paired with
 * the unique held note in the same track, channel and pitch. SMF channel
 * messages contain no note-instance identifier: this is an explicit practice
 * interpretation, not a claim that all MIDI players pair tracks this way.
 */
public final class KeyPlan {
    private KeyPlan() {}
    public static final class Result {
        public final Score score;
        public final int pairedNotes, sameChannelOverlaps, shiftedEvents, otherControls, expression, sysex, programs, releaseVelocities;
        Result(Score score,int pairs,int overlap,int shifted,int controls,int expression,int sysex,int programs,int releases){
            this.score=score;pairedNotes=pairs;sameChannelOverlaps=overlap;shiftedEvents=shifted;
            otherControls=controls;this.expression=expression;this.sysex=sysex;this.programs=programs;releaseVelocities=releases;
        }
    }
    private static final class Reader {
        final byte[] data;final int end;int pos;
        Reader(byte[] b,int p,int end){data=b;pos=p;this.end=end;}
        int u(){if(pos>=end)throw new IllegalArgumentException("MIDI 被截断");return data[pos++]&255;}
        long num(int n){long v=0;for(int i=0;i<n;i++)v=(v<<8)|u();return v;}
        long vlq(){long v=0;for(int i=0;i<4;i++){int c=u();v=(v<<7)|(c&127);if(c<128)return v;}throw new IllegalArgumentException("MIDI VLQ 错误");}
        void skip(long n){if(n<0||n>end-pos)throw new IllegalArgumentException("MIDI 数据块长度错误");pos+=(int)n;}
    }
    private static final class Raw {
        long tick,ms,time,endTick;int order,kind,track,ch,note,value,id;
        Raw(long t,int order,int kind,int track,int ch,int note,int value){this.tick=t;this.order=order;this.kind=kind;this.track=track;this.ch=ch;this.note=note;this.value=value;}
    }
    private static final class Edge {
        int to,reverse,capacity,cost;
        Edge(int to,int reverse,int cap,int cost){this.to=to;this.reverse=reverse;capacity=cap;this.cost=cost;}
    }
    private static void edge(List<List<Edge>> g,int from,int to,int cost){
        Edge a=new Edge(to,g.get(to).size(),1,cost), b=new Edge(from,g.get(from).size(),0,-cost);
        g.get(from).add(a);g.get(to).add(b);
    }
    /** Same minimum-cost assignment used by the offline checker, for each timestamp. */
    private static int[] assign(List<Raw> onsets,boolean[] occupied,int first,int[] lastKey){
        List<Integer> available=new ArrayList<Integer>();for(int k=0;k<25;k++)if(!occupied[k])available.add(k);
        int m=onsets.size(),n=available.size();if(m>n)throw new IllegalArgumentException("同时需要超过 25 个独立实体键");
        int source=0,left=1,right=1+m,sink=right+n;
        List<List<Edge>> g=new ArrayList<List<Edge>>();for(int i=0;i<=sink;i++)g.add(new ArrayList<Edge>());
        for(int i=0;i<m;i++){
            edge(g,source,left+i,0);Raw e=onsets.get(i);
            for(int j=0;j<n;j++){
                int key=available.get(j),physical=first+key;
                int pitchCost=physical==e.note?0:physical%12==e.note%12?1000:100000;
                int continuity=lastKey[e.note]==key?0:10;
                edge(g,left+i,right+j,pitchCost+Math.abs(physical-e.note)*4+continuity+key+1);
            }
        }
        for(int j=0;j<n;j++)edge(g,right+j,sink,0);
        for(int flow=0;flow<m;flow++){
            int[] dist=new int[sink+1],prev=new int[sink+1],prevEdge=new int[sink+1];boolean[] inQueue=new boolean[sink+1];
            Arrays.fill(dist,Integer.MAX_VALUE/4);Arrays.fill(prev,-1);dist[source]=0;
            ArrayDeque<Integer> queue=new ArrayDeque<Integer>();queue.add(source);inQueue[source]=true;
            while(!queue.isEmpty()){
                int u=queue.remove();inQueue[u]=false;List<Edge> edges=g.get(u);
                for(int k=0;k<edges.size();k++){Edge e=edges.get(k);if(e.capacity>0&&dist[e.to]>dist[u]+e.cost){
                    dist[e.to]=dist[u]+e.cost;prev[e.to]=u;prevEdge[e.to]=k;
                    if(!inQueue[e.to]){queue.add(e.to);inQueue[e.to]=true;}
                }}
            }
            if(prev[sink]<0)throw new IllegalArgumentException("当前时刻无法分配实体键");
            for(int v=sink;v!=source;v=prev[v]){Edge e=g.get(prev[v]).get(prevEdge[v]);e.capacity--;g.get(v).get(e.reverse).capacity++;}
        }
        int[] result=new int[m];Arrays.fill(result,-1);
        for(int i=0;i<m;i++)for(Edge e:g.get(left+i))if(e.to>=right&&e.to<sink&&e.capacity==0){result[i]=available.get(e.to-right);break;}
        for(int k:result)if(k<0)throw new IllegalArgumentException("实体键分配内部校验失败");
        return result;
    }

    public static Result fromMidi(String name,byte[] bytes,int firstKey){
        if(bytes==null||bytes.length>Score.MAX_BYTES)throw new IllegalArgumentException("MIDI 文件上限 1 MiB");
        if(firstKey<0||firstKey>103)throw new IllegalArgumentException("请先完成 25 键灯位校准");
        Reader h=new Reader(bytes,0,bytes.length);if(h.num(4)!=0x4d546864L)throw new IllegalArgumentException("请选择标准 MIDI");
        long header=h.num(4);if(header<6)throw new IllegalArgumentException("MIDI 头长度错误");
        int format=(int)h.num(2),tracks=(int)h.num(2),division=(int)h.num(2);h.skip(header-6);
        if(format>1||tracks<1||tracks>128||(format==0&&tracks!=1)||division==0||(division&0x8000)!=0)
            throw new IllegalArgumentException("仅支持 PPQ 格式 0/1 MIDI");
        List<Raw> all=new ArrayList<Raw>();Set<Integer> programs=new HashSet<Integer>();int order=0,controls=0,expression=0,sysex=0,releases=0;
        for(int tr=0;tr<tracks;tr++){
            if(h.num(4)!=0x4d54726bL)throw new IllegalArgumentException("缺少 MIDI 轨道");
            long length=h.num(4);if(length>h.end-h.pos)throw new IllegalArgumentException("MIDI 轨道被截断");
            Reader r=new Reader(bytes,h.pos,h.pos+(int)length);h.skip(length);long tick=0;int running=0;
            while(r.pos<r.end){
                tick+=r.vlq();if(tick>0x7fffffffL)throw new IllegalArgumentException("MIDI 时长过大");
                int s=r.u();if(s<128){if(running==0)throw new IllegalArgumentException("MIDI 运行状态错误");r.pos--;s=running;}
                if(s==255){int meta=r.u();long len=r.vlq();if(meta==0x51){if(len!=3)throw new IllegalArgumentException("速度事件错误");int tempo=(int)r.num(3);if(tempo==0)throw new IllegalArgumentException("速度不能为零");all.add(new Raw(tick,order++,0,tr,0,0,tempo));}else r.skip(len);if(meta==0x2f){if(len!=0)throw new IllegalArgumentException("轨道结束事件错误");break;}}
                else if(s==240||s==247){r.skip(r.vlq());running=0;sysex++;}
                else {
                    if(s>=240)throw new IllegalArgumentException("不支持的 MIDI 状态");running=s;
                    int a=r.u(),b=0,type=s&240,ch=s&15;if(type!=192&&type!=208)b=r.u();
                    if(a>127||b>127)throw new IllegalArgumentException("MIDI 数据越界");
                    if(type==128||type==144){if(ch==9)throw new IllegalArgumentException("含鼓通道音符，不能映射为钢琴音");if(type==128&&b!=0)releases++;all.add(new Raw(tick,order++,1,tr,ch,a,type==128?0:b));}
                    else if(type==176&&a==64)throw new IllegalArgumentException("曲谱含延音踏板；逐轨映射暂不支持，未生成计划");
                    else if(type==192)programs.add(a);
                    else if(type==176)controls++;
                    else if(type==224||type==208||type==160)expression++;
                }
                if(all.size()>200000)throw new IllegalArgumentException("MIDI 事件过多");
            }
        }
        Collections.sort(all,new Comparator<Raw>(){public int compare(Raw a,Raw b){int c=Long.compare(a.tick,b.tick);return c!=0?c:Integer.compare(a.order,b.order);}});
        long firstTick=Long.MAX_VALUE;for(Raw e:all)if(e.kind==1&&e.value>0){firstTick=e.tick;break;}
        int firstTempo=500000;for(Raw e:all)if(e.kind==0&&e.tick<=firstTick)firstTempo=e.value;
        long last=0,us=0,rem=0,previous=0;int tempo=500000,shifted=0,nextId=0,overlaps=0;
        Map<Integer,Raw> held=new HashMap<Integer,Raw>();List<Raw> events=new ArrayList<Raw>(),starts=new ArrayList<Raw>();
        for(Raw e:all){
            long numerator=(e.tick-last)*tempo+rem;us+=numerator/division;rem=numerator%division;last=e.tick;e.ms=(us+500)/1000;
            if(e.kind==0){tempo=e.value;continue;}
            int key=(e.track<<11)|(e.ch<<7)|e.note;
            if(e.value>0){
                if(held.containsKey(key))throw new IllegalArgumentException("同一轨道、通道、音高的重叠音无法唯一配对：轨道 "+(e.track+1)+"，MIDI "+e.note);
                e.id=nextId++;e.time=Math.max(previous,e.ms);held.put(key,e);starts.add(e);
            } else {
                Raw begin=held.remove(key);if(begin==null)throw new IllegalArgumentException("轨道内存在无法配对的松键：轨道 "+(e.track+1)+"，MIDI "+e.note);
                begin.endTick=e.tick;e.id=begin.id;e.time=Math.max(Math.max(previous,e.ms),begin.time+1);
            }
            if(e.time-e.ms>1)throw new IllegalArgumentException("短音需要后移超过 1 ms，拒绝静默更改节奏");
            if(e.time!=e.ms)shifted++;previous=e.time;events.add(e);
            if(events.size()>Score.MAX_EVENTS)throw new IllegalArgumentException("曲谱超过 "+Score.MAX_EVENTS+" 事件");
        }
        if(!held.isEmpty())throw new IllegalArgumentException("轨道内有未松开的音符");
        if(events.isEmpty())throw new IllegalArgumentException("MIDI 没有可演奏的音符");
        // Same-tick release and onset are adjacent, not overlapping. Track
        // ordering in the SMF must not turn that boundary into a false overlap.
        for(int i=0;i<starts.size();i++)for(int j=0;j<i;j++){
            Raw a=starts.get(i),b=starts.get(j);
            if(a.ch==b.ch&&a.note==b.note&&Math.max(a.tick,b.tick)<Math.min(a.endTick,b.endTick))overlaps++;
        }
        int[] keyById=new int[nextId],targetById=new int[nextId],lastKey=new int[128];Arrays.fill(keyById,-1);Arrays.fill(lastKey,-1);
        boolean[] occupied=new boolean[25];List<Score.Event> planned=new ArrayList<Score.Event>();
        for(int begin=0;begin<events.size();){
            int end=begin+1;while(end<events.size()&&events.get(end).time==events.get(begin).time)end++;
            for(int i=begin;i<end;i++){Raw e=events.get(i);if(e.value==0){int k=keyById[e.id];
                if(k<0||!occupied[k]||targetById[e.id]!=e.note)throw new IllegalArgumentException("实体键松开校验失败");
                occupied[k]=false;keyById[e.id]=-1;planned.add(new Score.Event(e.time,firstKey+k,0,e.note));
            }}
            List<Raw> ons=new ArrayList<Raw>();for(int i=begin;i<end;i++)if(events.get(i).value>0)ons.add(events.get(i));
            int[] selected=assign(ons,occupied,firstKey,lastKey);
            for(int i=0;i<ons.size();i++){Raw e=ons.get(i);int k=selected[i];if(occupied[k])throw new IllegalArgumentException("实体键重复占用");
                occupied[k]=true;keyById[e.id]=k;targetById[e.id]=e.note;lastKey[e.note]=k;
                planned.add(new Score.Event(e.time,firstKey+k,e.value,e.note));
            }
            begin=end;
        }
        for(boolean used:occupied)if(used)throw new IllegalArgumentException("计划有未松开的实体键");
        Score score=Score.mapped(name,planned,Math.max(1,(firstTempo+500)/1000),firstKey);
        return new Result(score,nextId,overlaps,shifted,controls,expression,sysex,programs.size(),releases);
    }
}
