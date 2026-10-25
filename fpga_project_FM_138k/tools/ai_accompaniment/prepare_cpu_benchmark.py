"""Build the same INT8 policy as scalar C for the existing RV32I soft core.
Measures kernel+call overhead, excludes feature construction, UI and MIDI I/O.
This is not a comparison with a desktop CPU or a CPU with a multiply unit.
"""
import argparse
import os
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--zig',default=os.environ.get('ZIG_EXE'))
    ap.add_argument('--optimized',action='store_true',help='Byte multiply and zero-activation skipping')
    args=ap.parse_args()
    if not args.zig:ap.error('Pass --zig or set ZIG_EXE')
    dst=ROOT/'tmp/ai_cpu_benchmark';dst.mkdir(exist_ok=True)
    model=ROOT/'src/generated/ai_bass'
    weights=[int(v,16) for v in (model/'ai_bass_weights.mem').read_text().split()]
    weights=[v if v<128 else v-256 for v in weights]
    biases=[int(v,16) for v in (model/'ai_bass_biases.mem').read_text().split()]
    biases=[v if v<2**31 else v-2**32 for v in biases]
    inputs=[int(v,16) for v in (model/'test_features.mem').read_text().split()]
    vectors=inputs[:48]+inputs[-48:]
    header='static const signed char weights[1792]={'+','.join(map(str,weights))+'};\n'
    header+='static const int biases[40]={'+','.join(map(str,biases))+'};\n'
    header+='static const unsigned char vectors[96]={'+','.join(map(str,vectors))+'};\n'
    (dst/'model.h').write_text(header)
    code='''typedef unsigned int u32;
#include "model.h"
#define IO ((volatile u32*)0x23000000u)
u32 __mulsi3(u32 a,u32 b){u32 r=0;while(b){if(b&1u)r+=a;a<<=1;b>>=1;}return r;}
static int scores[8];
__attribute__((noinline)) static int infer(const unsigned char *x){
    unsigned char hidden[32];int i,j,sum,best,action=0;
    for(i=0;i<32;i++){
        sum=biases[i];for(j=0;j<48;j++)sum+=(int)weights[i*48+j]*(int)x[j];
        hidden[i]=sum<0?0:sum>=4064?127:(unsigned char)(sum>>5);
    }
    best=(-2147483647-1);
    for(i=0;i<8;i++){
        sum=biases[32+i];for(j=0;j<32;j++)sum+=(int)weights[1536+i*32+j]*(int)hidden[j];
        scores[i]=sum;if(sum>best){best=sum;action=i;}
    }
    return action;
}
int main(void){int n,i,a;u32 begin,elapsed;
    for(n=0;n<2;n++){
        begin=IO[0];a=infer(vectors+n*48);elapsed=IO[0]-begin;
        for(i=0;i<8;i++)IO[2+i]=(u32)scores[i];
        IO[10]=elapsed;IO[1]=(u32)(n+1)|((u32)a<<8);
    }
    for(;;){}return 0;
}
'''
    if args.optimized:
        code=code.replace('static int scores[8];','''__attribute__((always_inline)) static inline int mul8(signed char w,unsigned char x){
    int a=w,p=0;unsigned int b=x;
    while(b){if(b&1u)p+=a;a+=a;b>>=1;}return p;
}
static int scores[8];''')
        code=code.replace('sum+=(int)weights[i*48+j]*(int)x[j];','if(x[j])sum+=mul8(weights[i*48+j],x[j]);')
        code=code.replace('sum+=(int)weights[1536+i*32+j]*(int)hidden[j];','if(hidden[j])sum+=mul8(weights[1536+i*32+j],hidden[j]);')
    (dst/'main.c').write_text(code)
    (dst/'start.S').write_text((ROOT/'src/ui_firmware/start.S').read_text())
    (dst/'linker.ld').write_text('''ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 128K }
SECTIONS {
.text : { KEEP(*(.text.start)) *(.text*) *(.rodata*) } > RAM
.data : { *(.data*) *(.sdata*) } > RAM
.bss (NOLOAD) : { . = ALIGN(4); _sbss = .; *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); _ebss = .; } > RAM
_stack_top = ORIGIN(RAM)+LENGTH(RAM);
ASSERT(SIZEOF(.text)+SIZEOF(.data)<65536,"Benchmark exceeds base ROM")
}
''')
    exe=str(Path(args.zig).resolve())
    subprocess.check_call([exe,'cc','-target','riscv32-freestanding-none','-mcpu=generic_rv32','-mabi=ilp32',
        '-Oz','-ffreestanding','-fno-builtin','-fno-pic','-fno-stack-protector','-fno-unwind-tables',
        '-fno-asynchronous-unwind-tables','-msmall-data-limit=0','-nostdlib','-Wl,-T,linker.ld',
        '-Wl,--gc-sections','-Wl,--build-id=none','start.S','main.c','-o','benchmark.elf'],cwd=str(dst))
    subprocess.check_call([exe,'objcopy','-O','binary','benchmark.elf','benchmark.bin'],cwd=str(dst))
    data=(dst/'benchmark.bin').read_bytes();assert len(data)<65536
    data+=bytes(131072-len(data))
    (dst/'benchmark.hex').write_text(''.join('%08x\n'%int.from_bytes(data[i:i+4],'little') for i in range(0,len(data),4)))
    print('Built scalar RV32I -Oz benchmark, optimized=%s, %d load bytes, same weights/quantization as RTL'%(args.optimized,len((dst/'benchmark.bin').read_bytes())))

if __name__=='__main__':main()
