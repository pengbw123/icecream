"""Offline camera stress probes; never substitute these for real-camera tests."""
import os
os.environ.setdefault('OPENBLAS_NUM_THREADS', '1')
import argparse
import io
import json
import zipfile
from pathlib import Path
import numpy as np
from PIL import Image, ImageEnhance
from model import image_features, integer_forward, read_export, shape_energy

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--candidate', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    deployed = ROOT/'src/generated/gesture'
    report = json.loads((deployed/'training_report.json').read_text())
    labels = np.array([int(s, 16) for s in (deployed/'test_labels.mem').read_text().split()])
    candidate_mode = json.loads((args.candidate/'training_report.json').read_text())['feature_mode']
    modes = sorted(set(('silhouette','adaptive',candidate_mode)))
    models = [('deployed_fixed', deployed, 'silhouette'),
              ('old_weights_adaptive', deployed, 'adaptive'),
              ('retrained_'+candidate_mode, args.candidate, candidate_mode)]
    weights = [read_export(folder) for _, folder, _ in models]
    cases = ['original', 'exposure_87pct', 'exposure_70pct', 'exposure_50pct',
             'contrast_60pct', 'smaller_75pct', 'shift_right_10pct',
             'rotate_15deg', 'uneven_light', 'noise_std8']
    features = {(name, mode): [] for name in cases for mode in modes}
    rng = np.random.default_rng(29102026)
    with zipfile.ZipFile(ROOT/'tmp/gesture_data/rps-test-set.zip') as archive:
        for name in report['test_names']:
            with Image.open(io.BytesIO(archive.read(name))) as source:
                im = source.convert('RGB').resize((96,96), Image.Resampling.BILINEAR)
            raw = np.array(im).astype(np.float32)
            small = Image.new('RGB', (96,96), 'white')
            small.paste(im.resize((72,72)), (12,12))
            shift = Image.new('RGB', (96,96), 'white'); shift.paste(im, (10,0))
            variants = dict(original=im, smaller_75pct=small, shift_right_10pct=shift,
                            rotate_15deg=im.rotate(15, fillcolor='white'),
                            contrast_60pct=ImageEnhance.Contrast(im).enhance(.6))
            for percent in (87,70,50):
                variants['exposure_%dpct'%percent] = Image.fromarray((raw*percent/100).astype(np.uint8))
            variants['uneven_light'] = Image.fromarray((raw*np.linspace(.65,1,96)[None,:,None]).astype(np.uint8))
            variants['noise_std8'] = Image.fromarray(np.clip(raw+rng.normal(0,8,raw.shape),0,255).astype(np.uint8))
            for case, image in variants.items():
                for mode in modes:
                    features[case,mode].append(image_features(image, mode))
    def measure(x, w, b, truth=None, shape_check=False):
        x = np.asarray(x)
        s = integer_forward(x,w,b); ordered = np.sort(s,axis=1)
        energy = shape_energy(x) if shape_check else x.sum(axis=1)
        area = (energy>=768)&(energy<=30000)
        accepted = area&((ordered[:,-1]-ordered[:,-2])>=2048)
        result = dict(samples=len(x), accepted=int(accepted.sum()), area_rejected=int((~area).sum()))
        if truth is not None:
            correct = s.argmax(1)==truth
            result.update(raw_correct=int(correct.sum()), correct_accepted=int((correct&accepted).sum()))
        return result
    negative = [Image.new('RGB',(96,96),(i,i,i)) for i in range(0,256,8)]
    gradient = np.tile(np.arange(96)*255//95,(96,1)).astype(np.uint8)
    negative.append(Image.fromarray(gradient).convert('RGB'))
    negative += [Image.fromarray(rng.integers(0,256,(96,96,3),dtype=np.uint8)) for _ in range(16)]
    output = dict(note='Synthetic transforms of already-viewed public test images. No real-camera accuracy claim; no threshold tuning.', models={})
    for (name, _, mode),(w,b) in zip(models, weights):
        rows = {case:measure(features[case,mode],w,b,labels,mode=='plane') for case in cases}
        rows['non_hand_probes'] = measure([image_features(im,mode) for im in negative],w,b,shape_check=mode=='plane')
        output['models'][name] = rows
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(output,indent=2)+'\n',encoding='utf-8')
    for name, rows in output['models'].items():
        print(name)
        for case,row in rows.items(): print(' ',case,row)


if __name__ == '__main__':
    main()
