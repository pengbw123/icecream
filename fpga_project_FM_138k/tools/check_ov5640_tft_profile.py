"""Compare all emitted writes with the independently supplied working ch45 ROM.
No evaluation of source code: only the vendor's literal and width/flip forms.
"""
from pathlib import Path
import argparse,hashlib,json,re
ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('vendor_table',type=Path)
    ap.add_argument('--record',type=Path);a=ap.parse_args()
    raw=a.vendor_table.read_bytes();source=raw.decode('utf-8',errors='replace')
    assert re.search(r"IMAGE_FLIP_DAT\s*=\s*IMAGE_FLIP_EN\s*\?\s*8'h47\s*:\s*8'h40",source)
    assert re.search(r"IMAGE_MIRROR_DAT\s*=\s*IMAGE_MIRROR_EN\s*\?\s*4'h0\s*:\s*4'h7",source)
    vendor_top=a.vendor_table.parent.parent/'ov5640_ddr3_tft.v'
    vendor_pll=a.vendor_table.parent.parent/'gowin_pll/gowin_pll.v'
    top=vendor_top.read_bytes().decode('utf-8',errors='replace')
    pll=vendor_pll.read_bytes().decode('utf-8',errors='replace')
    own_pll=(ROOT/'src/camera/camera_reference_pll.v').read_text(encoding='utf-8')
    for name,value in [('IMAGE_WIDTH',800),('IMAGE_HEIGHT',480)]:
        assert re.search(r'parameter\s+'+name+r'\s*=\s*'+str(value)+r'\s*;',top)
    for name in ['IMAGE_FLIP_EN','IMAGE_MIRROR_EN']:
        assert re.search(r'\.'+name+r'\s*\(\s*0\s*\)',top)
    assert re.search(r'\.clkout1\s*\(\s*loc_clk24m\s*\)',top)
    assert re.search(r'assign\s+camera_xclk\s*=\s*loc_clk24m\s*;',top)
    for name,value in [('IDIV_SEL',1),('FBDIV_SEL',1),('MDIV_SEL',16),('MDIV_FRAC_SEL',0),('ODIV1_SEL',33)]:
        for data in [pll,own_pll]:assert re.search(r'\.'+name+r'\s*=\s*'+str(value)+r'\s*;',data)
    entries={int(n):v.strip() for n,v in re.findall(r'rom\s*\[\s*(\d+)\s*\]\s*=\s*(.*?);',source)}
    assert len(entries)==252,'Expected working TFT table with 252 writes'
    expected=[]
    for n in range(252):
        v=entries[n];lit=re.fullmatch(r"24'h([\da-fA-F_]+)",v)
        if lit:word=int(lit[1].replace('_',''),16)
        elif n==211:word=0x382040
        elif n==212:word=0x382107
        elif n in (223,224,225,226):
            address=0x3808+n-223;dimension=800 if n<225 else 480
            word=(address<<8)|((dimension>>8) if n%2 else (dimension&255))
        else:raise ValueError('Unrecognized vendor expression at '+str(n)+': '+v)
        expected.append(word)
    p=ROOT/'src/generated/ov5640_tft_800x480.mem'
    actual=[int(x,16) for x in p.read_text().split()]
    assert actual==expected,'Generated writes differ from working TFT profile'
    record=dict(vendor_source=str(a.vendor_table),vendor_sha256=hashlib.sha256(raw).hexdigest(),
                vendor_top_sha256=hashlib.sha256(vendor_top.read_bytes()).hexdigest(),
                vendor_active_pll_sha256=hashlib.sha256(vendor_pll.read_bytes()).hexdigest(),
                camera_reference_rtl_sha256=hashlib.sha256((ROOT/'src/camera/camera_reference_pll.v').read_bytes()).hexdigest(),
                generated_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),writes=252,
                sensor_dimensions=[800,480],camera_xclk_mhz=50*16/33,crop=[80,0,640,480],
                decimation=[4,4],preview_dimensions=[160,120],all_writes_match_vendor=True)
    if a.record:a.record.parent.mkdir(parents=True,exist_ok=True);a.record.write_bytes((json.dumps(record,indent=2)+'\n').encode())
    print('PASS all 252 writes match working ch45 TFT profile: 800x480, flip=0, mirror=0')
if __name__=='__main__':main()
