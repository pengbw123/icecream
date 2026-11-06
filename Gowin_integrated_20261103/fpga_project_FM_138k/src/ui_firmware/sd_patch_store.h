/* SDHC/SDXC SPI + bounded FAT32 access to a PC-created FMUSER.BIN.
 * No FAT allocation or directory writes. File sectors are mapped and checked
 * before writing. Every slot has two CRC32-protected, versioned sectors. */
#ifndef SD_STORE_TEST
#define SDREG ((volatile u32 *)0x26000000u)
static u8 sd_fast;
static void sd_select(u8 selected){SDREG[0]=(selected?0u:1u)|((u32)sd_fast<<1);}
static u8 sd_xfer(u8 v){SDREG[2]=v;while(SDREG[1]&1u){}return (u8)(SDREG[1]>>8);}
#endif
static u8 sd_sector[512],sd_copy[512];
static u32 sd_lba[17],sd_fat,sd_data,sd_clusters,sd_fat_size,sd_spc;
static const char *sd_message="SD: NOT LOADED";
static u16 sd_u16(const u8 *p){return (u16)(p[0]|((u16)p[1]<<8));}
static u32 sd_u32(const u8 *p){return (u32)sd_u16(p)|((u32)sd_u16(p+2)<<16);}
static void sd_put32(u8 *p,u32 v){u8 i;for(i=0;i<4;i++){p[i]=(u8)v;v>>=8;}}
static u32 sd_crc32(const u8 *p,u32 n){u32 c=~0u;u8 i;
    while(n--){c^=*p++;for(i=0;i<8;i++)c=(c>>1)^((0u-(c&1u))&0xedb88320u);}return ~c;}
static u16 sd_crc16(u16 c,u8 v){u8 i;c^=(u16)v<<8;
    for(i=0;i<8;i++)c=(u16)((c<<1)^((c&0x8000u)?0x1021u:0u));return c;}
static void sd_end(void){sd_select(0);sd_xfer(255);}
static int sd_fail(const char *s){sd_message=s;sd_end();return 0;}
static u8 sd_command(u8 cmd,u32 arg){u8 i,r,crc=0,b[5];
    sd_end();sd_select(1);sd_xfer(255);
    b[0]=(u8)(64u|cmd);for(i=0;i<4;i++)b[i+1]=(u8)(arg>>(24-i*8));
    for(i=0;i<5;i++){u8 j;sd_xfer(b[i]);for(j=0;j<8;j++){
        crc<<=1;if((b[i]^(u8)(crc))&128u)crc^=9u;b[i]<<=1;}}
    sd_xfer((u8)((crc<<1)|1u));
    for(i=0;i<16;i++){r=sd_xfer(255);if(!(r&128u))return r;}return 255;
}
static int sd_initialize(void){u8 i,r;u32 echo=0,ocr=0,t;
    sd_fast=0;sd_select(0);delay_us(2000);for(i=0;i<10;i++)sd_xfer(255);
    if(sd_command(0,0)!=1)return sd_fail("SD: NO CARD / INIT ERROR");
    if(sd_command(8,0x1aau)!=1)return sd_fail("SD: SDHC CARD REQUIRED");
    for(i=0;i<4;i++)echo=(echo<<8)|sd_xfer(255);
    if(echo!=0x1aau)return sd_fail("SD: CMD8 ERROR");
    t=now();do{
        r=sd_command(55,0);if(r>1)return sd_fail("SD: CMD55 ERROR");
        r=sd_command(41,0x40000000u);if(r>1)return sd_fail("SD: ACMD41 ERROR");
        if((u32)(now()-t)>2000000u)return sd_fail("SD: INIT TIMEOUT");
    }while(r);
    if(sd_command(58,0))return sd_fail("SD: OCR ERROR");
    for(i=0;i<4;i++)ocr=(ocr<<8)|sd_xfer(255);
    if((ocr&0xc0000000u)!=0xc0000000u||!(ocr&0x00300000u))return sd_fail("SD: SDHC / 3V3 REQUIRED");
    sd_end();sd_fast=1;return 1;
}
static int sd_read(u32 lba,u8 *p){u32 t;u16 i,c=0,got;u8 r;
    if(sd_command(17,lba))return sd_fail("SD: READ COMMAND ERROR");
    t=now();do{r=sd_xfer(255);if((u32)(now()-t)>300000u)return sd_fail("SD: READ TIMEOUT");}while(r==255);
    if(r!=254)return sd_fail("SD: READ TOKEN ERROR");
    for(i=0;i<512;i++){p[i]=sd_xfer(255);c=sd_crc16(c,p[i]);}
    got=(u16)sd_xfer(255)<<8;got|=sd_xfer(255);sd_end();
    if(c!=got)return sd_fail("SD: DATA CRC ERROR");return 1;
}
static int sd_write(u32 lba,const u8 *p){u16 i,c=0;u8 r;u32 t;
    if(sd_command(24,lba))return sd_fail("SD: WRITE COMMAND ERROR");
    sd_xfer(255);sd_xfer(254);
    for(i=0;i<512;i++){sd_xfer(p[i]);c=sd_crc16(c,p[i]);}
    sd_xfer((u8)(c>>8));sd_xfer((u8)c);r=sd_xfer(255);
    if((r&31u)!=5u)return sd_fail("SD: WRITE REJECTED");
    t=now();do{r=sd_xfer(255);if((u32)(now()-t)>1000000u)return sd_fail("SD: WRITE TIMEOUT");}while(r!=255);
    sd_end();if(sd_command(13,0)||sd_xfer(255))return sd_fail("SD: WRITE STATUS ERROR");
    sd_end();return 1;
}
static int sd_cluster_ok(u32 c){return c>=2&&c-2<sd_clusters;}
static u32 sd_cluster_lba(u32 c){return sd_data+(c-2)*sd_spc;}
static u32 sd_next(u32 c){u32 v;
    if(!sd_cluster_ok(c)||!sd_read(sd_fat+c/128u,sd_sector))return 0;
    v=sd_u32(sd_sector+(c%128u)*4u)&0x0fffffffu;return v;
}
static int sd_equal(const u8 *a,const char *b,u32 n){while(n--)if(*a++!=(u8)*b++)return 0;return 1;}
static int sd_mount(void){u32 base=0,limit=~0u,total,res,fats,root,root_count=0,c,file=0,size=0,i,j,flags;
    if(!sd_initialize()||!sd_read(0,sd_sector))return 0;
    if(sd_u16(sd_sector+510)!=0xaa55u)return sd_fail("SD: BAD PARTITION");
    if(sd_u16(sd_sector+11)!=512){
        for(i=0;i<4;i++){u8 *e=sd_sector+446+i*16;
            if(e[4]==11||e[4]==12){base=sd_u32(e+8);limit=sd_u32(e+12);break;}}
        if(!base||!limit||base>~0u-limit||!sd_read(base,sd_sector))return sd_fail("SD: FAT32 REQUIRED");
    }
    sd_spc=sd_sector[13];res=sd_u16(sd_sector+14);fats=sd_sector[16];
    total=sd_u32(sd_sector+32);sd_fat_size=sd_u32(sd_sector+36);flags=sd_u16(sd_sector+40);
    root=sd_u32(sd_sector+44);
    if(sd_u16(sd_sector+510)!=0xaa55u||sd_u16(sd_sector+11)!=512||
       !sd_spc||sd_spc>128||(sd_spc&(sd_spc-1))||!res||(fats!=1&&fats!=2)||
       sd_u16(sd_sector+17)||sd_u16(sd_sector+19)||sd_u16(sd_sector+22)||sd_u16(sd_sector+42)||
       !sd_fat_size||sd_fat_size>0x1fffffu||total>limit||base>~0u-total||
       total<=res+fats*sd_fat_size||((flags&128u)&&(flags&15u)>=fats))return sd_fail("SD: UNSUPPORTED FAT32");
    sd_clusters=(total-res-fats*sd_fat_size)/sd_spc;
    if(sd_clusters<65525||sd_clusters>=0x0ffffff5u||sd_clusters+2>sd_fat_size*128u)
        return sd_fail("SD: BAD FAT GEOMETRY");
    sd_fat=base+res+((flags&128u)?(flags&15u)*sd_fat_size:0u);
    sd_data=base+res+fats*sd_fat_size;
    c=root;
    while(!file){
        if(!sd_cluster_ok(c))return sd_fail("SD: FILE NOT FOUND");
        for(i=0;i<sd_spc&&!file;i++){
            if(++root_count>128)return sd_fail("SD: ROOT TOO LARGE");
            if(!sd_read(sd_cluster_lba(c)+i,sd_sector))return 0;
            for(j=0;j<512;j+=32){u8 *e=sd_sector+j;
                if(!e[0])return sd_fail("SD: NEED FMUSER.BIN");
                if(e[0]!=229&&!(e[11]&0x18u)&&sd_equal(e,"FMUSER  BIN",11)){
                    if(e[11]&1u)return sd_fail("SD: FILE READ ONLY");
                    file=((u32)sd_u16(e+20)<<16)|sd_u16(e+26);size=sd_u32(e+28);break;}}
        }
        if(!file){c=sd_next(c);if(!c)return 0;}
    }
    if(size!=17u*512u)return sd_fail("SD: WRONG BANK SIZE");
    c=file;
    for(i=0;i<17;i++){
        if(!sd_cluster_ok(c))return sd_fail("SD: BROKEN FILE CHAIN");
        sd_lba[i]=sd_cluster_lba(c)+i%sd_spc;
        for(j=0;j<i;j++)if(sd_lba[j]==sd_lba[i])return sd_fail("SD: CYCLIC FILE CHAIN");
        if((i+1)%sd_spc==0&&i!=16){c=sd_next(c);if(!c)return 0;}
    }
    if(!sd_read(sd_lba[0],sd_sector))return 0;
    if(!sd_equal(sd_sector,"FMUSER1",8)||sd_u32(sd_sector+8)!=1||sd_u32(sd_sector+12)!=8||
       sd_u32(sd_sector+16)!=260||sd_u32(sd_sector+508)!=sd_crc32(sd_sector,508))
        return sd_fail("SD: BAD BANK HEADER");
    return 1;
}
static int sd_valid_record(const u8 *p,u8 slot){return sd_equal(p,"FMP1",4)&&sd_u16(p+4)==1&&
    sd_u16(p+6)==slot&&sd_u32(p+12)==260&&sd_u32(p+508)==sd_crc32(p,508);}
/* Read both copies before choosing. No partial slot image reaches the synth. */
static int sd_slot(u8 slot,u8 *payload,u8 store){u8 a,b,latest;u32 seq=0,i,target;
    if(slot>=8||!sd_read(sd_lba[1+slot*2],sd_sector)||!sd_read(sd_lba[2+slot*2],sd_copy))return 0;
    a=(u8)sd_valid_record(sd_sector,slot);b=(u8)sd_valid_record(sd_copy,slot);
    latest=(u8)(b&&(!a||(s32)(sd_u32(sd_copy+8)-sd_u32(sd_sector+8))>0));
    if(a||b)seq=sd_u32((latest?sd_copy:sd_sector)+8);
    if(!store){
        if(!a&&!b){for(i=0;i<512;i++)if(sd_sector[i]||sd_copy[i])return sd_fail("SD: SLOT CRC ERROR");
            for(i=0;i<260;i++)payload[i]=0;return 1;}
        for(i=0;i<260;i++)payload[i]=(latest?sd_copy:sd_sector)[16+i];return 1;
    }
    target=sd_lba[1+slot*2+((a||b)?!latest:0)];
    for(i=0;i<512;i++)sd_sector[i]=0;
    for(i=0;i<4;i++)sd_sector[i]=(u8)"FMP1"[i];
    sd_sector[4]=1;sd_sector[6]=slot;sd_put32(sd_sector+8,seq+1);sd_put32(sd_sector+12,260);
    for(i=0;i<260;i++)sd_sector[16+i]=payload[i];
    sd_put32(sd_sector+508,sd_crc32(sd_sector,508));
    if(!sd_write(target,sd_sector)||!sd_read(target,sd_copy))return 0;
    for(i=0;i<512;i++)if(sd_sector[i]!=sd_copy[i])return sd_fail("SD: VERIFY FAILED");
    return 1;
}
