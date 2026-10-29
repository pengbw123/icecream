"""Run exported FPGA-equivalent inference on one local image, with no hardware.

--camera-frame uses the exact 96x96 ROI of a 160x120 preview frame. Without
this flag the image must already be a square hand crop on a light background.
"""
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image
from model import image_features, integer_forward, read_export, shape_energy

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser()
    p.add_argument('image', type=Path)
    p.add_argument('--camera-frame', action='store_true')
    p.add_argument('--model', type=Path, default=ROOT/'src/generated/gesture')
    args = p.parse_args()
    report = json.loads((args.model/'training_report.json').read_text())
    with Image.open(args.image) as im:
        if args.camera_frame:
            if im.size != (160,120):
                p.error('--camera-frame requires exactly 160x120 pixels')
            im = im.crop((32,12,128,108))
        elif im.width != im.height:
            p.error('Provide a square hand crop, or use --camera-frame')
        x = image_features(im, report['feature_mode'])
    w, b = read_export(args.model)
    scores = integer_forward(x, w, b)
    ordered = np.sort(scores)
    margin = int(ordered[-1]-ordered[-2]); raw_energy = int(x.sum())
    energy = int(shape_energy(x)[0]) if report['feature_mode'] == 'plane' else raw_energy
    reasons = []
    if energy < 768:
        reasons.append('shape_filter_rejected' if raw_energy>=768 else 'too_little_foreground')
    if energy > 30000:
        reasons.append('too_much_foreground_check_background_brightness')
    if margin < 2048:
        reasons.append('class_margin_too_small')
    print(json.dumps(dict(raw_class=report['labels'][int(scores.argmax())],
        scores=[int(s) for s in scores], margin=margin, energy=energy,
        raw_energy=raw_energy,
        rejection_reasons=reasons,
        foreground_cells=int(np.count_nonzero(x)),
        feature_rows=[''.join('#' if v else '.' for v in row) for row in x.reshape(16,16)],
        passes_initial_gate=bool(margin >= 2048 and 768 <= energy <= 30000),
        warning='Prototype only: not a calibrated probability, no trained unknown class, no real-camera validation'), indent=2))


if __name__ == '__main__':
    main()
