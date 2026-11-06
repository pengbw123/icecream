package com.gowin.instrument;

import java.util.*;
import java.util.zip.CRC32;

/** SMF 0/1 -> a bounded, channel-merged note schedule. No audio playback. */
public final class Score {
    // Parser storage limit; upload permission is checked against the connected device.
    public static final int MAX_EVENTS=8192, MAX_BYTES=1024*1024;
    public static final class Event {
        // For mapped scores note is the physical MIDI key and targetNote is
        // the pitch to sound. Legacy scores use the same value for both.
        public final long timeMs; public final int note, velocity, targetNote;
        public Event(long timeMs,int note,int velocity){this(timeMs,note,velocity,note);}
        public Event(long timeMs,int note,int velocity,int targetNote){this.timeMs=timeMs;this.note=note;this.velocity=velocity;this.targetNote=targetNote;}
    }
    public final String name;
    public final List<Event> events;
    public final int peakVoices, minNote, maxNote;
    public final int mappedFirstKey;
    /** Non-null when the old channel-merged parser cannot preserve raw notes. */
    public final String fidelityIssue;
    /** Milliseconds per quarter note at the beginning of the first played note. */
    public final int firstBeatMs;
    public final long durationMs;
    public Score(String name,List<Event> input) {this(name,input,500);}
    private Score(String name,List<Event> input,int beatMs) {this(name,input,beatMs,-1);}
    private Score(String name,List<Event> input,int beatMs,int firstKey) {this(name,input,beatMs,firstKey,null);}
    private Score(String name,List<Event> input,int beatMs,int firstKey,String issue) {
        if(input.isEmpty()||input.size()>MAX_EVENTS)throw new IllegalArgumentException("曲谱事件数必须为1.."+MAX_EVENTS+"；当前 "+input.size());
        if(firstKey < -1 || firstKey > 103)throw new IllegalArgumentException("自动映射的最低实体键必须为 MIDI 0..103");
        boolean[] active=new boolean[128];int[] target=new int[128];int voices=0,peak=0,min=127,max=0;long prev=0;
        for(Event e:input){
            if(e.timeMs<prev||e.timeMs-prev>600000||e.note<0||e.note>127||e.targetNote<0||e.targetNote>127||e.velocity<0||e.velocity>127||
               (firstKey>=0&&(e.note<firstKey||e.note>=firstKey+25))||(firstKey<0&&e.targetNote!=e.note))throw new IllegalArgumentException("非法曲谱事件");
            if(e.velocity==0){if(!active[e.note]||target[e.note]!=e.targetNote)throw new IllegalArgumentException("未按下音符或实体键目标不一致的松键");active[e.note]=false;voices--;}
            else {if(active[e.note])throw new IllegalArgumentException("同一实体键被重复占用");active[e.note]=true;target[e.note]=e.targetNote;voices++;min=Math.min(min,e.note);max=Math.max(max,e.note);}
            peak=Math.max(peak,voices);prev=e.timeMs;
        }
        if(voices!=0)throw new IllegalArgumentException("曲谱存在未结束音符");
        this.name=name;events=Collections.unmodifiableList(new ArrayList<Event>(input));peakVoices=peak;minNote=min;maxNote=max;durationMs=prev;firstBeatMs=beatMs;mappedFirstKey=firstKey;fidelityIssue=issue;
    }
    static Score mapped(String name,List<Event> input,int beatMs,int firstKey){return new Score(name,input,beatMs,firstKey);}
    public boolean isMapped(){return mappedFirstKey>=0;}
    /** Beginning of the score by event count; timestamps and pitches are unchanged. */
    public Score prefix(int divisor){
        if(divisor!=1&&divisor!=2&&divisor!=4&&divisor!=8)throw new IllegalArgumentException("不支持的曲谱片段比例");
        if(divisor==1)return this;
        int size=events.size(),wanted=(size+divisor-1)/divisor;
        if(wanted>=size)return this;
        long boundary=events.get(wanted).timeMs;
        int end=wanted;
        // Never split events at a single timestamp (especially a chord).
        while(end>0&&events.get(end-1).timeMs==boundary)end--;
        if(end==0){
            // For a chord at the beginning keep the complete first timestamp.
            while(end<size&&events.get(end).timeMs==boundary)end++;
            if(end==size)return this;
            boundary=events.get(end).timeMs;
        }
        List<Event> part=new ArrayList<Event>(events.subList(0,end));
        Event[] active=new Event[128];
        for(Event e:part)active[e.note]=e.velocity!=0?e:null;
        for(int n=0;n<active.length;n++)if(active[n]!=null)part.add(new Event(boundary,n,0,active[n].targetNote));
        // An unusually dense first timestamp may already occupy the entire score.
        if(part.size()>=size||part.size()>MAX_EVENTS)return this;
        return new Score(name+" · 前 1/"+divisor,part,firstBeatMs,mappedFirstKey);
    }
    /** Keep complete note pairs for pitches selected by the user; preserve timestamps and source. */
    public Score onlyPitches(boolean[] allowed){
        if(allowed==null||allowed.length!=128)throw new IllegalArgumentException("琴键范围无效");
        List<Event> kept=new ArrayList<Event>();
        for(Event e:events)if(allowed[e.note])kept.add(e);
        if(kept.isEmpty())throw new IllegalArgumentException("所选片段没有已校准琴键可演奏的音符；请选择更长片段或调整校准 / 移调。");
        if(kept.size()==events.size())return this;
        return new Score(name,kept,firstBeatMs,mappedFirstKey);
    }

    /** Explicit transposition happens before upload, never silently in the FPGA. */
    public Score transposed(int semitones){
        if(semitones < -24 || semitones > 24)throw new IllegalArgumentException("移调需为 -24..24 半音");
        if(semitones==0)return this;
        List<Event> out=new ArrayList<Event>(events.size());for(Event e:events){
            int target=e.targetNote+semitones;
            if(target<0||target>127)throw new IllegalArgumentException("移调后音符超出 MIDI 0..127");
            out.add(new Event(e.timeMs,isMapped()?e.note:target,e.velocity,target));
        }
        return new Score(name,out,firstBeatMs,mappedFirstKey);
    }
    public byte[] practiceCommand(int percent,boolean waitForKey){
        if(percent<50||percent>150||firstBeatMs<1||firstBeatMs>60000)throw new IllegalArgumentException("曲谱速度或预备拍参数超出范围");
        byte[] d=new byte[8];d[0]=(byte)percent;d[1]=(byte)(waitForKey?1:0);d[2]=4;d[3]=(byte)firstBeatMs;d[4]=(byte)(firstBeatMs>>>8);d[5]='G';d[6]='P';d[7]='1';
        return Protocol.packet(0x5a,d);
    }
    public static byte[] command(int cmd){return Protocol.packet(cmd,new byte[8]);}
    public static byte[] volume(int value){
        if(value<0||value>127)throw new IllegalArgumentException("音量必须为0..127");
        byte[] data=new byte[8];data[0]=(byte)value;return Protocol.packet(0x56,data);
    }
    private static void le(byte[] d,int at,long v,int n){for(int i=0;i<n;i++)d[at+i]=(byte)(v>>>(i*8));}
    public List<byte[]> uploadFrames(){
        int version=isMapped()?2:1;
        List<byte[]> out=new ArrayList<byte[]>();byte[] begin=new byte[8];le(begin,0,events.size(),2);begin[2]=(byte)version;if(isMapped())begin[3]=(byte)mappedFirstKey;out.add(Protocol.packet(0x50,begin));
        CRC32 crc=new CRC32();long prev=0;
        for(int i=0;i<events.size();i++){Event e=events.get(i);byte[] d=new byte[8];le(d,0,i,2);long delay=e.timeMs-prev;if(isMapped())delay|=(long)(e.note-mappedFirstKey)<<20;le(d,2,delay,4);d[6]=(byte)e.targetNote;d[7]=(byte)e.velocity;crc.update(d,2,6);out.add(Protocol.packet(0x51,d));prev=e.timeMs;}
        byte[] seal=new byte[8];le(seal,0,crc.getValue(),4);le(seal,4,events.size(),2);seal[6]=(byte)version;out.add(Protocol.packet(0x52,seal));return out;
    }
    private static final class Raw {long tick;int order,type,a,b,ch;Raw(long t,int o,int k,int a,int b,int ch){tick=t;order=o;type=k;this.a=a;this.b=b;this.ch=ch;}}
    private static final class Reader {
        final byte[] b;int p,end;Reader(byte[] b,int p,int end){this.b=b;this.p=p;this.end=end;}
        int u(){if(p>=end)throw new IllegalArgumentException("MIDI被截断");return b[p++]&255;}
        long num(int n){long v=0;for(int i=0;i<n;i++)v=(v<<8)|u();return v;}
        long vlq(){long v=0;for(int i=0;i<4;i++){int c=u();v=(v<<7)|(c&127);if(c<128)return v;}throw new IllegalArgumentException("非法MIDI VLQ");}
        void skip(long n){if(n<0||n>end-p)throw new IllegalArgumentException("MIDI块长度错误");p+=(int)n;}
    }
    public static Score fromMidi(String name,byte[] bytes){
        if(bytes==null||bytes.length>MAX_BYTES)throw new IllegalArgumentException("MIDI文件上限1 MiB");
        Reader h=new Reader(bytes,0,bytes.length);
        if(h.num(4)!=0x4d546864L)throw new IllegalArgumentException("请选择标准.mid文件，不支持音频/NCM");
        long header=h.num(4);if(header<6)throw new IllegalArgumentException("MIDI头长度错误");
        int format=(int)h.num(2),tracks=(int)h.num(2),division=(int)h.num(2);h.skip(header-6);
        if(format>1||tracks<1||tracks>128||(format==0&&tracks!=1))throw new IllegalArgumentException("只支持MIDI类型0/1，最多128轨");
        if(division==0||(division&0x8000)!=0)throw new IllegalArgumentException("只支持PPQ节拍MIDI");
        List<Raw> raw=new ArrayList<Raw>();int order=0;long endTick=0;
        for(int tr=0;tr<tracks;tr++){
            if(h.num(4)!=0x4d54726bL)throw new IllegalArgumentException("缺少MTrk");long n=h.num(4);if(n>h.end-h.p)throw new IllegalArgumentException("轨道被截断");
            Reader r=new Reader(bytes,h.p,h.p+(int)n);h.skip(n);long tick=0;int running=0;
            while(r.p<r.end){
                tick+=r.vlq();if(tick>0x7fffffffL)throw new IllegalArgumentException("MIDI时长过大");int s=r.u();if(s<128){if(running==0)throw new IllegalArgumentException("无运行状态");r.p--;s=running;}
                if(s==255){int meta=r.u();long len=r.vlq();if(meta==0x51){if(len!=3)throw new IllegalArgumentException("非法速度事件");int tempo=(int)r.num(3);if(tempo==0)throw new IllegalArgumentException("速度为零");raw.add(new Raw(tick,order++,0,tempo,0,0));}else r.skip(len);if(meta==0x2f){if(len!=0)throw new IllegalArgumentException("非法轨道结束");break;}}
                else if(s==240||s==247){r.skip(r.vlq());running=0;}
                else {if(s>=240)throw new IllegalArgumentException("不支持的MIDI状态");running=s;int a=r.u(),b=0,type=s&240;if(type!=192&&type!=208)b=r.u();if(a>127||b>127)throw new IllegalArgumentException("MIDI数据越界");
                    if(type==128||type==144)raw.add(new Raw(tick,order++,1,a,type==128?0:b,s&15));
                    else if(type==176&&a==64)raw.add(new Raw(tick,order++,2,a,b,s&15));
                }
                if(raw.size()>200000)throw new IllegalArgumentException("MIDI事件过多");
            }
            endTick=Math.max(endTick,tick);
        }
        Collections.sort(raw,new Comparator<Raw>(){public int compare(Raw a,Raw b){int c=Long.compare(a.tick,b.tick);return c!=0?c:Integer.compare(a.order,b.order);}});
        // Audit the original note stream before the legacy parser merges by
        // channel/pitch. Do not treat a paired-on count alone as proof of the
        // original durations: repeated presses can truncate an earlier note.
        boolean[][] rawHeld=new boolean[16][128];String fidelityIssue=null;int rawOn=0;
        for(Raw e:raw)if(e.type==1){
            if(e.ch==9){if(fidelityIssue==null)fidelityIssue="原 MIDI 含鼓通道，常规解析会忽略鼓轨。";continue;}
            if(e.b>0){rawOn++;if(rawHeld[e.ch][e.a]&&fidelityIssue==null)fidelityIssue="原 MIDI 有同通道同音重叠，常规解析会改变音符结束时间。";rawHeld[e.ch][e.a]=true;}
            else {if(!rawHeld[e.ch][e.a]&&fidelityIssue==null)fidelityIssue="原 MIDI 存在无法在通道内唯一配对的松键。";rawHeld[e.ch][e.a]=false;}
        }
        for(int ch=0;ch<16;ch++)for(int n=0;n<128;n++)if(rawHeld[ch][n]&&fidelityIssue==null)fidelityIssue="原 MIDI 存在未松开的音符，常规解析会自动补松键。";
        long firstNoteTick=Long.MAX_VALUE;for(Raw e:raw)if(e.type==1&&e.ch!=9&&e.b>0)firstNoteTick=Math.min(firstNoteTick,e.tick);
        int firstTempo=500000;for(Raw e:raw)if(e.type==0&&e.tick<=firstNoteTick)firstTempo=e.a;
        boolean[][] held=new boolean[16][128],sounding=new boolean[16][128];boolean[] pedal=new boolean[16];int[] total=new int[128];
        List<Event> notes=new ArrayList<Event>();long lastTick=0,us=0,remainder=0;int tempo=500000;
        for(Raw e:raw){long numerator=(e.tick-lastTick)*tempo+remainder;us+=numerator/division;remainder=numerator%division;lastTick=e.tick;long ms=(us+500)/1000;
            if(e.type==0){tempo=e.a;continue;}
            if(e.type==2){pedal[e.ch]=e.b>=64;if(!pedal[e.ch])for(int note=0;note<128;note++)if(sounding[e.ch][note]&&!held[e.ch][note])release(notes,sounding,total,e.ch,note,ms);continue;}
            if(e.ch==9)continue; // Drum notes are not pitched instruments in this synth.
            if(e.b>0){if(sounding[e.ch][e.a])release(notes,sounding,total,e.ch,e.a,ms);held[e.ch][e.a]=true;sounding[e.ch][e.a]=true;if(total[e.a]++==0)notes.add(new Event(ms,e.a,e.b));}
            else {held[e.ch][e.a]=false;if(!pedal[e.ch]&&sounding[e.ch][e.a])release(notes,sounding,total,e.ch,e.a,ms);}
        }
        long finalMs=(us+((endTick-lastTick)*tempo+remainder)/division+500)/1000;
        for(int ch=0;ch<16;ch++)for(int n=0;n<128;n++)if(sounding[ch][n])release(notes,sounding,total,ch,n,finalMs);
        int parsedOn=0;for(Event e:notes)if(e.velocity>0)parsedOn++;
        if(parsedOn!=rawOn&&fidelityIssue==null)fidelityIssue="常规解析会合并或丢失原 MIDI 音符。";
        return new Score(name,notes,Math.max(1,(firstTempo+500)/1000),-1,fidelityIssue);
    }
    private static void release(List<Event> out,boolean[][] sounding,int[] total,int ch,int note,long ms){sounding[ch][note]=false;if(--total[note]==0)out.add(new Event(ms,note,0));}
}
