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
/* Selected operator cache */
static u8 o_en,o_fx,o_det,o_lvl,o_rs,o_vel,o_ams,o_bp,o_ld,o_rd,o_lc,o_rc,o_coarse,o_fine,o_eg0r;
static u8 o_rate[4],o_lev[4];
static u16 o_eg0l;
static u32 o_freq;

static u8 rate_from_qrate(u8 q);
static u8 qrate_from_rate(u8 r);
static u16 internal_from_level(u8 l);
static u8 level_from_internal(u16 v);
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
static void draw_status(void){
    u32 st=UI[4];u16 pidx=(u16)((st>>7)&31u);u8 vol=(u8)(st&127u);
    u8 alg=(u8)((st>>12)&31u);u8 vc=(u8)((st>>17)&31u);
    char buf[40];u8 n=0,i;
    buf[n++]='P';
    buf[n++]=(char)('0'+(((pidx+1u)/10u)%10u));
    buf[n++]=(char)('0'+((pidx+1u)%10u));
    buf[n++]=' ';
    for(i=0;i<10&&preset_names[pidx&31u][i];i++)buf[n++]=preset_names[pidx&31u][i];
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
    u8 i;
    clear_all();
    draw_tabs();
    text(2,28,"TAP ROW   -/+ STEP   DRAG SLIDE",2,0);
    text_r(98,28,"V1.1",2,0);
    for(i=0;i<100;i++)c_at(i,27,0,12,4);
}
static void buttons(u8 row){
    u8 c;
    for(c=56;c<=62;c++)c_at(c,row,0,2,1);
    c_at(59,row,'-',2,1);
    for(c=64;c<=70;c++)c_at(c,row,0,2,1);
    c_at(67,row,'+',2,1);
}
static void prow(u8 row,const char*label,const char*val,int selected){
    if(selected){
        fill_cells(2,52,row,3,1);
        text(2,row,label,3,1);text_r(52,row,val,3,1);
        buttons(row);
    }else{
        text(2,row,label,1,0);text_r(52,row,val,1,0);
    }
}
static void draw_placeholder(void){
    text(2,4,"PAGE NOT READY",3,0);
    text(2,6,"PHASE 2 ADDS THIS EDITOR",2,0);
    text(2,8,"TABS 1-3 AND 8 ARE ACTIVE",2,0);
}
static void draw_algo(void){
    u8 i,row;u32 f;u16 w0,w1,w2;
    text(2,4,"ALGORITHM",3,0);
    prow(6,"ALGORITHM",u2d((u32)g_algo+1u),(sel_row==0));
    prow(7,"FEEDBACK",u1d(g_fb),(sel_row==1));
    prow(8,"OSC SYNC",g_sync?"ON":"OFF",(sel_row==2));
    text(2,10,"ROUTING (LIVE FROM FPGA)",2,0);
    w0=rd(0x0009u);w1=rd(0x000Au);w2=rd(0x000Bu);
    for(i=0;i<6;i++){
        if(i==0)f=(u32)(w0&0xFFu);
        else if(i==1)f=(u32)((w0>>8)&0xFFu);
        else if(i==2)f=(u32)(w1&0xFFu);
        else if(i==3)f=(u32)((w1>>8)&0xFFu);
        else if(i==4)f=(u32)(w2&0xFFu);
        else f=(u32)((w2>>8)&0xFFu);
        row=(u8)(11u+i);
        c_at(4,row,'O',2,0);c_at(5,row,'P',2,0);c_at(6,row,(u8)('0'+(6-i)),2,0);
        text(9,row,"OUT",2,0);
        text(13,row,(f&3u)==0u?"CAR":(((f&3u)==1u)?"BUS1":"BUS2"),2,0);
        text(20,row,"IN",2,0);
        text(23,row,(((f>>4)&3u)==0u)?"--":((((f>>4)&3u)==1u)?"BUS1":"BUS2"),2,0);
        if((f>>6)==3u)text(31,row,"FB",2,0);
    }
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
    prow(row,"R CURVE",curve_name(o_rc),(sel_row==12));
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
static void draw_eg(void){
    u8 i,j,row=6;
    for(i=0;i<6;i++){
        u8 base=(u8)(2u+i*9u);u8 pal=(sel_op==(u8)(5-i))?3u:2u;
        for(j=0;j<7;j++)c_at((u8)(base+j),4,0,pal,1);
        c_at(base,4,'O',pal,1);c_at((u8)(base+1u),4,'P',pal,1);
        c_at((u8)(base+2u),4,(u8)('0'+(i+1)),pal,1);
    }
    text(66,4,"ENVELOPE",3,0);
    for(i=0;i<4;i++){
        char lbl[7];u8 n=0;
        lbl[n++]='R';lbl[n++]='A';lbl[n++]='T';lbl[n++]='E';lbl[n++]=' ';
        lbl[n++]=(char)('1'+i);lbl[n]=0;
        prow(row,lbl,u2d(o_rate[i]),(sel_row==i));row++;
    }
    row=11;
    for(i=0;i<4;i++){
        char lbl[8];u8 n=0;
        lbl[n++]='L';lbl[n++]='E';lbl[n++]='V';lbl[n++]='E';lbl[n++]='L';lbl[n++]=' ';
        lbl[n++]=(char)('1'+i);lbl[n]=0;
        prow(row,lbl,u2d(o_lev[i]),(sel_row==4+i));row++;
    }
    /* Four-stage target preview: one bar per level, 4 cells wide. */
    for(i=0;i<4;i++){
        u8 h=(u8)(((u32)o_lev[i]*12u)/99u);
        u8 top=(u8)(23u-h);
        for(row=10;row<=23;row++)
            for(j=0;j<4;j++)c_at((u8)(78u+i*5u+j),row,0,12,4);
        for(row=top;row<=23;row++)
            for(j=0;j<4;j++)c_at((u8)(78u+i*5u+j),row,0,3,4);
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
static void draw_theme(void){
    text(2,4,"THEME",3,0);
    btn_cells(2,20,6,theme_names[theme],3);
    text(2,8,"TAP ANYWHERE TO CHANGE",2,0);
    text(2,10,"THE THEME ALSO COLOURS THE",2,0);
    text(2,11,"WAVE, XY, LEVEL AND KEYS",2,0);
    text(2,24,"UI 1.1  PHASE 1",2,0);
}
static void draw_page(void){
    if(page==PAGE_PERF){clear_all();draw_perf();return;}
    draw_header();
    if(page==PAGE_ALGO)draw_algo();
    else if(page==PAGE_OSC)draw_osc();
    else if(page==3)draw_eg();
    else if(page==4)draw_lfo();
    else if(page==7)draw_theme();
    else draw_placeholder();
}
static void page_enter(u8 p){
    if(p==page&&p!=PAGE_PERF)return;
    
    release_all();
    page=p;sel_row=0;last_adj=0;
    if(p==PAGE_ALGO)load_globals();
    else if(p==PAGE_OSC)load_op(sel_op);
    else if(p==3)load_op(sel_op);
    else if(p==4)load_globals();
    
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
    else {g_sync=(u8)(g_sync?0:1);send_global();}
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
static int editable_rows(void){
    if(page==PAGE_ALGO)return 3;
    if(page==PAGE_OSC)return 13;
    if(page==3)return 8;
    if(page==4)return 8;
    return 0;
}
/* First pixel row of the editable list (ALGO/OSC start below the title/OP row). */
static int content_top(void){
    if(page==PAGE_ALGO||page==PAGE_OSC||page==3||page==4)return 96;
    return 64;
}
static void adj(u8 row,int d){
    if(page==PAGE_ALGO)adj_algo(row,d);
    else if(page==3)adj_eg(row,d);
    else if(page==4)adj_lfo(row,d);
    else adj_op(row,d);
}
static int menu_press(int x,int y){
    int t;
    if(y<16){t=(x-4)/96;if(t<0)t=0;if(t>7)t=7;
        if((u8)t!=page)page_enter((u8)t);return 1;}
    if(page==7&&y>=64){theme=(u8)((theme+1u)%3u);apply_theme(theme);draw_page();return 1;}
    if((page==PAGE_OSC||page==3)&&y>=64&&y<80){
        int i;for(i=0;i<6;i++){int x0=16+i*72;
            if(x>=x0&&x<x0+64){sel_op=(u8)(5-i);load_op(sel_op);sel_row=0;draw_page();return 1;}}
        return 1;
    }
    {int top=content_top();
     if(y>=top&&(int)((y-top)/16)<editable_rows()){
        u8 row=(u8)((y-top)/16);
        u32 t=now();
        if(x>=448&&x<504){
            if(last_adj==0u||(u32)(t-last_adj)>120000u){last_adj=t;adj(row,-1);}
        } else if(x>=512&&x<568){
            if(last_adj==0u||(u32)(t-last_adj)>120000u){last_adj=t;adj(row,1);}
        } else {sel_row=row;draw_page();}
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
                if(menu_press(px[id],py[id])){
                    int top=content_top();
                    if(py[id]>=top&&py[id]<top+editable_rows()*16){
                        u8 row=(u8)((py[id]-top)/16);
                        held_id=(u8)id;held_x=px[id];held_t=now();held_count=0;
                        held_row=row;
                        if(px[id]>=448&&px[id]<504)held_kind=1;
                        else if(px[id]>=512&&px[id]<568)held_kind=2;
                        else held_kind=3;
                    }
                }
            }
        }else if(page!=PAGE_PERF&&held_id==(u8)id&&held_kind==3){
            int guard=0;
            while(px[id]-held_x>=8&&guard<6){adj(held_row,1);held_x+=8;guard++;}
            guard=0;
            while(held_x-px[id]>=8&&guard<6){adj(held_row,-1);held_x-=8;guard++;}
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
        menu_repeat();perf_repeat();}
        else if((u32)(now()-retry)>500000u){retry=now();present=detect();publish();}
        delay_us(2000);
    }
}










