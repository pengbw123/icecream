"""Hardware-exact corner-plane illumination and contrast normalization."""
import numpy as np

def adapt_gray(images):
    a=np.asarray(images,dtype=np.int64);shape=a.shape;a=a.reshape(-1,32,32)
    tl=a[:,:2,:2].max((1,2));tr=a[:,:2,30:].max((1,2))
    bl=a[:,30:,:2].max((1,2));br=a[:,30:,30:].max((1,2))
    y,x=np.mgrid[:32,:32]
    left=(tl[:,None,None]*(32-y)+bl[:,None,None]*y)>>5
    right=(tr[:,None,None]*(32-y)+br[:,None,None]*y)>>5
    background=(left*(32-x)+right*x)>>5
    black=a.min((1,2))[:,None,None]
    span=np.maximum(background-black,32)
    darkness=np.maximum(background-a,0)
    reciprocal=65535//span
    corrected=np.minimum((darkness*reciprocal)>>8,255)
    return (255-corrected).astype(np.uint8).reshape(shape)
