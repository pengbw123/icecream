"""Decode an SMF melody into the transport-independent lesson upload format.

Usage: python tools/midi_to_lesson.py song.mid --output tmp/song.json
Optional --channel 1..16 selects one melody channel. No serial/USB/Bluetooth
dependencies: a future receiver writes the resulting words to UI[31..34].
This version intentionally rejects chords, out-of-range pitches and long scores.
"""
import argparse
import json
import struct
from fractions import Fraction
from pathlib import Path

def vlq(data, pos):
    value = 0
    for _ in range(4):
        if pos >= len(data):
            raise ValueError('Truncated MIDI variable-length value')
        b = data[pos]; pos += 1
        value = (value << 7) | (b & 127)
        if b < 128:
            return value, pos
    raise ValueError('Invalid MIDI variable-length value')

def decode(blob, channel=None):
    if len(blob) < 14 or blob[:4] != b'MThd':
        raise ValueError('Not a standard MIDI file')
    size = struct.unpack('>I', blob[4:8])[0]
    fmt, tracks, division = struct.unpack('>HHH', blob[8:14])
    if size < 6 or fmt not in (0, 1) or not division or division & 0x8000:
        raise ValueError('Only format 0/1 MIDI with PPQN timing is supported')
    pos = 8 + size; events = []; order = 0
    for _ in range(tracks):
        if blob[pos:pos+4] != b'MTrk' or pos + 8 > len(blob):
            raise ValueError('Missing MIDI track')
        n = struct.unpack('>I', blob[pos+4:pos+8])[0]
        data = blob[pos+8:pos+8+n]; pos += 8+n
        if len(data) != n:
            raise ValueError('Truncated MIDI track')
        i = 0; tick = 0; running = None
        while i < len(data):
            delta, i = vlq(data, i); tick += delta
            if i >= len(data):
                raise ValueError('Missing MIDI status')
            status = data[i]
            if status >= 128:
                i += 1
                if status < 0xf0:
                    running = status
            elif running is not None:
                status = running
            else:
                raise ValueError('Running status without channel status')
            if status == 0xff:
                if i >= len(data):
                    raise ValueError('Truncated MIDI meta event')
                kind = data[i]; i += 1
                length, i = vlq(data, i); value = data[i:i+length]; i += length
                if len(value) != length:
                    raise ValueError('Truncated MIDI meta payload')
                if kind == 0x51:
                    if length != 3 or int.from_bytes(value, 'big') == 0:
                        raise ValueError('Invalid tempo')
                    events.append((tick, 0, order, 'tempo', int.from_bytes(value, 'big')))
            elif status in (0xf0, 0xf7):
                running = None
                length, i = vlq(data, i); i += length
                if i > len(data):
                    raise ValueError('Truncated SysEx')
            elif status < 0xf0:
                n = 1 if status >> 4 in (0xc, 0xd) else 2
                args = data[i:i+n]; i += n
                if len(args) != n or any(b >= 128 for b in args):
                    raise ValueError('Invalid channel event')
                ch = status & 15
                if (channel is None and ch != 9) or channel == ch:
                    if status >> 4 in (8, 9):
                        on = status >> 4 == 9 and args[1] != 0
                        events.append((tick, 2 if on else 1, order, 'on' if on else 'off', (ch, args[0])))
            else:
                raise ValueError('Unsupported system event in MIDI track')
            order += 1
    elapsed = Fraction(0); last_tick = 0; tempo = 500000
    active = {}; notes = []
    for tick, _, _, kind, value in sorted(events):
        elapsed += Fraction((tick-last_tick)*tempo, division); last_tick = tick
        if kind == 'tempo':
            tempo = value
        elif kind == 'on':
            if value in active:
                raise ValueError('Repeated Note On before Note Off')
            active[value] = elapsed
        elif value in active:
            start = active.pop(value)
            if elapsed > start:
                notes.append((start, elapsed, value[1]))
    if active:
        raise ValueError('Unterminated MIDI notes')
    notes.sort()
    if not notes or len(notes) > 128:
        raise ValueError('Lesson requires 1..128 notes; select a melody/channel or shorten the excerpt')
    first = notes[0][0]; previous_end = Fraction(-1); words = []; last_end = 0
    for start, end, note in notes:
        if start < previous_end:
            raise ValueError('Polyphonic/overlapping melody; select or edit a monophonic track first')
        if not 48 <= note <= 72:
            raise ValueError('Pitch %d outside the displayed C3..C5 range (MIDI 48..72)' % note)
        onset = 128 + round((start-first)/16000)
        stop = 128 + round((end-first)/16000)
        gate = max(1, stop-onset)
        if gate > 511 or onset+gate+4 > 65535:
            raise ValueError('Note duration/time exceeds the current score format')
        if onset < last_end:
            raise ValueError('Quantization created overlapping notes')
        words.append((onset << 16) | (gate << 7) | note)
        last_end = onset+gate; previous_end = end
    return {'version': 1, 'tick_us': 16000, 'count': len(words),
            'end': last_end+4, 'entries': words}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('midi', type=Path)
    p.add_argument('--channel', type=int, choices=range(1, 17))
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    try:
        score = decode(args.midi.read_bytes(), None if args.channel is None else args.channel-1)
    except ValueError as e:
        p.error(str(e))
    args.output.write_text(json.dumps(score, indent=2)+'\n', encoding='utf-8')
    args.output.with_suffix('.mem').write_text(''.join('%08x\n'%w for w in score['entries']+[0]*(128-score['count'])),encoding='ascii')
    print('%d notes, %.3f s; upload format v1' % (score['count'], score['end']*.016))

if __name__ == '__main__':
    main()
