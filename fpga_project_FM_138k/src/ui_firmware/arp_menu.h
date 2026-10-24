/* ARP controls use the existing character renderer and full-width keyboard. */
static u16 arp_bpm=120;
static u8 arp_hold,arp_order,arp_octaves=1,arp_rate=1,arp_gate=70;
static u8 arp_fixed,arp_velocity=96,arp_swing=50,arp_stop,arp_saved_glide;
static u32 arp_last_draw;
static const char *const arp_orders[5]={"UP","DOWN","UP / DOWN","AS PLAYED","RANDOM"};
static const char *const arp_rates[6]={"1/4","1/8","1/16","1/32","1/8 T","1/16 T"};
static void arp_publish(void){
    static const u8 divisions[6]={1,2,4,8,3,6};
    u32 step=60000000u/((u32)arp_bpm*divisions[arp_rate]);
    u32 even=step*arp_swing/50u,odd=step*2u-even;
    UI[37]=even;UI[38]=odd;UI[39]=even*arp_gate/100u;UI[40]=odd*arp_gate/100u;
    /* Control write atomically commits all four shadow timing words. */
    UI[36]=arp_on|((u32)arp_hold<<1)|((u32)arp_fixed<<2)|((u32)arp_order<<3)|
        ((u32)(arp_octaves-1u)<<6)|((u32)arp_velocity<<8)|((u32)arp_stop<<15);
}
static void arp_enable(u8 enable){u32 t;u8 from_sequence=(u8)(enable&&seq_is_active());
    if(enable)seq_stop();
    release_all();
    if(enable){arp_saved_glide=from_sequence?glide_on:(u8)(rd(0x00c)!=0);
        set_glide(0);}
    arp_on=enable;arp_publish();
    if(!enable){
        t=now();while((UI[41]&2u)&&(u32)(now()-t)<20000u){}
        set_glide(arp_saved_glide);
    }
}
static void arp_row(u8 c,u8 r,const char *label,const char *value){
    row_box(c,r,46,3,label,"",0);
    button_box(c+16,r,6,3,"-",0);button_box(c+23,r,16,3,value,0);button_box(c+40,r,6,3,"+",0);
}
static void draw_arp_status(void){u32 st=UI[41];u8 n,c=10,shown=0;u32 mask[4];
    rect_cells(0,20,100,2,5);pair_text(2,20,"CHORD",5,0);
    for(n=0;n<4;n++)mask[n]=UI[42+n];
    for(n=0;n<128;n++)if(mask[n>>5]&(1u<<(n&31))){
        if(shown<10){const char *v=lesson_note_name(n);pair_text(c,20,v,5,0);c+=(u8)(str_len(v)+1);shown++;}
    }
    if((st>>24)>10)pair_text(c,20,"...",5,0);
    pair_text(74,20,"OUT",5,0);
    if(st&8u)pair_text(79,20,lesson_note_name((u8)((st>>17)&127u)),5,0);
    pair_text(89,20,(st&4u)?"RUN":"READY",5,0);
    if(st&16u)pair_text(2,21,"PEDAL",5,0);
    pair_text(16,21,"STEP",5,0);pair_text(22,21,u3d((u8)((st>>8)&255u)+1u),5,0);
}
static void draw_arp(void){
    button_box(2,5,18,3,arp_on?"ARP: ON":"ARP: OFF",arp_on);
    button_box(22,5,18,3,arp_hold?"HOLD: ON":"HOLD: OFF",arp_hold);
    button_box(42,5,16,3,"STOP",0);
    button_box(60,5,8,3,"-",0);row_box(69,5,19,3,"BPM",u3d(arp_bpm),0);button_box(90,5,8,3,"+",0);
    arp_row(2,8,"RATE",arp_rates[arp_rate]);arp_row(52,8,"ORDER",arp_orders[arp_order]);
    arp_row(2,11,"OCTAVES",u1d(arp_octaves));arp_row(52,11,"GATE %",u2d(arp_gate));
    arp_row(2,14,"VELOCITY",arp_fixed?u3d(arp_velocity):"INPUT");arp_row(52,14,"SWING %",u2d(arp_swing));
    button_box(2,17,14,3,"OCT -",0);row_box(18,17,14,3,"VIEW",sgn1(octave),0);button_box(34,17,14,3,"OCT +",0);
    text(53,17,"HOLD: RELEASE, THEN NEW CHORD",2,0);
    text(53,18,"VELOCITY: TAP VALUE TO SWITCH",2,0);
    draw_arp_status();
}
static void arp_adj(u8 row,int d){int v;
    if(row==0){v=arp_bpm+d;if(v<30)v=30;if(v>240)v=240;arp_bpm=(u16)v;}
    else if(row==1)arp_rate=(u8)(((int)arp_rate+d+6)%6);
    else if(row==2)arp_order=(u8)(((int)arp_order+d+5)%5);
    else if(row==3){v=arp_octaves+d;if(v<1)v=1;if(v>4)v=4;arp_octaves=(u8)v;}
    else if(row==4){v=arp_gate+d;if(v<10)v=10;if(v>95)v=95;arp_gate=(u8)v;}
    else if(row==5){v=arp_velocity+d;if(v<1)v=1;if(v>127)v=127;arp_velocity=(u8)v;arp_fixed=1;}
    else if(row==6){v=arp_swing+d;if(v<50)v=50;if(v>75)v=75;arp_swing=(u8)v;}
    arp_publish();seq_publish();draw_arp();
}
static void arp_press(int x,int y){u8 row=0;int local,d=0;
    if(y>=80&&y<128){
        if(x>=16&&x<160){arp_enable(!arp_on);draw_arp();return;}
        if(x>=176&&x<320){arp_hold=!arp_hold;arp_publish();draw_arp();return;}
        if(x>=336&&x<464){release_all();arp_stop^=1;arp_publish();draw_arp();return;}
        if(x>=480&&x<544)d=-1;else if(x>=720&&x<784)d=1;
    }else if(y>=128&&y<272&&((x>=16&&x<384)||(x>=416&&x<784))){
        row=(u8)(1+((y-128)/48)*2+(x>=416));local=x-(x>=416?416:16);
        if(local>=128&&local<176)d=-1;else if(local>=320&&local<368)d=1;
        else if(local>=184&&local<312){
            if(row==5){arp_fixed=!arp_fixed;arp_publish();draw_arp();return;}
            if(row==1||row==2)d=1;
        }
    }else if(y>=272&&y<320){
        if((x>=16&&x<128)||(x>=272&&x<384)){
            release_all();octave+=x<128?-1:1;if(octave< -3)octave=-3;if(octave>3)octave=3;
            publish();draw_status();draw_arp();
        }
    }
    if(d){held_row=row;held_kind=d<0?1:2;held_t=now();held_count=0;arp_adj(row,d);}
}
static void arp_poll(void){
    if(page!=PAGE_ARP||(u32)(now()-arp_last_draw)<100000u)return;
    arp_last_draw=now();draw_arp_status();
}
