"""Pack the 512-entry Q15 quarter sine and forward differences for RTL."""

from __future__ import annotations

from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / "src/generated/additive_sine_quarter_512.mem"
OUTPUT = PROJECT / "src/generated/dx7_sine_quarter_delta_512.mem"


def packed_words() -> list[int]:
    sine = [int(line, 16) for line in SOURCE.read_text("ascii").split()]
    if len(sine) != 512:
        raise ValueError("expected exactly 512 quarter-wave samples")
    endpoint = 32767
    words = []
    for index, base in enumerate(sine):
        following = sine[index + 1] if index < len(sine) - 1 else endpoint
        delta = following - base
        if not (0 <= delta <= 255):
            raise ValueError(f"delta at sample {index} does not fit in 8 bits")
        words.append((base << 8) | delta)
    return words


def main() -> None:
    words = packed_words()
    OUTPUT.write_text("".join(f"{word:06X}\n" for word in words),
                      encoding="ascii")
    print(f"wrote {len(words)} packed samples to {OUTPUT}")


if __name__ == "__main__":
    main()
