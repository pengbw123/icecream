"""Train causal 96->32->17 four-head INT8 bass model, no teacher-forced AI history."""
import os
os.environ.setdefault('OPENBLAS_NUM_THREADS','1')
import argparse,json,hashlib
from pathlib import Path
import numpy as np
from model import INPUTS,HIDDEN,OUTPUTS,HEADS,quantize,fixed,export
from dataset import build
ROOT=Path(__file__).resolve().parents[2]

def metrics(x,y,q):
    p,_=fixed(x,q);out={}
    for h,name in enumerate(['articulation','pitch','gate','dynamics']):
        valid=y[:,h]>=0;a=y[valid,h];b=p[valid,h];n=HEADS[h][1]-HEADS[h][0]
        out[name]={'samples':int(valid.sum()),'accuracy':float(np.mean(a==b)),
          'confusion':np.bincount(a*n+b,minlength=n*n).reshape(n,n).tolist()}
    tp=np.sum((p[:,0]==2)&(y[:,0]==2));pp=np.sum(p[:,0]==2);gt=np.sum(y[:,0]==2)
    out['attack_precision']=float(tp/max(1,pp));out['attack_recall']=float(tp/max(1,gt))
    out['attack_f1']=float(2*tp/max(1,pp+gt))
    out['predicted_articulation_counts']=np.bincount(p[:,0],minlength=3).tolist()
    return out

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--epochs',type=int,default=45);args=ap.parse_args()
    data,songs=build(ROOT/'tmp/ai_pop909/POP909')
    for k,(x,y) in data.items():print(k,x.shape,'articulation',np.bincount(y[:,0],minlength=3).tolist(),flush=True)
    rng=np.random.RandomState(139);params=[rng.normal(0,.10,(INPUTS,HIDDEN)),np.zeros(HIDDEN),rng.normal(0,.12,(HIDDEN,OUTPUTS)),np.zeros(OUTPUTS)]
    mom=[np.zeros_like(v) for v in params];var=[v.copy() for v in mom];iteration=0;best=-1;bestparams=None
    tx,ty=data['train'];tx=tx.astype(np.float64)/128
    counts=np.bincount(ty[:,0],minlength=3);weights=np.clip(len(ty)/(3*np.maximum(counts,1)),.4,5)
    for epoch in range(args.epochs):
        order=rng.permutation(len(ty));loss=0
        for start in range(0,len(order),512):
            ix=order[start:start+512];x=tx[ix];y=ty[ix];w1,b1,w2,b2=params
            z=x@w1+b1;hidden=np.clip(z,0,127/128);logits=hidden@w2+b2;deriv=np.zeros_like(logits)
            for head,(a,b) in enumerate(HEADS):
                valid=y[:,head]>=0
                if not valid.any():continue
                yy=y[valid,head];v=logits[valid,a:b];v-=v.max(axis=1,keepdims=True)
                prob=np.exp(v);prob/=prob.sum(axis=1,keepdims=True)
                loss-=np.log(np.maximum(prob[np.arange(len(yy)),yy],1e-12)).sum()
                prob[np.arange(len(yy)),yy]-=1
                prob*=((weights[yy] if head==0 else np.ones(len(yy)))*[1,.8,.4,.4][head]/len(yy))[:,None]
                deriv[np.flatnonzero(valid),a:b]=prob
            dh=(deriv@w2.T)*((z>0)&(z<127/128))
            grads=[x.T@dh,dh.sum(axis=0),hidden.T@deriv,deriv.sum(axis=0)]
            iteration+=1
            for i,(p,g) in enumerate(zip(params,grads)):
                mom[i]*=.9;mom[i]+=.1*g;var[i]*=.999;var[i]+=.001*g*g
                p-=.002*(mom[i]/(1-.9**iteration))/(np.sqrt(var[i]/(1-.999**iteration))+1e-8)
                if i in (0,2):np.clip(p,-3.9,3.9,out=p)
        vx,vy=data['validation'];m=metrics(vx,vy,quantize(*params))
        score=.6*m['attack_f1']+.2*m['pitch']['accuracy']+.1*m['gate']['accuracy']+.1*m['dynamics']['accuracy']
        if score>best:best=score;bestparams=[p.copy() for p in params]
        if epoch%5==0 or epoch+1==args.epochs:print('epoch',epoch+1,'loss',round(loss/len(ty),4),'validation',json.dumps(m),flush=True)
    q=quantize(*bestparams);dst=ROOT/'src/generated/ai_bass';export(q,dst)
    manifest=(ROOT/'tmp/ai_pop909/manifest.json').read_bytes()
    (ROOT/'assets/ai/POP909_subset_manifest.json').write_bytes(manifest)
    report={'version':2,'architecture':[INPUTS,HIDDEN,OUTPUTS],'heads':['articulation 3','pitch 6','gate 4','dynamics 4'],
       'weight_count':3616,'bias_count':49,'seed':139,'epochs':args.epochs,'songs':songs,
       'features':'one-bar onset history, last 8 ordered pitches, durations, IOIs, velocities, held pitch classes, known harmony. No previous AI action feature.',
       'labels':'POP909 PIANO <= MIDI60 derived low-register proxy, reduced to six harmonic degrees; duration and velocity from corresponding note.',
       'limitations':'Prototype. Performance quality and closed-loop paired responsiveness must be evaluated separately; not a true annotated bass dataset.',
       'dataset_manifest_sha256':hashlib.sha256(manifest).hexdigest()}
    for split,(x,y) in data.items():report[split]=metrics(x,y,q)
    (dst/'training_report.json').write_text(json.dumps(report,indent=2))
    tests=np.concatenate([data['test'][0][:128],rng.randint(0,128,(32,INPUTS)).astype(np.uint8),np.zeros((1,INPUTS),dtype=np.uint8),np.full((1,INPUTS),127,dtype=np.uint8)])
    p,scores=fixed(tests,q);packed=p[:,0]|(p[:,1]<<2)|(p[:,2]<<5)|(p[:,3]<<7)
    action=np.where(p[:,0]==2,p[:,1]+2,p[:,0])
    (dst/'test_features.mem').write_text(''.join('%02x\n'%int(v) for v in tests.reshape(-1)))
    (dst/'test_policy.mem').write_text(''.join('%03x\n'%int(v) for v in packed))
    (dst/'test_actions.mem').write_text(''.join('%01x\n'%int(v) for v in action))
    (dst/'test_scores.mem').write_text(''.join('%08x\n'%(int(v)&0xffffffff) for v in scores.reshape(-1)))
    print(json.dumps(report,indent=2),flush=True)
if __name__=='__main__':main()
