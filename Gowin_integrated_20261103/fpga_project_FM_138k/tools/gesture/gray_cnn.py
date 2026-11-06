"""Small stride-2 CNN, hardware-exact INT8 reference. No binary segmentation.

32x32 u8 -> valid3x3/stride2 conv4 -> clipReLU -> 3x3 maxpool ->
5x5x4 (channel-major) -> four signed logits. Fourth label is synthetic other.
"""
import numpy as np

def patches(x):
    x=np.asarray(x).reshape(-1,32,32)
    return np.stack([x[:,dy:dy+30:2,dx:dx+30:2] for dy in range(3) for dx in range(3)],axis=-1)

def integer_forward(x,w,b):
    p=patches(x).astype(np.int64)
    z=np.clip((p@np.asarray(w[:36]).reshape(4,9).T+np.asarray(b[:4]))>>7,0,127)
    # N,Ypool,Yinner,Xpool,Xinner,C -> N,C,Ypool,Xpool
    h=z.reshape(-1,5,3,5,3,4).max(axis=(2,4)).transpose(0,3,1,2).reshape(-1,100)
    return h@np.asarray(w[36:]).reshape(4,100).T+np.asarray(b[4:])

def load(folder):
    w=np.array([int(v,16) for v in (folder/'weights.mem').read_text().split()],dtype=np.int64)
    w=np.where(w>=128,w-256,w)
    b=np.array([int(v,16) for v in (folder/'biases.mem').read_text().split()],dtype=np.int64)
    b=np.where(b>=2**31,b-2**32,b)
    assert len(w)==436 and len(b)==8
    return w,b
