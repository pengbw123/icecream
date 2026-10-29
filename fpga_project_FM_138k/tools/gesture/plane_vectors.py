"""Generate deterministic independent Python oracles for plane RTL tests."""
import argparse
from pathlib import Path
import numpy as np
from model import rgb332_features, shape_energy, shape_reason, integer_forward, read_export

ROOT=Path(__file__).resolve().parents[2]

def main():
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=ROOT/'tmp/plane_vectors');a=p.parse_args()
    packed=np.array([int(s,16) for s in (ROOT/'src/generated/gesture/test_rgb332.mem').read_text().split()]).reshape(-1,256)
    rgb=np.stack([(packed>>5)*255//7,((packed>>2)&7)*255//7,(packed&3)*255//3],axis=-1)
    frames=[rgb,(rgb*.7).astype(int),(rgb*np.tile(np.linspace(.65,1,16),16)[None,:,None]).astype(int)]
    rng=np.random.default_rng(29102026)
    frames.append(rng.integers(0,256,(128,256,3)))
    frames.append(np.broadcast_to(np.arange(256)[:,None,None],(256,256,3)))
    samples=np.concatenate(frames).astype(np.uint8)
    # Explicit shape-filter probes; keep original public samples unchanged.
    checker=np.full((16,16,3),255,dtype=np.uint8)
    for y in range(2,14):
        for x in range(2,14):
            if (x+y)%2:checker[y,x]=0
    samples[1116]=checker.reshape(256,3)
    border=np.full((16,16,3),255,dtype=np.uint8)
    border[0,2:14]=0;border[15,2:14]=0;border[2:14,0]=0
    samples[1117]=border.reshape(256,3)
    fill=np.zeros((16,16,3),dtype=np.uint8)
    for yy,xx in [(slice(0,2),slice(0,2)),(slice(0,2),slice(14,16)),(slice(14,16),slice(0,2)),(slice(14,16),slice(14,16))]:fill[yy,xx]=255
    samples[1118]=fill.reshape(256,3)
    raw=rgb332_features(samples,'gray');features=rgb332_features(samples,'plane')
    energy=shape_energy(features)
    assert shape_reason(features)[1116:1119].tolist()==[4,3,2]
    w,b=read_export(ROOT/'src/generated/gesture_plane');scores=integer_forward(features,w,b)
    a.out.mkdir(parents=True,exist_ok=True)
    packed=((samples[:,:,0]>>5)<<5)|((samples[:,:,1]>>5)<<2)|(samples[:,:,2]>>6)
    for name,data,width in [('reason',shape_reason(features),1),('packed',packed,2),('raw',raw,2),('features',features,2),('energy',energy,4),('scores',scores,8)]:
        (a.out/(name+'.mem')).write_text(''.join(f'{int(x)&0xffffffff:0{width}x}\n' for x in data.flat))
    (a.out/'count.txt').write_text(str(len(samples)))
    (a.out/'controller_scores.mem').write_text(''.join(f'{int(x)&0xffffffff:08x}\n' for x in scores[:372].flat))
    print('plane oracle frames:',len(samples))

if __name__=='__main__':main()
