"""Check exported integer CNN and generate RGB565 integration vectors."""
from pathlib import Path
import json,sys
import numpy as np
from gray_cnn import load,integer_forward
from gray_reference import rgb888_to_rgb565,rgb565_gray
ROOT=Path(__file__).resolve().parents[2]
def main():
    folder=ROOT/'src/generated/gesture_gray'
    def mem(n):return np.array([int(v,16) for v in (folder/(n+'.mem')).read_text().split()],dtype=np.int64)
    x=mem('test_features').reshape(-1,32,32);expected=mem('test_scores').reshape(-1,4)
    expected=np.where(expected>=2**31,expected-2**32,expected)
    w,b=load(folder);got=integer_forward(x,w,b);assert np.array_equal(got,expected)
    bound=100*127*127+max(abs(b));assert bound<2**31
    # Camera replay vectors exercise quantization, CDC, CNN and reject logic.
    rgb=np.repeat(x[...,None],3,axis=-1);packed=rgb888_to_rgb565(rgb)
    gray=rgb565_gray(packed);scores=integer_forward(gray,w,b)
    out=ROOT/'tmp/gray_cnn_vectors';out.mkdir(exist_ok=True)
    for name,data,width in [('rgb565',packed,4),('gray',gray,2),('scores',scores,8)]:
        (out/(name+'.mem')).write_text(''.join(f'{int(v)&((1<<(4*width))-1):0{width}x}\n' for v in data.flat))
    sorted_scores=np.sort(scores,axis=1);pred=scores.argmax(1);gap=sorted_scores[:,-1]-sorted_scores[:,-2]
    ids=[int(np.flatnonzero((pred==c)&(gap>=2048))[0]) for c in range(4)]
    (out/'ids.mem').write_text(''.join(f'{v:04x}\n' for v in ids))
    report=dict(images=len(x),scores=int(got.size),all_bit_exact=True,accumulator_bound=int(bound),integration_ids=ids,real_camera_verified=False)
    (folder/'export_validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
