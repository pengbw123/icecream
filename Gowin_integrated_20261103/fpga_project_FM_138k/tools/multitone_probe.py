"""Send only MIDI control packets over the project's existing PC UART.
The FPGA generates every audio sample. Prepare a one-carrier sine patch first.
Without --port this prints the expected notes/frequencies and sends nothing.
"""
import argparse
import json
import time
from core.fm_patch import midi_event_packet


def notes_for(count):
    return [60, 64, 67, 72] if count == 4 else list(range(48, 48+count))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--voices', type=int, choices=[4, 8, 16, 32], default=4)
    p.add_argument('--seconds', type=float, default=10)
    p.add_argument('--port', help='Existing FPGA PC UART, e.g. COM6; close other serial applications')
    p.add_argument('--prepared-sine', action='store_true', help='Confirm one carrier, ratio1, no FX, no LFO/glide, stable sustain, AI/ARP/SEQ off')
    a = p.parse_args()
    if not 1 <= a.seconds <= 120:
        p.error('--seconds must be 1..120')
    notes = notes_for(a.voices)
    print(json.dumps(dict(voices=a.voices, notes=notes,
                         expected_hz=[round(440*2**((n-69)/12), 4) for n in notes],
                         port=a.port, pcm_playback=False), indent=2))
    if not a.port:
        return
    if not a.prepared_sine:
        p.error('Prepare the sine patch and pass --prepared-sine before sending')
    import serial
    with serial.Serial(a.port, 115200, timeout=1, write_timeout=2) as connection:
        try:
            for cc in (64, 123):
                connection.write(midi_event_packet(0xb0, cc, 0))
            connection.flush()
            time.sleep(.5)
            for n in notes:
                connection.write(midi_event_packet(0x90, n, 64))
            connection.flush()
            time.sleep(a.seconds)
        finally:
            for n in notes:
                connection.write(midi_event_packet(0x80, n, 0))
            connection.write(midi_event_packet(0xb0, 123, 0))
            connection.flush()


if __name__ == '__main__':
    main()
