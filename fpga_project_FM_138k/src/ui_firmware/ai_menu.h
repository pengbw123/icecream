/* Trained POP low-voice prototype; ARP/SEQ share the one BACKING part. */
static u16 ai_bpm=120;
static u8 ai_key,ai_sparse,ai_harmony=2,ai_minor,ai_velocity=70,ai_saved_glide;
static u8 ai_follow=1,ai_split=60;
static u32 ai_last_draw;
static struct backing_t ai_patch;
static const char *const ai_keys[12]={"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"};
static void ai_publish(void){u32 period=15000000u/ai_bpm;
    backing_word(0x3f1,(u16)period);backing_word(0x3f2,(u16)(period>>16));
    backing_word(0x3f3,(u16)(((u16)ai_split<<8)|2|ai_follow));
    backing_word(0x3f0,(u16)(ai_on|((u16)ai_sparse<<1)|((u16)(ai_harmony==1)<<2)|((u16)(ai_harmony==2)<<3)|
        ((u16)ai_key<<4)|((u16)ai_minor<<8)|((u16)ai_velocity<<9)));
}
static void ai_stop(void){u32 t;
    if(!ai_on)return;ai_on=0;ai_publish();t=now();
    while((UI[60]&7u)&&(u32)(now()-t)<20000u){}
    set_glide(ai_saved_glide);
}
static void ai_start(void){u8 saved=seq_is_active()?seq_saved_glide:arp_on?arp_saved_glide:(u8)(rd(0x00c)!=0);
    seq_stop();if(arp_on)arp_enable(0);release_all();
    ai_saved_glide=saved;set_glide(0);
    backing_capture(&ai_patch);backing_upload(&ai_patch);ai_on=1;ai_publish();
}
static void draw_ai_status(void){u32 st=UI[60];
    rect_cells(0,20,100,2,5);
    pair_text(2,20,"AI BASS",5,0);pair_text(14,20,(st&8u)?"PANIC / STOPPED":!(st&1u)?"STOPPED":(st&512u)?"PLAYING":"WAITING",5,0);
    pair_text(50,20,"MISSED STEPS",5,0);pair_text(65,20,(st>>16)>999?"999+":u3d(st>>16),5,0);
    pair_text(2,21,"CHORD",5,0);pair_text(14,21,ai_keys[((st>>4)&15u)<12?((st>>4)&15u):0],5,0);
    pair_text(24,21,(st&256u)?"MINOR":"MAJOR",5,0);pair_text(50,21,"LH < SPLIT / RH >= SPLIT",5,0);
}
static void draw_ai(void){
    button_box(2,5,18,3,ai_on?"STOP":"START",ai_on);
    row_box(22,5,76,3,"BACKING",ai_patch.patch.magic==SLOT_MAGIC?ai_patch.patch.name:"LIVE AT START",0);
    arp_row(2,8,"BPM",u3d(ai_bpm));arp_row(52,8,"KEY",ai_keys[ai_key]);
    arp_row(2,11,"DENSITY",ai_sparse?"SPARSE":"NORMAL");arp_row(52,11,"DYN LEVEL",u3d(ai_velocity));
    arp_row(2,14,"HARMONY",ai_harmony==2?"LEFT HAND":ai_harmony==1?"I-vi-IV-V":"STATIC");arp_row(52,14,"STATIC TYPE",ai_minor?"MINOR":"MAJOR");
    arp_row(2,17,"PLAY MODE",ai_follow?"FOLLOW":"CONTINUE");arp_row(52,17,"SPLIT MIDI",u3d(ai_split));
    draw_ai_status();
}
static void ai_adj(u8 row,int d){int n;
    if(row==0){n=ai_bpm+d;if(n<30)n=30;if(n>240)n=240;ai_bpm=(u16)n;}
    else if(row==1)ai_key=(u8)(((int)ai_key+d+12)%12);
    else if(row==2)ai_sparse=!ai_sparse;
    else if(row==3){n=ai_velocity+d;if(n<1)n=1;if(n>127)n=127;ai_velocity=(u8)n;}
    else if(row==4)ai_harmony=(u8)(((int)ai_harmony+d+3)%3);
    else if(row==5)ai_minor=!ai_minor;
    else if(row==6)ai_follow=!ai_follow;
    else if(row==7){n=ai_split+d;if(n<36)n=36;if(n>84)n=84;ai_split=(u8)n;}
    ai_publish();draw_ai();
}
static void ai_press(int x,int y){int local,d=0;u8 row;
    if(y>=80&&y<128&&x>=16&&x<160){if(ai_on)ai_stop();else ai_start();draw_ai();return;}
    if(y<128||y>=320||!((x>=16&&x<384)||(x>=416&&x<784)))return;
    row=(u8)(((y-128)/48)*2+(x>=416));local=x-(x>=416?416:16);
    if(local>=128&&local<176)d=-1;else if(local>=320&&local<368)d=1;
    else if(local>=184&&local<312&&row!=0&&row!=3)d=1;
    if(row==7&&local>=184&&local<312)d=0;
    if(d){held_row=row;held_kind=d<0?1:2;held_t=now();held_count=0;ai_adj(row,d);}
}
static void ai_poll(void){
    if(page!=PAGE_AI||(u32)(now()-ai_last_draw)<100000u)return;
    ai_last_draw=now();draw_ai_status();
}
