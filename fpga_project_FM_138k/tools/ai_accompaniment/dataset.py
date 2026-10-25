"""POP909 adapter: derive constrained monophonic bass from PIANO accompaniment.
Melody features are causal, labels may use accompaniment at the target step.
The extracted bass is a simplification, not a separately annotated bass track.
"""
import bisect
import re
from pathlib import Path
import mido
import numpy as np
from model import features,action_note

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
    melody=tracks.get('MELODY',[]);piano=tracks.get('PIANO',[])
    beats=np.loadtxt(str(folder/'beat_midi.txt'),ndmin=2)[:,0]
    if len(beats)<8 or not melody or not piano:return [],[],[]
    chords=[]
    for line in (folder/'chord_midi.txt').read_text().splitlines():
        a,b,c=line.split();chords.append((float(a),float(b),chord(c)))
    # Only 4/4 excerpts: downbeats in the third beat annotation column.
    beatinfo=np.loadtxt(str(folder/'beat_midi.txt'),ndmin=2)
    downs=np.flatnonzero(beatinfo[:,2]>.5)
    if len(downs)>1 and np.median(np.diff(downs))!=4:return [],[],[]
    anchor=int(downs[0]) if len(downs) else 0
    times=[]
    for j in range(anchor,len(beats)-1):
        times.extend(beats[j]+(beats[j+1]-beats[j])*k/4 for k in range(4))
    hist=[0]*12;history=[0]*4;velocity=0;last_pc=0;silence=16;previous=0;prev_root=-1
    mi=0;ci=0;pi=0;held=[];active_bass=[];xs=[];ys=[];metadata=[]
    for step,t in enumerate(times):
        onset=0
        while mi<len(melody) and melody[mi][0]<=t+1e-7:
            a,b,p,v=melody[mi];mi+=1;onset+=1;hist[p%12]=min(127,hist[p%12]+48)
            velocity=v;last_pc=p%12;held.append((b,p))
        held=[n for n in held if n[0]>t];history=[onset]+history[:3]
        silence=0 if onset else min(16,silence+1)
        while ci+1<len(chords) and chords[ci][1]<=t:ci+=1
        ch=chords[ci][2] if chords[ci][0]<=t<chords[ci][1] else None
        next_t=times[step+1] if step+1<len(times) else t+.125
        attacks=[]
        while pi<len(piano) and piano[pi][0]<t+(next_t-t)*.5:
            a,b,p,v=piano[pi];pi+=1;active_bass.append((b,p))
            if a>=t-(next_t-t)*.5:attacks.append((b,p))
        active_bass=[n for n in active_bass if n[0]>t]
        if ch is None:
            hist=[h//2 for h in hist];previous=0;continue
        root,minor=ch
        x=features(step,hist,history,len(held),velocity,minor,previous,sparse,root!=prev_root,silence,last_pc,root)
        y=1 if active_bass else 0
        if attacks and (not sparse or step%4==0):
            p=min(n[1] for n in attacks)
            if not active_bass or p<=min(n[1] for n in active_bass)+2:
                # Fold into a bass register, preserving pitch-class and contour.
                p=36+p%12+(12 if p%12<root and p>=48 else 0)
                y=min(range(2,8),key=lambda a:abs(action_note(a,root,minor)-p))
        if sparse and step%4!=0:y=1 if active_bass else 0
        xs.append(x);ys.append(y);metadata.append((t,root,minor,step))
        previous=int(rollout(x)) if rollout else y
        prev_root=root;hist=[h//2 for h in hist]
    return xs,ys,metadata

def build(folder):
    sets={'train':([],[]),'validation':([],[]),'test':([],[])};songs={k:[] for k in sets}
    for song in sorted(folder.glob('[0-9][0-9][0-9]')):
        idx=int(song.name);split='test' if idx%6==0 else 'validation' if idx%6==5 else 'train'
        for sparse in (False,True):
            x,y,_=sequence(song,sparse)
            sets[split][0].extend(x);sets[split][1].extend(y)
        if x:songs[split].append(song.name)
    return {k:(np.array(x,dtype=np.uint8),np.array(y,dtype=np.int64)) for k,(x,y) in sets.items()},songs
