"""CPU/NumPy training, explicit train/validation/test, deterministic int8 export.

Download URLs are from TensorFlow Datasets' official RPS builder. Archives
stay under ignored tmp/. No test image is used for fitting or model selection.
"""
import os
os.environ.setdefault('OPENBLAS_NUM_THREADS', '1')
import argparse
import hashlib
import io
import json
from pathlib import Path
import zipfile
import numpy as np
from PIL import Image
from model import LABELS, INPUTS, HIDDEN, OUTPUTS, SHIFT, image_features, image_samples, integer_forward
from download import download

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'src/generated/gesture'
DATA = ROOT/'tmp/gesture_data'
URL = 'https://storage.googleapis.com/download.tensorflow.org/data/'
CLASSES = ['rock', 'paper', 'scissors']


def load(name, mode):
    path = DATA/name
    download(URL+name, path)
    x, y, names = [], [], []
    with zipfile.ZipFile(path) as z:
        for n in sorted(z.namelist()):
            p = n.split('/')
            if len(p) != 3 or p[1] not in CLASSES or not n.endswith('.png'):
                continue
            with Image.open(io.BytesIO(z.read(n))) as im:
                x.append(image_features(im, mode))
            y.append(CLASSES.index(p[1])); names.append(n)
    return np.array(x), np.array(y), names


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--epochs', type=int, default=180)
    parser.add_argument('--features', choices=['gray','silhouette','adaptive','plane'], default='silhouette')
    parser.add_argument('--out', type=Path, default=OUT)
    parser.add_argument('--geometry-augment', action='store_true')
    args = parser.parse_args()
    if args.features in ('adaptive','plane') and args.out.resolve() == OUT.resolve():
        parser.error('Adaptive is an offline candidate: specify a separate --out directory')
    if args.geometry_augment and args.out.resolve() == OUT.resolve():
        parser.error('Augmentation experiment requires a separate --out directory')
    out = args.out
    rng = np.random.default_rng(720138)
    x, y, names = load('rps.zip', args.features)
    # Hold out entire filename sequences; adjacent CGI animation frames must
    # not be divided randomly between train and validation.
    groups = np.array([n.rsplit('/',1)[1].rsplit('-',1)[0] for n in names])
    selected = []
    for label in range(3):
        sequences = sorted(set(groups[y == label]))
        if len(sequences) < 2:
            raise RuntimeError('Cannot make a sequence-held-out validation split')
        selected.extend(rng.permutation(sequences)[:max(1, len(sequences)//5)])
    vi = np.flatnonzero(np.isin(groups, selected))
    ti = np.setdiff1d(np.arange(len(x)), vi)
    a = (rng.normal(0, .1, (INPUTS, HIDDEN))).astype(np.float32)
    b = np.zeros(HIDDEN, np.float32)
    c = (rng.normal(0, .15, (HIDDEN, OUTPUTS))).astype(np.float32)
    d = np.zeros(OUTPUTS, np.float32)
    params = [a, b, c, d]; m = [np.zeros_like(p) for p in params]; v = [p.copy() for p in m]
    best, saved, step = -1, None, 0
    xf = x.astype(np.float32)/127
    for epoch in range(args.epochs):
        ids = rng.permutation(ti)
        for start in range(0, len(ids), 96):
            ix = ids[start:start+96]; xx = xf[ix]
            if args.geometry_augment:
                # Inverse affine sampling, white fill; training split only.
                gy, gx = np.mgrid[:16,:16].astype(np.float32)
                theta = rng.uniform(-.26,.26,(len(ix),1,1))
                scale = rng.uniform(.7,1.12,(len(ix),1,1))
                tx, ty = rng.uniform(-1.5,1.5,(2,len(ix),1,1))
                ux, uy = gx-7.5-tx, gy-7.5-ty
                sx = np.rint((np.cos(theta)*ux+np.sin(theta)*uy)/scale+7.5).astype(int)
                sy = np.rint((-np.sin(theta)*ux+np.cos(theta)*uy)/scale+7.5).astype(int)
                valid = (sx>=0)&(sx<16)&(sy>=0)&(sy<16)
                xx = np.where(valid, xx.reshape(-1,16,16)[np.arange(len(ix))[:,None,None],
                    sy.clip(0,15),sx.clip(0,15)],0).reshape(-1,INPUTS)
            # Small shifts on the 16x16 grid, white fill, training only.
            if epoch % 2:
                dx, dy = rng.integers(-1, 2, 2)
                grid = xx.reshape(-1, 16, 16)
                shifted = np.full_like(grid, 1/127 if args.features == 'gray' else 0)
                sy, sx = slice(max(0,-dy), min(16,16-dy)), slice(max(0,-dx), min(16,16-dx))
                ty, tx = slice(max(0,dy), min(16,16+dy)), slice(max(0,dx), min(16,16+dx))
                shifted[:, ty, tx] = grid[:, sy, sx]; xx = shifted.reshape(-1, INPUTS)
            pre = xx@a+b; h = np.clip(pre, 0, 1)
            logits = h@c+d; p = np.exp(logits-logits.max(1, keepdims=True)); p /= p.sum(1, keepdims=True)
            p[np.arange(len(ix)), y[ix]] -= 1; p /= len(ix)
            dh = (p@c.T)*((pre > 0) & (pre < 1))
            grads = [xx.T@dh+1e-4*a, dh.sum(0), h.T@p+1e-4*c, p.sum(0)]
            step += 1
            for j, (param, grad) in enumerate(zip(params, grads)):
                m[j] *= .9; m[j] += .1*grad; v[j] *= .999; v[j] += .001*grad*grad
                param -= .004*(m[j]/(1-.9**step))/(np.sqrt(v[j]/(1-.999**step))+1e-8)
            np.clip(a, -1.98, 1.98, out=a); np.clip(c, -1.98, 1.98, out=c)
        # Select by fixed-point accuracy, not floating accuracy.
        weights = np.clip(np.rint(np.r_[a.T.ravel(), c.T.ravel()]*(1 << SHIFT)), -127, 127).astype(np.int8)
        biases = np.rint(np.r_[b, d]*127*(1 << SHIFT)).astype(np.int64)
        acc = float((integer_forward(x[vi], weights, biases).argmax(1) == y[vi]).mean())
        if acc > best:
            best = acc; saved = (weights.copy(), biases.copy(), epoch+1)
        if epoch % 20 == 0 or epoch == args.epochs-1:
            print(f'epoch {epoch+1}: validation_int8={acc:.4f}, best={best:.4f}', flush=True)
    weights, biases, epoch = saved
    xt, yt, testnames = load('rps-test-set.zip', args.features)
    scores = integer_forward(xt, weights, biases); pred = scores.argmax(1)
    confusion = np.zeros((3,3), dtype=int)
    np.add.at(confusion, (yt, pred), 1)
    out.mkdir(parents=True, exist_ok=True)
    (out/'weights.mem').write_text(''.join(f'{int(w)&255:02x}\n' for w in weights))
    (out/'biases.mem').write_text(''.join(f'{int(b)&0xffffffff:08x}\n' for b in biases))
    # Every held-out image is compared against all 3 RTL logits, not just argmax.
    (out/'test_features.mem').write_text(''.join(f'{int(q):02x}\n' for q in xt.flat))
    (out/'test_scores.mem').write_text(''.join(f'{int(q)&0xffffffff:08x}\n' for q in scores.flat))
    (out/'test_labels.mem').write_text(''.join(f'{int(q):02x}\n' for q in yt))
    # Camera-equivalent RGB332 point samples for end-to-end RTL tests.
    samples = []
    with zipfile.ZipFile(DATA/'rps-test-set.zip') as z:
        for n in testnames:
            with Image.open(io.BytesIO(z.read(n))) as im:
                rgb = image_samples(im).astype(np.uint16)
                samples.extend((((rgb[...,0]>>5)<<5)|((rgb[...,1]>>5)<<2)|(rgb[...,2]>>6)).ravel())
    (out/'test_rgb332.mem').write_text(''.join(f'{int(q):02x}\n' for q in samples))
    report = dict(dataset='Laurence Moroney Rock Paper Scissors (CGI, white background)',
        source='https://laurencemoroney.com/datasets.html', license='CC BY 2.0',
        seed=720138, architecture=[INPUTS,HIDDEN,OUTPUTS], labels=LABELS, feature_mode=args.features,
        weight_count=len(weights), bias_count=len(biases), shift=SHIFT,
        train=len(ti), validation=len(vi), validation_sequences=selected, test=len(yt), selected_epoch=epoch,
        validation_int8=best, test_int8=float((pred == yt).mean()), confusion=confusion.tolist(),
        hardware_verified=False, real_camera_accuracy=None,
        geometry_augmentation=args.geometry_augment,
        limitations=['CGI domain; not validated on OV5640', 'Fixed square ROI; hand must fill ROI',
            'No trained no-hand class; margin rejection cannot guarantee unknown rejection',
            'Validation holds out filename sequences; independent real-subject accuracy unknown'],
        archives={n:hashlib.sha256((DATA/n).read_bytes()).hexdigest() for n in ['rps.zip','rps-test-set.zip']},
        split_names={k:[names[i] for i in ix] for k,ix in [('train',ti),('validation',vi)]},
        test_names=testnames)
    (out/'training_report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k not in ['split_names','test_names']}, indent=2), flush=True)


if __name__ == '__main__':
    main()
