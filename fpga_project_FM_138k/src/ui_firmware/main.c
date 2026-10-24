/* GT911/GT9147 control ported from piano1/ps/main.c and gt9147_reset.v.
 * Keep controller configuration untouched; select 0x14 with the proven INT
 * reset sequence, probe 0x5D too, use repeated-start and clear status AFTER
 * reading complete 8-byte point records. No synthetic pressure mapping.
 *
 * Phase 1 adds the on-device professional menu: a character-cell page engine
 * that writes the RTL character layer, reads live patch parameters through
 * UART command 0x69 and edits them through the normal 0x60..0x64 commands.
 * The instrument menu layout and shared touch geometry are in menu_layout.h. */
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
static int display_auto_gain=1;
static int xy_delay=24;
static u8 touch_velocity=100, headphone_select=0,glide_on=0,arp_on;
static int slot_note[16];
static u16 control_down;
static int control_x[16],control_y[16];
/* RV32I has no divide instruction; coordinates use this integer helper. */
u32 __udivsi3(u32 n,u32 d){u32 q=0,bit=1;if(!d)return ~0u;
    while(d<=(n>>1)&&!(d&0x80000000u)){d<<=1;bit<<=1;}
    while(bit){if(n>=d){n-=d;q|=bit;}d>>=1;bit>>=1;}return q;}
int __divsi3(int a,int b){u32 q;int neg=0;u32 ua,ub;
    if(a<0){ua=(u32)(-a);neg^=1;}else ua=(u32)a;
    if(b<0){ub=(u32)(-b);neg^=1;}else ub=(u32)b;
    q=__udivsi3(ua,ub);return neg?-(int)q:(int)q;}
u32 __umodsi3(u32 n,u32 d){u32 r=0;int i;if(!d)return 0;
    for(i=31;i>=0;i--){r=(r<<1)|((n>>i)&1u);if(r>=d)r-=d;}return r;}
int __modsi3(int a,int b){unsigned ua,ub,r;
    if(!b)return 0;
    ua=(a<0)?(unsigned)(-a):(unsigned)a;
    ub=(b<0)?(unsigned)(-b):(unsigned)b;
    r=__umodsi3(ua,ub);
    return (a<0)?-(int)r:(int)r;}
/* Shift-add multiply: the RV32I core has no M extension and the C compiler
   emits libcalls for some non-power-of-two products used by the EG scaling. */
u32 __mulsi3(u32 a,u32 b){u32 r=0;while(b){if(b&1u)r+=a;a<<=1;b>>=1;}return r;}

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
/* Release every sounding note.  Deliberately does NOT clear control_down:
 * doing so made a still-held finger look like a brand-new press, so a single
 * OCTAVE tap stepped repeatedly and page switches could re-enter the menu. */
static void release_all(void){int i,j,n;for(i=0;i<16;i++)if(slot_note[i]>=0){
    n=slot_note[i];emit(0x80,(u8)n,0);
    for(j=i;j<16;j++)if(slot_note[j]==n)slot_note[j]=-1;}}

/* ------------------------------------------------------------------ */
/* Menu state                                                          */
/* ------------------------------------------------------------------ */
#define PAGE_PERF 0
#define PAGE_ALGO 1
#define PAGE_OSC  2
#define PAGE_LESSON 9
#define PAGE_ARP 10
#define PAGE_SEQ 11
#define PAGE_METRICS 12
static void seq_stop(void);
static u8 seq_is_active(void);
static void seq_publish(void);
static void seq_poll(void);
static void seq_adj(u8 row,int d);
static void arp_adj(u8 row,int d);
static void arp_poll(void);
static void draw_lesson_status(void);
static void lesson_poll(void);
static u8 page;
static u8 op_enabled[6];
static u8 bg_pick=3, accent_pick=0, patch_dirty, dialog, eg_mode;
static void request_rom(u8 n);
static void page_enter(u8 p);
static void adj_setup(u8 r,int d);
static u8 sel_row;
static u8 sel_op;            /* protocol index: 0 = OP6 ... 5 = OP1 */
static u8 held_id=0xFF;
static u8 held_kind;          /* 1 minus, 2 plus, 3 row drag */
static u8 held_row;
static int held_x;
static u32 held_t;
static u32 held_count;

static void publish(void){UI[5]=((u32)((page==3&&eg_mode)?8:page)<<24)|
    (display_auto_gain?0u:0x80000000u)|((u32)xy_delay<<16)|
    ((u32)(visual_mode==2)<<14)|((u32)headphone_select<<13)|((u32)(visual_mode==1)<<12)|((u32)(octave&15)<<8)|(present?1u:0u);}

/* Performance-page controls, hit boxes shared with draw_perf_controls(). */
static void draw_status(void);
static void draw_perf_controls(void);
static void c_at(u8 col,u8 row,u8 ch,u8 pal,u8 attr);
static u32 ctrl_last[9];
static u8 ctrl_hold, ctrl_hold_id;
static u32 ctrl_hold_t, ctrl_hold_count;
static u32 last_adj;
static int vol_local=5, preset_local=0;
static u8 status_preset(u32 st){return (u8)(((st>>7)&31u)|((st>>17)&96u));}
static u8 status_voices(u32 st){return (u8)(((st>>17)&31u)|((st>>19)&224u));}
/* k: 1 preset-, 2 preset+, 3 volume-, 4 volume+, 5 octave-, 6 octave+,
   7 xy-, 8 xy+.  Single tap = one step; repeat starts after 1.5 s. */
static void perf_step(u8 k){
    if(k==1||k==2){
        request_rom((u8)((preset_local+(k==1?127:1))&127));
    } else if(k==3||k==4){
        int v=vol_local+((k==3)?-5:5);
        if(v<0)v=0;if(v>127)v=127;vol_local=v;
        emit(0xb0,20,(u8)v);draw_status();draw_perf_controls();
    } else if(k==5||k==6){
        release_all();octave+= (k==5)?-1:1;
        if(octave< -3)octave=-3;if(octave>3)octave=3;
        publish();draw_status();draw_perf_controls();
    } else if(k==7||k==8){
        xy_delay+= (k==7)?-1:1;
        if(xy_delay<1)xy_delay=1;if(xy_delay>96)xy_delay=96;
        publish();draw_perf_controls();
    }
}
static void perf_control(int x,int y,u8 id);
static void perf_repeat(void){
    u32 dt;
    if(!ctrl_hold)return;
    dt=(u32)(now()-ctrl_hold_t);
    if(dt>1500000u){
        u32 n=1u+(dt-1500000u)/150000u;
        if(n>ctrl_hold_count&&n<100u){ctrl_hold_count=n;perf_step(ctrl_hold);}
    }
}
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

/* ------------------------------------------------------------------ */
/* Character layer helpers.  Cell word = {attr,palette,char}.          */
/* ------------------------------------------------------------------ */
static void cell(u16 a,u8 ch,u8 pal,u8 attr){UI[6]=(u32)(a&0xFFFu)|
    ((u32)(attr&15u)<<28)|((u32)(pal&15u)<<24)|((u32)ch<<16);}
static void c_at(u8 col,u8 row,u8 ch,u8 pal,u8 attr){
    cell((u16)(((u16)row<<7)|(col&127u)),ch,pal,attr);}
static void fill_cells(u8 c0,u8 c1,u8 row,u8 pal,u8 attr){
    for(;c0<=c1;c0++)c_at(c0,row,0,pal,attr);}
static void text(u8 col,u8 row,const char*s,u8 pal,u8 attr){
    while(*s&&col<100){c_at(col,row,(u8)*s,pal,attr);col++;s++;}}
static void text_r(u8 endcol,u8 row,const char*s,u8 pal,u8 attr){
    u8 n=0;while(s[n]&&n<40)n++;text((u8)(endcol-n),row,s,pal,attr);}
static void clear_all(void){u8 r,c;for(r=0;r<30;r++)for(c=0;c<100;c++)c_at(c,r,0,0,0);}
static char nb[8];
static const char* u3d(u32 v){nb[0]=(char)('0'+(v/100u)%10u);nb[1]=(char)('0'+(v/10u)%10u);nb[2]=(char)('0'+v%10u);nb[3]=0;return nb;}
static const char* u2d(u32 v){nb[0]=(char)('0'+((v/10u)%10u));nb[1]=(char)('0'+(v%10u));nb[2]=0;return nb;}
static const char* u1d(u32 v){nb[0]=(char)('0'+(v%10u));nb[1]=0;return nb;}
static const char* sgn1(int v){
    u32 n=(u32)(v<0?-v:v);u8 k=0;nb[k++]=v<0?'-':'+';
    if(n>=10u)nb[k++]=(char)('0'+(n/10u)%10u);
    nb[k++]=(char)('0'+n%10u);nb[k]=0;return nb;
}
static const char* curve_name(u8 c){static const char* n[4]={"-LIN","-EXP","+LIN","+EXP"};return n[c&3u];}

/* ------------------------------------------------------------------ */
/* Patch access                                                        */
/* ------------------------------------------------------------------ */
static void cmd(u8 op,u32 lo,u32 hi){u32 t=now();
    while(!(UI[9]&1u))if((u32)(now()-t)>20000u)return;
    UI[7]=lo;UI[8]=hi;UI[9]=op;}
static u16 rd(u16 addr){u32 t;cmd(0x69,(u32)addr,0);t=now();
    while(!(UI[15]&1u))if((u32)(now()-t)>5000u)return 0xFFFFu;
    {u16 v=(u16)(UI[14]&0xFFFFu);UI[15]=0;return v;}}
/* MIDI and readback travel through separate queues. Wait for the mode change
 * before another tool snapshots/restores it; never mistake a timeout for ON. */
static void set_glide(u8 enable){u32 t;
    emit(0xb0,22,enable?127:0);t=now();
    do{if(rd(0x00c)==(u16)enable)break;}while((u32)(now()-t)<20000u);
    glide_on=enable;
}

static u32 mul32(u32 a,u32 b){u32 r=0;while(b){if(b&1u)r+=a;a<<=1;b>>=1;}return r;}
static u32 mul_small(u32 a,u32 b){return (mul32(a>>16,b)<<16)+mul32(a&0xFFFFu,b);}
static const int detune_delta[15]={-264,-212,-166,-129,-95,-64,-30,0,30,64,95,129,167,212,266};
static const int fixed_detune_delta[15]={0,0,0,0,0,0,0,0,36,73,109,146,182,219,256};
static const u32 fixed_word_table[400]={
  87961,90010,92106,94252,96447,98694,100993,103345,105752,108216,
  110736,113316,115955,118656,121420,124248,127142,130104,133134,136235,
  139409,142656,145979,149379,152859,156419,160063,163791,167606,171510,
  175505,179593,183776,188057,192438,196920,201507,206201,211004,215918,
  220948,226094,231361,236750,242265,247908,253682,259591,265638,271825,
  278157,284636,291266,298050,304993,312097,319367,326806,334418,342208,
  350179,358335,366682,375223,383963,392907,402059,411424,421007,430814,
  440849,451118,461626,472378,483381,494641,506162,517952,530017,542363,
  554996,567923,581152,594689,608541,622716,637221,652063,667252,682794,
  698699,714973,731627,748669,766108,783953,802213,820899,840020,859587,
  879609,900098,921064,942518,964472,986938,1009927,1033451,1057523,1082156,
  1107363,1133156,1159551,1186560,1214199,1242481,1271422,1301037,1331343,1362354,
  1394087,1426559,1459788,1493791,1528586,1564191,1600626,1637909,1676061,1715101,
  1755051,1795932,1837764,1880571,1924375,1969200,2015068,2062005,2110036,2159185,
  2209479,2260944,2313608,2367499,2422645,2479076,2536821,2595911,2656378,2718253,
  2781569,2846360,2912660,2980505,3049930,3120972,3193668,3268058,3344181,3422077,
  3501788,3583355,3666822,3752233,3839634,3929070,4020590,4114242,4210075,4308140,
  4408490,4511176,4616255,4723782,4833813,4946407,5061623,5179524,5300170,5423627,
  5549959,5679235,5811521,5946889,6085410,6227157,6372206,6520634,6672519,6827942,
  6986985,7149733,7316272,7486689,7661077,7839526,8022132,8208992,8400204,8595870,
  8796093,9000980,9210640,9425183,9644724,9869379,10099266,10334508,10575230,10821559,
  11073625,11331563,11595509,11865603,12141988,12424812,12714223,13010375,13313426,13623535,
  13940868,14265592,14597881,14937909,15285858,15641911,16006258,16379092,16760610,17151014,
  17550513,17959317,18377643,18805713,19243755,19691999,20150685,20620055,21100358,21591848,
  22094787,22609440,23136082,23674991,24226452,24790758,25368209,25959111,26563776,27182526,
  27815688,28463599,29126601,29805047,30499296,31209716,31936683,32680584,33441813,34220773,
  35017877,35833548,36668219,37522331,38396339,39290704,40205902,41142418,42100748,43081401,
  44084895,45111764,46162552,47237816,48338126,49464066,50616232,51795236,53001702,54236270,
  55499595,56792347,58115210,59468887,60854096,62271570,63722061,65206338,66725189,68279418,
  69869850,71497328,73162715,74866894,76610768,78395262,80221322,82089916,84002036,85958695,
  87960930,90009803,92106401,94251835,96447242,98693787,100992661,103345082,105752298,108215586,
  110736250,113315629,115955089,118656030,121419884,124248116,127142227,130103750,133134255,136235351,
  139408680,142655925,145978808,149379091,152858577,156419111,160062580,163790917,167606097,171510145,
  175505129,179593169,183776431,188057134,192437548,196919994,201506850,206200547,211003575,215918480,
  220947867,226094404,231360819,236749905,242264519,247907584,253682094,259591109,265637763,271825261,
  278156885,284635991,291266015,298050472,304992959,312097158,319366834,326805844,334418130,342207729,
  350178770,358335482,366682188,375223313,383963387,392907043,402059024,411424181,421007482,430814006,
  440848953,451117644,461625524,472378164,483381265,494640661,506162322,517952357,530017017,542362699,
  554995950,567923466,581152103,594688874,608540958,622715697,637220609,652063384,667251891,682794185,
  698698504,714973283,731627150,748668936,766107676,783952616,802213218,820899164,840020362,859586950
};
static u32 ratio_word(u8 coarse,u8 fine,u8 det){
    u32 base=(coarse==0)?0x8000u:((u32)coarse<<16);
    u32 w=mul_small(base,(u32)(100u+fine))/100u;
    int d=detune_delta[det&15u];
    if(d>0)w+=mul_small(w,(u32)d)>>16;
    else if(d<0)w-=mul_small(w,(u32)(-d))>>16;
    return w;
}
static u32 fixed_word(u8 coarse,u8 fine,u8 det){
    u32 w=fixed_word_table[(((u32)(coarse&3u))*100u)+fine];
    int d=fixed_detune_delta[det&15u];
    if(d>0)w+=mul_small(w>>8,(u32)d)>>8;
    return w;
}
static void decode_ratio(u32 w,u8 det,u8*co,u8*fi){
    int c,f,est;u32 best=0xFFFFFFFFu,bw;
    *co=1;*fi=0;
    for(c=0;c<32;c++){
        u32 base=(c==0)?0x8000u:((u32)c<<16);
        u32 bd=ratio_word((u8)c,0,det);
        u32 wx=ratio_word((u8)c,99,det);
        if(w<bd||w>wx)continue;
        est=(int)(mul_small(w,100u)/bd)-100;
        for(f=est-2;f<=est+2;f++){
            u32 dd;
            if(f<0||f>99)continue;
            bw=ratio_word((u8)c,(u8)f,det);
            dd=(bw>w)?(bw-w):(w-bw);
            if(dd<best){best=dd;*co=(u8)c;*fi=(u8)f;}
        }
    }
}
static void decode_fixed(u32 w,u8 det,u8*co,u8*fi){
    int c,f,d=fixed_detune_delta[det&15u];u32 target=w,best=0xFFFFFFFFu,bw;
    if(d>0)target-=mul_small(w>>8,(u32)d)>>8;
    *co=0;*fi=0;
    for(c=0;c<4;c++)for(f=0;f<100;f++){
        u32 dd;
        bw=fixed_word_table[c*100+f];
        dd=(bw>target)?(bw-target):(target-bw);
        if(dd<best){best=dd;*co=(u8)c;*fi=(u8)f;}
    }
}

/* Global patch cache */
static u8 g_algo,g_fb,g_sync,g_lsync,g_trans,g_wave,g_speed,g_delay,g_pmd,g_amd,g_pms;
static u16 g_flags[3];
/* Selected operator cache */
static u8 o_en,o_fx,o_det,o_lvl,o_rs,o_vel,o_ams,o_bp,o_ld,o_rd,o_lc,o_rc,o_coarse,o_fine,o_eg0r;
static u8 o_rate[4],o_lev[4];
static u16 o_eg0l;
static u32 o_freq;

static u8 rate_from_qrate(u8 q);
static u8 qrate_from_rate(u8 r);
static u16 internal_from_level(u8 l);
static u8 level_from_internal(u16 v);
static void load_flags(void){
    g_flags[0]=rd(0x0009u);g_flags[1]=rd(0x000Au);g_flags[2]=rd(0x000Bu);
}
static void load_globals(void){
    u16 v;
    g_algo=(u8)(rd(0x000)&31u);g_fb=(u8)(rd(0x001)&7u);
    v=rd(0x002);g_wave=(u8)((v>>2)&7u);g_lsync=(u8)((v>>1)&1u);g_sync=(u8)(v&1u);
    g_trans=(u8)(rd(0x003)&0x7Fu);g_speed=(u8)(rd(0x004)&0x7Fu);
    g_delay=(u8)(rd(0x005)&0x7Fu);g_pmd=(u8)(rd(0x006)&0x7Fu);
    g_amd=(u8)(rd(0x007)&0x7Fu);g_pms=(u8)(rd(0x008)&7u);
}
static void load_op(u8 op){
    u16 a=(u16)(0x040u+(u16)op*0x20u);u16 v;
    v=rd(a);o_en=(u8)(v&1u);op_enabled[op]=o_en;o_fx=(u8)((v>>1)&1u);o_det=(u8)((v>>2)&15u);
    o_freq=(u32)rd((u16)(a+1u));o_freq|=((u32)rd((u16)(a+2u))<<16);
    o_lvl=(u8)(rd((u16)(a+3u))&0xFFu);
    o_bp=(u8)(rd((u16)(a+4u))&0x7Fu);o_ld=(u8)(rd((u16)(a+5u))&0x7Fu);
    o_rd=(u8)(rd((u16)(a+6u))&0x7Fu);
    v=rd((u16)(a+7u));o_lc=(u8)(v&3u);o_rc=(u8)((v>>2)&3u);
    v=rd((u16)(a+8u));o_ams=(u8)((v>>6)&3u);o_vel=(u8)((v>>3)&7u);o_rs=(u8)(v&7u);
    o_eg0r=(u8)(rd((u16)(a+9u))&0x3Fu);o_eg0l=rd((u16)(a+13u));
    {u8 s;for(s=0;s<4;s++){
        o_rate[s]=rate_from_qrate((u8)(rd((u16)(a+9u+s))&0x3Fu));
        o_lev[s]=level_from_internal(rd((u16)(a+13u+s)));
    }}
    if(o_fx)decode_fixed(o_freq,o_det,&o_coarse,&o_fine);
    else decode_ratio(o_freq,o_det,&o_coarse,&o_fine);
}
static void send_global(void){
    u32 lo=(u32)g_algo|((u32)g_fb<<8)|((u32)g_sync<<11)|((u32)g_lsync<<12)|
            ((u32)g_trans<<16)|((u32)g_wave<<24);
    u32 hi=(u32)g_speed|((u32)g_delay<<8)|((u32)g_pmd<<16)|((u32)g_amd<<24);
    cmd(0x60,lo,hi);cmd(0x61,(u32)g_pms,0);
}
static void send_op(void){
    u32 freq=o_fx?fixed_word(o_coarse,o_fine,o_det):ratio_word(o_coarse,o_fine,o_det);
    u32 lo,hi;
    o_freq=freq;
    lo=(u32)sel_op|((u32)o_en<<8)|((u32)o_fx<<9)|((u32)o_det<<10)|(1u<<14)|
       ((freq&0xFFFFu)<<16);
    hi=((freq>>16)&0xFFFFu)|((u32)o_lvl<<16);
    cmd(0x62,lo,hi);
}
static void send_eg0(void){
    u32 lo=(u32)sel_op|((u32)o_eg0r<<16);
    u32 hi=(u32)o_eg0l|((u32)o_rs<<16)|((u32)o_vel<<24)|((u32)o_ams<<28);
    cmd(0x63,lo,hi);
}
static void send_scaling(void){
    u32 lo=(u32)sel_op|((u32)o_bp<<8)|((u32)o_ld<<16)|((u32)o_rd<<24);
    u32 hi=(u32)o_lc|((u32)o_rc<<8);
    cmd(0x64,lo,hi);
}

/* ------------------------------------------------------------------ */
/* Page drawing                                                        */
/* ------------------------------------------------------------------ */
#include "../generated/fm_preset_names.h"
static const char*const tab_names[8]={"PLAY","ALGO","OSC","EG","LFO","FX","PATCH","SETUP"};
static void apply_theme(u8 t);
static void draw_tabs(void);
static char cur_name[11];
static void draw_status(void);

/* Two-cell-tall button with a single glyph in the upper row (the old version
   drew the same "-"/"+" twice and looked like two separate buttons). */

static void draw_perf_controls(void);
static void draw_perf(void);
static void draw_header(void);
/* One value column and one selection bar for every parameter page.  The old
   per-row 56x16 px +/- cells were removed: they were easy to miss and easy to
   hit on the neighbouring row.  Editing now happens on the big bottom bar. */




/* ALGORITHM routing diagram: firmware rasterises a 512x256 2bpp canvas and
   uploads it through UI[20]/UI[21]; RTL only displays the bitmap. */
static u8 map_buf[32768];
static u8 algo_map_dirty;
static void map_clear(void){u32 i;for(i=0;i<32768u;i++)map_buf[i]=0;}
static void map_px(u16 x,u16 y,u8 c){
    u32 idx;u16 b;u8 sh;
    if(x>=512u||y>=256u)return;
    idx=(((u32)y)<<9)+x; b=(u16)(idx>>2); sh=(u8)((idx&3u)<<1);
    map_buf[b]=(u8)((map_buf[b]&(u8)~(3u<<sh))|(u8)(c<<sh));
}
static void map_hline(u16 x0,u16 x1,u16 y,u8 c){
    u16 x;if(y>=256u)return;
    if(x0>511u)x0=511u;if(x1>511u)x1=511u;
    if(x0>x1){u16 t=x0;x0=x1;x1=t;}
    for(x=x0;x<=x1;x++)map_px(x,y,c);
}
static void map_vline(u16 x,u16 y0,u16 y1,u8 c){
    u16 y;if(x>511u)return;
    if(y0>255u)y0=255u;if(y1>255u)y1=255u;
    if(y0>y1){u16 t=y0;y0=y1;y1=t;}
    for(y=y0;y<=y1;y++)map_px(x,y,c);
}
static void map_frame(u16 x0,u16 y0,u16 x1,u16 y1,u8 c){
    map_hline(x0,x1,y0,c);map_hline(x0,x1,y1,c);
    map_vline(x0,y0,y1,c);map_vline(x1,y0,y1,c);
}
static void map_fill(u16 x0,u16 y0,u16 x1,u16 y1,u8 c){
    u16 x,y;
    if(x0>511u)x0=511u;if(x1>511u)x1=511u;
    if(y0>255u)y0=255u;if(y1>255u)y1=255u;
    if(x0>x1){u16 t=x0;x0=x1;x1=t;}
    if(y0>y1){u16 t=y0;y0=y1;y1=t;}
    for(y=y0;y<=y1;y++)for(x=x0;x<=x1;x++)map_px(x,y,c);
}
static void map_arrow_r(u16 x,u16 y,u8 c){
    map_px(x,y,c);
    map_px((u16)(x-1u),(u16)(y-1u),c);map_px((u16)(x-1u),(u16)(y+1u),c);
    map_px((u16)(x-2u),(u16)(y-2u),c);map_px((u16)(x-2u),(u16)(y+2u),c);
}
static void map_arrow_l(u16 x,u16 y,u8 c){
    map_px(x,y,c);
    map_px((u16)(x+1u),(u16)(y-1u),c);map_px((u16)(x+1u),(u16)(y+1u),c);
    map_px((u16)(x+2u),(u16)(y-2u),c);map_px((u16)(x+2u),(u16)(y+2u),c);
}
static u16 algo_ax[6],algo_ay[6],algo_out_x;
static void map_digit(u16 cx,u16 cy,u8 n,u8 c){
    u8 pat[5],r,k;
    switch(n){
        case 1:pat[0]=2;pat[1]=6;pat[2]=2;pat[3]=2;pat[4]=7;break;
        case 2:pat[0]=7;pat[1]=1;pat[2]=7;pat[3]=4;pat[4]=7;break;
        case 3:pat[0]=7;pat[1]=1;pat[2]=7;pat[3]=1;pat[4]=7;break;
        case 4:pat[0]=5;pat[1]=5;pat[2]=7;pat[3]=1;pat[4]=1;break;
        case 5:pat[0]=7;pat[1]=4;pat[2]=7;pat[3]=1;pat[4]=7;break;
        default:pat[0]=7;pat[1]=4;pat[2]=7;pat[3]=5;pat[4]=7;break;
    }
    for(r=0;r<5;r++)for(k=0;k<3;k++)if(pat[r]&(4u>>k)){
        u16 x=(u16)(cx-3u+k*2u),y=(u16)(cy-5u+r*2u);
        map_px(x,y,c);map_px((u16)(x+1u),y,c);
        map_px(x,(u16)(y+1u),c);map_px((u16)(x+1u),(u16)(y+1u),c);
    }
}
static u8 algo_carrier[6],algo_ncarrier;

/* Dexed-style operator diagram: carriers green on the bottom row, modulators
   blue above them, lines show modulation, the bottom row feeds an OUT rail.
   The bus contributions are simulated in OP6..OP1 order to recover the real
   modulation graph from the 48-bit routing flags. */
static void build_algo_map(void){
    u8 f[6],b1[6],b2[6],n1=0,n2=0,dep[6],es[32],ed[32],ne=0,i,k,pass,d;
    u8 car[6],nc=0,order[6];
    map_clear();
    for(i=0;i<6;i++){f[i]=(u8)((g_flags[i>>1]>>((i&1u)*8u))&0xFFu);dep[i]=0;}
    for(i=0;i<6;i++){
        u8 in=(f[i]>>4)&3u,dest=f[i]&3u,add=(f[i]>>2)&1u;
        if(in==1u){for(k=0;k<n1;k++){if(ne<32u){es[ne]=b1[k];ed[ne]=i;ne++;}}}
        else if(in==2u){for(k=0;k<n2;k++){if(ne<32u){es[ne]=b2[k];ed[ne]=i;ne++;}}}
        if(dest==1u){if(add){if(n1<6u)b1[n1++]=i;}else{n1=0;b1[n1++]=i;}}
        else if(dest==2u){if(add){if(n2<6u)b2[n2++]=i;}else{n2=0;b2[n2++]=i;}}
    }
    for(pass=0;pass<8u;pass++)
        for(k=0;k<ne;k++)
            if(dep[es[k]]<dep[ed[k]]+1u)dep[es[k]]=(u8)(dep[ed[k]]+1u);
    /* A modulator whose bus is overwritten before any reader has no edge;
       still give it a row so it always gets a valid position. */
    for(i=0;i<6;i++)if((f[i]&3u)!=0u&&dep[i]==0u)dep[i]=1;
    for(i=6;i>0;i--){u8 op=(u8)(i-1u);if((f[op]&3u)==0u)car[nc++]=op;}
    algo_ncarrier=nc;
    if(nc==1u){algo_ax[car[0]]=233;}
    else{
        u16 gap=(u16)((440u-26u)/(nc-1u));if(gap>92u)gap=92u;
        u16 x0=(u16)(26u+(414u-gap*(nc-1u))/2u);
        for(i=0;i<nc;i++)algo_ax[car[i]]=(u16)(x0+i*gap);
    }
    for(i=0;i<nc;i++){algo_carrier[i]=car[i];algo_ay[car[i]]=206;}
    for(d=1;d<=5u;d++){
        u8 n=0;
        for(i=0;i<6;i++)if(dep[i]==d)order[n++]=i;
        if(!n)continue;
        for(i=0;i<n;i++){
            u8 op=order[i];u16 sx=0;u8 cnt=0;
            for(k=0;k<ne;k++)if(es[k]==op&&dep[ed[k]]<d){sx+=algo_ax[ed[k]];cnt++;}
            algo_ax[op]=cnt?(u16)(sx/cnt):256;
            algo_ay[op]=(u8)(206u-d*34u);
        }
        for(i=0;i<n;i++)for(k=(u8)(i+1u);k<n;k++){
            u8 a=order[i],b=order[k];
            if(algo_ax[a]>algo_ax[b]||
               (algo_ax[a]==algo_ax[b]&&(6u-a)>(6u-b))){order[i]=b;order[k]=a;}
        }
        {int minx=26;for(i=0;i<n;i++){u8 op=order[i];
            if(algo_ax[op]<minx)algo_ax[op]=(u16)minx;minx=algo_ax[op]+76;}}
        {int lo=999,hi=-999,sh=0;
         for(i=0;i<n;i++){if(algo_ax[order[i]]<lo)lo=algo_ax[order[i]];
                          if(algo_ax[order[i]]>hi)hi=algo_ax[order[i]];}
         if(hi>440)sh=440-hi;if(lo+sh<26)sh=26-lo;
         for(i=0;i<n;i++)algo_ax[order[i]]=(u16)(algo_ax[order[i]]+sh);}
    }
    for(i=0;i<6;i++){
        u16 cx=algo_ax[i],cy=algo_ay[i],c=((f[i]&3u)==0u)?1u:2u;
        map_fill((u16)(cx-22u),(u16)(cy-14u),(u16)(cx+22u),(u16)(cy+14u),c);
        map_frame((u16)(cx-22u),(u16)(cy-14u),(u16)(cx+22u),(u16)(cy+14u),3);
    }
    for(k=0;k<ne;k++){
        u8 s=es[k],tt=ed[k];
        u16 sx=algo_ax[s],sy=algo_ay[s],tx=algo_ax[tt],ty=algo_ay[tt];
        u16 mid=(u16)((sy+ty)/2u);
        map_vline(sx,(u16)(sy+14u),mid,3);
        map_hline(sx,tx,mid,3);
        map_vline(tx,mid,(u16)(ty-14u),3);
    }
    for(i=0;i<6;i++)if(((f[i]>>6)&3u)==3u){
        u16 cx=algo_ax[i],cy=algo_ay[i];
        /* large right-angle feedback loop: right, up, back into the box */
        map_hline((u16)(cx+22u),(u16)(cx+46u),(u16)(cy+12u),3);
        map_vline((u16)(cx+46u),(u16)(cy+12u),(u16)(cy-16u),3);
        map_hline((u16)(cx+24u),(u16)(cx+46u),(u16)(cy-16u),3);
        map_arrow_l((u16)(cx+24u),(u16)(cy-16u),3);
    }
    for(i=0;i<6;i++)map_digit(algo_ax[i],algo_ay[i],(u8)(6-i),3);
    {u16 minx=511,maxx=0;
     for(i=0;i<nc;i++){u16 cx=algo_ax[car[i]];map_vline(cx,220,238,3);
         if(cx<minx)minx=cx;if(cx>maxx)maxx=cx;}
     if(nc){map_hline(minx,maxx,238,3);algo_out_x=maxx;}}
}
static void upload_algo_map(void){
    u32 i;
    UI[23]=0u;
    for(i=0;i<8192u;i++){
        u32 w=(u32)map_buf[i*4u]|((u32)map_buf[i*4u+1u]<<8)|
              ((u32)map_buf[i*4u+2u]<<16)|((u32)map_buf[i*4u+3u]<<24);
        UI[24]=w;
    }
    UI[22]=1u;
}
/* ------------------------------------------------------------------ */
/* FX page (phase 3).  Registers live in audio_fx.v; command 0x70 writes   */
/* and 0x69 addresses 0x200+addr read them back.                          */
/* ------------------------------------------------------------------ */
static u16 fx_regs[32];
static u8 fx_sel;              /* selected effect 0..5 */

static u8 fx_load_n(u8 reg){     /* read with clamping, 0xFFFF -> 0 */
    u16 v=rd((u16)(0x200u+reg));
    if(v==0xFFFFu)v=0;
    return (u8)(v>99u?99u:(u8)v);
}
static void load_fx(void){
    u8 i;
    for(i=0;i<25;i++)fx_regs[i]=fx_load_n(i);
}
static void fx_write(u8 reg,u16 val){
    if(reg<25u){fx_regs[reg]=val;cmd(0x70,(u32)reg|((u32)val<<8),0);}
}
static const u8 fx_en_reg[6]  ={1,21,17,5,9,13};
static const u8 fx_type_reg[6]={2,22,0xFF,0xFF,0xFF,0xFF};
static const u8 fx_p_reg[6][3]={
    {3,4,0xFF},       /* FILTER: cutoff,Q */
    {23,24,0xFF},     /* REVERB: decay,mix */
    {19,18,20},       /* DELAY: time,decay,mix */
    {6,7,8},          /* DIST: gain,tone,wet mix */
    {10,11,12},       /* CHORUS */
    {14,15,16}        /* PHASER */
};
static const char*const fx_names[6]={"FILTER","REVERB","DELAY","DIST","CHORUS","PHASER"};
static const char*const fx_p_names[6][3]={
    {"CUTOFF","Q",""},
    {"DECAY","MIX",""},
    {"TIME","DECAY","MIX"},
    {"GAIN","TONE","MIX"},
    {"FREQ","DEPTH","MIX"},
    {"FREQ","DEPTH","MIX"}
};
static const char*const filter_type_names[3]={"LOW PASS","BAND","HIGH PASS"};
static const char*const reverb_type_names[3]={"ROOM","HALL","PLATE"};

static void draw_fx(void);
static void draw_algo(void);
static void draw_osc(void);
/* DX7 helpers shared by the EG page.  The patch stores a 6-bit qrate and a
   16-bit internal level; the UI works in the familiar 0..99 units. */
static const u8 dx7_low_levels[20]={0,5,9,13,17,20,23,25,27,29,31,33,35,37,39,41,42,43,45,46};
static const char*const lfo_wave_names[6]={"TRI","SAW D","SAW U","SQR","SIN","S&H"};
static u8 qrate_from_rate(u8 r){return (u8)(((u32)r*41u)>>6);}
static u8 rate_from_qrate(u8 q){u32 r=(((u32)q*64u)+40u)/41u;if(r>99u)r=99u;return (u8)r;}
static u16 internal_from_level(u8 l){
    u32 s;if(l>=20u)s=28u+l;else s=dx7_low_levels[l];
    return (u16)((s>>1)<<6);
}
static u8 level_from_internal(u16 v){
    u32 s=(u32)((v>>6)<<1);int i,bl=0;u32 bd=0xFFFFFFFFu;
    if(s>=48u){u32 l=s-28u;if(l>99u)l=99u;return (u8)l;}
    for(i=0;i<20;i++){
        u32 d=internal_from_level((u8)i);
        d=(d>v)?(d-v):(v-d);
        if(d<bd){bd=d;bl=i;}
    }
    return (u8)bl;
}

/* ------------------------------------------------------------------ */
/* Pitch EG, user slots and patch name (phase 2b)                      */
/* ------------------------------------------------------------------ */
static const signed char pitch_units_tab[100]={
    -128, -116, -104, -95, -85, -76, -68, -61, -56, -52,
    -49, -46, -43, -41, -39, -37, -35, -33, -32, -31,
    -30, -29, -28, -27, -26, -25, -24, -23, -22, -21,
    -20, -19, -18, -17, -16, -15, -14, -13, -12, -11,
    -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
    10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
    20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
    30, 31, 32, 33, 34, 35, 38, 40, 43, 46,
    49, 53, 58, 65, 73, 82, 92, 103, 115, 127,
};
static const unsigned short pitch_rate_tab[100]={
    1, 2, 3, 3, 4, 4, 5, 5, 6, 6,
    7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
    12, 12, 13, 13, 14, 14, 15, 16, 16, 17,
    18, 18, 19, 20, 21, 22, 23, 24, 25, 26,
    27, 28, 30, 31, 33, 34, 36, 37, 38, 39,
    41, 42, 44, 46, 47, 49, 51, 53, 54, 56,
    58, 60, 62, 64, 66, 68, 70, 72, 74, 76,
    79, 82, 85, 88, 91, 94, 98, 102, 106, 110,
    115, 120, 125, 130, 135, 141, 147, 153, 159, 165,
    171, 178, 185, 193, 202, 211, 232, 243, 254, 255,
};

/* eg_mode: 0 = operator amp EG, 1 = pitch EG; declared with UI state. */
static u8 p_rate[4],p_lev[4];
static u8 name_pos,slot_sel;
static u8 last_preset=0;
static void draw_page(void);
static const char name_chars[]="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.- ";
#define NAME_CHAR_COUNT 39

static u8 pitch_rate_from_coeff(u16 c){
    int i,best=0;u32 bd=0xFFFFFFFFu;
    for(i=0;i<100;i++){
        u32 d=((u32)pitch_rate_tab[i]>c)?((u32)pitch_rate_tab[i]-c):((u32)c-pitch_rate_tab[i]);
        if(d<bd){bd=d;best=i;}
    }
    return (u8)best;
}
static u8 pitch_level_from_units(s32 u){
    int i,best=0;u32 bd=0xFFFFFFFFu;
    for(i=0;i<100;i++){
        s32 d=(s32)pitch_units_tab[i]-u;
        u32 ad=(d<0)?(u32)(-d):(u32)d;
        if(ad<bd){bd=ad;best=i;}
    }
    return (u8)best;
}
static void load_pitch(void){
    u8 s;
    for(s=0;s<4;s++){
        u16 a=(u16)(0x140u+s*8u);u32 t;
        p_rate[s]=pitch_rate_from_coeff((u16)(rd(a)&0xFFu));
        t=(u32)rd((u16)(a+1u))|((u32)rd((u16)(a+2u))<<16);
        if(t&0x400000u)t|=0xFF800000u;
        p_lev[s]=pitch_level_from_units(((s32)t)>>15);
    }
}
static void send_pitch_stage(u8 s){
    u32 lo=(u32)s|((u32)pitch_rate_tab[p_rate[s]]<<8);
    s32 target=((s32)pitch_units_tab[p_lev[s]])<<15;
    cmd(0x65,lo|(((u32)target&255u)<<24),((u32)target&0x7FFFFFu)>>8);
}
static void adj_pitch(u8 row,int d){
    int v;
    if(row<4){v=(int)p_rate[row]+d;if(v<0)v=0;if(v>99)v=99;p_rate[row]=(u8)v;send_pitch_stage(row);}
    else {v=(int)p_lev[row-4]+d;if(v<0)v=0;if(v>99)v=99;p_lev[row-4]=(u8)v;send_pitch_stage((u8)(row-4));}
    draw_page();
}
static void name_from_preset(u8 pr){
    u8 i;pr&=127u;
    for(i=0;i<10&&preset_names[pr][i];i++)cur_name[i]=preset_names[pr][i];
    cur_name[i]=0;
}
static void name_cycle(int d){
    char c=cur_name[name_pos];u8 i,idx=0;
    for(i=0;i<NAME_CHAR_COUNT;i++)if(name_chars[i]==c){idx=i;break;}
    idx=(u8)((idx+(d>0?1:NAME_CHAR_COUNT-1))%NAME_CHAR_COUNT);
    cur_name[name_pos]=name_chars[idx];
}
/* User slots keep the complete parameter image: 9 globals, 6x17 operator
   words and 12 pitch-EG words, read through 0x69 and written back through
   0x60/0x62/0x63/0x64/0x65. */
#define SLOT_MAGIC 0x5A5Au
struct slot_t {u16 magic;char name[11];u16 globals[9];u16 op[6][17];u16 pitch[12];};
static struct slot_t slots[8];
static void slot_read_all(struct slot_t *s){
    u8 i,j;
    s->magic=SLOT_MAGIC;
    for(i=0;i<11;i++)s->name[i]=cur_name[i];
    for(i=0;i<9;i++)s->globals[i]=rd((u16)i);
    for(i=0;i<6;i++){
        u16 a=(u16)(0x040u+(u16)i*0x20u);
        for(j=0;j<17;j++)s->op[i][j]=rd((u16)(a+j));
    }
    for(i=0;i<4;i++){
        u16 a=(u16)(0x140u+(u16)i*8u);
        s->pitch[i*3+0]=rd(a);
        s->pitch[i*3+1]=rd((u16)(a+1u));
        s->pitch[i*3+2]=rd((u16)(a+2u));
    }
}
static void slot_save(void){
    if(slot_sel>7u)slot_sel=0;
    slot_read_all(&slots[slot_sel]);
    draw_page();
}
static void slot_load(void){
    struct slot_t *s;
    u8 i,j;
    if(slot_sel>7u)slot_sel=0;
    s=&slots[slot_sel];
    if(s->magic!=SLOT_MAGIC)return;
    {
        u16 g2=s->globals[2];
        u32 lo=(u32)(s->globals[0]&31u)|((u32)(s->globals[1]&7u)<<8)|
               ((u32)(g2&1u)<<11)|((u32)((g2>>1)&1u)<<12)|
               ((u32)(s->globals[3]&0x7Fu)<<16)|((u32)((g2>>2)&7u)<<24);
        u32 hi=(u32)(s->globals[4]&0x7Fu)|((u32)(s->globals[5]&0x7Fu)<<8)|
               ((u32)(s->globals[6]&0x7Fu)<<16)|((u32)(s->globals[7]&0x7Fu)<<24);
        cmd(0x60,lo,hi);cmd(0x61,(u32)(s->globals[8]&7u),0);
    }
    for(i=0;i<6;i++){
        u16 w0=s->op[i][0];u32 freq=(u32)s->op[i][1]|((u32)s->op[i][2]<<16);
        u32 lo=(u32)i|((u32)(w0&1u)<<8)|((u32)((w0>>1)&1u)<<9)|
               ((u32)((w0>>2)&15u)<<10)|(1u<<14)|((freq&0xFFFFu)<<16);
        u32 hi=((freq>>16)&0xFFFFu)|((u32)s->op[i][3]<<16);
        cmd(0x62,lo,hi);
        for(j=0;j<4;j++){
            u32 elo=(u32)i|((u32)j<<8)|((u32)(s->op[i][9+j]&0x3Fu)<<16);
            u32 ehi=(u32)s->op[i][13+j]|((u32)(s->op[i][8]&7u)<<16)|
                    ((u32)((s->op[i][8]>>3)&7u)<<24)|((u32)((s->op[i][8]>>6)&3u)<<28);
            cmd(0x63,elo,ehi);
        }
        {
            u16 cw=s->op[i][7];
            u32 slo=(u32)i|((u32)(s->op[i][4]&0x7Fu)<<8)|
                    ((u32)(s->op[i][5]&0x7Fu)<<16)|((u32)(s->op[i][6]&0x7Fu)<<24);
            u32 shi=(u32)(cw&3u)|((u32)((cw>>2)&3u)<<8);
            cmd(0x64,slo,shi);
        }
    }
    for(i=0;i<4;i++){
        u32 target=(u32)s->pitch[i*3+1]|((u32)(s->pitch[i*3+2]&0x7Fu)<<16);
        cmd(0x65,(u32)i|((u32)(s->pitch[i*3+0]&0xFFu)<<8)|((target&255u)<<24),(target&0x7FFFFFu)>>8);
    }
    for(i=0;i<11;i++)cur_name[i]=s->name[i];
    cur_name[10]=0;
    if(page==1||page==4)load_globals();
    else if(page==2){load_op(sel_op);}
    else if(page==3){load_op(sel_op);if(eg_mode)load_pitch();}
    draw_page();
}
static void eg_rebuild(void){
    u16 i;u32 wt[4];u16 bx[5],lv[5];u32 total=0;
    if(eg_mode==0u){
        for(i=0;i<4;i++){
            u32 s=99u-o_rate[i];wt[i]=4u+(s*s)/10u;
            lv[i+1]=(u16)(((u32)o_lev[i]*255u)/99u);
        }
        lv[0]=0;
    }else{
        for(i=0;i<4;i++){
            u32 s=99u-p_rate[i];wt[i]=4u+(s*s)/10u;
            lv[i+1]=(u16)(((u32)p_lev[i]*255u)/99u);
        }
        lv[0]=(u16)((50u*255u)/99u);
    }
    for(i=0;i<4;i++){if(wt[i]<4u)wt[i]=4u;total+=wt[i];}
    bx[0]=0;
    for(i=0;i<4;i++){
        u32 v=(u32)bx[i]+(((u32)wt[i]*256u)/total);
        if(v>256u)v=256u;
        if(v<=bx[i])v=(u32)bx[i]+4u;
        if(v>256u)v=256u;
        bx[i+1]=(u16)v;
    }
    bx[4]=256;
    for(i=0;i<256;i++){
        u8 s=0;u32 tt,h,w;
        while(s<3&&i>=bx[s+1])s++;
        w=(u32)bx[s+1]-bx[s];if(w==0u)w=1u;
        tt=(u32)(i-bx[s]);
        {s32 d=(s32)lv[s+1]-(s32)lv[s];
         h=(u32)lv[s]+(u32)((d*(s32)tt)/(s32)w);}
        if(h>255u)h=255u;
        UI[18]=i;UI[19]=(u8)h;
    }
}
static u8 eg6_rate[6][4],eg6_lev[6][4];
static u8 eg6_buf[768];
static void load_all_eg(void){
    u8 op,s;
    for(op=0;op<6;op++){
        u16 a=(u16)(0x040u+(u16)op*0x20u);
        for(s=0;s<4;s++){
            eg6_rate[op][s]=rate_from_qrate((u8)(rd((u16)(a+9u+s))&0x3Fu));
            eg6_lev[op][s]=level_from_internal(rd((u16)(a+13u+s)));
        }
    }
}
static void build_eg6_panel(u8 op,u8 panel){
    u16 i;u32 wt[4];u16 bx[5],lv[5];u32 total=0;
    for(i=0;i<4;i++){
        u32 s=99u-eg6_rate[op][i];
        wt[i]=4u+(s*s)/10u;
        lv[i+1]=(u16)(((u32)eg6_lev[op][i]*255u)/99u);
    }
    lv[0]=0;
    for(i=0;i<4;i++){if(wt[i]<4u)wt[i]=4u;total+=wt[i];}
    bx[0]=0;
    for(i=0;i<4;i++){
        u32 v=(u32)bx[i]+(((u32)wt[i]*128u)/total);
        if(v<=bx[i])v=(u32)bx[i]+2u;
        if(v>128u)v=128u;
        bx[i+1]=(u16)v;
    }
    bx[4]=128;
    for(i=0;i<128;i++){
        u8 s=0;u32 tt,h,w;
        while(s<3&&i>=bx[s+1])s++;
        w=(u32)bx[s+1]-bx[s];if(w==0u)w=1u;
        tt=(u32)(i-bx[s]);
        if(lv[s+1]>=lv[s])
            h=(u32)lv[s]+(((u32)(lv[s+1]-lv[s])*(u32)tt)/w);
        else
            h=(u32)lv[s]-(((u32)(lv[s]-lv[s+1])*(u32)tt)/w);
        if(h>255u)h=255u;
        eg6_buf[(u16)panel*128u+i]=(u8)h;
    }
}
static void build_all_eg(void){u8 p;for(p=0;p<6;p++)build_eg6_panel((u8)(5u-p),p);}
static void upload_eg6(void){
    u16 i;u32 w;
    UI[25]=0;
    for(i=0;i<192u;i++){
        u16 b=(u16)(i*4u);
        w=(u32)eg6_buf[b]|((u32)eg6_buf[b+1]<<8)|
          ((u32)eg6_buf[b+2]<<16)|((u32)eg6_buf[b+3]<<24);
        UI[26]=w;
    }
    UI[27]=1;
}
static void upload_eg6_panel(u8 panel){
    u16 i;u32 w;
    UI[25]=(u32)panel*128u;
    for(i=0;i<32u;i++){
        u16 b=(u16)(panel*128u+i*4u);
        w=(u32)eg6_buf[b]|((u32)eg6_buf[b+1]<<8)|
          ((u32)eg6_buf[b+2]<<16)|((u32)eg6_buf[b+3]<<24);
        UI[26]=w;
    }
}
static void sync_eg6(void){
    u8 i;
    if(eg_mode)return;
    for(i=0;i<4;i++){eg6_rate[sel_op][i]=o_rate[i];eg6_lev[sel_op][i]=o_lev[i];}
    build_eg6_panel(sel_op,(u8)(5u-sel_op));
    upload_eg6_panel((u8)(5u-sel_op));
}
static void draw_eg(void);
static void draw_lfo(void);
static void draw_name(void);
static void draw_theme(void);
static void adj(u8 row,int d);

/* Current raw value and range of the selected row, used by the bottom slider.
   cyc > 0 means a cyclic/toggle row (ON/OFF, wave, curve, type). */
static int get_sel(int *cur,int *lo,int *hi,int *cyc){
    *cyc=0;*lo=0;*hi=99;*cur=0;
    if(page==PAGE_ALGO){
        if(sel_row==0){*cur=g_algo;*hi=31;}
        else if(sel_row==1){*cur=g_fb;*hi=7;}
        else if(sel_row==2){*cur=g_sync;*hi=1;*cyc=2;}
        else if(sel_row==3){*cur=g_trans;*hi=48;}
        else return 0;
        return 1;
    }
    if(page==PAGE_OSC){
        switch(sel_row){
            case 0:*cur=o_fx;*cyc=2;break;
            case 1:*cur=o_coarse;*hi=o_fx?3:31;break;
            case 2:*cur=o_fine;break;
            case 3:*cur=o_det;*hi=14;break;
            case 4:*cur=o_lvl;break;
            case 5:*cur=o_rs;*hi=7;break;
            case 6:*cur=o_vel;*hi=7;break;
            case 7:*cur=o_ams;*hi=3;break;
            case 8:*cur=o_bp;break;
            case 9:*cur=o_ld;break;
            case 10:*cur=o_rd;break;
            case 11:*cur=o_lc;*cyc=4;break;
            case 12:*cur=o_rc;*cyc=4;break;
            case 13:*cur=o_en;*cyc=2;break;
            default:return 0;
        }
        return 1;
    }
    if(page==3){
        if(eg_mode){if(sel_row<4)*cur=p_rate[sel_row];else *cur=p_lev[sel_row-4];}
        else {if(sel_row<4)*cur=o_rate[sel_row];else *cur=o_lev[sel_row-4];}
        return sel_row<8;
    }
    if(page==4){
        switch(sel_row){
            case 0:*cur=g_wave;*cyc=6;break;
            case 1:*cur=g_speed;break;
            case 2:*cur=g_delay;break;
            case 3:*cur=g_pmd;break;
            case 4:*cur=g_amd;break;
            case 5:*cur=g_pms;*hi=7;break;
            case 6:*cur=g_lsync;*cyc=2;break;
            case 7:*cur=g_sync;*cyc=2;break;
            default:return 0;
        }
        return 1;
    }
    if(page==5){
        u8 sel=fx_sel%6u;
        if(sel_row==0){*cur=(u8)(fx_regs[0]&1u);*cyc=2;}
        else if(sel_row==1){*cur=(u8)(fx_regs[fx_en_reg[sel]]&1u);*cyc=2;}
        else if(sel_row==2){
            u8 tr=fx_type_reg[sel];
            if(tr==0xFFu)return 0;
            *cur=(u8)(fx_regs[tr]%3u);*cyc=3;
        }else if(sel_row<6){
            u8 pr=fx_p_reg[sel][sel_row-3u];
            if(pr==0xFFu)return 0;
            *cur=(u8)(fx_regs[pr]&0x7Fu);
        }else return 0;
        return 1;
    }
    if(page==7){
        if(sel_row==0){*cur=bg_pick;*hi=3;*cyc=4;}
        else if(sel_row==1){*cur=accent_pick;*hi=4;*cyc=5;}
        else if(sel_row==2){*cur=visual_mode;*hi=2;*cyc=3;}
        else if(sel_row==3){*cur=xy_delay;*lo=1;*hi=96;}
        else if(sel_row==4){*cur=display_auto_gain;*hi=1;*cyc=2;}
        else if(sel_row==5){*cur=touch_velocity;*lo=1;*hi=127;}
        else if(sel_row==6){*cur=headphone_select;*hi=1;*cyc=2;}
        else if(sel_row==8){*cur=glide_on;*hi=1;*cyc=2;}
        else return 0;return 1;
    }
    return 0;
}

static void slider_apply(int x){
    int cur,lo,hi,cyc,t,target,d,n;
    if(!get_sel(&cur,&lo,&hi,&cyc))return;
    t=(x-336)*99/(704-336);
    if(t<0)t=0;if(t>99)t=99;
    if(cyc>0){
        target=(t*cyc)/100;if(target>=cyc)target=cyc-1;
        n=cyc;d=((target-cur)%n+n)%n;if(d>n/2)d-=n;
    }else{
        target=lo+(t*(hi-lo)+49)/99;
        d=target-cur;
    }
    if(d)adj(sel_row,d);
}

/* Big bottom bar, rows 27..29: minus, slider, plus.  Only drawn on parameter
   pages; PERFORM/NAME/UTIL keep their own controls. */
static void draw_bottom(void);
static void draw_page(void);
static void page_enter(u8 p);

/* ------------------------------------------------------------------ */
/* Editing                                                             */
/* ------------------------------------------------------------------ */
static void adj_op(u8 row,int d);
static void adj_algo(u8 row,int d){
    int v;
    if(row==0){v=(int)g_algo+d;if(v<0)v=0;if(v>31)v=31;g_algo=(u8)v;send_global();}
    else if(row==1){v=(int)g_fb+d;if(v<0)v=0;if(v>7)v=7;g_fb=(u8)v;send_global();}
    else if(row==2){g_sync=(u8)(g_sync?0:1);send_global();}
    else {v=(int)g_trans+d;if(v<0)v=0;if(v>48)v=48;g_trans=(u8)v;send_global();}
    if(row<3u){load_flags();algo_map_dirty=1;}
    draw_page();
}
static void adj_op(u8 row,int d){
    int v;
    if(row==0){o_fx=(u8)(o_fx?0:1);o_coarse=0;o_fine=0;send_op();draw_page();return;}
    if(row==1){
        v=(int)o_coarse+d;
        if(o_fx){if(v<0)v=0;if(v>3)v=3;}
        else {if(v<0)v=0;if(v>31)v=31;}
        o_coarse=(u8)v;send_op();draw_page();return;
    }
    if(row==2){v=(int)o_fine+d;if(v<0)v=0;if(v>99)v=99;o_fine=(u8)v;send_op();draw_page();return;}
    if(row==3){v=(int)o_det+d;if(v<0)v=0;if(v>14)v=14;o_det=(u8)v;send_op();draw_page();return;}
    if(row==4){v=(int)o_lvl+d;if(v<0)v=0;if(v>99)v=99;o_lvl=(u8)v;send_op();draw_page();return;}
    if(row==5){v=(int)o_rs+d;if(v<0)v=0;if(v>7)v=7;o_rs=(u8)v;send_eg0();draw_page();return;}
    if(row==6){v=(int)o_vel+d;if(v<0)v=0;if(v>7)v=7;o_vel=(u8)v;send_eg0();draw_page();return;}
    if(row==7){v=(int)o_ams+d;if(v<0)v=0;if(v>3)v=3;o_ams=(u8)v;send_eg0();draw_page();return;}
    if(row==8){v=(int)o_bp+d;if(v<0)v=0;if(v>99)v=99;o_bp=(u8)v;send_scaling();draw_page();return;}
    if(row==9){v=(int)o_ld+d;if(v<0)v=0;if(v>99)v=99;o_ld=(u8)v;send_scaling();draw_page();return;}
    if(row==10){v=(int)o_rd+d;if(v<0)v=0;if(v>99)v=99;o_rd=(u8)v;send_scaling();draw_page();return;}
    if(row==11){v=(int)o_lc+d;if(v<0)v=0;if(v>3)v=3;o_lc=(u8)v;send_scaling();draw_page();return;}
    if(row==12){v=(int)o_rc+d;if(v<0)v=0;if(v>3)v=3;o_rc=(u8)v;send_scaling();draw_page();return;}
    if(row==13){o_en=(u8)(o_en?0:1);op_enabled[sel_op]=o_en;send_op();draw_page();return;}
}

static void send_eg_stage(u8 s){
    u32 lo=(u32)sel_op|((u32)s<<8)|((u32)qrate_from_rate(o_rate[s])<<16);
    u32 hi=(u32)internal_from_level(o_lev[s])|((u32)o_rs<<16)|((u32)o_vel<<24)|((u32)o_ams<<28);
    cmd(0x63,lo,hi);
}
static void adj_eg(u8 row,int d){
    int v;
    if(row<4){
        v=(int)o_rate[row]+d;
        if(v<0)v=0;if(v>99)v=99;
        o_rate[row]=(u8)v;send_eg_stage(row);
    }else{
        v=(int)o_lev[row-4]+d;
        if(v<0)v=0;if(v>99)v=99;
        o_lev[row-4]=(u8)v;send_eg_stage((u8)(row-4));
    }
    draw_page();
}
static void adj_lfo(u8 row,int d){
    int v;
    if(row==0){v=((int)g_wave+d+6)%6;g_wave=(u8)v;}
    else if(row==1){v=(int)g_speed+d;if(v<0)v=0;if(v>99)v=99;g_speed=(u8)v;}
    else if(row==2){v=(int)g_delay+d;if(v<0)v=0;if(v>99)v=99;g_delay=(u8)v;}
    else if(row==3){v=(int)g_pmd+d;if(v<0)v=0;if(v>99)v=99;g_pmd=(u8)v;}
    else if(row==4){v=(int)g_amd+d;if(v<0)v=0;if(v>99)v=99;g_amd=(u8)v;}
    else if(row==5){v=(int)g_pms+d;if(v<0)v=0;if(v>7)v=7;g_pms=(u8)v;}
    else if(row==6){g_lsync=(u8)(g_lsync?0:1);}
    else {g_sync=(u8)(g_sync?0:1);}
    send_global();
    draw_page();
}
static void adj_fx(u8 row,int d){
    u8 sel=fx_sel%6u;int v;
    if(row==0){fx_write(0,(u16)(fx_regs[0]^1u));}
    else if(row==1){fx_write(fx_en_reg[sel],(u16)(fx_regs[fx_en_reg[sel]]^1u));}
    else if(row==2){
        u8 tr=fx_type_reg[sel];
        if(tr!=0xFFu){v=((int)fx_regs[tr]+d+3)%3;fx_write(tr,(u16)v);}
    }else{
        u8 pr=fx_p_reg[sel][row-3u];
        if(pr!=0xFFu){v=(int)fx_regs[pr]+d;if(v<0)v=0;if(v>99)v=99;fx_write(pr,(u16)v);}
    }
    draw_page();
}

/* First pixel row of the editable list (ALGO/OSC start below the title/OP row). */

static void adj(u8 row,int d){
    if(page>=1&&page<=4)patch_dirty=1;
    if(page==PAGE_SEQ){seq_adj(row,d);return;}
    if(page==PAGE_ARP){arp_adj(row,d);return;}
    if(page==7){adj_setup(row,d);return;}
    if(page==PAGE_ALGO){adj_algo(row,d);load_flags();}
    else if(page==3){if(eg_mode)adj_pitch(row,d);else adj_eg(row,d);sync_eg6();}
    else if(page==4)adj_lfo(row,d);
    else if(page==5)adj_fx(row,d);
    else adj_op(row,d);
}
static int menu_press(int x,int y);
static void menu_repeat(void){
    if(page==PAGE_PERF||held_id==0xFF)return;
    if(held_kind==1||held_kind==2){
        u32 dt=(u32)(now()-held_t);
        /* Single tap = one step.  Continuous stepping starts only after a
           deliberate 1.5 s hold, then repeats every 150 ms. */
        if(dt>1500000u){
            u32 n=1u+(dt-1500000u)/150000u;
            if(n>held_count&&n<40u){held_count=n;adj(held_row,held_kind==1?-1:1);}
        }
    }
}

/* ------------------------------------------------------------------ */
/* Touch polling                                                       */
/* ------------------------------------------------------------------ */
#include "menu_layout.h"

static int poll_touch(void){u8 status,d[40];int n,i,b,id,x,y,note;
    int next[16],px[16],py[16];u16 seen=0;u32 raw_x,raw_y,old_mask[4],new_mask[4];
    if(!gt_read(0x814e,&status,1)){return -2;}
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
        if((page==PAGE_PERF||page==PAGE_LESSON||page==PAGE_ARP||page==PAGE_SEQ)&&!dialog&&x>=0&&x<800&&y>=352&&y<480){
            static const u8 whites[15]={0,2,4,5,7,9,11,12,14,16,17,19,21,23,24};
            static const u8 edges[10]={1,2,4,5,6,8,9,11,12,13};
            static const u8 blacks[10]={1,3,6,8,10,13,15,18,20,22};
            int k;note=whites[(x*15)/800];
            if(y<432)for(k=0;k<10;k++)if(x>=(edges[k]*800)/15-16&&x<(edges[k]*800)/15+16)note=blacks[k];
            note+=48+octave*12;
        }
        next[id]=note;px[id]=x;py[id]=y;
    }
    if(page==PAGE_PERF||page==PAGE_LESSON||page==PAGE_ARP||page==PAGE_SEQ){
        /* Compare note sets, not individual fingers: two fingers on the same
         * key share one Note On, and only the final finger sends Note Off. */
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
            if((new_mask[i]&bit)&&!(old_mask[i]&bit))emit(0x90,(u8)note,touch_velocity);
        }
    }
    for(id=0;id<16;id++)if(seen&(1u<<id)){
        /* A redraw/upload can hide an entire release frame. Reused Goodix IDs
         * must not permanently latch a previous menu button. Include vertical
         * motion as well as horizontal motion; preserve deliberate slider drags. */
        if((control_down&(1u<<id))&&!(held_id==(u8)id&&held_kind==3)&&
           (px[id]>control_x[id]+160||px[id]+160<control_x[id]||
            py[id]>control_y[id]+80||py[id]+80<control_y[id])){
            control_down&=(u16)~(1u<<id);held_id=0xFF;held_kind=0;ctrl_hold=0;
        }
        if(!(control_down&(1u<<id))){
            control_down|=(u16)(1u<<id);
            control_x[id]=px[id];control_y[id]=py[id];
            
            if(page==PAGE_LESSON||page==PAGE_ARP||page==PAGE_SEQ){
                if(next[id]<0){held_id=(u8)id;held_kind=0;menu_press(px[id],py[id]);}
            }else if(page==PAGE_PERF){
                if(dialog||py[id]<48){menu_press(px[id],py[id]);}
                else if(next[id]<0)perf_control(px[id],py[id],(u8)id);
            }else{
                held_id=0xFF;held_kind=0;
                if(!dialog&&((page>=1&&page<=5)||page==7)&&py[id]>=432&&px[id]>=256){
                    /* Bottom bar: big minus / slider / big plus. */
                    held_id=(u8)id;held_row=sel_row;held_x=px[id];
                    held_t=now();held_count=0;
                    if(px[id]<320){held_kind=1;adj(sel_row,-1);}
                    else if(px[id]>=720){held_kind=2;adj(sel_row,1);}
                    else {held_kind=3;slider_apply(px[id]);}
                }else{
                    /* Row tap only selects; no per-row +/- anymore. */
                    menu_press(px[id],py[id]);
                }
            }
        }else if(held_id==(u8)id&&held_kind!=0&&held_kind!=3&&
                 (px[id]>held_x+160||px[id]+160<held_x)){
            /* A release frame can be missed while a page redraw is running.
               A large coordinate jump therefore means "new touch"; forget the
               latched row/button so the next frame is processed as a press. */
            held_id=0xFF;held_kind=0;control_down&=(u16)~(1u<<id);
        }else if(page!=PAGE_PERF&&held_id==(u8)id&&held_kind==3){
            /* Dragging the slider continuously updates the selected row. */
            slider_apply(px[id]);
            held_x=px[id];
        }
    }else control_down&=(u16)~(1u<<id);
    if(held_id!=0xFF&&!(seen&(1u<<held_id))){held_id=0xFF;held_kind=0;}
    if(ctrl_hold&&!(seen&(1u<<ctrl_hold_id)))ctrl_hold=0;
    return n;
}


int main(void){int i,result,errors=0;u32 retry=0;u32 last_status=0xFFFFFFFFu;
    for(i=0;i<16;i++)slot_note[i]=-1;
    lines=0;UI[0]=0;
    page=0;sel_row=0;sel_op=5;held_id=0xFF;
    apply_theme(0);
    name_from_preset(0);
    clear_all();
    draw_perf();
    UI[17]=1; /* enable the character layer after the first clear */
    publish();puts("ACG720 138K FM RGB/GT UI ready\r\n");
    while(!(UI[0]&0x100u)){} /* Exact 177 ms reset/synchronization in RTL. */
    delay_us(10000);present=detect();publish();
    for(;;){if(present){result=poll_touch();if(result!=-2)errors=0;
        else if(result==-2&&++errors>=40){puts("GT I2C lost\r\n");release_all();
            control_down=0;ctrl_hold=0;held_id=0xFF;held_kind=0;
            present=0;publish();retry=now();}
        {
            u32 st=UI[4];
            if(st!=last_status){
                last_status=st;
                vol_local=(int)(st&127u);preset_local=(int)status_preset(st);
                draw_status();
                if(page==PAGE_PERF&&!dialog)draw_perf_controls();
            }
        }
        {
            u8 pr=status_preset(UI[4]);
            if(pr!=last_preset){
                last_preset=pr;patch_dirty=0;
                name_from_preset(pr);
                if(page==PAGE_PERF)draw_status();
                else if(page>=1&&page<=4){
                    if(page==PAGE_ALGO){load_globals();load_flags();algo_map_dirty=1;}
                    else if(page==4)load_globals();
                    else {if(page==2)cache_operator_switches();load_op(sel_op);if(page==3){load_all_eg();build_all_eg();upload_eg6();if(eg_mode)load_pitch();}}
                    draw_page();
                }
            }
        }
        menu_repeat();perf_repeat();lesson_poll();arp_poll();seq_poll();metrics_poll();}
        else if((u32)(now()-retry)>500000u){retry=now();present=detect();publish();}
        delay_us(2000);
    }
}














