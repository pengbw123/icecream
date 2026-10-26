"""Untrained first-stage controls must not inject arbitrary logit changes."""
from pathlib import Path
import numpy as np
from composer_model import INPUTS,HIDDEN,OUTPUTS,RESERVED_ZERO,fixed
ROOT=Path(__file__).resolve().parents[2]

def load(folder):
    w=np.array([int(v,16) for v in (folder/'weights.mem').read_text().split()],dtype=np.uint8).view(np.int8)
    b=np.array([int(v,16) for v in (folder/'biases.mem').read_text().split()],dtype=np.uint32).view(np.int32)
    assert len(w)==INPUTS*HIDDEN+HIDDEN*OUTPUTS and len(b)==HIDDEN+OUTPUTS
    return w[:INPUTS*HIDDEN].reshape(HIDDEN,INPUTS).T,b[:HIDDEN],w[INPUTS*HIDDEN:].reshape(OUTPUTS,HIDDEN).T,b[HIDDEN:]

def main():
    d=ROOT/'src/generated/ai_composer';q=load(d);assert not q[0][RESERVED_ZERO+[102]].any()
    x=np.array([int(v,16) for v in (d/'test_features.mem').read_text().split()],dtype=np.uint8).reshape(-1,INPUTS)
    expected=fixed(x,q)[1];rng=np.random.RandomState(317)
    for _ in range(8):
        y=x.copy();y[:,RESERVED_ZERO+[102]]=rng.randint(0,128,(len(x),len(RESERVED_ZERO)+1))
        assert np.array_equal(fixed(y,q)[1],expected),'Untrained controls changed logits'
    print('PASS export control invariance: 162 vectors x 8 perturbations; scheduler-only controls cannot inject random weights')
if __name__=='__main__':main()
