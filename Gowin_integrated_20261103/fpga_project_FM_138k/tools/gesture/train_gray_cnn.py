"""CPU NumPy CNN training. Model selection uses held-out sequences only.
Synthetic other/background probes do not establish real-camera robustness.
"""
import os
os.environ['OPENBLAS_NUM_THREADS']='1'
import argparse,io,json,zipfile,hashlib
from pathlib import Path
import numpy as np
from PIL import Image,ImageEnhance
from gray_reference import roi_image_features
from gray_cnn import patches,integer_forward
from gray_adapt import adapt_gray
ROOT=Path(__file__).resolve().parents[2]

def dataset(archive):
    xs=[];ys=[];names=[]
    with zipfile.ZipFile(ROOT/'tmp/gesture_data'/archive) as z:
        for n in sorted(z.namelist()):
            p=n.split('/')
            if len(p)!=3 or p[1] not in ['rock','paper','scissors'] or not n.endswith('.png'):continue
            with Image.open(io.BytesIO(z.read(n))) as im:xs.append(roi_image_features(im))
            ys.append(['rock','paper','scissors'].index(p[1]));names.append(n)
    return np.asarray(xs),np.asarray(ys),names

def negatives(rng,n):
    yy,xx=np.mgrid[:32,:32];result=[]
    for i in range(n):
        base=rng.uniform(0,255)
        a=np.full((32,32),base)
        if i%5==1:a+=rng.uniform(-100,100)*(xx/31-.5)+rng.uniform(-100,100)*(yy/31-.5)
        if i%5==2:a=rng.uniform(0,255,(32,32))
        if i%5==3:a[((xx-rng.integers(8,24))**2+(yy-rng.integers(8,24))**2)<rng.integers(16,130)]=rng.uniform(0,255)
        if i%5==4:a[(xx//rng.integers(2,8)+yy//rng.integers(2,8))%2==0]=rng.uniform(0,255)
        result.append(np.clip(a,0,255).astype(np.uint8))
    return np.asarray(result)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--epochs',type=int,default=160);ap.add_argument('--out',type=Path,default=ROOT/'src/generated/gesture_gray');args=ap.parse_args()
    rng=np.random.default_rng(3010720)
    x,y,names=dataset('rps.zip');old=json.loads((ROOT/'src/generated/gesture/training_report.json').read_text())
    vi=np.array([i for i,n in enumerate(names) if n.rsplit('/',1)[1].rsplit('-',1)[0] in old['validation_sequences']])
    ti=np.setdiff1d(np.arange(len(x)),vi)
    train=np.concatenate([x[ti],negatives(rng,720)]);labels=np.r_[y[ti],np.full(720,3)]
    val=np.concatenate([x[vi],negatives(np.random.default_rng(310),180)]);vy=np.r_[y[vi],np.full(180,3)]
    params=[rng.normal(0,.18,(9,4)).astype(np.float32),np.zeros(4,np.float32),rng.normal(0,.1,(100,4)).astype(np.float32),np.zeros(4,np.float32)]
    m=[np.zeros_like(a) for a in params];v=[np.zeros_like(a) for a in params];step=0;best=-1;saved=None
    for epoch in range(args.epochs):
        for ids in np.array_split(rng.permutation(len(train)),max(1,len(train)//64)):
            images=train[ids].astype(np.float32)/254
            # Training-only geometry/exposure/contrast/background augmentation.
            yy,xx=np.mgrid[:32,:32];theta=rng.uniform(-.2,.2);scale=rng.uniform(.78,1.12)
            tx,ty=rng.uniform(-2,2,2);u=xx-15.5-tx;vv=yy-15.5-ty
            sx=np.rint((np.cos(theta)*u+np.sin(theta)*vv)/scale+15.5).astype(int)
            sy=np.rint((-np.sin(theta)*u+np.cos(theta)*vv)/scale+15.5).astype(int)
            images=np.where((sx>=0)&(sx<32)&(sy>=0)&(sy<32),images[:,sy.clip(0,31),sx.clip(0,31)],1)
            images=np.clip((images-.5)*rng.uniform(.7,1.2)+.5,0,1)*rng.uniform(.65,1.05)
            images=np.clip(images+np.linspace(*rng.uniform(-.12,.12,2),32)[None,None,:],0,1)
            images=adapt_gray(np.clip(np.rint(images*254),0,255).astype(np.uint8)).astype(np.float32)/254
            p=patches(images);a,b,c,d=params;pre=p@a+b;z=np.clip(pre,0,1)
            blocks=z.reshape(-1,5,3,5,3,4).transpose(0,5,1,3,2,4).reshape(-1,100,9)
            ix=blocks.argmax(2);h=blocks.max(2);scores=h@c+d
            prob=np.exp(scores-scores.max(1,keepdims=True));prob/=prob.sum(1,keepdims=True);prob[np.arange(len(ids)),labels[ids]]-=1;prob/=len(ids)
            dh=prob@c.T;db=np.zeros_like(blocks);np.put_along_axis(db,ix[:,:,None],dh[:,:,None],axis=2)
            dz=db.reshape(-1,4,5,5,3,3).transpose(0,2,4,3,5,1).reshape(-1,15,15,4)
            dz*=((pre>0)&(pre<1))
            grads=[p.reshape(-1,9).T@dz.reshape(-1,4)+a*1e-4,dz.sum((0,1,2)),h.T@prob+c*1e-4,prob.sum(0)]
            step+=1
            for j,g in enumerate(grads):
                m[j]=.9*m[j]+.1*g;v[j]=.999*v[j]+.001*g*g
                params[j]-=.002*(m[j]/(1-.9**step))/(np.sqrt(v[j]/(1-.999**step))+1e-8)
            np.clip(a,-1.98,1.98,out=a);np.clip(c,-1.98,1.98,out=c)
        w=np.clip(np.rint(np.r_[params[0].T.ravel(),params[2].T.ravel()]*64),-127,127).astype(np.int64)
        bias=np.rint(np.r_[params[1]*127*128,params[3]*127*64]).astype(np.int64)
        pred=integer_forward(adapt_gray(val),w,bias).argmax(1);acc=float((pred==vy).mean())
        if acc>best:best=acc;saved=(w.copy(),bias.copy(),epoch+1)
        if epoch%10==0:print('epoch',epoch+1,'validation',acc,'best',best,flush=True)
    w,b,chosen=saved;test,ty,tn=dataset('rps-test-set.zip');test=np.concatenate([test,negatives(np.random.default_rng(999),180)]);ty=np.r_[ty,np.full(180,3)]
    raw_test=test.copy();test=adapt_gray(test);scores=integer_forward(test,w,b);pred=scores.argmax(1);conf=np.zeros((4,4),int);np.add.at(conf,(ty,pred),1)
    out=args.out;out.mkdir(parents=True,exist_ok=True)
    for name,data,width in [('raw_test_features',raw_test,2),('weights',w,2),('biases',b,8),('test_features',test,2),('test_scores',scores,8),('test_labels',ty,2)]:
        (out/(name+'.mem')).write_text(''.join(f'{int(q)&((1<<(width*4))-1):0{width}x}\n' for q in data.flat))
    report=dict(preprocessing='corner-plane max2x2 / min-black / minspan32 / Q16 reciprocal; gray_adapt.py',architecture='32x32 -> 3x3 stride2 conv4 -> clip127 -> maxpool3 -> 100 -> 4',labels=['fist','palm','v_sign','other'],weights=436,biases=8,seed=3010720,epochs=args.epochs,selected_epoch=chosen,validation_accuracy=best,test_accuracy=float((pred==ty).mean()),test_gesture_accuracy=float((pred[:372]==ty[:372]).mean()),synthetic_other_recall=float((pred[372:]==3).mean()),confusion=conf.tolist(),test_count=len(test),train_gestures=len(ti),validation_gestures=len(vi),validation_sequences=old['validation_sequences'],real_camera_accuracy=None,limitations=['CGI gesture domain; no real camera validation','Other class uses synthetic negatives; not arbitrary background detection','Fixed ROI; no hand detector'],archives={n:hashlib.sha256((ROOT/'tmp/gesture_data'/n).read_bytes()).hexdigest() for n in ['rps.zip','rps-test-set.zip']})
    (out/'training_report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2),flush=True)
if __name__=='__main__':main()
