"""Deterministic transformed-public-test probes; not a real-camera benchmark."""
from pathlib import Path
import json
import numpy as np
from gray_cnn import load,integer_forward
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=ROOT/'src/generated/gesture_gray'
 x=np.array([int(v,16) for v in (p/'test_features.mem').read_text().split()],dtype=np.uint8).reshape(-1,32,32)
 y=np.array([int(v,16) for v in (p/'test_labels.mem').read_text().split()])
 w,b=load(p);rng=np.random.default_rng(3010)
 variants={'original':x,'exposure70':(x*.7).astype(np.uint8),
  'exposure50':(x*.5).astype(np.uint8),
  'contrast60':np.clip((x.astype(float)-127)*.6+127,0,255).astype(np.uint8),
  'uneven':(x*np.linspace(.65,1,32)[None,None,:]).astype(np.uint8),
  'noise8':np.clip(x.astype(float)+rng.normal(0,8,x.shape),0,255).astype(np.uint8)}
 shifted=np.full_like(x,255);shifted[:,:,3:]=x[:,:,:-3];variants['shift_right3']=shifted
 result={}
 for name,a in variants.items():
  scores=integer_forward(a,w,b);pred=scores.argmax(1);order=np.sort(scores,axis=1);accepted=(pred<3)&(order[:,-1]-order[:,-2]>=2048)
  result[name]=dict(gesture_samples=372,gesture_raw_correct=int((pred[:372]==y[:372]).sum()),
   gesture_correct_accepted=int(((pred[:372]==y[:372])&accepted[:372]).sum()),
   synthetic_other_samples=180,synthetic_other_false_accept=int(accepted[372:].sum()))
 out=ROOT/'assets/gesture_gray_cnn';out.mkdir(exist_ok=True)
 (out/'stress.json').write_text(json.dumps(dict(note='Synthetic transforms of already-viewed public test set. No threshold tuning or real-world accuracy claim.',results=result),indent=2)+'\n')
 print(json.dumps(result,indent=2))
if __name__=='__main__':main()
