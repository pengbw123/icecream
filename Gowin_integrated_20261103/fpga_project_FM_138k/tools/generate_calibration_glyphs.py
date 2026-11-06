from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
font_path = r'C:\Windows\Fonts\msyh.ttc'
font = ImageFont.truetype(font_path, 28, index=0)
rows=[]
for ch in '修改完成':
    im=Image.new('1',(32,32),0)
    d=ImageDraw.Draw(im)
    box=d.textbbox((0,0),ch,font=font)
    x=(32-(box[2]-box[0]))//2-box[0]
    y=(32-(box[3]-box[1]))//2-box[1]
    d.text((x,y),ch,font=font,fill=1)
    for yy in range(32):
        word=0
        for xx in range(32): word=(word<<1)|int(im.getpixel((xx,yy))!=0)
        rows.append(f'{word:08x}')
Path('src/generated/calibration_success_32.mem').write_text('\n'.join(rows)+'\n',encoding='ascii')
print('Generated 4 glyphs, 128 rows from Windows Microsoft YaHei, TTC index 0, 28 px, monochrome')
