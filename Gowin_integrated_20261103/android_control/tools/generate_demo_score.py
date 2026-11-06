"""Create a simple, unaccompanied public-domain melody for the LED guide.

Notes: MIDI 60..69; 42 notes; C major; 96 beats per minute.  The source
melody is the traditional Twinkle, Twinkle, Little Star.  The short gaps
make repeated notes separately visible on the LED strip.
"""
from pathlib import Path
import struct


def vlq(value):
    result = [value & 0x7f]
    value >>= 7
    while value:
        result.insert(0, 0x80 | (value & 0x7f))
        value >>= 7
    return bytes(result)


def main():
    phrases = [
        [60, 60, 67, 67, 69, 69, 67],
        [65, 65, 64, 64, 62, 62, 60],
        [67, 67, 65, 65, 64, 64, 62],
        [67, 67, 65, 65, 64, 64, 62],
        [60, 60, 67, 67, 69, 69, 67],
        [65, 65, 64, 64, 62, 62, 60],
    ]
    ppq, gap = 480, 40
    track = bytearray(b"\x00\xff\x51\x03\x09\x89\x68")  # 625000 us/beat = 96 bpm
    delay = 0
    for phrase in phrases:
        for index, note in enumerate(phrase):
            beats = 2 if index == len(phrase) - 1 else 1
            track.extend(vlq(delay) + bytes([0x90, note, 96]))
            track.extend(vlq(beats * ppq - gap) + bytes([0x80, note, 0]))
            delay = gap
    track.extend(vlq(delay) + b"\xff\x2f\x00")
    midi = b"MThd" + struct.pack(">IHHH", 6, 0, 1, ppq) + b"MTrk" + struct.pack(">I", len(track)) + track
    target = Path(__file__).resolve().parents[1] / "assets" / "scores" / "twinkle_25key_c4.mid"
    if target.exists():
        if target.read_bytes() != midi:
            raise RuntimeError("Existing demo differs; preserve it and choose a new output path")
    else:
        target.write_bytes(midi)
    print(f"{target}: {len(midi)} bytes, 42 notes, MIDI 60..69, 96 BPM")


if __name__ == "__main__":
    main()
