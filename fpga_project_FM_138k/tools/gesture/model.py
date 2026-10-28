"""Hardware-matched preprocessing and int8 gesture MLP reference.

Input is a square hand ROI on a plain light background. This is deliberately
NOT a detector for hands in arbitrary scenes. No softmax is needed in RTL.
"""
import numpy as np

LABELS = ['fist', 'palm', 'v_sign']
INPUTS, HIDDEN, OUTPUTS, SHIFT = 256, 24, 3, 6


def rgb332_features(rgb, mode='gray'):
    """RGB888 -> camera RGB332 -> inverted 7-bit luma, same as RTL.

    r3/g3 expand to 0..126, b2 to 0..126; cheap 1:2:1 luma.
    White -> 1, black -> 127. Preserve this quantization when retraining.
    """
    p = np.asarray(rgb, dtype=np.int32)
    r, g, b = (p[..., 0] >> 5)*18, (p[..., 1] >> 5)*18, (p[..., 2] >> 6)*42
    value = (127 - ((r + 2*g + b) >> 2)).astype(np.uint8)
    if mode == 'silhouette':
        return np.where(value >= 12, 127, 0).astype(np.uint8)
    if mode != 'gray':
        raise ValueError(mode)
    return value


def image_samples(image):
    # 16x16 point samples at centers of 16 cells (no bilinear/box mismatch).
    rgb = np.asarray(image.convert('RGB'))
    h, w = rgb.shape[:2]
    ys = ((np.arange(16)*2+1)*h//32).clip(0, h-1)
    xs = ((np.arange(16)*2+1)*w//32).clip(0, w-1)
    return rgb[ys[:, None], xs[None, :]]


def image_features(image, mode='gray'):
    return rgb332_features(image_samples(image), mode).reshape(-1)


def integer_forward(x, weights, biases):
    w1 = weights[:INPUTS*HIDDEN].reshape(HIDDEN, INPUTS).astype(np.int64)
    w2 = weights[INPUTS*HIDDEN:].reshape(OUTPUTS, HIDDEN).astype(np.int64)
    x = np.asarray(x, dtype=np.int64)
    h = np.clip((x @ w1.T + biases[:HIDDEN]) >> SHIFT, 0, 127)
    return h @ w2.T + biases[HIDDEN:]


def read_export(folder):
    weights = np.array([int(s, 16) for s in (folder/'weights.mem').read_text().split()], dtype=np.int32)
    weights = np.where(weights >= 128, weights-256, weights)
    biases = np.array([int(s, 16) for s in (folder/'biases.mem').read_text().split()], dtype=np.int64)
    biases = np.where(biases >= 2**31, biases-2**32, biases)
    assert len(weights) == INPUTS*HIDDEN+HIDDEN*OUTPUTS and len(biases) == HIDDEN+OUTPUTS
    return weights, biases
