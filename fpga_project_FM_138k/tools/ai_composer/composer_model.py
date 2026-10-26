"""Small causal melody policy; all inference arithmetic is reproduced in RTL."""
import numpy as np
INPUTS,HIDDEN,OUTPUTS=128,48,36
HEADS=[(0,3),(3,28),(28,32),(32,36)]
GATES=np.array([1,2,4,8],dtype=np.int32)
DYNAMICS=np.array([48,72,96,120],dtype=np.int32)
# These first-stage controls are enforced by the scheduler, not learned from
# unobserved examples. Do not expose random initialization to live gestures.
RESERVED_ZERO=list(range(76,84))+[123,124]

def neutralize_controls(q):
    w1,b1,w2,b2=[a.copy() for a in q]
    b1+=w1[102].astype(np.int32)*64
    w1[102]=0;w1[RESERVED_ZERO]=0
    return w1,b1,w2,b2

def quantize(w1,b1,w2,b2):
    return neutralize_controls((np.clip(np.rint(w1*32),-127,127).astype(np.int8),np.rint(b1*4096).astype(np.int32),
            np.clip(np.rint(w2*32),-127,127).astype(np.int8),np.rint(b2*4096).astype(np.int32)))

def fixed(x,q):
    w1,b1,w2,b2=q
    h=np.clip((np.asarray(x,dtype=np.int32)@w1.astype(np.int32)+b1)>>5,0,127)
    scores=h@w2.astype(np.int32)+b2
    return np.stack([np.argmax(scores[...,a:b],axis=-1) for a,b in HEADS],axis=-1),scores

def export(q,dst):
    dst.mkdir(parents=True,exist_ok=True);w1,b1,w2,b2=q
    w=np.concatenate([w1.T.reshape(-1),w2.T.reshape(-1)]);b=np.concatenate([b1,b2])
    (dst/'weights.mem').write_text(''.join('%02x\n'%(int(v)&255) for v in w))
    (dst/'biases.mem').write_text(''.join('%08x\n'%(int(v)&0xffffffff) for v in b))

def scale_note(note,key,minor,penta=False):
    # Nearest in-scale note, lower note wins ties. Runtime has the same LUT.
    allowed=([0,3,5,7,10] if minor else [0,2,4,7,9]) if penta else ([0,2,3,5,7,8,10] if minor else [0,2,4,5,7,9,11])
    note=max(48,min(84,int(note)))
    return min((n for n in range(48,85) if (n-key)%12 in allowed),key=lambda n:(abs(n-note),n))

def features(step,hp,ha,seed,rhythm,key,minor,form,density,direction,variation,last,repeat,contrast=0,rhythm_valid=0,velocity=96):
    x=np.zeros(INPUTS,dtype=np.uint8);x[step&15]=127;x[16+(step>>4)]=127
    x[20:36]=(hp+[0]*32)[:16];x[36:52]=[127 if a==2 else 0 for a in (ha+[0]*16)[:16]]
    x[52:68]=[a*63 for a in (ha+[0]*16)[:16]]
    x[68:68+len(seed[:8])]=seed[:8]
    x[76:84]=[127 if (rhythm>>((step+i)&31))&1 else 0 for i in range(8)]
    x[84+key]=127;x[96]=127 if minor else 0;x[97+form]=127
    x[100:106]=[density,direction,variation,min(127,len(seed)*16),last,min(127,repeat*32)]
    x[106:122]=(hp+[0]*32)[16:32]
    x[122:128]=[127 if step>=60 else 0,127 if contrast else 0,127 if rhythm_valid else 0,velocity,step*2,127]
    return x
