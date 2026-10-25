"""Hardware contract for causal 48 -> 32 clipped-ReLU -> 8 bass actions.
Features/hidden: unsigned Q0.7; weights: signed Q2.5; biases/logits: Q*.12.
No floating-point or softmax is needed in the FPGA inference path.
"""
import numpy as np

INPUTS,HIDDEN,OUTPUTS=48,32,8
ACTIONS=['REST','HOLD','ROOT','THIRD','FIFTH','OCTAVE','LOW_FIFTH','APPROACH']

def features(phase,hist,onsets,held,velocity,minor,previous,sparse,changed,silence,last_pc,root):
    x=np.zeros(INPUTS,dtype=np.uint8)
    x[phase&15]=127
    for p in range(12):x[16+p]=hist[(p+root)%12]
    x[28:32]=[min(127,int(v)*24) for v in onsets]
    x[32]=min(127,held*16);x[33]=velocity
    x[34]=min(127,sum(onsets)*12);x[35]=127 if minor else 0
    x[36+previous]=127;x[44]=0 if sparse else 127
    x[45]=127 if changed else 0;x[46]=min(127,silence*8)
    x[47]=((last_pc-root)%12)*11
    return x

def quantize(w1,b1,w2,b2):
    q=lambda w:np.clip(np.rint(w*32),-127,127).astype(np.int8)
    b=lambda v:np.rint(v*4096).astype(np.int32)
    return q(w1),b(b1),q(w2),b(b2)

def fixed(x,params):
    w1,b1,w2,b2=params
    h=np.clip((np.asarray(x,dtype=np.int32)@w1.astype(np.int32)+b1)>>5,0,127)
    scores=h@w2.astype(np.int32)+b2
    return np.argmax(scores,axis=-1),scores

def action_note(action,root,minor):
    return 36+root+[0,0,0,3 if minor else 4,7,12,-5,-1][int(action)]

def decode(action,phase,sparse,root,minor,active_note,changed):
    action=int(action)
    if sparse and phase%4 and action>=2:action=1
    if action==1 and changed and active_note is not None:
        if (active_note-root)%12 not in (0,3 if minor else 4,7):action=2
    return action

def export(params,folder):
    folder.mkdir(parents=True,exist_ok=True)
    w1,b1,w2,b2=params
    # Neuron-major, contiguous inputs per neuron, matching serial MAC RTL.
    weights=np.concatenate([w1.T.reshape(-1),w2.T.reshape(-1)])
    biases=np.concatenate([b1,b2])
    (folder/'ai_bass_weights.mem').write_text(''.join('%02x\n'%(int(v)&255) for v in weights))
    (folder/'ai_bass_biases.mem').write_text(''.join('%08x\n'%(int(v)&0xffffffff) for v in biases))

def load(folder):
    w=np.array([int(v,16) for v in (folder/'ai_bass_weights.mem').read_text().split()],dtype=np.uint8).view(np.int8)
    b=np.array([int(v,16) for v in (folder/'ai_bass_biases.mem').read_text().split()],dtype=np.uint32).view(np.int32)
    return w[:1536].reshape(32,48).T,b[:32],w[1536:].reshape(8,32).T,b[32:]
