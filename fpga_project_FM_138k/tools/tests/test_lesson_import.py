import struct
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from midi_to_lesson import decode

def smf(track):
    return b'MThd'+struct.pack('>IHHH',6,0,1,32)+b'MTrk'+struct.pack('>I',len(track))+track

class LessonImportTests(unittest.TestCase):
    def test_factory_round_trip(self):
        root=Path(__file__).resolve().parents[2]
        score=decode((root/'docs/lesson_twinkle.mid').read_bytes())
        rom=[int(x,16) for x in (root/'src/generated/lesson_score.mem').read_text().split()]
        self.assertEqual(score['entries'],rom[:42])
        self.assertEqual(score['end'],1664)

    def test_tempo_and_running_status(self):
        # 500ms quarter, followed by a tempo change to 1s/quarter.
        score=decode(smf(b'\0\x90\x3c\x60\x20\x3c\0\0\xff\x51\3\x0f\x42\x40\0\x90\x3e\x60\x20\x80\x3e\0'))
        self.assertEqual((score['entries'][0]>>7)&511,31)
        self.assertEqual((score['entries'][1]>>7)&511,63)

    def test_chords_rejected(self):
        with self.assertRaisesRegex(ValueError,'overlapping'):
            decode(smf(b'\0\x90\x3c\x60\0\x90\x40\x60\x20\x80\x3c\0\0\x80\x40\0'))

    def test_range_and_missing_off(self):
        with self.assertRaisesRegex(ValueError,'outside'):
            decode(smf(b'\0\x90\x20\x60\x20\x80\x20\0'))
        with self.assertRaisesRegex(ValueError,'Unterminated'):
            decode(smf(b'\0\x90\x3c\x60'))

    def test_channel_selection(self):
        track=b'\0\x91\x3c\x60\0\x92\x40\x60\x20\x81\x3c\0\0\x82\x40\0'
        self.assertEqual(decode(smf(track),1)['count'],1)
        with self.assertRaises(ValueError):
            decode(smf(track))

if __name__=='__main__':
    unittest.main()
