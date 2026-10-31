"""Replay a still image with production preprocessing and integer CNN weights.

No hand detector, temporal vote, or automatic crop is simulated. In particular,
an OBS screenshot is NOT raw camera data: RGB332 and UI overlays lose information.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

from gray_cnn import load, integer_forward
from gray_adapt import adapt_gray
from gray_reference import frame_features, rgb888_to_rgb565, roi_image_features


def features(image, format_name):
    if format_name == 'roi-square':
        return roi_image_features(image)
    expected = (800, 480) if format_name == 'camera800' else (160, 120)
    if image.size != expected:
        raise ValueError(f'{format_name} requires {expected}, got {image.size}')
    rgb = np.asarray(image.convert('RGB'))
    if format_name == 'camera800':
        # ov5640_capture: source x=80..719, every fourth column and row.
        rgb = rgb[0:480:4, 80:720:4]
    return frame_features(rgb888_to_rgb565(rgb))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('--format', required=True,
                        choices=['camera800', 'preview160', 'roi-square'])
    parser.add_argument('--out-prefix', type=Path)
    args = parser.parse_args()
    with Image.open(args.image) as image:
        gray = features(image, args.format)
    weights, biases = load(Path(__file__).resolve().parents[2]/'src/generated/gesture_gray')
    scores = integer_forward(adapt_gray(gray[None]), weights, biases)[0]
    # Stable sorting preserves hardware's lower-index tie winner.
    order = np.argsort(-scores, kind='stable')
    best = int(order[0])
    margin = int(scores[best]) - int(scores[order[1]])
    report = dict(source=str(args.image), source_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest(),
                  format=args.format, raw_class=['FIST', 'PALM', 'V', 'OTHER'][best],
                  accepted=best < 3 and margin >= 2048,
                  margin=margin, mean_gray=int(gray.astype(np.uint32).sum()) >> 10,
                  scores=[int(v) for v in scores],
                  temporal_filter_simulated=False, real_camera_validation=False)
    text = json.dumps(report, indent=2)
    if args.out_prefix:
        prefix = args.out_prefix
        prefix.parent.mkdir(parents=True, exist_ok=True)
        Path(str(prefix)+'.json').write_bytes((text+'\n').encode('utf-8'))
        Path(str(prefix)+'.mem').write_bytes(''.join(f'{int(v):02x}\n' for v in gray.flat).encode('ascii'))
        Image.fromarray(gray).resize((256, 256), Image.Resampling.NEAREST).save(str(prefix)+'.png')
    print(text)


if __name__ == '__main__':
    main()
