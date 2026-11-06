"""Verify exported vectors with independent int64 arithmetic; no training needed."""
from pathlib import Path
import json
import hashlib
import numpy as np
from model import read_export, integer_forward, rgb332_features

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'src/generated/gesture'


def mem(name):
    return np.array([int(s, 16) for s in (OUT/name).read_text().split()], dtype=np.int64)


def main():
    w, b = read_export(OUT)
    report = json.loads((OUT/'training_report.json').read_text())
    n = report['test']
    assert n == 372
    x = mem('test_features.mem').reshape(n,256)
    expected = mem('test_scores.mem').reshape(n,3)
    expected = np.where(expected >= 2**31, expected-2**32, expected)
    rgb = mem('test_rgb332.mem').reshape(n,256)
    # Reconstruct the *top* RGB bits, exactly the information camera preserves.
    channels = np.stack([(rgb >> 5) << 5, ((rgb >> 2)&7) << 5, (rgb&3) << 6], axis=-1)
    assert np.array_equal(rgb332_features(channels, report['feature_mode']), x)
    got = integer_forward(x, w, b)
    assert np.array_equal(got, expected)
    assert np.max(np.abs(b)) + 256*127*127 < 2**31  # all accumulator paths fit
    labels = mem('test_labels.mem')
    ordered = np.sort(got,axis=1)
    margin = ordered[:,-1]-ordered[:,-2]
    energy = x.sum(1)
    accept = (margin >= 2048)&(energy >= 768)&(energy <= 30000)
    validation = dict(vectors=n, scores_checked=n*3, bit_exact=True,
        max_abs_accumulator_bound=int(np.max(np.abs(b))+256*127*127),
        accepted=int(accept.sum()), correct_accepted=int(((got.argmax(1)==labels)&accept).sum()),
        threshold_source='initial engineering defaults, not tuned on test split',
        hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(OUT.glob('*.mem'))})
    (OUT/'export_validation.json').write_text(json.dumps(validation,indent=2)+'\n')
    print(json.dumps(validation,indent=2))


if __name__ == '__main__':
    main()
