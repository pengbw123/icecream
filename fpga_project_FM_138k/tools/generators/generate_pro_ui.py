"""Build on-board editor tables, RBJ biquad coefficients and 8x12 font."""
from pathlib import Path
import math,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from core.fm_patch import load_syx,normalise_patch,operator_frequency_word,ALGORITHM_FLAGS,DX7_PITCH_RATE,DX7_PITCH_LEVEL
from PIL import Image,ImageDraw,ImageFont
def main():
    source=Path(sys.argv[1])
    patches=[normalise_patch(p) for p in load_syx(source)[:32]]
    out=['/* Generated from ROM1A; no SYX sample library is embedded. */']
    raw=[]
    for p in patches:
        l=p['lfo'];v=[p['algorithm']-1,p['feedback'],p['osc_sync'],p['transpose'],l['waveform'],l['speed'],l['delay'],l['pitch_depth'],l['amp_depth'],l['pitch_sensitivity'],l['sync']]
        v+=p['pitch_eg_rates']+p['pitch_eg_levels']
        for op in p['operators']:
            v += [op['enabled'],int(op['mode']=='fixed'),op['coarse'],op['fine'],op['detune'],op['output_level']]+op['eg_rates']+op['eg_levels']+[op['rate_scaling'],op['velocity_sensitivity'],op['amp_mod_sensitivity'],op['breakpoint'],op['left_depth'],op['right_depth'],op['left_curve'],op['right_curve']]
        raw.append([int(x) for x in v])
    assert all(len(x)==151 for x in raw),[len(x) for x in raw]
    out+=['static const u8 raw_bank[32][151]={'+','.join('{'+','.join(map(str,r))+'}' for r in raw)+'};']
    out+=['static const u8 algo_flags[32][6]={'+','.join('{'+','.join(map(str,r))+'}' for r in ALGORITHM_FLAGS)+'};']
    f=[]
    for mode in ['ratio','fixed']:
        for coarse in range(32):
            for fine in range(100):f.append(operator_frequency_word(dict(mode=mode,coarse=coarse,fine=fine,detune=7)))
    out+=['static const u32 freq_words[6400]={'+','.join(map(str,f))+'};']
    out+=['static const int detune_delta[15]={'+','.join(str(round(65536*2**(c/1200))-65536) for c in [-7,-5.6,-4.4,-3.4,-2.5,-1.7,-.8,0,.8,1.7,2.5,3.4,4.4,5.6,7])+'};']
    out+=['static const int pitch_levels[100]={'+','.join(map(str,DX7_PITCH_LEVEL))+'};', 'static const u16 pitch_rates[100]={'+','.join(map(str,DX7_PITCH_RATE))+'};']
    freqs=[round(30*(16000/30)**(i/23)) for i in range(24)]
    out+=['static const u16 filter_hz[24]={'+','.join(map(str,freqs))+'};']
    coeff=[]
    for typ in range(5):
        for fi,fc in enumerate(freqs):
            w=2*math.pi*fc/48828.125;c=math.cos(w);s=math.sin(w)
            for q in [.5,.707,1.4,3.0]:
                a=s/(2*q)
                for gain in [-12,-6,0,6,12]:
                    A=10**(gain/40)
                    if typ==0:b0,b1,b2,a0,a1,a2=(1-c)/2,1-c,(1-c)/2,1+a,-2*c,1-a
                    elif typ==1:b0,b1,b2,a0,a1,a2=(1+c)/2,-1-c,(1+c)/2,1+a,-2*c,1-a
                    elif typ==2:b0,b1,b2,a0,a1,a2=a,0,-a,1+a,-2*c,1-a
                    elif typ==3:b0,b1,b2,a0,a1,a2=1,-2*c,1,1+a,-2*c,1-a
                    else:b0,b1,b2,a0,a1,a2=1+a*A,-2*c,1-a*A,1+a/A,-2*c,1-a/A
                    coeff.append([round(v/a0*2**28) for v in [b0,b1,b2,a1,a2]])
    # Only PEAK needs five gain tables; LP/HP/BP/notch share a single one.
    compact=[]
    for t in range(5):
        for fi in range(24):
            for qi in range(4):
                for gi in range(5 if t==4 else 1):compact.append(coeff[(((t*24+fi)*4+qi)*5)+(gi if t==4 else 2)])
    out+=['static const int filter_coeff[864][5]={'+','.join('{'+','.join(map(str,r))+'}' for r in compact)+'};']
    (ROOT/'src/ui_firmware/pro_tables.h').write_text('\n'.join(out)+'\n',encoding='ascii')
    font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',12)
    rows=[]
    for c in range(128):
        im=Image.new('L',(8,16));ImageDraw.Draw(im).text((0,-1),chr(c) if c>=32 else ' ',font=font,fill=255)
        for y in range(16):rows.append(sum((1<<(7-x)) for x in range(8) if im.getpixel((x,y))>=90))
    (ROOT/'src/generated/font8x16.mem').write_text(''.join(f'{r:02X}\n' for r in rows),encoding='ascii')
    (ROOT/'src/generated/menu_blank.mem').write_text('0020\n'*2048,encoding='ascii')
    print('Generated bank, 6400 frequency words, 864 filter coefficient sets, 8x16 cell font.')
if __name__=='__main__':main()
