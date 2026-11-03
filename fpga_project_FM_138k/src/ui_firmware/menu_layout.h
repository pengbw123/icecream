/* 800x480 instrument layout. Geometry is in 8x16 character cells; touch
 * coordinates below use the same boundaries. No framebuffer or DSP changes. */
static u8 osc_group, patch_pick, patch_bank, patch_rom_page;

static const u32 backgrounds[4]={0xFFFFFF,0xEDF1F5,0x1B222A,0x0E1116};
static const u32 accents[5]={0x245E8F,0x52B9D2,0x33856D,0x665C9C,0x647A90};
static const char *const bg_labels[4]={"WHITE","COOL GRAY","CHARCOAL","BLACK"};
static const char *const ac_labels[5]={"BLUE","CYAN","TEAL","VIOLET","SLATE"};
static u32 palette_now[16];
static void cache_operator_switches(void){u8 i;for(i=0;i<6;i++)op_enabled[i]=(u8)(rd((u16)(0x40u+i*32u))&1u);}
static u8 str_len(const char *s){u8 n=0;while(s[n])n++;return n;}
static u32 mix_color(u32 a,u32 b,u32 t){u32 r=0;u8 i;for(i=0;i<3;i++){
    u32 sh=i*8u;u32 v=(((a>>sh)&255u)*(256u-t)+((b>>sh)&255u)*t)>>8;r|=v<<sh;}return r;}
static int light_color(u32 c){return (((c>>16)&255u)*54u+((c>>8)&255u)*183u+(c&255u)*19u)>36000u;}
static void apply_theme(u8 unused){
    u8 i;u32 bg=backgrounds[bg_pick],ac=accents[accent_pick],fg=light_color(bg)?0x111820:0xF5F8FB;
    u32 vis=ac;u32 on=light_color(ac)?0x111820:0xF5F8FB;
    (void)unused;
    /* Dark blue needs a lighter trace on a dark background. Keep the selected
       button's actual fill unchanged, with a separately contrasting label. */
    if(!light_color(bg))vis=mix_color(ac,0xF5F8FB,96);
    palette_now[0]=bg;palette_now[1]=fg;palette_now[2]=mix_color(bg,fg,176);
    palette_now[3]=ac;palette_now[4]=vis;palette_now[5]=mix_color(bg,fg,12);
    palette_now[6]=mix_color(bg,fg,77);palette_now[7]=mix_color(bg,fg,41);
    palette_now[8]=vis;palette_now[9]=on;palette_now[10]=0xF5F8FB;
    palette_now[11]=mix_color(bg,fg,31);palette_now[12]=mix_color(bg,fg,18);
    palette_now[13]=0x111820;palette_now[14]=mix_color(bg,ac,46);palette_now[15]=bg;
    for(i=0;i<16;i++)UI[16]=((u32)i<<24)|palette_now[i];
    UI[10]=bg;UI[11]=vis;UI[12]=vis;
}
static __attribute__((noinline)) void rect_cells(u8 c,u8 r,u8 w,u8 h,u8 pal){u8 y;for(y=r;y<r+h;y++)fill_cells(c,(u8)(c+w-1),y,pal,4);}
static __attribute__((noinline)) void pair_text(u8 c,u8 r,const char *s,u8 bg,int selected){text(c,r,s,bg,(u8)(selected?9:8));}
static __attribute__((noinline)) void button_box(u8 c,u8 r,u8 w,u8 h,const char *label,int selected){
    u8 n=str_len(label),bg=selected?3:5;
    rect_cells(c,r,w,h,bg);
    pair_text((u8)(c+(w-n)/2u),(u8)(r+h/2),label,bg,selected);
}
static void row_box(u8 c,u8 r,u8 w,u8 h,const char *label,const char *value,int selected){
    u8 bg=selected?14:0;
    rect_cells(c,r,w,h,bg);
    pair_text((u8)(c+2),(u8)(r+h/2),label,bg,0);
    pair_text((u8)(c+w-2-str_len(value)),(u8)(r+h/2),value,bg,0);
}
static void draw_tabs(void){u8 i;rect_cells(0,0,100,3,12);
    for(i=0;i<8;i++)button_box((u8)(2+i*12),0,12,3,tab_names[i],page==i||((page==PAGE_METRICS||page==PAGE_AI||page==PAGE_COMPOSER||page==PAGE_GESTURE)&&i==7)||((page==PAGE_LESSON||page==PAGE_ARP||page==PAGE_SEQ)&&i==0));
}
static void draw_status(void){u8 i;u32 st=UI[4];u8 pr=status_preset(st);
    if(page==PAGE_LESSON){draw_lesson_status();return;}
    rect_cells(0,3,100,2,5);
    pair_text(2,3,"ROM",5,0);pair_text(5,3,u3d(pr+1u),5,0);
    pair_text(8,3,cur_name[0]?cur_name:preset_names[pr],5,0);
    if(patch_dirty)pair_text(28,3,"EDIT",5,0);
    pair_text(38,3,"ALG",5,0);pair_text(42,3,u2d(((st>>12)&31u)+1u),5,0);
    pair_text(52,3,"VOICE",5,0);pair_text(58,3,u2d(status_voices(st)),5,0);
    pair_text(60,3,"/",5,0);pair_text(61,3,u2d(UI[59]),5,0);pair_text(71,3,"OCT",5,0);pair_text(75,3,sgn1(octave),5,0);
    pair_text(86,3,"VOL",5,0);
    /* Hardware volume is 0..127; show the full value, never wrap 100..127. */
    i=(u8)(st&127u);nb[0]=(char)('0'+i/100);nb[1]=(char)('0'+(i/10)%10);nb[2]=(char)('0'+i%10);nb[3]=0;
    pair_text(92,3,nb,5,0);
}
static void draw_perf_controls(void){
    text(2,5,visual_mode==4?"LINEAR FFT / 47.68 Hz PER BIN":visual_mode==3?"VOICE SLOTS / 32":visual_mode==2?"SPECTRUM / dBFS":visual_mode==1?"LISSAJOUS":"WAVEFORM",2,0);text(68,5,(visual_mode==2||visual_mode==4)?"dBFS":"OUT",2,0);
    if(visual_mode==4){text(2,20,"0",2,0);text(16,20,"6k",2,0);text(32,20,"12k",2,0);text(48,20,"18k",2,0);text(61,20,"24k",2,0);}
    if(visual_mode==3)text(36,5,"S0: START / STOP",2,0);
    if(visual_mode==2){
        text(2,20,"50",2,0);text(16,20,"200",2,0);text(32,20,"1k",2,0);text(48,20,"5k",2,0);text(61,20,"20k",2,0);
        text(68,6,"0",2,0);text(68,10,"-24",2,0);text(68,15,"-48",2,0);text(68,19,"-72",2,0);
    }
    text(76,5,composer_session?"AI MELODY":ai_on?"AI BACKING":arp_on?"ARP ON":"",2,0);
    text(76,6,"VOLUME",2,0);
    nb[0]=(char)('0'+vol_local/100);nb[1]=(char)('0'+(vol_local/10)%10);nb[2]=(char)('0'+vol_local%10);nb[3]=0;
    text_r(98,6,nb,1,0);
    button_box(76,8,10,3,"-",0);button_box(88,8,10,3,"+",0);
    button_box(76,11,10,3,"< PREV",0);button_box(88,11,10,3,"NEXT >",0);
    button_box(76,14,10,2,"WAVE",visual_mode==0);button_box(88,14,10,2,"XY",visual_mode==1);
    button_box(76,16,10,2,visual_mode==4?"LIN FFT":"FFT",visual_mode==2||visual_mode==4);button_box(88,16,10,2,"VOICES",visual_mode==3);
    button_box(76,18,10,3,"OCT -",0);button_box(88,18,10,3,"OCT +",0);
}
static void draw_perf(void){draw_tabs();draw_status();draw_perf_controls();}
static void draw_header(void){clear_all();draw_tabs();draw_status();}
static void draw_algo(void){
    row_box(2,6,28,3,"ALGORITHM",u2d(g_algo+1u),sel_row==0);
    row_box(2,10,28,3,"FEEDBACK",u1d(g_fb),sel_row==1);
    row_box(2,14,28,3,"OSC SYNC",g_sync?"ON":"OFF",sel_row==2);
    row_box(2,18,28,3,"TRANSPOSE",sgn1((int)g_trans-24),sel_row==3);
    text(34,7,"OPERATOR ROUTING",2,0);text(2,23,"CARRIER = FILLED",4,0);text(2,24,"MODULATOR = OUTLINE",2,0);
    if(algo_map_dirty){build_algo_map();upload_algo_map();algo_map_dirty=0;}
}
static const u8 osc_first[3]={0,4,8},osc_count[3]={4,4,5};
static const char *const osc_labels[14]={"MODE","COARSE","FINE","DETUNE","LEVEL","RATE SCALE","VEL SENS","AM SENS","KEY BP","L DEPTH","R DEPTH","L CURVE","R CURVE","ENABLE"};
static const char *osc_value(u8 i){switch(i){
    case 0:return o_fx?"FIXED":"RATIO";case 1:return u2d(o_coarse);case 2:return u2d(o_fine);
    case 3:return sgn1((int)o_det-7);case 4:return u2d(o_lvl);case 5:return u1d(o_rs);
    case 6:return u1d(o_vel);case 7:return u1d(o_ams);case 8:return u2d(o_bp);
    case 9:return u2d(o_ld);case 10:return u2d(o_rd);case 11:return curve_name(o_lc);
    case 12:return curve_name(o_rc);default:return o_en?"ON":"OFF";}}
static void draw_osc(void){u8 i;char label[4]="OP1";
    text(2,5,"OPERATORS",2,0);
    for(i=0;i<6;i++){label[2]=(char)('1'+i);button_box(2,(u8)(6+i*3),20,3,label,sel_op==5-i);
        button_box(22,(u8)(6+i*3),8,3,op_enabled[5-i]?"ON":"OFF",0);}
    button_box(32,6,22,3,"PITCH",osc_group==0);button_box(54,6,22,3,"RESPONSE",osc_group==1);
    button_box(76,6,22,3,"KEY SCALE",osc_group==2);
    for(i=0;i<osc_count[osc_group];i++){u8 n=(u8)(osc_first[osc_group]+i);
        row_box(32,(u8)(10+i*3),66,3,osc_labels[n],osc_value(n),sel_row==n);}
}
static void draw_eg(void){u8 i;char s[4]="R1";
    if(eg_mode)eg_rebuild();
    for(i=0;i<8;i++){s[0]=i<4?'R':'L';s[1]=(char)('1'+(i&3));
        row_box((u8)(2+(i&3)*24),(u8)(5+(i/4)*3),24,3,s,u2d(eg_mode?(i<4?p_rate[i]:p_lev[i-4]):(i<4?o_rate[i]:o_lev[i-4])),sel_row==i);}
    if(eg_mode){text(2,12,"PITCH ENVELOPE",4,0);text(2,14,"50 = CENTER",2,0);return;}
    for(i=0;i<6;i++){s[0]='O';s[1]='P';s[2]=(char)('1'+i);s[3]=0;
        rect_cells((u8)(2+(i%3)*32),(u8)(12+(i/3)*7),30,1,sel_op==5-i?3:12);
        pair_text((u8)(3+(i%3)*32),(u8)(12+(i/3)*7),s,sel_op==5-i?3:12,sel_op==5-i);}
}
static const u8 lfo_order[8]={0,1,2,6,3,4,5,7};
static const char *const lfo_labels[8]={"WAVE","SPEED","DELAY","PM DEPTH","AM DEPTH","PM SENS","LFO SYNC","OSC SYNC"};
static const char *lfo_value(u8 n){switch(n){case 0:return lfo_wave_names[g_wave%6];case 1:return u2d(g_speed);
    case 2:return u2d(g_delay);case 3:return u2d(g_pmd);case 4:return u2d(g_amd);case 5:return u1d(g_pms);
    case 6:return g_lsync?"ON":"OFF";default:return g_sync?"ON":"OFF";}}
static void draw_lfo(void){u8 i;text(2,6,"LFO GENERATOR",2,0);text(52,6,"MODULATION",2,0);
    for(i=0;i<8;i++){u8 n=lfo_order[i];row_box(i<4?2:52,(u8)(8+(i%4)*4),46,4,lfo_labels[n],lfo_value(n),sel_row==n);}}
static const char *fx_value(u8 n){u8 reg=fx_p_reg[fx_sel][n];u16 v=fx_regs[reg];
    if(fx_sel==2&&n==0){u16 ms=(u16)(20u+((u32)v*980u+49u)/99u);u8 k=0;
        if(ms>=1000)nb[k++]='1';if(ms>=100)nb[k++]=(char)('0'+(ms/100)%10);
        if(ms>=10)nb[k++]=(char)('0'+(ms/10)%10);nb[k++]=(char)('0'+ms%10);nb[k++]='m';nb[k++]='s';nb[k]=0;return nb;}
    return u2d(v);}
static void draw_fx(void){u8 i;u8 type=fx_type_reg[fx_sel];
    text(2,5,"FX CHAIN",2,0);
    for(i=0;i<6;i++){button_box(2,(u8)(6+i*3),20,3,fx_names[i],fx_sel==i);
        button_box(22,(u8)(6+i*3),8,3,(fx_regs[fx_en_reg[i]]&1)?"ON":"OFF",0);}
    text(32,6,fx_names[fx_sel],1,0);text_r(98,6,(fx_regs[fx_en_reg[fx_sel]]&1)?"ENABLED":"BYPASSED",4,0);
    if(type!=255){for(i=0;i<3;i++)button_box((u8)(32+i*22),8,22,3,fx_sel==0?filter_type_names[i]:reverb_type_names[i],(fx_regs[type]%3)==i);}
    for(i=0;i<3;i++)if(fx_p_reg[fx_sel][i]!=255)row_box(32,(u8)(12+i*4),66,3,fx_p_names[fx_sel][i],fx_value(i),sel_row==3+i);
    if(fx_sel==2)text(32,24,"TIME 20..1000 ms",2,0);
}
static void draw_name(void){u8 i;char label[12];text(2,6,"ROM1+2 / 128",2,0);
    text(52,6,"USER / 8 SLOTS",2,0);text(52,7,sd_message,4,0);
    for(i=0;i<5;i++){u8 n=(u8)(patch_rom_page*5+i);if(n<128)row_box(2,(u8)(8+i*3),46,3,u3d(n+1u),preset_names[n],n==patch_pick);}
    for(i=0;i<4;i++){u8 n=(u8)(patch_bank*4+i);row_box(52,(u8)(8+i*3),46,3,u2d(n+1u),slots[n].magic==SLOT_MAGIC?slots[n].name:"-- EMPTY --",slot_sel==n);}
    button_box(2,23,24,3,"< PREV",0);button_box(26,23,22,3,"NEXT >",0);
    button_box(52,21,22,3,"LOAD RAM",0);button_box(76,21,22,3,"STORE RAM",0);
    button_box(52,24,22,3,"READ SD",0);button_box(76,24,22,3,"STORE SD",0);
    button_box(86,5,12,3,patch_bank?"5-8 >":"1-4 >",0);
    button_box(2,27,46,3,"LOAD ROM",1);button_box(52,27,22,3,"RENAME",0);button_box(76,27,22,3,"PLAY",0);
    (void)label;
}
/* Lesson transport uses dedicated RTL registers; the CPU never schedules notes. */
static u8 lesson_demo,lesson_run,lesson_speed=100,lesson_saved_glide;
static int lesson_saved_octave;
static u32 lesson_last_draw,lesson_last_status=~0u;
static void lesson_control(u8 restart){UI[28]=1u|((u32)lesson_run<<1)|((u32)lesson_demo<<2)|((u32)restart<<3)|((u32)lesson_speed<<8);}
static const char *lesson_note_name(u8 n){static char v[5];static const char names[12]={'C','C','D','D','E','F','F','G','G','A','A','B'};
    u8 k=n%12;v[0]=names[k];v[1]=(k==1||k==3||k==6||k==8||k==10)?'#':' ';if(n<12){v[2]='-';v[3]='1';v[4]=0;}else{v[2]=(char)('0'+n/12-1);v[3]=0;}return v;}
static void draw_lesson_status(void){u32 st=UI[28];u32 meta=UI[30];
    rect_cells(0,3,100,2,5);
    pair_text(2,3,(meta&0x100u)?"LOADED MELODY":"TWINKLE / ROM",5,0);
    pair_text(34,3,(st&16u)?"FINISHED":(st&8u)?"WAIT KEY":!(st&2u)?"PAUSED":(st&4u)?"DEMO":"PLAY",5,0);
    if(st&8u)pair_text(46,3,lesson_note_name((u8)((st>>8)&127u)),5,0);
    pair_text(60,3,"NOTE",5,0);pair_text(65,3,u3d((st>>24)&255u),5,0);
    pair_text(69,3,"/",5,0);pair_text(71,3,u3d(meta&255u),5,0);
    pair_text(80,3,"C3 - C5",5,0);
}
static void draw_lesson_controls(void){
    button_box(2,5,18,3,lesson_demo?"MODE: DEMO":"MODE: WAIT",lesson_demo);
    button_box(22,5,18,3,lesson_run?"PAUSE":"START",lesson_run);
    button_box(42,5,18,3,"RESTART",0);
    button_box(62,5,11,3,"SPEED -",0);button_box(75,5,11,3,"SPEED +",0);
    rect_cells(88,5,12,3,0);text(89,6,u3d(lesson_speed),2,0);text(92,6,"%",2,0);
}
static void lesson_poll(void){u32 st;
    if(page!=PAGE_LESSON||(u32)(now()-lesson_last_draw)<100000u)return;
    lesson_last_draw=now();st=UI[28];
    if((st&16u)&&lesson_run){lesson_run=0;draw_lesson_controls();}
    if(st!=lesson_last_status){lesson_last_status=st;draw_lesson_status();}
}
static void lesson_press(int x,int y){
    if(y<80||y>=128)return;
    if(x>=16&&x<160){lesson_demo=!lesson_demo;lesson_run=0;lesson_control(1);}
    else if(x>=176&&x<320){lesson_run=!lesson_run;lesson_control((UI[28]&16u)?1:0);}
    else if(x>=336&&x<480){lesson_run=0;lesson_control(1);}
    else if(x>=496&&x<584){if(lesson_speed>50)lesson_speed-=25;lesson_control(0);}
    else if(x>=600&&x<688){if(lesson_speed<150)lesson_speed+=25;lesson_control(0);}
    draw_lesson_controls();draw_lesson_status();
}
#include "arp_menu.h"
#include "seq_menu.h"
#include "performance_menu.h"
#include "ai_menu.h"
#include "composer_menu.h"
static const char *const setup_labels[11]={"BACKGROUND","ACCENT","DISPLAY","XY DELAY","AUTO RANGE","KEY VELOCITY","AUDIO OUTPUT","SPECTRUM","GLIDE MONO","PRACTICE","GLIDE MS"};
static const char *setup_value(u8 n){if(n==0)return bg_labels[bg_pick];if(n==1)return ac_labels[accent_pick];
    if(n==2)return visual_mode==4?"LINEAR FFT":visual_mode==3?"VOICES":visual_mode==2?"SPECTRUM":visual_mode==1?"XY":"WAVE";if(n==3)return u2d(xy_delay);
    if(n==4)return display_auto_gain?"ON":"OFF";if(n==5){
        nb[0]=(char)('0'+touch_velocity/100);nb[1]=(char)('0'+(touch_velocity/10)%10);nb[2]=(char)('0'+touch_velocity%10);nb[3]=0;return nb;}
    if(n==10)return glide_ms==1000?"1000":u3d(glide_ms);
    if(n==6)return headphone_select?"HEADPHONE":"SPEAKER";if(n==8)return glide_on?"ON":"OFF";return "OPEN >";}
static void draw_theme(void){u8 i;button_box(2,5,30,3,"ARPEGGIATOR >",arp_on);button_box(35,5,30,3,"SEQUENCER >",0);button_box(68,5,30,3,"GESTURES >",UI[63]&2u);
    for(i=0;i<5;i++)row_box(2,(u8)(8+i*3),46,3,setup_labels[i],setup_value(i),sel_row==i);
    for(i=5;i<10;i++)row_box(52,(u8)(8+(i-5)*3),46,3,setup_labels[i],setup_value(i),sel_row==i);
    button_box(2,23,22,3,"METERS >",0);button_box(26,23,22,3,"AI BACKING >",ai_on);button_box(52,23,22,3,"AI MELODY >",composer_session);row_box(76,23,22,3,setup_labels[10],setup_value(10),sel_row==10);
}
static const char *selected_label(void){if(page==1){static const char *const a[4]={"ALGORITHM","FEEDBACK","OSC SYNC","TRANSPOSE"};return a[sel_row];}
    if(page==2)return osc_labels[sel_row];if(page==3)return sel_row<4?"RATE":"LEVEL";
    if(page==4)return lfo_labels[sel_row];if(page==5)return sel_row>=3?fx_p_names[fx_sel][sel_row-3]:"CONTROL";
    if(page==7)return setup_labels[sel_row];return "VALUE";}
static void draw_bottom(void){int cur,lo,hi,cyc,norm;u8 c;
    if(page==0||page==6||page==PAGE_LESSON||page==PAGE_ARP||page==PAGE_SEQ||page==PAGE_METRICS||page==PAGE_AI||page==PAGE_COMPOSER||page==PAGE_GESTURE)return;
    rect_cells(0,26,100,4,12);
    button_box(2,27,28,3,page==5?((fx_regs[0]&1)?"FX MASTER ON":"FX MASTER OFF"):page==3?(eg_mode?"PITCH EG":"OPERATOR EG"):"PLAY",0);
    button_box(32,27,8,3,"-1",0);button_box(90,27,8,3,"+1",0);
    if(!get_sel(&cur,&lo,&hi,&cyc))return;
    pair_text(42,26,selected_label(),12,0);
    {const char *v;
     if(page==7)v=setup_value(sel_row);
     else if(page==2)v=osc_value(sel_row);
     else if(page==4)v=lfo_value(sel_row);
     else if(page==5&&sel_row>=3)v=fx_value(sel_row-3);
     else if(page==1&&sel_row==2)v=g_sync?"ON":"OFF";
     else if(page==1&&sel_row==3)v=sgn1((int)g_trans-24);
     else v=u2d((u32)(page==1&&sel_row==0?cur+1:cur));
     pair_text((u8)(88-str_len(v)),26,v,12,0);}
    if(cyc>0)norm=cyc>1?cur*45/(cyc-1):0;else norm=hi>lo?(cur-lo)*45/(hi-lo):0;
    for(c=42;c<88;c++)c_at(c,28,0,c<=42+norm?3:7,4);
    c_at((u8)(42+norm),28,'|',1,0);
}
static void draw_dialog(void){
    rect_cells(10,8,80,15,5);
    pair_text(14,9,dialog==8?"STORE SD SLOT":dialog==9?"READ SD BANK":dialog==1?"ARPEGGIATOR":dialog==2?"STEP SEQUENCER":dialog==3?"SPECTRUM":dialog==4?"RENAME":dialog==5?"LOAD ROM":dialog==6?"OVERWRITE RAM":"LOAD RAM",5,0);
    if(dialog<=3){pair_text(14,12,"RESERVED / NOT AVAILABLE YET",5,0);button_box(30,18,40,3,"BACK",1);}
    else if(dialog==4){pair_text(34,13,cur_name,5,0);button_box(12,14,8,3,"<",0);button_box(22,14,8,3,">",0);
        button_box(70,14,8,3,"-",0);button_box(80,14,8,3,"+",0);button_box(30,19,40,3,"DONE",1);
        c_at((u8)(34+name_pos),14,'^',4,0);}
    else{pair_text(14,12,dialog==9?"REPLACE ALL RAM SLOTS FROM SD?":dialog==8?"SAVE CURRENT PATCH TO SD SLOT?":dialog==6?"REPLACE SELECTED SLOT?":"REPLACE CURRENT EDITS?",5,0);
        button_box(14,19,30,3,"CANCEL",0);button_box(54,19,30,3,(dialog==6||dialog==8)?"STORE":"LOAD",1);}
}
static void draw_page(void){draw_header();
    if(page==PAGE_GESTURE)draw_gesture();else if(page==PAGE_COMPOSER)draw_composer();else if(page==PAGE_AI)draw_ai();else if(page==PAGE_METRICS)draw_metrics();else if(page==PAGE_SEQ)draw_seq();else if(page==PAGE_ARP)draw_arp();else if(page==PAGE_LESSON)draw_lesson_controls();else if(page==0)draw_perf_controls();else if(page==1)draw_algo();else if(page==2)draw_osc();
    else if(page==3)draw_eg();else if(page==4)draw_lfo();else if(page==5)draw_fx();else if(page==6)draw_name();else draw_theme();
    draw_bottom();if(dialog)draw_dialog();
}
static void load_selected_rom(void){release_all();emit(0xb0,27,patch_pick);preset_local=patch_pick;
    name_from_preset(patch_pick);last_preset=patch_pick;patch_dirty=0;dialog=0;draw_page();}
static void request_rom(u8 n){patch_pick=n;if(patch_dirty){dialog=5;draw_page();}else load_selected_rom();}
static void perf_control(int x,int y,u8 id){u8 k=0;u32 t=now();
    if(y>=128&&y<176&&x>=608)k=x<696?3:4;
    else if(y>=176&&y<224&&x>=608){request_rom((u8)((preset_local+(x<696?127:1))&127));return;}
    else if(y>=224&&y<256&&x>=608){visual_mode=x<696?0:1;publish();draw_page();return;}
    else if(y>=256&&y<288&&x>=608){visual_mode=x<696?(visual_mode==2?4:2):3;publish();draw_page();return;}
    else if(y>=288&&y<336&&x>=608)k=x<696?5:6;
    if(!k)return;if(ctrl_last[k]&&(u32)(t-ctrl_last[k])<300000u)return;
    ctrl_last[k]=t;perf_step(k);ctrl_hold=k;ctrl_hold_id=id;ctrl_hold_t=t;ctrl_hold_count=0;
}
static void page_enter(u8 p){if(p==page&&p!=0)return;keyboard_blocked|=control_down;release_all();ctrl_hold=0;held_id=255;held_kind=0;
    if(page==PAGE_LESSON){UI[28]=0;octave=lesson_saved_octave;
        if(lesson_saved_glide)set_glide(1);}
    if(p==PAGE_LESSON){composer_stop();ai_stop();seq_stop();lesson_saved_octave=octave;octave=0;
        lesson_saved_glide=(u8)(rd(0x00c)!=0);if(lesson_saved_glide)set_glide(0);
        emit(0xb0,64,0);lesson_run=0;lesson_control(1);lesson_last_status=~0u;}
    if(p==PAGE_COMPOSER)composer_enter();
    if(p==PAGE_GESTURE){composer_stop();ai_stop();seq_stop();if(arp_on)arp_enable(0);}
    dialog=0;page=p;sel_row=0;last_adj=0;
    arp_publish();
    if(p==PAGE_METRICS){metrics_frozen=0;metrics_last_poll=now();metrics_read();}
    if(p==PAGE_SEQ){seq_confirm=0;seq_select();seq_cache();}
    if(p==1){load_globals();load_flags();algo_map_dirty=1;}
    else if(p==2){osc_group=0;cache_operator_switches();load_op(sel_op);load_flags();}
    else if(p==3){load_op(sel_op);load_all_eg();build_all_eg();upload_eg6();if(eg_mode)load_pitch();}
    else if(p==7){glide_on=rd(0x00c)!=0;glide_ms=rd(0x00d);if(glide_ms<10||glide_ms>1000)glide_ms=170;}
    else if(p==4)load_globals();else if(p==5){load_fx();sel_row=3;}
    else if(p==6){patch_pick=status_preset(UI[4]);patch_rom_page=patch_pick/5;}
    publish();draw_page();
}
static void adj_setup(u8 r,int d){int n;
    if(r<2){u8 max=r==0?4:5;u8 *p=r==0?&bg_pick:&accent_pick;n=((int)*p+d+(int)max)%max;*p=(u8)n;apply_theme(0);}
    else if(r==2)visual_mode=(visual_mode+d+5)%5;
    else if(r==3){n=xy_delay+d;if(n<1)n=1;if(n>96)n=96;xy_delay=n;}
    else if(r==4)display_auto_gain=!display_auto_gain;
    else if(r==5){n=touch_velocity+d;if(n<1)n=1;if(n>127)n=127;touch_velocity=(u8)n;}
    else if(r==6)headphone_select=!headphone_select;
    else if(r==8){if(composer_session){composer_stop();glide_on=1;}else if(arp_on){arp_enable(0);glide_on=1;}else if(seq_run||seq_record){seq_stop();glide_on=1;}else glide_on=!glide_on;set_glide(glide_on);}
    else if(r==10){n=(int)glide_ms+d;set_glide_time((u16)(n<10?10:n>1000?1000:n));}
    publish();draw_page();
}
static int menu_press(int x,int y){int i,n;
    if(dialog){
        if(dialog<=3){if(y>=288&&y<336){dialog=0;draw_page();}return 1;}
        if(dialog==4){if(y>=304){name_commit();dialog=0;draw_page();return 1;}
            if(y>=224&&y<272){if(x>=96&&x<160)name_pos=(name_pos+9)%10;else if(x>=176&&x<240)name_pos=(name_pos+1)%10;
                else if(x>=560&&x<624){name_cycle(-1);patch_dirty=1;}else if(x>=640&&x<704){name_cycle(1);patch_dirty=1;}draw_page();}return 1;}
        if(y>=304&&y<352){if(x>=112&&x<352){dialog=0;draw_page();}
            else if(x>=432&&x<672){u8 d=dialog;dialog=0;if(d==8||d==9){sd_bank_action(d==8);draw_page();}else if(d==5)load_selected_rom();else if(d==6)slot_save();else{slot_load();patch_dirty=0;draw_page();}}}return 1;
    }
    if(y<48){i=(x-16)/96;if(x>=16&&x<784)page_enter((u8)i);return 1;}
    if(page==PAGE_GESTURE){gesture_press(x,y);return 1;}
    if(page==PAGE_COMPOSER){composer_press(x,y);return 1;}
    if(page==PAGE_AI&&x>=624&&x<784&&y>=80&&y<128){page_enter(PAGE_COMPOSER);return 1;}
    if(page==PAGE_AI){ai_press(x,y);return 1;}
    if(page==7&&x>=416&&x<592&&y>=368&&y<416){page_enter(PAGE_COMPOSER);return 1;}
    if(page==7&&x>=208&&x<384&&y>=368&&y<416){page_enter(PAGE_AI);return 1;}
    if(page==PAGE_METRICS){metrics_press(x,y);return 1;}
    if(page==7&&x>=16&&x<192&&y>=368&&y<416){page_enter(PAGE_METRICS);return 1;}
    if(page==PAGE_SEQ){seq_press(x,y);return 1;}
    if(page==7&&x>=544&&x<784&&y>=80&&y<128){page_enter(PAGE_GESTURE);return 1;}
    if(page==7&&x>=280&&x<520&&y>=80&&y<128){page_enter(PAGE_SEQ);return 1;}
    if(page==PAGE_ARP){arp_press(x,y);return 1;}
    if(page==7&&x>=16&&x<256&&y>=80&&y<128){page_enter(PAGE_ARP);return 1;}
    if(page==PAGE_LESSON){lesson_press(x,y);return 1;}
    if(page==0){perf_control(x,y,0);return 1;}
    if(y>=432&&x>=16&&x<240){
        if(page==5){adj_fx(0,1);return 1;}if(page==3){eg_mode=!eg_mode;if(eg_mode)load_pitch();publish();draw_page();return 1;}
        if(page!=6){page_enter(0);return 1;}}
    if(page==6){
        if(y>=384&&y<432&&x>=416&&x<784){
            if(x>=608){dialog=8;}
            else {dialog=9;}
            draw_page();return 1;
        }
        if(y>=80&&y<128&&x>=688){patch_bank^=1;slot_sel=patch_bank*4;}
        else if(y>=128&&y<368&&x>=16&&x<384){n=patch_rom_page*5+(y-128)/48;if(n<128)patch_pick=(u8)n;}
        else if(y>=128&&y<320&&x>=416&&x<784)slot_sel=(u8)(patch_bank*4+(y-128)/48);
        else if(y>=368&&y<416&&x>=16&&x<384){patch_rom_page=(u8)((patch_rom_page+(x<208?25:1))%26);}
        else if(y>=336&&y<384&&x>=416){if(x>=608){if(slots[slot_sel].magic==SLOT_MAGIC)dialog=6;else slot_save();}
            else if(slots[slot_sel].magic==SLOT_MAGIC){if(patch_dirty)dialog=7;else{slot_load();patch_dirty=0;}}}
        else if(y>=432){if(x<384)request_rom(patch_pick);else if(x>=416&&x<592){dialog=4;name_pos=0;name_changed=0;}else if(x>=608)page_enter(0);}
        draw_page();return 1;
    }
    if(page==1&&x>=16&&x<240&&y>=96&&y<352){i=(y-96)/64;if(i<4)sel_row=(u8)i;}
    else if(page==2){
        if(x>=16&&x<240&&y>=96&&y<384){sel_op=(u8)(5-(y-96)/48);load_op(sel_op);publish();if(x>=176){adj_op(13,1);patch_dirty=1;}}
        else if(x>=256&&x<784&&y>=96&&y<144){osc_group=(u8)((x-256)/176);sel_row=osc_first[osc_group];}
        else if(x>=256&&x<784&&y>=160&&y<400){i=(y-160)/48;if(i<osc_count[osc_group])sel_row=(u8)(osc_first[osc_group]+i);}}
    else if(page==3){if(y>=80&&y<176&&x>=16&&x<784){i=(x-16)/192;if(i>3)i=3;sel_row=(u8)(i+(y>=128?4:0));}
        else if(!eg_mode&&y>=192&&y<400&&x>=16&&x<768){i=(x-16)/256;if(i<3){n=(y>=304?3:0)+i;sel_op=(u8)(5-n);load_op(sel_op);publish();}}}
    else if(page==4&&y>=128&&y<384){i=(y-128)/64;if(x>=16&&x<384)sel_row=lfo_order[i];else if(x>=416&&x<784)sel_row=lfo_order[i+4];}
    else if(page==5){if(x>=16&&x<240&&y>=96&&y<384){fx_sel=(u8)((y-96)/48);sel_row=3;if(x>=176)adj_fx(1,1);}
        else if(x>=256&&x<784&&y>=128&&y<176&&fx_type_reg[fx_sel]!=255){n=(x-256)/176;fx_write(fx_type_reg[fx_sel],(u16)n);}
        else if(x>=256&&x<784&&y>=192&&y<368){i=(y-192)/64;if(i<3&&fx_p_reg[fx_sel][i]!=255)sel_row=(u8)(3+i);}}
    else if(page==7&&x>=608&&x<784&&y>=368&&y<416)sel_row=10;
    else if(page==7&&y>=128&&y<368){if(x>=16&&x<384)sel_row=(u8)((y-128)/48);
        else if(x>=416&&x<784&&y<368){sel_row=(u8)(5+(y-128)/48);if(sel_row==9){page_enter(PAGE_LESSON);return 1;}if(sel_row==7){visual_mode=2;page_enter(0);publish();return 1;}}}
    draw_page();return 1;
}
