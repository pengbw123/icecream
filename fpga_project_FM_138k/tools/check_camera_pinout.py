"""Independent fixture from supplied GW5AT138K ch59, not generic PDF pinout.
The generic schematic differs on D0/D1/D3/D6 and omits PWDN=L1.
"""
import re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
EXPECTED={'camera_data[0]':'J2','camera_data[1]':'J1','camera_data[2]':'G1',
 'camera_data[3]':'H2','camera_data[4]':'F1','camera_data[5]':'G2','camera_data[6]':'D1','camera_data[7]':'E1',
 'camera_pclk':'B1','camera_href':'A1','camera_vsync':'B2','camera_xclk':'M17',
 'camera_reset_n':'N20','camera_pwdn':'L1','camera_scl':'M20','camera_sda':'L18'}
def main():
    text=(ROOT/'src/acg720_rgb_hdmi.cst').read_text()
    pairs=re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+)\s*;',text)
    assert len({pin for _,pin in pairs})==len(pairs),'Multiple nets bound to one package pin'
    actual=dict(pairs)
    for name,pin in EXPECTED.items():assert actual.get(name)==pin,(name,actual.get(name),pin)
    print('PASS board ch59 camera pin fixture: all 16 signals including PWDN; no I/O collisions')
if __name__=='__main__':main()
