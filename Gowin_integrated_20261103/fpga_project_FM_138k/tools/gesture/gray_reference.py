"""RGB565 -> 8-bit gray, hardware cell-center oracle; no trained classifier."""
import argparse
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[2]

def rgb565_gray(pixels):
    p=np.asarray(pixels,dtype=np.uint32)
    r=(p>>11)&31;g=(p>>5)&63;b=p&31
    r=(r<<3)|(r>>2);g=(g<<2)|(g>>4);b=(b<<3)|(b>>2)
    return ((r+2*g+b+2)>>2).astype(np.uint8)

def frame_features(rgb565):
    p=np.asarray(rgb565)
    if p.shape!=(120,160):raise ValueError('requires exactly 160x120 RGB565')
    return rgb565_gray(p[13:107:3,33:127:3])

def rgb888_to_rgb565(rgb):
    p=np.asarray(rgb,dtype=np.uint16)
    if p.shape[-1]!=3:raise ValueError('RGB image must have three channels')
    return ((p[...,0]>>3)<<11)|((p[...,1]>>2)<<5)|(p[...,2]>>3)

def roi_image_features(image):
    """Training adapter: a PRE-CROPPED square ROI, not arbitrary hand detection.

    The caller must use the same ROI framing as the board. Resize is a dataset
    adapter; hardware receives a 96x96 ROI and does not do this resize itself.
    """
    from PIL import Image
    if image.width!=image.height:raise ValueError('requires pre-cropped square ROI')
    roi=np.asarray(image.convert('RGB').resize((96,96),Image.Resampling.BOX))
    packed=rgb888_to_rgb565(roi)
    return rgb565_gray(packed[1:96:3,1:96:3])

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path,default=ROOT/'tmp/gray_vectors')
    args=parser.parse_args();args.out.mkdir(parents=True,exist_ok=True)
    # Exhaustive RGB565 gray lookup used by RTL test; independent integer code.
    gray=rgb565_gray(np.arange(65536))
    assert gray[0]==0 and gray[-1]==255
    (args.out/'gray.mem').write_text(''.join(f'{int(v):02x}\n' for v in gray))
    # Exposure remains graded: no binary hand/background threshold.
    for v in (0,32,64,128,192,255):
        packed=((v>>3)<<11)|((v>>2)<<5)|(v>>3)
        assert abs(int(gray[packed])-v)<=7
    p=np.arange(19200,dtype=np.uint32).reshape(120,160)
    assert frame_features(p).shape==(32,32)
    print('PASS gray reference: exhaustive 65536 RGB565 levels, endpoints, 32x32 coordinates and graded brightness')

if __name__=='__main__':main()
