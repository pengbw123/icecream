"""Train on real POP909 MELODY tracks. Given seed is a prompt, not a target label."""
import os
os.environ.setdefault('OPENBLAS_NUM_THREADS','1')
import argparse,json,sys,hashlib
from pathlib import Path
import numpy as np
from composer_model import *
ROOT=Path(__file__).resolve().parents[2]
sys.path.append(str(ROOT/'tools/ai_accompaniment'))
from dataset import notes,chord

def dataset():
    data={k:([],[]) for k in ['train','validation','test']};songs={k:[] for k in data}
    for folder in sorted((ROOT/'tmp/ai_pop909/POP909').glob('[0-9][0-9][0-9]')):
        melody=notes(folder/(folder.name+'.mid')).get('MELODY',[])
        beatinfo=np.loadtxt(str(folder/'beat_midi.txt'),ndmin=2);beats=beatinfo[:,0]
        down=np.flatnonzero(beatinfo[:,2]>.5)
        if not melody or len(down)<2 or np.median(np.diff(down))!=4:continue
        chs=[chord(line.split()[2]) for line in (folder/'chord_midi.txt').read_text().splitlines()]
        ch=next((v for v in chs if v is not None),(0,False));key,minor=ch
        times=np.array([beats[j]+(beats[j+1]-beats[j])*k/4 for j in range(int(down[0]),len(beats)-1) for k in range(4)])
        events={};unit=float(np.median(np.diff(times)))
        for a,b,p,v in melody:
            s=int(np.searchsorted(times,a));s=min(len(times)-1,max(0,s))
            if s and abs(times[s-1]-a)<abs(times[s]-a):s-=1
            length=max(1,int(round((b-a)/unit)))
            if s not in events or p>events[s][0]:events[s]=(p,v,length)
        split='test' if int(folder.name)%6==0 else 'validation' if int(folder.name)%6==5 else 'train'
        used=False
        for base in range(0,len(times)-63,64):
            es=[(s,events[s]) for s in range(base,base+64) if s in events]
            if len(es)<4:continue
            # Conditions measured from the target phrase, supplied as user knobs at runtime.
            density=24 if len(es)<9 else 64 if len(es)<20 else 110
            movement=es[-1][1][0]-es[0][1][0];direction=100 if movement>3 else 28 if movement<-3 else 64
            form=0 if np.median([e[1][2] for e in es])>=3 else 1
            for penta in [False,True]:
                f=2 if penta else form
                seed=[scale_note(e[1][0],key,minor,penta) for e in es[:8]]
                hp=[];ha=[];last=seed[0];repeats=0;held=0;vel=96;gate=0
                for step in range(64):
                    x=features(step,hp,ha,seed,0,key,minor,f,density,direction,64,last,repeats,velocity=vel)
                    y=[1 if held>0 else 0,-1,-1,-1];pitch=last
                    if base+step in events:
                        p,v,length=events[base+step];pitch=scale_note(p,key,minor,penta)
                        y=[2,max(0,min(24,pitch-last+12)),int(np.argmin(abs(np.log2(GATES)-np.log2(length)))),int(np.argmin(abs(DYNAMICS-v)))]
                        held=length;repeats=repeats+1 if pitch==last else 0;last=pitch;vel=v
                    data[split][0].append(x);data[split][1].append(y)
                    hp=[pitch if y[0] else 0]+hp[:31];ha=[y[0]]+ha[:15];held=max(0,held-1)
                used=True
        if used:songs[split].append(folder.name)
    return {k:(np.array(x,dtype=np.uint8),np.array(y,dtype=np.int64)) for k,(x,y) in data.items()},songs

def metrics(x,y,q):
    p,_=fixed(x,q);r={}
    for h,name in enumerate(['articulation','interval','gate','dynamics']):
        mask=y[:,h]>=0;r[name]={'samples':int(mask.sum()),'accuracy':float(np.mean(p[mask,h]==y[mask,h]))}
    tp=np.sum((p[:,0]==2)&(y[:,0]==2));r['attack_f1']=float(2*tp/max(1,np.sum(p[:,0]==2)+np.sum(y[:,0]==2)))
    return r

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--epochs',type=int,default=35);args=ap.parse_args()
    data,songs=dataset()
    for x,y in data.values():
        assert np.all(x[:,RESERVED_ZERO]==0) and np.all(x[:,102]==64), 'Control training changed; revise exact export folding'
    for k,(x,y) in data.items():print(k,x.shape,flush=True)
    rng=np.random.RandomState(720138);params=[rng.normal(0,.09,(INPUTS,HIDDEN)),np.zeros(HIDDEN),rng.normal(0,.10,(HIDDEN,OUTPUTS)),np.zeros(OUTPUTS)]
    mom=[np.zeros_like(v) for v in params];var=[v.copy() for v in mom];iteration=0;best=-1;bestp=None
    tx,ty=data['train'];tx=tx.astype(np.float32)/128
    counts=np.bincount(ty[:,0],minlength=3);balance=np.clip(len(ty)/(3*np.maximum(1,counts)),.4,5)
    for epoch in range(args.epochs):
        order=rng.permutation(len(ty))
        for begin in range(0,len(order),512):
            ix=order[begin:begin+512];x=tx[ix];y=ty[ix];w1,b1,w2,b2=params
            z=x@w1+b1;h=np.clip(z,0,127/128);logits=h@w2+b2;d=np.zeros_like(logits)
            for head,(a,b) in enumerate(HEADS):
                mask=y[:,head]>=0;yy=y[mask,head];v=logits[mask,a:b];v-=v.max(axis=1,keepdims=True)
                p=np.exp(v);p/=p.sum(axis=1,keepdims=True);p[np.arange(len(yy)),yy]-=1
                p*=((balance[yy] if head==0 else np.ones(len(yy)))*[1,1,.35,.25][head]/len(yy))[:,None]
                d[np.flatnonzero(mask),a:b]=p
            dh=(d@w2.T)*((z>0)&(z<127/128));grads=[x.T@dh,dh.sum(axis=0),h.T@d,d.sum(axis=0)];iteration+=1
            for i,(p,g) in enumerate(zip(params,grads)):
                mom[i]=.9*mom[i]+.1*g;var[i]=.999*var[i]+.001*g*g
                p-=.002*(mom[i]/(1-.9**iteration))/(np.sqrt(var[i]/(1-.999**iteration))+1e-8)
                if i in (0,2):np.clip(p,-3.9,3.9,out=p)
        vx,vy=data['validation'];m=metrics(vx,vy,quantize(*params));score=.5*m['attack_f1']+.35*m['interval']['accuracy']+.1*m['gate']['accuracy']+.05*m['dynamics']['accuracy']
        if score>best:best=score;bestp=[p.copy() for p in params]
        if epoch%5==0 or epoch+1==args.epochs:print('epoch',epoch+1,json.dumps(m),flush=True)
    q=quantize(*bestp);dst=ROOT/'src/generated/ai_composer';export(q,dst)
    report={'architecture':[INPUTS,HIDDEN,OUTPUTS],'weights':INPUTS*HIDDEN+HIDDEN*OUTPUTS,'biases':HIDDEN+OUTPUTS,'epochs':args.epochs,'seed':720138,'songs':songs,
        'dataset':'POP909 pinned existing 128-song download, actual MELODY track, song-separated splits',
        'manifest_sha256':hashlib.sha256((ROOT/'assets/ai/POP909_subset_manifest.json').read_bytes()).hexdigest(),
        'conditioning':'given eight-note seed plus density, direction and form; density/direction labels derived from the given phrase',
        'control_export':'Untrained rhythm bits76..83/contrast123/rhythmValid124 weights are zero; constant variation102=64 is folded into biases exactly. These controls act in RTL, not random untrained weights.',
        'limits':'Teacher-forced next-step metrics are not free-running quality. Phrase scheduling, seed repetition, scale and gesture constraints are explicit RTL rules.'}
    for k,(x,y) in data.items():report[k]=metrics(x,y,q)
    (dst/'training_report.json').write_text(json.dumps(report,indent=2))
    tests=np.concatenate([data['test'][0][:128],rng.randint(0,128,(32,INPUTS)).astype(np.uint8),np.zeros((1,INPUTS),dtype=np.uint8),np.full((1,INPUTS),127,dtype=np.uint8)])
    p,s=fixed(tests,q);alt=np.argsort(-s[:,3:28],axis=1,kind='stable')[:,1]
    packed=p[:,0]|(p[:,1]<<2)|(p[:,2]<<7)|(p[:,3]<<9)|(alt<<11)
    for name,values,width in [('test_features',tests.reshape(-1),2),('test_scores',s.reshape(-1),8),('test_policy',packed,4)]:
        (dst/(name+'.mem')).write_text(''.join(('%0'+str(width)+'x\n')%(int(v)&(0xffffffff if width==8 else 65535)) for v in values))
    print(json.dumps(report,indent=2),flush=True)
if __name__=='__main__':main()
