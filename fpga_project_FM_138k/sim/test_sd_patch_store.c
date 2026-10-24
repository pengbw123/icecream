/* Native test executes the production firmware's SD protocol, FAT32 parser,
 * CRCs and redundant records against an SPI card model and fragmented volume. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef uint8_t u8;typedef uint16_t u16;typedef uint32_t u32;typedef int32_t s32;
#define SD_STORE_TEST
static u8 sd_fast,selected,absent,corrupt_read,torn_write;
static u32 clock_us;
static u32 now(void){return ++clock_us;}
static void delay_us(u32 n){clock_us+=n;}
static void sd_select(u8 s);
static u8 sd_xfer(u8 v);
#include "../src/ui_firmware/sd_patch_store.h"
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL line %d: %s (%s)\n",__LINE__,#x,sd_message);exit(1);}}while(0)
#define SECTORS 150000u
static u8 model_spc=1;
static u8 *disk;
static u8 packet[6],queue[520],write_buffer[514];
static unsigned packet_n,queue_n,queue_pos,write_n,write_state;
static u32 write_lba;
static unsigned writes;
static u8 idle=1;
static void sd_select(u8 s){selected=s;if(!s){packet_n=queue_n=queue_pos=write_state=0;}}
static void response(u8 c){queue[queue_n++]=c;}
static u8 sd_xfer(u8 v){u8 r;unsigned i;u32 arg;
    clock_us+=10;
    if(!selected||absent)return 255;
    if(queue_pos<queue_n){r=queue[queue_pos++];return r;}
    if(write_state){
        if(write_state==1){if(v==254){write_state=2;write_n=0;}return 255;}
        write_buffer[write_n++]=v;
        if(write_n==514){u16 crc=0;for(i=0;i<512;i++)crc=sd_crc16(crc,write_buffer[i]);
            CHECK(crc==sd_u16((u8[]){write_buffer[513],write_buffer[512]}));
            CHECK(write_lba<SECTORS);memcpy(disk+write_lba*512,write_buffer,torn_write?128:512);
            writes++;write_state=0;queue_n=queue_pos=0;response(5);response(0);response(255);}
        return 255;
    }
    if(!packet_n&&(v&0xc0)!=0x40)return 255;
    packet[packet_n++]=v;
    if(packet_n<6)return 255;
    packet_n=0;queue_n=queue_pos=0;arg=((u32)packet[1]<<24)|((u32)packet[2]<<16)|((u32)packet[3]<<8)|packet[4];
    switch(packet[0]&63){
        case 0:CHECK(packet[5]==0x95);idle=1;response(1);break;
        case 8:CHECK(packet[5]==0x87);response(1);response(0);response(0);response(1);response(0xaa);break;
        case 55:response(idle);break;
        case 41:idle=0;response(0);break;
        case 58:response(0);response(0xc0);response(0xff);response(0x80);response(0);break;
        case 17:{u16 crc=0;CHECK(arg<SECTORS);response(0);response(255);response(254);
            for(i=0;i<512;i++){u8 b=disk[arg*512+i];crc=sd_crc16(crc,b);response(b);}
            response(crc>>8);response((u8)crc^(corrupt_read?1:0));break;}
        case 24:response(0);write_state=1;write_lba=arg;break;
        case 13:response(0);response(0);break;
        default:CHECK(0);
    }
    return 255;
}
static u32 cluster_sector(u32 c){return 2048+32+1200+(c-2)*model_spc;}
static void fat(u32 c,u32 next){sd_put32(disk+(2048+32)*512+c*4,next);sd_put32(disk+(2048+632)*512+c*4,next);}
static void volume_spc(u8 spc){u8 *p;unsigned i;model_spc=spc;
    memset(disk,0,SECTORS*512u);p=disk;p[510]=0x55;p[511]=0xaa;p[450]=12;sd_put32(p+454,2048);sd_put32(p+458,70000*spc);
    p=disk+2048*512; p[11]=0;p[12]=2;p[13]=spc;p[14]=32;p[16]=2;
    sd_put32(p+32,70000*spc);sd_put32(p+36,600);sd_put32(p+44,2);p[510]=0x55;p[511]=0xaa;
    fat(2,0x0fffffff);p=disk+cluster_sector(2)*512;memcpy(p,"FMUSER  BIN",11);p[11]=32;p[26]=5;sd_put32(p+28,8704);
    for(i=0;i<17;i++)fat(5+3*i,i==16?0x0fffffff:8+3*i);
    p=disk+cluster_sector(5)*512;memcpy(p,"FMUSER1",8);sd_put32(p+8,1);sd_put32(p+12,8);sd_put32(p+16,260);sd_put32(p+508,sd_crc32(p,508));
}
static void volume(void){volume_spc(1);}
int main(void){u8 payload[260],out[260];u32 first,second;unsigned i,before;
    u16 known_crc=0;
    CHECK(sd_crc32((const u8 *)"123456789",9)==0xcbf43926u);
    for(i=0;i<9;i++)known_crc=sd_crc16(known_crc,(u8)"123456789"[i]);CHECK(known_crc==0x31c3);
    disk=calloc(SECTORS,512);CHECK(disk);volume();CHECK(sd_mount());
    for(i=0;i<17;i++)CHECK(sd_lba[i]==cluster_sector(5+3*i));
    CHECK(sd_slot(0,out,0));for(i=0;i<260;i++)CHECK(!out[i]);
    for(i=0;i<260;i++)payload[i]=(u8)(i*7);CHECK(sd_slot(0,payload,1));CHECK(sd_slot(0,out,0));CHECK(!memcmp(out,payload,260));
    first=sd_lba[1];second=sd_lba[2];CHECK(sd_u32(disk+first*512+8)==1);
    payload[42]^=123;CHECK(sd_slot(0,payload,1));CHECK(sd_u32(disk+second*512+8)==2);
    CHECK(sd_slot(0,out,0));CHECK(!memcmp(out,payload,260));
    disk[second*512+80]^=1;CHECK(sd_slot(0,out,0));CHECK(out[42]!=(payload[42]));
    CHECK(sd_slot(0,payload,1));torn_write=1;payload[10]^=0x21;CHECK(!sd_slot(0,payload,1));torn_write=0;
    CHECK(sd_slot(0,out,0));CHECK(out[10]!=payload[10]);
    // Both damaged copies reject a load; unrelated slot is still untouched.
    disk[first*512+50]^=1;disk[second*512+50]^=1;CHECK(!sd_slot(0,out,0));CHECK(sd_slot(7,out,0));
    corrupt_read=1;CHECK(!sd_mount());corrupt_read=0;
    absent=1;before=writes;CHECK(!sd_mount());CHECK(writes==before);absent=0;
    volume();fat(8,8);CHECK(!sd_mount());CHECK(writes==before);
    volume();disk[cluster_sector(5)*512]^=1;CHECK(!sd_mount());CHECK(writes==before);
    volume();CHECK(sd_mount());for(i=0;i<8;i++){payload[0]=i;CHECK(sd_slot(i,payload,1));}
    CHECK(sd_mount());for(i=0;i<8;i++){CHECK(sd_slot(i,out,0));CHECK(out[0]==i);}
    volume_spc(2);CHECK(sd_mount());for(i=0;i<17;i++)CHECK(sd_lba[i]==cluster_sector(5+3*(i/2))+i%2);
    CHECK(sd_slot(7,payload,1));CHECK(sd_slot(7,out,0));CHECK(!memcmp(out,payload,260));
    volume();disk[2048*512+40]=0x81;fat(8,8); // Break both then repair active FAT #1 only.
    sd_put32(disk+(2048+632)*512+8*4,11);CHECK(sd_mount());
    volume();memmove(disk,disk+2048*512,70000*512);CHECK(sd_mount());CHECK(sd_lba[0]==cluster_sector(5)-2048);
    puts("PASS SD SPI init/CRC16, FAT32 fragmented mapping, eight slots, CRC32, alternating copies, torn write recovery, corrupt file/chain/no card rejection");
    free(disk);return 0;
}
