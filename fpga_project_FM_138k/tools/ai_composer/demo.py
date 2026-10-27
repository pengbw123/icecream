"""Auditions from actual lead RTL; no independent software policy substitute."""
import csv
from pathlib import Path
import mido
ROOT=Path(__file__).resolve().parents[2]

def main():
    rows=list(csv.DictReader(open(str(ROOT/'tmp/ai_composer_events.csv'))))
    dest=ROOT/'assets/ai/composer';dest.mkdir(parents=True,exist_ok=True)
    for case,name in enumerate(['01_sparse','02_dense','03_rising']):
        events=[r for r in rows if int(r['case'])==case];base=min(int(r['cycle']) for r in events)
        mf=mido.MidiFile(ticks_per_beat=480);tr=mido.MidiTrack();mf.tracks.append(tr)
        tr.append(mido.MetaMessage('track_name',name='RTL '+name));tr.append(mido.MetaMessage('set_tempo',tempo=500000))
        tr.append(mido.Message('program_change',program=4,channel=0));previous=0
        for r in events:
            # Restore the deliberate 16th-note grid. Scaling every simulated
            # clock would incorrectly magnify the 318us NN delay to ~50ms.
            tick=round((int(r['cycle'])-base)/40000)*120
            tr.append(mido.Message('note_on' if int(r['status'],16)==0x90 else 'note_off',channel=0,note=int(r['note']),velocity=int(r['velocity']),time=tick-previous));previous=tick
        mf.save(str(dest/(name+'.mid')))
    (dest/'README.md').write_text('# Interactive lead RTL auditions\n\nOriginal C-E-G-E seed, actual trained RTL note choices and velocities, 120 BPM.\nSparse, dense, then rising control. Restore the 16th grid; do not magnify accelerated-test inference latency.\nGeneral MIDI EP playback is not FPGA timbre.\nReproduce: tb_ai_melody_composer then tools/ai_composer/demo.py.\n')
    print('Exported three actual RTL lead auditions to',dest)
if __name__=='__main__':main()
