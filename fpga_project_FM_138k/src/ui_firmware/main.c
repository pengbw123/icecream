/* GT911/GT9147 control ported from piano1/ps/main.c and gt9147_reset.v.
 * Keep controller configuration untouched; select 0x14 with the proven INT
 * reset sequence, probe 0x5D too, use repeated-start and clear status AFTER
 * reading complete 8-byte point records. No synthetic pressure mapping.
 *
 * Phase 1 adds the on-device professional menu: a character-cell page engine
 * that writes the RTL character layer, reads live patch parameters through
 * UART command 0x69 and edits them through the normal 0x60..0x64 commands.
 * Page 0 keeps the original performance screen and its controls untouched. */
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
static int slot_note[16];
static u16 control_down;
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
static u8 page;
static u8 sel_row;
static u8 sel_op;            /* protocol index: 0 = OP6 ... 5 = OP1 */
static u8 held_id=0xFF;
static u8 held_kind;          /* 1 minus, 2 plus, 3 row drag */
static u8 held_row;
static int held_x;
static u32 held_t;
static u32 held_count;

static void publish(void){UI[5]=((u32)(page&15u)<<24)|
    (display_auto_gain?0u:0x80000000u)|((u32)xy_delay<<16)|
    ((u32)visual_mode<<12)|((u32)(octave&15)<<8)|(present?1u:0u);}

/* Performance-page controls, hit boxes shared with draw_perf_controls(). */
static void draw_status(void);
static void draw_perf_controls(void);
static void c_at(u8 col,u8 row,u8 ch,u8 pal,u8 attr);
static u32 ctrl_last[9];
static u8 ctrl_hold, ctrl_hold_id;
static u32 ctrl_hold_t, ctrl_hold_count;
static u32 last_adj;
static int vol_local=96, preset_local=0;
/* k: 1 preset-, 2 preset+, 3 volume-, 4 volume+, 5 octave-, 6 octave+,
   7 xy-, 8 xy+.  Single tap = one step; repeat starts after 1.5 s. */
static void perf_step(u8 k){
    if(k==1||k==2){
        preset_local=(preset_local+(k==1?-1:1)+32)&31;
        emit(0xb0,27,(u8)preset_local);
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
static void perf_control(int x,int y,u8 id){u8 k=0;u32 t=now();
    if(x<640||x>=800)return;
    if(y>=80&&y<112)k=(x<720)?1:2;
    else if(y>=144&&y<176)k=(x<720)?3:4;
    else if(y>=208&&y<240)k=(x<720)?5:6;
    else if(y>=256&&y<272){release_all();emit(0xb0,64,0);emit(0xb0,123,0);return;}
    else if(y>=304&&y<320){visual_mode=x<720?0:1;publish();draw_perf_controls();return;}
    else if(y>=336&&y<352)k=(x<720)?7:8;
    else if(y>=368&&y<384){display_auto_gain=!display_auto_gain;publish();draw_perf_controls();return;}
    if(!k)return;
    /* Debounce: track-id churn used to fire the same button several times per
       physical tap, which made OCTAVE jump straight to -3/+3. */
    if(ctrl_last[k]!=0u&&(u32)(t-ctrl_last[k])<300000u)return;
    ctrl_last[k]=t;
    perf_step(k);
    ctrl_hold=k;ctrl_hold_id=id;ctrl_hold_t=t;ctrl_hold_count=0;
}
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
static const char* u2d(u32 v){nb[0]=(char)('0'+((v/10u)%10u));nb[1]=(char)('0'+(v%10u));nb[2]=0;return nb;}
static const char* u1d(u32 v){nb[0]=(char)('0'+(v%10u));nb[1]=0;return nb;}
static const char* sgn1(int v){nb[0]=v<0?'-':'+';
    nb[1]=(char)('0'+((u32)(v<0?-v:v)%10u));nb[2]=0;return nb;}
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
    v=rd(a);o_en=(u8)(v&1u);o_fx=(u8)((v>>1)&1u);o_det=(u8)((v>>2)&15u);
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
static const char preset_names[32][11]={
    "BRASS   1 ", "BRASS   2 ", "BRASS   3 ", "STRINGS 1 ",
    "STRINGS 2 ", "STRINGS 3 ", "ORCHESTRA ", "PIANO   1 ",
    "PIANO   2 ", "PIANO   3 ", "E.PIANO 1 ", "GUITAR  1 ",
    "GUITAR  2 ", "SYN-LEAD 1", "BASS    1 ", "BASS    2 ",
    "E.ORGAN 1 ", "PIPES   1 ", "HARPSICH 1", "CLAV    1 ",
    "VIBE    1 ", "MARIMBA   ", "KOTO      ", "FLUTE   1 ",
    "ORCH-CHIME", "TUB BELLS ", "STEEL DRUM", "TIMPANI   ",
    "REFS WHISL", "VOICE   1 ", "TRAIN     ", "TAKE OFF  "
};
static const char*const tab_names[8]={"1 PERF","2 ALGO","3 OSC","4 EG","5 LFO","6 FX","7 NAME","8 UTIL"};
static const char*const theme_names[3]={"GRAPHITE","AMBER","ICE"};
/* Palette: 0 bg,1 text,2 dim,3 accent,4 accent2,5 panel,6 button,7 active,
   8 ok,9 warn,10 danger,11 separator,12 dark2,13 header,14 light,15 black. */
static const u32 theme_pal[3][16]={
 {0x0B0B0Cu,0xF2F2F2u,0x6E6E72u,0xFF3B00u,0xFFB000u,0x151517u,0x1E1E22u,0x2A2A30u,
  0x35DFC1u,0xFFB000u,0x733946u,0x24242Au,0x101013u,0x16161Au,0xD8D8DCu,0x000000u},
 {0x0D0C0Au,0xF0E6D2u,0x8A8070u,0xFFA028u,0xFFD060u,0x16140Fu,0x221E16u,0x332B1Eu,
  0x7FD8B0u,0xFFC040u,0x6E3A2Au,0x2A251Cu,0x12100Bu,0x191612u,0xE8DCC4u,0x000000u},
 {0x081014u,0xE6F4F8u,0x6E8A94u,0x2FD8FFu,0x9BE8FFu,0x0E1A20u,0x15262Eu,0x1E3642u,
  0x4FD8A0u,0xFFC040u,0x5A2A3Au,0x1A3038u,0x0A1418u,0x0C181Eu,0xD8E8EEu,0x000000u}
};
static const u32 theme_bg[3]={0x0B0B0Cu,0x0D0C0Au,0x081014u};
static const u32 theme_wave[3]={0xFF3B00u,0xFFA028u,0x2FD8FFu};
static const u32 theme_xy[3]={0xFF6A2Cu,0xFFC040u,0x9BE8FFu};
static u8 theme=0;
static void apply_theme(u8 t){
    u8 i;theme=t;
    for(i=0;i<16;i++)UI[16]=((u32)i<<24)|theme_pal[t][i];
    UI[10]=theme_bg[t];UI[11]=theme_wave[t];UI[12]=theme_xy[t];
}
static void draw_tabs(void){
    u8 i,j;
    for(i=0;i<8;i++){
        u8 base=(u8)(i*12u+1u);
        u8 pal=(page==i)?3u:2u;
        for(j=0;j<11;j++)c_at((u8)(base+j),0,0,pal,1);
        for(j=0;j<10&&tab_names[i][j];j++)c_at((u8)(base+j),0,(u8)tab_names[i][j],pal,1);
    }
    for(i=0;i<100;i++)c_at(i,1,0,12,4);
}
static char cur_name[11];
static void draw_status(void){
    u32 st=UI[4];u16 pidx=(u16)((st>>7)&31u);u8 vol=(u8)(st&127u);
    u8 alg=(u8)((st>>12)&31u);u8 vc=(u8)((st>>17)&31u);
    char buf[40];u8 n=0,i;
    buf[n++]='P';
    buf[n++]=(char)('0'+(((pidx+1u)/10u)%10u));
    buf[n++]=(char)('0'+((pidx+1u)%10u));
    buf[n++]=' ';
    if(cur_name[0])for(i=0;i<10&&cur_name[i];i++)buf[n++]=cur_name[i];
    else for(i=0;i<10&&preset_names[pidx&31u][i];i++)buf[n++]=preset_names[pidx&31u][i];
    buf[n++]=' ';buf[n++]='V';
    buf[n++]=(char)('0'+((vol/100u)%10u));
    buf[n++]=(char)('0'+(((u16)vol/10u)%10u));
    buf[n++]=(char)('0'+(vol%10u));
    buf[n++]=' ';buf[n++]='O';buf[n++]=(octave<0)?'-':'+';
    buf[n++]=(char)('0'+((u32)(octave<0?-octave:octave)%10u));
    buf[n++]=' ';buf[n++]='A';
    buf[n++]=(char)('0'+(((alg+1u)/10u)%10u));
    buf[n++]=(char)('0'+((alg+1u)%10u));
    buf[n++]=' ';buf[n++]=(char)('0'+vc);
    buf[n++]='V';buf[n]=0;
    for(i=0;i<100;i++)c_at((u8)(2+i),2,(u8)(i<n?buf[i]:' '),1,0);
}
static void btn_cells(u8 c0,u8 c1,u8 row,const char*s,u8 pal){
    u8 c,j;u8 n=0;while(s[n])n++;
    for(c=c0;c<=c1;c++)c_at(c,row,0,pal,1);
    for(j=0;j<n&&(u8)(c0+j)<=c1;j++)c_at((u8)(c0+j),row,(u8)s[j],pal,1);
}
/* Two-cell-tall button with a single glyph in the upper row (the old version
   drew the same "-"/"+" twice and looked like two separate buttons). */
static void btn_tall(u8 c0,u8 c1,u8 row,const char*s,u8 pal){
    u8 c,j;u8 n=0;while(s[n])n++;
    for(c=c0;c<=c1;c++){c_at(c,row,0,pal,1);c_at(c,(u8)(row+1),0,pal,1);}
    for(j=0;j<n&&(u8)(c0+j)<=c1;j++)c_at((u8)(c0+j),row,(u8)s[j],pal,1);
}
static void draw_perf_controls(void){
    u32 st=UI[4];u8 vol=(u8)(st&127u);
    text(81,4,"PRESET",2,0);
    btn_tall(81,89,5,"-",2);btn_tall(91,99,5,"+",2);
    text(81,8,"VOLUME",2,0);text_r(99,8,u2d(vol),14,0);
    btn_tall(81,89,9,"-",2);btn_tall(91,99,9,"+",2);
    text(81,12,"OCTAVE",2,0);text_r(99,12,sgn1(octave),14,0);
    btn_tall(81,89,13,"-",2);btn_tall(91,99,13,"+",2);
    btn_cells(81,99,16,"PANIC",2);
    text(81,18,"VIEW",2,0);
    btn_cells(81,89,19,"WAVE",visual_mode?2:3);
    btn_cells(91,99,19,"XY",visual_mode?3:2);
    text(81,20,"XY DELAY",2,0);text_r(99,20,u2d(xy_delay),14,0);
    btn_cells(81,89,21,"-",2);btn_cells(91,99,21,"+",2);
    btn_cells(81,99,23,display_auto_gain?"AUTO ON":"AUTO OFF",2);
}
static void draw_perf(void){
    u8 i;
    for(i=0;i<100;i++)c_at(i,2,0,0,0);
    draw_tabs();
    draw_status();
    draw_perf_controls();
}
static void draw_header(void){
    clear_all();
    draw_tabs();
    text_r(98,29,"V1.1",2,0);
    if(page<1||page>5)text(2,29,"TAP ROW   BOTTOM -/+   SLIDE",2,0);
}
/* One value column and one selection bar for every parameter page.  The old
   per-row 56x16 px +/- cells were removed: they were easy to miss and easy to
   hit on the neighbouring row.  Editing now happens on the big bottom bar. */
#define VALUE_COL 22
static void prow(u8 row,const char*label,const char*val,int selected){
    if(selected){
        fill_cells(2,(u8)(VALUE_COL+2u),row,3,1);
        text(2,row,label,3,1);text_r(VALUE_COL,row,val,3,1);
    }else{
        text(2,row,label,1,0);text_r(VALUE_COL,row,val,1,0);
    }
}
static void prow_eg(u8 row,const char*label,const char*val,int selected){
    prow(row,label,val,selected);
}
static void draw_placeholder(void){
    text(2,4,"PAGE NOT READY",3,0);
    text(2,6,"PHASE 2 ADDS THIS EDITOR",2,0);
    text(2,8,"TABS 1-3 AND 8 ARE ACTIVE",2,0);
}
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
    u16 x;if(x0>x1){u16 t=x0;x0=x1;x1=t;}
    for(x=x0;x<=x1;x++)map_px(x,y,c);
}
static void map_vline(u16 x,u16 y0,u16 y1,u8 c){
    u16 y;if(y0>y1){u16 t=y0;y0=y1;y1=t;}
    for(y=y0;y<=y1;y++)map_px(x,y,c);
}
static void map_frame(u16 x0,u16 y0,u16 x1,u16 y1,u8 c){
    map_hline(x0,x1,y0,c);map_hline(x0,x1,y1,c);
    map_vline(x0,y0,y1,c);map_vline(x1,y0,y1,c);
}
static void map_fill(u16 x0,u16 y0,u16 x1,u16 y1,u8 c){
    u16 x,y;for(y=y0;y<=y1;y++)for(x=x0;x<=x1;x++)map_px(x,y,c);
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
static void build_algo_map(void){
    u8 i;
    map_clear();
    map_vline(232,4,250,1);
    map_vline(280,4,250,1);
    map_vline(472,4,250,1);
    for(i=0;i<6;i++){
        u16 y0=(u16)(6u+i*41u),y1=(u16)(y0+33u),cy=(u16)(y0+16u);
        u8 f=(u8)((g_flags[i>>1]>>((i&1u)*8u))&0xFFu);
        u8 out=(u8)(f&3u),in=(u8)((f>>4)&3u),fb=(u8)((f>>6)==3u);
        map_frame(16,y0,176,y1,1);
        if(out==0u){map_hline(177,471,cy,1);map_arrow_r(471,cy,1);}
        else if(out==1u){map_hline(177,231,cy,1);map_arrow_r(231,cy,1);}
        else if(out==2u){map_hline(177,279,cy,1);map_arrow_r(279,cy,1);}
        if(in==1u){map_hline(177,232,cy,1);map_arrow_l(177,cy,1);}
        else if(in==2u){map_hline(177,280,cy,1);map_arrow_l(177,cy,1);}
        if(fb){
            map_hline(8,16,cy,1);
            map_vline(8,(u16)(cy-8u),cy,1);
            map_hline(8,15,(u16)(cy-8u),1);
            map_arrow_r(15,(u16)(cy-8u),1);
        }
    }
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
static const u8 fx_en_reg[6]  ={5,1,9,13,17,21};
static const u8 fx_type_reg[6]={0xFF,2,0xFF,0xFF,0xFF,22};
static const u8 fx_p_reg[6][3]={
    {6,7,8},          /* DIST: gain,tone,level */
    {3,4,0xFF},       /* FILTER: cutoff,Q */
    {10,11,12},       /* CHORUS */
    {14,15,16},       /* PHASER */
    {18,19,20},       /* DELAY */
    {23,24,0xFF}      /* REVERB: decay,mix */
};
static const char*const fx_names[6]={"DIST","FILTER","CHORUS","PHASER","DELAY","REVERB"};
static const char*const fx_p_names[6][3]={
    {"GAIN","TONE","LEVEL"},
    {"CUTOFF","Q",""},
    {"FREQ","DEPTH","MIX"},
    {"FREQ","DEPTH","MIX"},
    {"DECAY","RATE","MIX"},
    {"DECAY","MIX",""}
};
static const char*const filter_type_names[3]={"LOW PASS","BAND","HIGH PASS"};
static const char*const reverb_type_names[3]={"ROOM","HALL","PLATE"};

static void draw_fx(void){
    u8 i,j,row=6;
    u8 sel=fx_sel%6u;
    for(i=0;i<6;i++){
        u8 base=(u8)(2u+i*9u);u8 pal=(i==sel)?3u:2u;
        for(j=0;j<8;j++)c_at((u8)(base+j),4,0,pal,1);
        {u8 n=0;while(fx_names[i][n]&&n<7)n++;
         for(j=0;j<n;j++)c_at((u8)(base+1u+j),4,(u8)fx_names[i][j],pal,1);}
    }
    /* ON/OFF under each button and a '>' between neighbours to show the
       processing order (DIST -> FILTER -> CHORUS -> PHASER -> DELAY -> REVERB). */
    for(i=0;i<6;i++){
        u8 base=(u8)(2u+i*9u);
        u8 on=(u8)(fx_regs[fx_en_reg[i]]&1u);
        text((u8)(base+(on?3u:2u)),5,on?"ON":"OFF",on?3u:2u,0);
        if(i<5)c_at((u8)(base+8u),4,'>',2,0);
    }
    text(66,4,"FX EDIT",3,0);
    text(66,5,(fx_regs[0]&1u)?"MASTER ON":"MASTER OFF",(fx_regs[0]&1u)?3u:2u,0);
    /* FX master on/off */
    prow_eg(row,"FX MASTER",(fx_regs[0]&1u)?"ON":"OFF",(sel_row==0));row++;
    prow_eg(row,"EFFECT",(fx_regs[fx_en_reg[sel]]&1u)?"ON":"OFF",(sel_row==1));row++;
    if(fx_type_reg[sel]!=0xFFu){
        u8 tv=(u8)(fx_regs[fx_type_reg[sel]]&3u);
        if(tv>2u)tv=0;
        prow_eg(row,"TYPE",(sel==1u)?filter_type_names[tv]:reverb_type_names[tv],(sel_row==2));
    }else{
        prow_eg(row,"TYPE","--",(sel_row==2));
    }
    row++;
    for(j=0;j<3;j++){
        u8 pr=fx_p_reg[sel][j];
        if(pr==0xFFu)prow_eg(row,fx_p_names[sel][j],"--",(sel_row==3+j));
        else prow_eg(row,fx_p_names[sel][j],u2d(fx_regs[pr]),(sel_row==3+j));
        row++;
    }
}
static void draw_algo(void){
    u8 i;
    static const u8 label_rows[6]={11u,13u,16u,19u,21u,24u};
    text(2,4,"ALGORITHM",3,0);
    prow(6,"ALGORITHM",u2d((u32)g_algo+1u),(sel_row==0));
    prow(7,"FEEDBACK",u1d(g_fb),(sel_row==1));
    prow(8,"OSC SYNC",g_sync?"ON":"OFF",(sel_row==2));
    prow(9,"TRANSPOSE",u2d(g_trans),(sel_row==3));
    if(algo_map_dirty){build_algo_map();upload_algo_map();algo_map_dirty=0;}
    for(i=0;i<6;i++){
        u8 r0=label_rows[i];
        c_at(29,r0,'O',1,0);c_at(30,r0,'P',1,0);
        c_at(31,r0,(u8)('0'+(6-i)),1,0);
    }
    text(2,26,"B1=MOD BUS1  B2=MOD BUS2  OUT=CARRIER",2,0);
}
static void draw_osc(void){
    u8 i,row,j;
    for(i=0;i<6;i++){
        u8 base=(u8)(2u+i*9u);
        u8 pal=(sel_op==(u8)(5-i))?3u:2u;
        for(j=0;j<7;j++)c_at((u8)(base+j),4,0,pal,1);
        c_at(base,4,'O',pal,1);c_at((u8)(base+1u),4,'P',pal,1);
        c_at((u8)(base+2u),4,(u8)('0'+(i+1)),pal,1);
    }
    text(66,4,"OSC EDIT",3,0);
    row=6;prow(row,"MODE",o_fx?"FIXED":"RATIO",(sel_row==0));row++;
    prow(row,o_fx?"FREQ":"COARSE",u1d(o_coarse),(sel_row==1));row++;
    prow(row,"FINE",u1d(o_fine),(sel_row==2));row++;
    prow(row,"DETUNE",sgn1((int)o_det-7),(sel_row==3));row++;
    prow(row,"LEVEL",u2d(o_lvl),(sel_row==4));row++;
    prow(row,"RATE SCALE",u1d(o_rs),(sel_row==5));row++;
    prow(row,"VEL SENS",u1d(o_vel),(sel_row==6));row++;
    prow(row,"AM SENS",u1d(o_ams),(sel_row==7));row++;
    prow(row,"KEY BP",u2d(o_bp),(sel_row==8));row++;
    prow(row,"L DEPTH",u2d(o_ld),(sel_row==9));row++;
    prow(row,"R DEPTH",u2d(o_rd),(sel_row==10));row++;
    prow(row,"L CURVE",curve_name(o_lc),(sel_row==11));row++;
    prow(row,"R CURVE",curve_name(o_rc),(sel_row==12));row++;
    prow(row,"ENABLE",o_en?"ON":"OFF",(sel_row==13));
    text(2,20,"ROUTING (ASCII)",2,0);
    for(i=0;i<6;i++){
        u8 c0=(u8)(2u+(i%3u)*28u);
        u8 r0=(u8)(21u+(i/3u)*3u);
        u8 f=(u8)((g_flags[i>>1]>>((i&1u)*8u))&0xFFu);
        u8 out=(u8)(f&3u),in=(u8)((f>>4)&3u),fb=(u8)((f>>6)==3u);
        u8 j;
        for(j=0;j<26;j++)c_at((u8)(c0+j),r0,'-',2,0);
        c_at(c0,r0,'+',2,0);c_at((u8)(c0+25u),r0,'+',2,0);
        for(j=0;j<26;j++)c_at((u8)(c0+j),(u8)(r0+2u),'-',2,0);
        c_at(c0,(u8)(r0+2u),'+',2,0);c_at((u8)(c0+25u),(u8)(r0+2u),'+',2,0);
        c_at(c0,(u8)(r0+1u),'|',2,0);c_at((u8)(c0+25u),(u8)(r0+1u),'|',2,0);
        c_at((u8)(c0+1u),(u8)(r0+1u),'O',1,0);
        c_at((u8)(c0+2u),(u8)(r0+1u),'P',1,0);
        c_at((u8)(c0+3u),(u8)(r0+1u),(u8)('0'+(6-i)),1,0);
        text((u8)(c0+5u),(u8)(r0+1u),"OUT",2,0);
        text((u8)(c0+9u),(u8)(r0+1u),out==0u?"CAR":(out==1u?"BUS1":"BUS2"),1,0);
        text((u8)(c0+15u),(u8)(r0+1u),"IN",2,0);
        text((u8)(c0+18u),(u8)(r0+1u),in==0u?"--":(in==1u?"BUS1":"BUS2"),1,0);
        if(fb)text((u8)(c0+23u),(u8)(r0+1u),"F",4,0);
    }
}
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

static u8 eg_mode;            /* 0 = operator amp EG, 1 = pitch EG */
static u8 p_rate[4],p_lev[4];
static u8 name_pos,slot_sel;
static u8 last_preset=0xFF;
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
    u32 hi=((u32)target&0x7FFFFFu)<<24;
    cmd(0x65,lo,hi);
}
static void adj_pitch(u8 row,int d){
    int v;
    if(row<4){v=(int)p_rate[row]+d;if(v<0)v=0;if(v>99)v=99;p_rate[row]=(u8)v;send_pitch_stage(row);}
    else {v=(int)p_lev[row-4]+d;if(v<0)v=0;if(v>99)v=99;p_lev[row-4]=(u8)v;send_pitch_stage((u8)(row-4));}
    draw_page();
}
static void name_from_preset(u8 pr){
    u8 i;pr&=31u;
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
            u32 shi=(u32)(cw&3u)|((u32)((cw>>2)&3u)<<2);
            cmd(0x64,slo,shi);
        }
    }
    for(i=0;i<4;i++){
        u32 target=(u32)s->pitch[i*3+1]|((u32)(s->pitch[i*3+2]&0x7Fu)<<16);
        cmd(0x65,(u32)i|((u32)(s->pitch[i*3+0]&0xFFu)<<8),((target&0x7FFFFFu)<<24));
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
static void draw_eg(void){
    u8 i,j,row=6;
    for(i=0;i<6;i++){
        u8 base=(u8)(2u+i*9u);u8 pal=(sel_op==(u8)(5-i))?3u:2u;
        for(j=0;j<7;j++)c_at((u8)(base+j),4,0,pal,1);
        c_at(base,4,'O',pal,1);c_at((u8)(base+1u),4,'P',pal,1);
        c_at((u8)(base+2u),4,(u8)('0'+(i+1)),pal,1);
    }
    text(66,4,eg_mode?"PITCH EG":"AMP EG",3,0);
    for(i=0;i<4;i++){
        char lbl[10];u8 n=0;
        lbl[n++]='R';lbl[n++]='A';lbl[n++]='T';lbl[n++]='E';lbl[n++]=' ';
        lbl[n++]=(char)('1'+i);lbl[n]=0;
        if(sel_row==i)fill_cells(2,24,(u8)(row+i),3,1);
        text(2,(u8)(row+i),lbl,(sel_row==i)?3:1,(sel_row==i)?1:0);
        text_r(22,(u8)(row+i),u2d(eg_mode?p_rate[i]:o_rate[i]),(sel_row==i)?3:1,(sel_row==i)?1:0);
    }
    for(i=0;i<4;i++){
        char lbl[10];u8 n=0;
        if(eg_mode){lbl[n++]='T';lbl[n++]='A';lbl[n++]='R';lbl[n++]='G';lbl[n++]='E';lbl[n++]='T';}
        else{lbl[n++]='L';lbl[n++]='E';lbl[n++]='V';lbl[n++]='E';lbl[n++]='L';}
        lbl[n++]=' ';lbl[n++]=(char)('1'+i);lbl[n]=0;
        if(sel_row==4+i)fill_cells(50,72,(u8)(row+i),3,1);
        text(50,(u8)(row+i),lbl,(sel_row==4+i)?3:1,(sel_row==4+i)?1:0);
        text_r(72,(u8)(row+i),u2d(eg_mode?p_lev[i]:o_lev[i]),(sel_row==4+i)?3:1,(sel_row==4+i)?1:0);
    }
    {
        static const u8 lx[3]={3u,35u,67u};
        u8 p;char t[4];
        for(p=0;p<3;p++){
            t[0]='O';t[1]='P';t[2]=(char)('1'+p);t[3]=0;
            text(lx[p],11,t,1,0);
            t[2]=(char)('4'+p);
            text(lx[p],18,t,1,0);
        }
    }
}
static void draw_lfo(void){
    u8 row=6;
    prow(row,"WAVE",lfo_wave_names[g_wave%6u],(sel_row==0));row++;
    prow(row,"SPEED",u2d(g_speed),(sel_row==1));row++;
    prow(row,"DELAY",u2d(g_delay),(sel_row==2));row++;
    prow(row,"P MOD DEPTH",u2d(g_pmd),(sel_row==3));row++;
    prow(row,"A MOD DEPTH",u2d(g_amd),(sel_row==4));row++;
    prow(row,"P MOD SENS",u1d(g_pms),(sel_row==5));row++;
    prow(row,"LFO SYNC",g_lsync?"ON":"OFF",(sel_row==6));row++;
    prow(row,"KEY SYNC",g_sync?"ON":"OFF",(sel_row==7));
}
static void draw_name(void){
    u8 i;
    u8 used=(slots[slot_sel].magic==SLOT_MAGIC);
    text(2,4,"NAME / USER SLOT",3,0);
    text(2,6,"NAME",2,0);
    for(i=0;i<10;i++){
        u8 col=(u8)(14u+i*3u);
        u8 pal=(i==name_pos)?3u:2u;
        c_at(col,6,0,pal,1);
        c_at(col,6,(u8)(cur_name[i]?cur_name[i]:' '),pal,1);
    }
    btn_cells(56,60,6,"-",2);btn_cells(64,68,6,"+",2);
    text(2,8,"SLOT",2,0);
    c_at(14,8,(u8)('1'+slot_sel),3,1);
    btn_cells(30,36,8,"SLOT -",2);btn_cells(40,46,8,"SLOT +",2);
    btn_cells(30,40,10,"SAVE",2);btn_cells(50,60,10,"LOAD",2);
    if(used)text(2,12,"SLOT HAS DATA",2,0);
    else text(2,12,"SLOT EMPTY",2,0);
    text(2,14,"TAP A NAME CHAR, THEN +/-",2,0);
    text(2,15,"SAVE KEEPS ALL PATCH FIELDS",2,0);
    for(i=0;i<10;i++)c_at((u8)(14u+i*3u),7,0,12,4);
}
static void draw_theme(void){
    text(2,4,"THEME",3,0);
    btn_cells(2,20,6,theme_names[theme],3);
    text(2,8,"TAP ANYWHERE TO CHANGE",2,0);
    text(2,10,"THE THEME ALSO COLOURS THE",2,0);
    text(2,11,"WAVE, XY, LEVEL AND KEYS",2,0);
    text(2,24,"UI 1.1  PHASE 1",2,0);
}
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
    return 0;
}

static void slider_apply(int x){
    int cur,lo,hi,cyc,t,target,d,n;
    if(!get_sel(&cur,&lo,&hi,&cyc))return;
    t=(x-112)*99/(672-112);
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
static void draw_bottom(void){
    u8 c;int cur,lo,hi,cyc,norm,knob;
    if(page<1||page>5)return;
    for(c=0;c<100;c++){c_at(c,27,0,12,4);c_at(c,28,0,12,4);c_at(c,29,0,12,4);}
    for(c=2;c<=10;c++){c_at(c,27,0,0,1);c_at(c,28,0,0,1);c_at(c,29,0,0,1);}
    c_at(5,28,'<',3,0);c_at(6,28,'<',3,0);
    for(c=90;c<=98;c++){c_at(c,27,0,0,1);c_at(c,28,0,0,1);c_at(c,29,0,0,1);}
    c_at(94,28,'>',3,0);c_at(95,28,'>',3,0);
    for(c=11;c<=89;c++)c_at(c,28,0,7,1);
    text(11,27,"VALUE",2,0);
    text(11,29,"DRAG SLIDE   HOLD -/+",2,0);
    if(!get_sel(&cur,&lo,&hi,&cyc)){
        text(30,27,"NO SELECTION",2,0);
        return;
    }
    if(cyc>0)norm=(cyc>1)?(cur*99/(cyc-1)):0;
    else norm=(hi>lo)?((cur-lo)*99/(hi-lo)):0;
    if(norm<0)norm=0;if(norm>99)norm=99;
    knob=(u8)(11+norm*78/99);
    for(c=11;c<=knob;c++)c_at(c,28,0,3,1);
    c_at(knob,28,'|',1,1);
    text_r(89,27,u2d((u32)(cur>99?99:cur)),3,0);
}
static void draw_page(void){
    if(page==PAGE_PERF){clear_all();draw_perf();return;}
    draw_header();
    if(page==PAGE_ALGO)draw_algo();
    else if(page==PAGE_OSC)draw_osc();
    else if(page==3)draw_eg();
    else if(page==4)draw_lfo();
    else if(page==5)draw_fx();
    else if(page==6)draw_name();
    else if(page==7)draw_theme();
    else draw_placeholder();
    draw_bottom();
}
static void page_enter(u8 p){
    if(p==page&&p!=PAGE_PERF)return;
    
    release_all();
    page=p;sel_row=0;last_adj=0;
    if(p==PAGE_ALGO){load_globals();load_flags();algo_map_dirty=1;}
    else if(p==PAGE_OSC){load_op(sel_op);load_flags();}
    else if(p==3){load_op(sel_op);load_all_eg();build_all_eg();upload_eg6();}
    else if(p==4)load_globals();
    else if(p==5)load_fx();
    else if(p==6)name_from_preset((u8)((UI[4]>>7)&31u));
    
    publish();
    draw_page();
    
}

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
    if(row==12){v=(int)o_rc+d;if(v<0)v=0;if(v>3)v=3;o_rc=(u8)v;send_scaling();return;}
    if(row==13){o_en=(u8)(o_en?0:1);send_op();draw_page();return;}
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
static int editable_rows(void){
    if(page==PAGE_ALGO)return 4;
    if(page==PAGE_OSC)return 14;
    if(page==3)return 8;
    if(page==4)return 8;
    if(page==5)return 6;
    return 0;
}
/* First pixel row of the editable list (ALGO/OSC start below the title/OP row). */
static int content_top(void){
    if(page==PAGE_ALGO||page==PAGE_OSC||page==3||page==4||page==5)return 96;
    return 64;
}
static void adj(u8 row,int d){
    if(page==PAGE_ALGO){adj_algo(row,d);load_flags();}
    else if(page==3){if(eg_mode)adj_pitch(row,d);else adj_eg(row,d);sync_eg6();}
    else if(page==4)adj_lfo(row,d);
    else if(page==5)adj_fx(row,d);
    else adj_op(row,d);
}
static int menu_press(int x,int y){
    int t;
    if(y<16){t=(x-4)/96;if(t<0)t=0;if(t>7)t=7;
        if((u8)t!=page)page_enter((u8)t);return 1;}
    if(page==7&&y>=64){theme=(u8)((theme+1u)%3u);apply_theme(theme);draw_page();return 1;}
    if(page==3&&y>=64&&y<80&&x>=620){eg_mode=(u8)(eg_mode?0:1);if(eg_mode)load_pitch();draw_page();return 1;}
    if(page==6){
        if(y>=96&&y<112){
            if(x>=448&&x<504)name_cycle(-1);
            else if(x>=512&&x<568)name_cycle(1);
            else {int q=(x-112)/24;if(q<0)q=0;if(q>9)q=9;name_pos=(u8)q;}
            draw_page();return 1;
        }
        if(y>=128&&y<144){
            if(x>=240&&x<328)slot_sel=(u8)((slot_sel+7u)&7u);
            else if(x>=320&&x<488)slot_sel=(u8)((slot_sel+1u)&7u);
            draw_page();return 1;
        }
        if(y>=160&&y<176){
            if(x>=240&&x<328)slot_save();
            else if(x>=400&&x<488)slot_load();
            return 1;
        }
        return 1;
    }
    if(page==5&&y>=64&&y<80){
        int i;for(i=0;i<6;i++){int x0=16+i*72;
            if(x>=x0&&x<x0+64){fx_sel=(u8)i;sel_row=0;draw_page();return 1;}}
        return 1;
    }
    if((page==PAGE_OSC||page==3)&&y>=64&&y<80){
        int i;for(i=0;i<6;i++){int x0=16+i*72;
            if(x>=x0&&x<x0+64){sel_op=(u8)(5-i);load_op(sel_op);sel_row=0;draw_page();return 1;}}
        return 1;
    }
    if(page==3&&y>=96&&y<160){
        int r=(y-96)/16;
        sel_row=(u8)(x<400?r:r+4);
        draw_page();
        return 1;
    }
    {int top=content_top();
     if(y>=top&&(int)((y-top)/16)<editable_rows()){
        sel_row=(u8)((y-top)/16);
        draw_page();
        return 1;
    }}
    return 0;
}
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
        if(page==PAGE_PERF&&x>=20&&x<620&&y>=408&&y<460){
            static const u8 whites[15]={0,2,4,5,7,9,11,12,14,16,17,19,21,23,24};
            static const u8 edges[10]={1,2,4,5,6,8,9,11,12,13};
            static const u8 blacks[10]={1,3,6,8,10,13,15,18,20,22};
            int k;note=whites[(x-20)/40];
            if(y<439)for(k=0;k<10;k++)if(x>=20+edges[k]*40-11&&x<20+edges[k]*40+11)note=blacks[k];
            note+=48+octave*12;
        }
        next[id]=note;px[id]=x;py[id]=y;
    }
    if(page==PAGE_PERF){
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
            if((new_mask[i]&bit)&&!(old_mask[i]&bit))emit(0x90,(u8)note,100);
        }
    }
    for(id=0;id<16;id++)if(seen&(1u<<id)){
        if(!(control_down&(1u<<id))){
            control_down|=(u16)(1u<<id);
            
            if(page==PAGE_PERF){
                if(py[id]<16){menu_press(px[id],py[id]);}
                else if(px[id]>=640&&px[id]<800)perf_control(px[id],py[id],(u8)id);
            }else{
                held_id=0xFF;held_kind=0;
                if((page>=1&&page<=5)&&py[id]>=432){
                    /* Bottom bar: big minus / slider / big plus. */
                    held_id=(u8)id;held_row=sel_row;held_x=px[id];
                    held_t=now();held_count=0;
                    if(px[id]<104){held_kind=1;adj(sel_row,-1);}
                    else if(px[id]>=696){held_kind=2;adj(sel_row,1);}
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

static void init_colors(void){
    static const u32 pal[16]={
        0x0B0B0Cu,0xF2F2F2u,0x6E6E72u,0xFF3B00u,
        0xFFB000u,0x151517u,0x1E1E22u,0x2A2A30u,
        0x35DFC1u,0xFFB000u,0x733946u,0x24242Au,
        0x101013u,0x16161Au,0xD8D8DCu,0x000000u};
    u8 i;
    for(i=0;i<16;i++)UI[16]=((u32)i<<24)|pal[i];
    UI[10]=0x0B0B0Cu; /* RTL background / menu page background */
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
        if(page==PAGE_PERF){
            u32 st=UI[4];
            if(st!=last_status){
                last_status=st;
                vol_local=(int)(st&127u);preset_local=(int)((st>>7)&31u);
                draw_status();
            }
        }
        {
            u8 pr=(u8)((UI[4]>>7)&31u);
            if(pr!=last_preset){
                last_preset=pr;
                name_from_preset(pr);
                if(page==PAGE_PERF)draw_status();
                else if(page>=1&&page<=4){
                    if(page==PAGE_ALGO){load_globals();load_flags();algo_map_dirty=1;}
                    else if(page==4)load_globals();
                    else {load_op(sel_op);if(page==3&&eg_mode)load_pitch();}
                    draw_page();
                }
            }
        }
        menu_repeat();perf_repeat();}
        else if((u32)(now()-retry)>500000u){retry=now();present=detect();publish();}
        delay_us(2000);
    }
}














