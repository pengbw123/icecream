"""Reproducible NumPy training; no GPU/PyTorch requirement, true held-song split."""
import os
os.environ.setdefault('OPENBLAS_NUM_THREADS','1')
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from model import INPUTS,HIDDEN,OUTPUTS,quantize,fixed,export
from dataset import build

ROOT=Path(__file__).resolve().parents[2]

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--epochs',type=int,default=45);args=ap.parse_args()
    data,songs=build(ROOT/'tmp/ai_pop909/POP909')
    assert all(len(y)>0 for x,y in data.values()),'Need nonempty song-disjoint train/validation/test subsets'
    for k,(x,y) in data.items():print(k,x.shape,np.bincount(y,minlength=8).tolist(),flush=True)
    rng=np.random.RandomState(138);w1=rng.normal(0,.15,(INPUTS,HIDDEN));b1=np.zeros(HIDDEN)
    w2=rng.normal(0,.15,(HIDDEN,OUTPUTS));b2=np.zeros(OUTPUTS)
    params=[w1,b1,w2,b2];mom=[np.zeros_like(v) for v in params];var=[v.copy() for v in mom];iteration=0
    tx,ty=data['train'];tx=tx.astype(np.float64)/128
    counts=np.bincount(ty,minlength=8);class_weight=1/np.sqrt(np.maximum(counts,1));class_weight/=class_weight.mean()
    best=-1;bestparams=None
    for epoch in range(args.epochs):
        order=rng.permutation(len(ty));loss=0
        for start in range(0,len(order),512):
            ix=order[start:start+512];x=tx[ix];y=ty[ix];z=x@w1+b1;h=np.clip(z,0,127/128)
            logits=h@w2+b2;logits-=logits.max(axis=1,keepdims=True)
            prob=np.exp(logits);prob/=prob.sum(axis=1,keepdims=True)
            loss-=np.sum(np.log(np.maximum(prob[np.arange(len(y)),y],1e-12)))
            prob[np.arange(len(y)),y]-=1;prob*=class_weight[y,None]/len(y)
            dh=(prob@w2.T)*((z>0)&(z<127/128))
            grads=[x.T@dh,dh.sum(axis=0),h.T@prob,prob.sum(axis=0)]
            iteration+=1
            for i,(p,g) in enumerate(zip(params,grads)):
                mom[i]*=.9;mom[i]+=.1*g;var[i]*=.999;var[i]+=.001*g*g
                p-=.003*(mom[i]/(1-.9**iteration))/(np.sqrt(var[i]/(1-.999**iteration))+1e-8)
                if i in (0,2):np.clip(p,-3.9,3.9,out=p)
        vx,vy=data['validation'];pred,_=fixed(vx,quantize(*params))
        recall=np.mean([np.mean(pred[vy==c]==c) for c in np.unique(vy)])
        if recall>best:best=recall;bestparams=[p.copy() for p in params]
        if epoch%5==0 or epoch+1==args.epochs:print('epoch %d loss %.4f validation balanced recall %.4f'%(epoch+1,loss/len(ty),recall),flush=True)
    q=quantize(*bestparams);dst=ROOT/'src/generated/ai_bass';export(q,dst)
    report={'architecture':[48,32,8],'weight_count':1792,'bias_count':40,'weight_format':'signed INT8 Q2.5',
            'seed':138,'epochs':args.epochs,'songs':songs,'labels':'lowest-note reduction of POP909 PIANO, constrained to bass action vocabulary',
            'limitations':'Prototype trained on a small pop subset; not a general musician or proof of subjective musical quality.',
            'dataset_manifest_path':'assets/ai/POP909_subset_manifest.json',
            'dataset_manifest_sha256':hashlib.sha256((ROOT/'tmp/ai_pop909/manifest.json').read_bytes()).hexdigest()}
    for split,(x,y) in data.items():
        pred,_=fixed(x,q);report[split]={'samples':len(y),'accuracy':float(np.mean(pred==y)),
          'majority_accuracy':float(np.bincount(y,minlength=8).max()/len(y)),
          'balanced_recall':float(np.mean([np.mean(pred[y==c]==c) for c in np.unique(y)])),
          'confusion':np.bincount(y*8+pred,minlength=64).reshape(8,8).tolist()}
    (dst/'training_report.json').write_text(json.dumps(report,indent=2))
    # Fixed reference vectors include unseen songs and numeric extremes.
    tests=np.concatenate([data['test'][0][:128],rng.randint(0,128,(32,48)).astype(np.uint8),np.zeros((1,48),dtype=np.uint8),np.full((1,48),127,dtype=np.uint8)])
    pred,scores=fixed(tests,q)
    (dst/'test_features.mem').write_text(''.join('%02x\n'%int(v) for v in tests.reshape(-1)))
    (dst/'test_actions.mem').write_text(''.join('%01x\n'%int(v) for v in pred))
    (dst/'test_scores.mem').write_text(''.join('%08x\n'%(int(v)&0xffffffff) for v in scores.reshape(-1)))
    print(json.dumps({k:report[k] for k in ['train','validation','test']},indent=2),flush=True)

if __name__=='__main__':main()
