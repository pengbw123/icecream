"""Verify the UI's 96KiB address window with 48KiB sparse physical DATA RAM."""
import argparse,struct
from pathlib import Path

def check(path):
    data=Path(path).read_bytes();assert data[:6]==b'\x7fELF\x01\x01','Expected little-endian ELF32'
    off=struct.unpack_from('<I',data,32)[0];size,count,strings=struct.unpack_from('<HHH',data,46)
    sections=[struct.unpack_from('<10I',data,off+i*size) for i in range(count)]
    tab=sections[strings];names=data[tab[4]:tab[4]+tab[5]]
    byname={names[s[0]:].split(b'\0')[0].decode():s for s in sections};symbols={}
    for s in sections:
        if s[1]!=2:continue
        st=sections[s[6]];text=data[st[4]:st[4]+st[5]]
        for at in range(s[4],s[4]+s[5],s[9]):
            name,value,sz,info,other,idx=struct.unpack_from('<IIIBBH',data,at)
            symbols[text[name:].split(b'\0')[0].decode()]=value
    bss=byname['.bss'];image=max(s[3]+s[5] for name,s in byname.items() if name in ('.text','.rodata','.data'))
    assert 0x10020000<=bss[3]<=bss[3]+bss[5]<=0x10030000,'BSS must use low-data alias'
    assert (bss[3]&0x1ffff)+bss[5]<=byname['.rodata'][3]-0x10000000,'BSS would overwrite constants'
    assert image-0x10000000<=81920,'Instruction ROM overflow'
    assert bss[5]<=16384,'Sparse UI data RAM: BSS exceeds 16KiB'
    assert byname['.rodata'][3]>=0x10010000,'Sparse UI data RAM: constants below high bank'
    assert byname['.data'][3]>=0x10010000,'Sparse UI data RAM: initialized data below high bank'
    stack=0x10018000-image;assert stack>=12288,'Stack headroom below 12KiB'
    print('PASS UI layout: {} image bytes, {} BSS bytes in data alias, {} stack bytes; constants/instructions isolated'.format(image-0x10000000,bss[5],stack))

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('elf');args=ap.parse_args();check(args.elf)
