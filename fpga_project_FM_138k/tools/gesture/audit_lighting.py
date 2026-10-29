"""Measure fixed-threshold sensitivity without changing the deployed model.

Synthetic exposure changes to exported CGI samples are diagnostic probes,
not real-camera accuracy measurements or a new model-selection dataset.
"""
import argparse
import json
from pathlib import Path
import numpy as np
from model import rgb332_features, read_export, integer_forward

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    folder = ROOT / 'src/generated/gesture'
    def mem(name):
        return np.array([int(s, 16) for s in (folder/name).read_text().split()])
    packed = mem('test_rgb332.mem').reshape(-1, 256)
    labels = mem('test_labels.mem')
    # Reconstruct levels covering the original full range; the top bits,
    # and hence the unmodified FPGA input, remain identical.
    rgb = np.stack([(packed >> 5)*255//7,
                    ((packed >> 2)&7)*255//7, (packed&3)*255//3], axis=-1)
    weights, biases = read_export(folder)
    rows = []
    for scale in (1.0, 0.95, 0.9, 0.875, 0.85, 0.8):
        x = rgb332_features((rgb*scale).astype(np.uint8), 'silhouette')
        scores = integer_forward(x, weights, biases)
        ordered = np.sort(scores, axis=1)
        gap = ordered[:, -1]-ordered[:, -2]
        energy = x.sum(axis=1)
        area_ok = (energy >= 768)&(energy <= 30000)
        accepted = area_ok&(gap >= 2048)
        if scale == 1.0:
            assert np.array_equal(x, mem('test_features.mem').reshape(-1, 256))
        rows.append(dict(brightness_scale=scale, samples=len(labels),
                         raw_correct=int((scores.argmax(1) == labels).sum()),
                         area_rejected=int((~area_ok).sum()),
                         accepted=int(accepted.sum()),
                         correct_accepted=int((accepted&(scores.argmax(1) == labels)).sum()),
                         median_foreground_cells=float(np.median(energy/127))))
    solid = {}
    for value in (255, 240, 224, 223, 220, 200):
        cells = rgb332_features(np.full((256, 3), value), 'silhouette')
        solid[str(value)] = int(cells.sum())
    assert solid['224'] == 0 and solid['223'] == 32512
    result = dict(note='Synthetic lighting sensitivity only; not real-camera validation.',
                  solid_gray_energy=solid, exposure_probes=rows)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
