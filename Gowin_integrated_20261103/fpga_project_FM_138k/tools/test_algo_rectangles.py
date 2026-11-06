"""Compare actual C layout/raster code with frozen bitmap reference, all pixels.
Also produces display-list fixtures consumed by the RTL priority/latency test.
Requires a host C compiler (gcc); no FPGA production source is replaced.
"""
from pathlib import Path
import subprocess
import os
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
TMP=ROOT/'tmp/algo_rect_test'

def run():
    TMP.mkdir(exist_ok=True)
    source=(ROOT/'src/ui_firmware/main.c').read_text()
    current=source[source.index('/* Ordered rectangle list:'):source.index('static void upload_algo_map(void){')]
    reference=(ROOT/'sim/fixtures/algo_bitmap_reference.h').read_text()
    prefix='#include <stdio.h>\ntypedef unsigned char u8;typedef unsigned short u16;typedef unsigned int u32;\nstatic u16 g_flags[3];\n'
    flags=[int(s,16) for s in (ROOT/'src/generated/fm_algorithm_flags.mem').read_text().split() if len(s)==12]
    # Custom feedback changes exercise non-ROM routing descriptions as well.
    flags += [v | 0xc0c0c0c0c0c0 for v in flags]
    inp=TMP/'flags.txt';inp.write_text('\n'.join('%012x'%v for v in flags))
    for kind,body,out in [('old',reference,'fwrite(map_buf,1,32768,stdout);'),('new',current,'fwrite(&map_count,2,1,stdout);for(int j=0;j<map_count;j++){fwrite(&map_lo[j],4,1,stdout);fwrite(&map_hi[j],1,1,stdout);}if(map_overflow)return 2;')]:
        code=prefix+body+'\nint main(int argc,char **argv){unsigned long long f;FILE *fp=fopen(argv[1],"r");freopen(argv[2],"wb",stdout);while(fscanf(fp,"%llx",&f)==1){for(int i=0;i<3;i++)g_flags[i]=(f>>(16*i))&65535;build_algo_map();'+out+'}return 0;}\n'
        path=TMP/(kind+'.c');path.write_text(code)
        compiler=[os.environ['ZIG_EXE'],'cc'] if os.environ.get('ZIG_EXE') else ['gcc']
        subprocess.check_call(compiler+['-O2',str(path),'-o',str(TMP/(kind+'.exe'))])
        subprocess.check_call([str(TMP/(kind+'.exe')),str(inp),str(TMP/(kind+'.bin'))])
    old=np.frombuffer((TMP/'old.bin').read_bytes(),dtype=np.uint8).reshape(len(flags),-1)
    new=(TMP/'new.bin').read_bytes();offset=0;maximum=0;fixtures=[];samples=[]
    for i in range(len(flags)):
        count=int.from_bytes(new[offset:offset+2],'little');offset+=2;maximum=max(maximum,count)
        frame=np.zeros((256,512),dtype=np.uint8);rects=[]
        for j in range(count):
            val=int.from_bytes(new[offset:offset+5],'little');offset+=5;rects.append(val)
            x0=val&511;x1=(val>>9)&511;y0=(val>>18)&255;y1=(val>>26)&255;c=(val>>34)&3
            assert c and x0<=x1 and y0<=y1
            frame[y0:y1+1,x0:x1+1]=c
        ref=((old[i,:,None]>>np.array([0,2,4,6],dtype=np.uint8))&3).reshape(256,512)
        assert np.array_equal(ref,frame),'Pixel mismatch algorithm/custom %d'%i
        fixtures.append('%09x'%count);fixtures.extend('%09x'%v for v in rects);fixtures.extend(['000000000']*(256-count))
        # Deterministic sparse samples plus every rectangle corner and boundary.
        points={(0,0),(511,255),(100,100)}
        for v in rects:
            x0=v&511;x1=(v>>9)&511;y0=(v>>18)&255;y1=(v>>26)&255
            for x in (max(0,x0-1),x0,x1,min(511,x1+1)):
                for y in (max(0,y0-1),y0,y1,min(255,y1+1)):points.add((x,y))
        samples.append('%06x'%len(points));samples.extend('%06x'%((int(frame[y,x])<<17)|(y<<9)|x) for x,y in sorted(points))
    assert offset==len(new)
    (TMP/'rectangles.mem').write_text('\n'.join(fixtures)+'\n')
    (TMP/'samples.mem').write_text('\n'.join(samples)+'\n')
    print('PASS %d ROM/custom graphs, every pixel equal; max %d/256 rectangles; RTL fixtures ready'%(len(flags),maximum))

if __name__=='__main__':run()
