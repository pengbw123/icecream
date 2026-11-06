"""POP909 adapter: derive constrained monophonic bass from PIANO accompaniment.
Melody features are causal, labels may use accompaniment at the target step.
The extracted bass is a simplification, not a separately annotated bass track.
"""
import bisect
import re
from pathlib import Path
import mido
import numpy as np
from model import action_note,GATES,DYNAMICS

ROOTS={'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}

def notes(path):
    midi=mido.MidiFile(str(path));tempos=[(0,500000)]
    for tr in midi.tracks:
        tick=0
        for msg in tr:
            tick+=msg.time
            if msg.type=='set_tempo':tempos.append((tick,msg.tempo))
    tempos=sorted(dict(tempos).items());ticks=[v[0] for v in tempos];secs=[0.]
    for i in range(1,len(tempos)):
        secs.append(secs[-1]+mido.tick2second(ticks[i]-ticks[i-1],midi.ticks_per_beat,tempos[i-1][1]))
    def sec(t):
        i=bisect.bisect_right(ticks,t)-1
        return secs[i]+mido.tick2second(t-ticks[i],midi.ticks_per_beat,tempos[i][1])
    tracks={}
    for tr in midi.tracks:
        pending={};out=[];tick=0
        for msg in tr:
            tick+=msg.time
            if msg.type not in ('note_on','note_off'):continue
            key=(msg.channel,msg.note)
            if msg.type=='note_on' and msg.velocity:
                pending.setdefault(key,[]).append((sec(tick),msg.velocity))
            elif pending.get(key):
                start,vel=pending[key].pop(0)
                out.append((start,sec(tick),msg.note,vel))
        tracks[tr.name]=sorted(out)
    return tracks

def chord(token):
    m=re.match(r'^([A-G])([b#]?):(maj|min)',token)
    if not m:return None
    return (ROOTS[m[1]]+{'':0,'b':-1,'#':1}[m[2]])%12,m[3]=='min'

def sequence(folder,sparse=False,rollout=None):
    tracks=notes(folder/(folder.name+'.mid'))
    melody=tracks.get('MELODY',[])
    # Derived low-register proxy, not an annotated bass instrument.
    piano=[n for n in tracks.get('PIANO',[]) if n[2]<=60]
    beatinfo=np.loadtxt(str(folder/'beat_midi.txt'),ndmin=2);beats=beatinfo[:,0]
    if len(beats)<8 or not melody or not piano:return [],[],[]
    downs=np.flatnonzero(beatinfo[:,2]>.5)
    if len(downs)>1 and np.median(np.diff(downs))!=4:return [],[],[]
    anchor=int(downs[0]) if len(downs) else 0
    chords=[]
    for line in (folder/'chord_midi.txt').read_text().splitlines():
        a,b,c=line.split();chords.append((float(a),float(b),chord(c)))
    times=[]
    for j in range(anchor,len(beats)-1):
        times.extend(beats[j]+(beats[j+1]-beats[j])*k/4 for k in range(4))
    hist=[0]*12;history=[0]*16;recent=[];held=[];active_bass=[]
    mi=0;pi=0;ci=0;prev_root=-1;prev_minor=False;silence=16;velocity=0;prev_on=None
    xs=[];ys=[];metadata=[]
    for step,t in enumerate(times):
        step_seconds=(times[step+1]-t) if step+1<len(times) else (t-times[step-1])
        unit=max(step_seconds/8,1e-5);onset=0
        while mi<len(melody) and melody[mi][0]<=t+1e-7:
            a,b,p,v=melody[mi];mi+=1;onset+=1
            hist[p%12]=min(127,hist[p%12]+48);held.append((b,p))
            recent=[(a,b,p,v,0 if prev_on is None else a-prev_on)]+recent[:7]
            prev_on=a;velocity=v
        held=[n for n in held if n[0]>t];history=[onset]+history[:15]
        silence=0 if onset else min(16,silence+1)
        while ci+1<len(chords) and chords[ci][1]<=t:ci+=1
        ch=chords[ci][2] if chords[ci][0]<=t<chords[ci][1] else None
        attacks=[]
        while pi<len(piano) and piano[pi][0]<t+step_seconds*.5:
            n=piano[pi];pi+=1;active_bass.append(n)
            if n[0]>=t-step_seconds*.5:attacks.append(n)
        active_bass=[n for n in active_bass if n[1]>t]
        if ch is None:hist=[h//2 for h in hist];continue
        root,minor=ch;x=np.zeros(96,dtype=np.uint8)
        x[step&15]=127
        x[16:28]=[hist[(p+root)%12] for p in range(12)]
        for end,p in held:x[28+(p-root)%12]=127
        for pc in [0,3 if minor else 4,7]:x[28+pc]=127
        x[40:44]=[min(127,n*24) for n in history[:4]]
        x[44]=velocity;x[45]=min(127,len(held)*16);x[46]=min(127,silence*8);x[47]=127 if minor else 0
        for k,(a,b,p,v,ioi) in enumerate(recent):
            x[48+k]=p;x[56+k]=min(127,max(0,int((min(t,b)-a)/unit)))
            x[64+k]=min(127,max(0,int(ioi/unit)));x[72+k]=v
        x[80:92]=[min(127,n*24) for n in history[4:]]
        x[92]=127 if (root!=prev_root or minor!=prev_minor) else 0
        x[93]=127 if sparse else 0;x[94]=root*11;x[95]=0
        target=[1 if active_bass else 0,-1,-1,-1]
        if attacks and (not sparse or step%4==0):
            a,b,p,v=min(attacks,key=lambda n:n[2])
            p=36+p%12+(12 if p%12<root and p>=48 else 0)
            target=[2,min(range(6),key=lambda d:abs(action_note(d,root,minor)-p)),
                    int(np.argmin(np.abs(np.log2(np.maximum(GATES,1))-np.log2(max(1,(b-a)/unit))))),
                    int(np.argmin(np.abs(DYNAMICS-v)))]
        xs.append(x);ys.append(target);metadata.append((t,root,minor,step))
        prev_root=root;prev_minor=minor;hist=[h//2 for h in hist]
    return xs,ys,metadata

def build(folder):
    sets={'train':([],[]),'validation':([],[]),'test':([],[])};songs={k:[] for k in sets}
    for song in sorted(folder.glob('[0-9][0-9][0-9]')):
        idx=int(song.name);split='test' if idx%6==0 else 'validation' if idx%6==5 else 'train';valid=False
        for sparse in (False,True):
            x,y,_=sequence(song,sparse);valid=valid or bool(x)
            sets[split][0].extend(x);sets[split][1].extend(y)
        if valid:songs[split].append(song.name)
    return {k:(np.array(x,dtype=np.uint8),np.array(y,dtype=np.int64)) for k,(x,y) in sets.items()},songs
