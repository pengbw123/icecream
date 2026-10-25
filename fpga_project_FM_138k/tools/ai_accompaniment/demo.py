"""Export an original, deterministic LIVE+AI MIDI demo using trained weights.
No POP909 note sequence is copied into this demonstration.
"""
import csv
from pathlib import Path
import mido
from model import features,fixed,load,action_note,decode

ROOT=Path(__file__).resolve().parents[2]

def main():
    dst=ROOT/'assets/ai';dst.mkdir(exist_ok=True);params=load(ROOT/'src/generated/ai_bass')
    events=[[],[]];hist=[0]*12;history=[0]*4;velocity=0;silence=16;last_pc=0;previous=0;previous_root=-1
    active_live=None;active_bass=None;rows=[]
    # Alternating busy melody and held notes; all composed by this script.
    motif=[60,64,67,69,67,64,62,60];chords=[(0,False),(9,True),(5,False),(7,False)]
    for step in range(256):
        beat=step%16;bar=step//16;root,minor=chords[bar%4];tick=step*120
        onset=0
        if (bar%2==0 and step%2==0) or (bar%2==1 and beat==0):
            if active_live is not None:events[0].append((tick,mido.Message('note_off',note=active_live,velocity=0,channel=0)))
            active_live=motif[(step//2)%8]+(12 if bar>=8 else 0);velocity=80+(bar%3)*10;last_pc=active_live%12;onset=1
            events[0].append((tick,mido.Message('note_on',note=active_live,velocity=velocity,channel=0)))
            hist[last_pc]=min(127,hist[last_pc]+48)
        history=[onset]+history[:3];silence=0 if onset else min(16,silence+1)
        x=features(beat,hist,history,int(active_live is not None),velocity,minor,previous,False,root!=previous_root,silence,last_pc,root)
        action,_=fixed(x,params);action=decode(action,beat,False,root,minor,active_bass,root!=previous_root)
        if action==0 or action>=2:
            if active_bass is not None:events[1].append((tick,mido.Message('note_off',note=active_bass,velocity=0,channel=1)))
            active_bass=None
        if action>=2:
            active_bass=action_note(action,root,minor)
            events[1].append((tick,mido.Message('note_on',note=active_bass,velocity=70,channel=1)))
        rows.append((step,bar+1,beat,root,int(minor),onset,action,active_bass if active_bass is not None else ''))
        previous=action;previous_root=root;hist=[h//2 for h in hist]
    for channel,note in enumerate([active_live,active_bass]):
        if note is not None:events[channel].append((256*120,mido.Message('note_off',note=note,velocity=0,channel=channel)))
    midi=mido.MidiFile(ticks_per_beat=480)
    for channel in range(2):
        tr=mido.MidiTrack();midi.tracks.append(tr)
        tr.append(mido.MetaMessage('track_name',name='Original LIVE' if channel==0 else 'FPGA INT8 policy bass'))
        if channel==0:tr.append(mido.MetaMessage('set_tempo',tempo=500000))
        tr.append(mido.Message('program_change',program=4 if channel==0 else 33,channel=channel))
        last=0
        for tick,msg in sorted(events[channel],key=lambda pair:pair[0]):tr.append(msg.copy(time=tick-last));last=tick
    midi.save(str(dst/'ai_bass_demo.mid'))
    with (dst/'ai_bass_demo_actions.csv').open('w',newline='') as f:
        w=csv.writer(f);w.writerow(['step','bar','sixteenth','root_pc','minor','live_onset','model_action','bass_note']);w.writerows(rows)
    count=sum(msg.type=='note_on' for t,msg in events[1])
    print('Exported 16 bars, 32 seconds, %d learned bass attacks; GM audition is not the FPGA DX7 timbre'%count)

if __name__=='__main__':main()
