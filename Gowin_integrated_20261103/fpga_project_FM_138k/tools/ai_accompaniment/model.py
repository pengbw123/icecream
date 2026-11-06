"""Interactive bass V2: causal player history, four independent output heads."""
import numpy as np
INPUTS,HIDDEN,OUTPUTS=96,32,17
HEADS=[(0,3),(3,9),(9,13),(13,17)]
ACTIONS=['REST','HOLD','ROOT','THIRD','FIFTH','OCTAVE','LOW_FIFTH','APPROACH']
GATES=np.array([4,8,24,64],dtype=np.int32) # eighths of a sixteenth note
DYNAMICS=np.array([40,64,88,112],dtype=np.int32)

def quantize(w1,b1,w2,b2):
    q=lambda w:np.clip(np.rint(w*32),-127,127).astype(np.int8)
    b=lambda v:np.rint(v*4096).astype(np.int32)
    return q(w1),b(b1),q(w2),b(b2)

def fixed(x,params):
    w1,b1,w2,b2=params
    h=np.clip((np.asarray(x,dtype=np.int32)@w1.astype(np.int32)+b1)>>5,0,127)
    scores=h@w2.astype(np.int32)+b2
    policy=np.stack([np.argmax(scores[...,a:b],axis=-1) for a,b in HEADS],axis=-1)
    return policy,scores

def action_note(degree,root,minor):
    return 36+root+[0,3 if minor else 4,7,12,-5,-1][int(degree)]

def export(params,folder):
    folder.mkdir(parents=True,exist_ok=True)
    w1,b1,w2,b2=params
    weights=np.concatenate([w1.T.reshape(-1),w2.T.reshape(-1)])
    biases=np.concatenate([b1,b2])
    (folder/'ai_bass_weights.mem').write_text(''.join('%02x\n'%(int(v)&255) for v in weights))
    (folder/'ai_bass_biases.mem').write_text(''.join('%08x\n'%(int(v)&0xffffffff) for v in biases))

def load(folder):
    w=np.array([int(v,16) for v in (folder/'ai_bass_weights.mem').read_text().split()],dtype=np.uint8).view(np.int8)
    b=np.array([int(v,16) for v in (folder/'ai_bass_biases.mem').read_text().split()],dtype=np.uint32).view(np.int32)
    assert len(w)==INPUTS*HIDDEN+HIDDEN*OUTPUTS
    return w[:INPUTS*HIDDEN].reshape(HIDDEN,INPUTS).T,b[:HIDDEN],w[INPUTS*HIDDEN:].reshape(OUTPUTS,HIDDEN).T,b[HIDDEN:]
