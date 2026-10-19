/* GT911/GT9147 control ported from piano1/ps/main.c and gt9147_reset.v.
 * Keep controller configuration untouched; select 0x14 with the proven INT
 * reset sequence, probe 0x5D too, use repeated-start and clear status AFTER
 * reading complete 8-byte point records. No synthetic pressure mapping. */
typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef int s32;
#define UI ((volatile u32 *)0x23000000u)
#define UART ((volatile u32 *)0x20000000u)
static u32 lines;
static u8 gt_addr=0x14;
static u16 x_res=800,y_res=480;
static int octave;
static int present;
static int visual_mode;
static int xy_delay=24;
static int slot_note[16];
static u16 control_down;
/* RV32I has no divide instruction; coordinates use this integer helper. */
u32 __udivsi3(u32 n,u32 d){u32 q=0,bit=1;if(!d)return ~0u;
    while(d<=(n>>1)&&!(d&0x80000000u)){d<<=1;bit<<=1;}
    while(bit){if(n>=d){n-=d;q|=bit;}d>>=1;bit>>=1;}return q;}

static u32 now(void){return UI[1];}
static void delay_us(u32 us){u32 start=now();while((u32)(now()-start)<us){}}
static void putc(char c){while(!(UART[1]&1u)){}UART[0]=(u8)c;}
static void puts(const char *s){while(*s)putc(*s++);}
static void hex(u32 v){int i;for(i=28;i>=0;i-=4)putc("0123456789ABCDEF"[(v>>i)&15]);}
static void set_lines(u32 v){lines=v;UI[0]=v;}
static void sda(int low){set_lines((lines&2u)|(low?1u:0u));}
static int scl(int low){u32 start;set_lines((lines&1u)|(low?2u:0u));if(low)return 1;
    start=now();while(!(UI[0]&2u))if((u32)(now()-start)>1000)return 0;return 1;}
static void stop(void){scl(1);sda(1);delay_us(3);scl(0);delay_us(3);sda(0);delay_us(3);}
static int start(void){sda(0);if(!scl(0))return 0;delay_us(3);sda(1);delay_us(3);scl(1);return 1;}
static int write_byte(u8 b){int i,ack;for(i=0;i<8;i++){sda(!(b&0x80));delay_us(2);
    if(!scl(0))return 0;delay_us(3);scl(1);b<<=1;}sda(0);delay_us(2);
    if(!scl(0))return 0;delay_us(3);ack=!(UI[0]&1u);scl(1);return ack;}
static int read_byte(u8 *out,int last){int i;u8 b=0;sda(0);for(i=0;i<8;i++){
    delay_us(2);if(!scl(0))return 0;delay_us(3);b=(u8)((b<<1)|(UI[0]&1u));scl(1);}
    sda(!last);delay_us(2);if(!scl(0))return 0;delay_us(3);scl(1);sda(0);*out=b;return 1;}
static int gt_read(u16 reg,u8 *data,int n){int i,ok=0;
    if(!start()||!write_byte(gt_addr<<1)||!write_byte(reg>>8)||!write_byte(reg))goto done;
    if(!start()||!write_byte((gt_addr<<1)|1))goto done;
    for(i=0;i<n;i++)if(!read_byte(data+i,i==n-1))goto done;ok=1;
done:stop();return ok;}
static int gt_write(u16 reg,u8 value){int ok=start()&&write_byte(gt_addr<<1)&&
    write_byte(reg>>8)&&write_byte(reg)&&write_byte(value);stop();return ok;}
static void bus_recover(void){int i;sda(0);for(i=0;i<9;i++){scl(1);delay_us(5);scl(0);delay_us(5);}stop();}
static void emit(u8 status,u8 d1,u8 d2){u32 t=now();while(!(UI[2]&1u))
    if((u32)(now()-t)>20000)return;UI[3]=((u32)status<<16)|((u32)d1<<8)|d2;}
static void release_all(void){int i,j,n;for(i=0;i<16;i++)if(slot_note[i]>=0){
    n=slot_note[i];emit(0x80,(u8)n,0);
    for(j=i;j<16;j++)if(slot_note[j]==n)slot_note[j]=-1;}control_down=0;}
static void publish(void){UI[5]=((u32)xy_delay<<16)|((u32)visual_mode<<12)|((u32)(octave&15)<<8)|(present?1u:0u);}
static int detect(void){u8 id[4],res[4],cfg[7];int a,r;
    bus_recover();for(r=0;r<3;r++)for(a=0;a<2;a++){
        gt_addr=a?0x5d:0x14;
        if(!gt_read(0x8140,id,4)||id[0]!='9'||id[1]!='1')continue;
        puts("GT found addr=");hex(gt_addr);puts(" id=");
        putc(id[0]);putc(id[1]);putc(id[2]);putc('\r');putc('\n');
        if(gt_read(0x8047,cfg,7)&&(!cfg[0]||cfg[0]==255))
            puts("GT config invalid; preserving controller contents\r\n");
        gt_write(0x8040,0);delay_us(20000);gt_write(0x814e,0);
        if(gt_read(0x8146,res,4)){x_res=res[0]|((u16)res[1]<<8);y_res=res[2]|((u16)res[3]<<8);}
        if(!x_res)x_res=800;if(!y_res)y_res=480;
        puts("GT resolution ");hex(x_res);putc(' ');hex(y_res);
        puts(x_res<=y_res?" SWAP_XY\r\n":" DIRECT\r\n");return 1;
    }puts("GT not found; retrying\r\n");return 0;}
static void control(int x,int y){u32 st=UI[4];int value;
    if(x<640||x>=800)return;
    if(y>=80&&y<120){value=(int)((st>>7)&31u)+(x<720?-1:1);emit(0xb0,27,(u8)(value&31));}
    else if(y>=136&&y<176){value=(int)(st&127u)+(x<720?-5:5);
        if(value<0)value=0;if(value>127)value=127;emit(0xb0,20,(u8)value);}
    else if(y>=192&&y<232){release_all();octave+=x<720?-1:1;
        if(octave< -3)octave=-3;if(octave>3)octave=3;publish();}
    else if(y>=248&&y<288){release_all();emit(0xb0,64,0);emit(0xb0,123,0);}
    else if(y>=344&&y<384){visual_mode=x<720?0:1;publish();}
    else if(y>=400&&y<440){xy_delay+=x<720?-1:1;
        if(xy_delay<1)xy_delay=1;if(xy_delay>96)xy_delay=96;publish();}
}
static int poll_touch(void){u8 status,d[40];int n,i,b,id,x,y,note;
    int next[16],px[16],py[16];u16 seen=0;u32 raw_x,raw_y,old_mask[4],new_mask[4];
    if(!gt_read(0x814e,&status,1))return -2;
    if(!(status&0x80))return -1; /* No fresh frame means keep current key state. */
    n=status&15;if(n>5){gt_write(0x814e,0);return -2;}
    if(n&&!gt_read(0x814f,d,n*8))return -2;
    /* Commit only a completely read and acknowledged frame. A failed clear
     * must not repeat menu presses or partly change the current chord. */
    if(!gt_write(0x814e,0))return -2;
    for(i=0;i<16;i++){next[i]=-1;px[i]=0;py[i]=0;}
    for(i=0;i<4;i++){old_mask[i]=0;new_mask[i]=0;}
    for(i=0;i<n;i++){
        b=i*8;id=d[b]&15;seen|=(u16)(1u<<id);
        raw_x=d[b+1]|((u32)d[b+2]<<8);raw_y=d[b+3]|((u32)d[b+4]<<8);
        if(x_res<=y_res){x=(int)(raw_y*800/y_res);y=(int)(raw_x*480/x_res);}
        else{x=(int)(raw_x*800/x_res);y=(int)(raw_y*480/y_res);}
        if(x>799)x=799;if(y>479)y=479;
        note=-1;
        if(x>=20&&x<620&&y>=408&&y<460){
            static const u8 whites[15]={0,2,4,5,7,9,11,12,14,16,17,19,21,23,24};
            static const u8 edges[10]={1,2,4,5,6,8,9,11,12,13};
            static const u8 blacks[10]={1,3,6,8,10,13,15,18,20,22};
            int k;note=whites[(x-20)/40];
            if(y<439)for(k=0;k<10;k++)if(x>=20+edges[k]*40-11&&x<20+edges[k]*40+11)note=blacks[k];
            note+=48+octave*12;
        }
        next[id]=note;px[id]=x;py[id]=y;
    }
    /* Compare note sets, not individual fingers: two fingers on the same
     * key share one Note On, and only the final finger sends Note Off.
     * Swapping track IDs or crossing fingers cannot retrigger held notes. */
    for(id=0;id<16;id++){
        note=slot_note[id];if(note>=0)old_mask[note>>5]|=1u<<(note&31);
        note=next[id];if(note>=0)new_mask[note>>5]|=1u<<(note&31);
        slot_note[id]=note;
    }
    for(note=0;note<128;note++){
        u32 bit=1u<<(note&31);i=note>>5;
        if((old_mask[i]&bit)&&!(new_mask[i]&bit))emit(0x80,(u8)note,0);
    }
    for(note=0;note<128;note++){
        u32 bit=1u<<(note&31);i=note>>5;
        if((new_mask[i]&bit)&&!(old_mask[i]&bit))emit(0x90,(u8)note,100);
    }
    for(id=0;id<16;id++)if(seen&(1u<<id)){
        if(next[id]<0&&!(control_down&(1u<<id))){control(px[id],py[id]);control_down|=(u16)(1u<<id);}
    }else control_down&=(u16)~(1u<<id);
    return n;
}
int main(void){int i,result,errors=0;u32 retry=0;
    for(i=0;i<16;i++)slot_note[i]=-1;
    lines=0;UI[0]=0;publish();puts("ACG720 138K FM RGB/GT UI ready\r\n");
    while(!(UI[0]&0x100u)){} /* Exact 177 ms reset/synchronization in RTL. */
    delay_us(10000);present=detect();publish();
    for(;;){if(present){result=poll_touch();if(result!=-2)errors=0;
        else if(result==-2&&++errors>=40){puts("GT I2C lost\r\n");release_all();present=0;publish();retry=now();}}
        else if((u32)(now()-retry)>500000u){retry=now();present=detect();publish();}
        delay_us(2000);
    }
}
