/* 8 x 16 volatile patterns; the hardware owns recording and playback time. */
static u8 seq_run,seq_record,seq_pattern,seq_step,seq_settings,seq_confirm;
static u8 seq_rate=2,seq_gate=70,seq_swing=50,seq_restart,seq_saved_glide;
static u8 seq_lengths[8]={16,16,16,16,16,16,16,16};
static u32 seq_words[16],seq_last_poll;
static u8 seq_is_active(void){return (u8)(seq_run||seq_record);}
static void seq_publish(void){
    static const u8 divisions[6]={1,2,4,8,3,6};
    u32 step=60000000u/((u32)arp_bpm*divisions[seq_rate]);
    u32 even=step*seq_swing/50u,odd=step*2u-even;
    UI[50]=even;UI[51]=odd;UI[52]=even*seq_gate/100u;UI[53]=odd*seq_gate/100u;
    UI[46]=seq_run|((u32)seq_record<<1)|((u32)seq_restart<<2)|((u32)seq_pattern<<3)|
        ((u32)(seq_lengths[seq_pattern]-1u)<<6);
}
static void seq_wait(void){u32 t=now();while((UI[49]&4u)&&(u32)(now()-t)<20000u){}}
static void seq_stop(void){
    if(!seq_run&&!seq_record)return;
    seq_run=0;seq_record=0;seq_publish();seq_wait();
    set_glide(seq_saved_glide);
}
static void seq_backing(u8 capture){
    struct backing_t *b=&seq_patch[seq_pattern];
    if(capture||b->patch.magic!=SLOT_MAGIC)backing_capture(b);
    backing_upload(b);
}
static void seq_prepare(void){
    if(!seq_run&&!seq_record){
        // A preceding tool may have just queued restoration of glide. Its
        // logical saved state is newer than the synth's asynchronous readback.
        seq_saved_glide=arp_on?arp_saved_glide:(u8)(rd(0x00c)!=0);
        if(arp_on)arp_enable(0);
        set_glide(0);
        emit(0xb0,64,0);
    }
}
static void seq_cache(void){u8 i;
    for(i=0;i<16;i++){UI[55]=(u32)seq_pattern*16u+i;seq_words[i]=UI[48];}
}
static void seq_select(void){UI[47]=(u32)seq_pattern*16u+seq_step;}
static void seq_store(u32 word,u8 advance){u8 rec=seq_record;
    if(rec){seq_step=(u8)(UI[47]&15u);seq_record=0;seq_publish();seq_wait();}
    seq_select();UI[48]=word;seq_words[seq_step]=word;
    if(advance){seq_step++;if(seq_step>=seq_lengths[seq_pattern])seq_step=0;seq_select();}
    if(rec){seq_record=1;seq_publish();}
}
static void draw_seq_status(void){u32 st=UI[49];
    rect_cells(0,20,100,2,5);
    pair_text(2,20,"PATTERN",5,0);pair_text(11,20,u1d(seq_pattern+1u),5,0);
    pair_text(16,20,"STEP",5,0);pair_text(22,20,u2d(seq_step+1u),5,0);
    pair_text(29,20,"LENGTH",5,0);pair_text(37,20,u2d(seq_lengths[seq_pattern]),5,0);
    pair_text(44,20,"BPM",5,0);pair_text(49,20,u3d(arp_bpm),5,0);
    pair_text(58,20,(st&16u)?"WRITE ERROR":seq_record?"STEP RECORD":seq_run?"PLAYING":"STOPPED",5,0);
    if(seq_run){pair_text(81,20,"PLAY",5,0);pair_text(87,20,u2d(((st>>8)&15u)+1u),5,0);}
    pair_text(2,21,"RAM ONLY / NO POWER-OFF SAVE",5,0);
    if(seq_record)pair_text(48,21,"NEW NOTE = WRITE + NEXT STEP",5,0);
    else {pair_text(48,21,"BACKING",5,0);pair_text(58,21,seq_patch[seq_pattern].patch.magic==SLOT_MAGIC?seq_patch[seq_pattern].patch.name:"LIVE AT START",5,0);}
}
static void draw_seq_grid(void){u8 i,c,r;u32 st=UI[49];char label[12];
    for(i=0;i<16;i++){
        const char *v;u8 j=0;
        c=(u8)(2+(i%8)*12);r=(u8)(8+(i/8)*3);
        if(seq_words[i]&0x80000000u)v=lesson_note_name((u8)(seq_words[i]&127u));
        else v=(seq_words[i]&0x40000000u)?"TIE":"---";
        label[0]=(char)('0'+(i+1)/10);label[1]=(char)('0'+(i+1)%10);label[2]=' ';
        while(v[j]&&j<7){label[3+j]=v[j];j++;}label[3+j]=0;
        button_box(c,r,12,3,label,seq_step==i);
        if(i>=seq_lengths[seq_pattern])pair_text(c+1,r,"x",5,0);
        if(seq_run&&((st>>8)&15u)==i)pair_text(c+1,r,">",seq_step==i?3:5,seq_step==i);
    }
}
static void draw_seq(void){u32 word=seq_words[seq_step];
    button_box(2,5,18,3,seq_run?"STOP":"START",seq_run);
    button_box(22,5,18,3,seq_record?"REC: ON":"STEP REC",seq_record);
    button_box(42,5,12,3,"REST",0);button_box(56,5,12,3,"TIE",0);
    button_box(70,5,12,3,seq_confirm?"CONFIRM?":"CLEAR BANK",seq_confirm);
    button_box(84,5,14,3,seq_settings?"STEPS":"SETTINGS",seq_settings);
    if(seq_settings){
        arp_row(2,8,"BPM",u3d(arp_bpm));arp_row(52,8,"RATE",arp_rates[seq_rate]);
        arp_row(2,11,"GATE %",u2d(seq_gate));arp_row(52,11,"SWING %",u2d(seq_swing));
        arp_row(2,14,"LENGTH",u2d(seq_lengths[seq_pattern]));arp_row(52,14,"PATTERN",u1d(seq_pattern+1u));
        text(3,17,"ONE NOTE PER STEP / TIE EXTENDS",2,0);text(3,18,"REST IS SILENT FOR ONE STEP",2,0);
    }else{
        draw_seq_grid();
        arp_row(2,14,"NOTE",(word&0x80000000u)?lesson_note_name((u8)(word&127u)):(word&0x40000000u)?"TIE":"REST");
        arp_row(52,14,"VELOCITY",u3d((word>>8)&127u));
        arp_row(2,17,"PATTERN",u1d(seq_pattern+1u));arp_row(52,17,"LENGTH",u2d(seq_lengths[seq_pattern]));
    }
    if(seq_settings)button_box(52,17,46,3,"CAPTURE LIVE PATCH",0);
    draw_seq_status();
}
static void seq_adj(u8 row,int d){int v;u32 w;
    if(seq_record){seq_step=(u8)(UI[47]&15u);UI[55]=(u32)seq_pattern*16u+seq_step;seq_words[seq_step]=UI[48];}
    w=seq_words[seq_step];
    if(row==0||row==1){
        if(!(w&0x80000000u))w=0x8000603cu;
        if(row==0){v=(int)(w&127u)+d;if(v<0)v=0;if(v>127)v=127;w=(w&~127u)|(u32)v;}
        else{v=(int)((w>>8)&127u)+d;if(v<1)v=1;if(v>127)v=127;w=(w&~0x7f00u)|((u32)v<<8);}
        seq_store(w,0);
    }else if(row==2){
        if(seq_run||seq_record)return;
        seq_pattern=(u8)(((int)seq_pattern+d+8)%8);seq_step=0;seq_confirm=0;seq_select();seq_cache();
    }else if(row==3){v=seq_lengths[seq_pattern]+d;if(v<1)v=1;if(v>16)v=16;seq_lengths[seq_pattern]=(u8)v;
        if(seq_step>=v){seq_step=0;seq_select();}}
    else if(row==4){v=arp_bpm+d;if(v<30)v=30;if(v>240)v=240;arp_bpm=(u16)v;arp_publish();}
    else if(row==5)seq_rate=(u8)(((int)seq_rate+d+6)%6);
    else if(row==6){v=seq_gate+d;if(v<10)v=10;if(v>95)v=95;seq_gate=(u8)v;}
    else if(row==7){v=seq_swing+d;if(v<50)v=50;if(v>75)v=75;seq_swing=(u8)v;}
    seq_publish();draw_seq();
}
static void seq_press(int x,int y){int local,d=0;u8 row=0;
    if(seq_settings&&y>=272&&y<320&&x>=416&&x<784){
        if(!seq_run&&!seq_record){backing_capture(&seq_patch[seq_pattern]);draw_seq();}return;
    }
    if(seq_record)seq_step=(u8)(UI[47]&15u);
    if(!(y>=80&&y<128&&x>=560&&x<656))seq_confirm=0;
    if(y>=80&&y<128){
        if(x>=16&&x<160){if(seq_run)seq_stop();else{seq_prepare();seq_backing(0);seq_run=1;seq_record=0;seq_restart^=1;seq_publish();}draw_seq();return;}
        if(x>=176&&x<320){if(seq_record)seq_stop();else{seq_prepare();seq_backing(1);seq_record=1;seq_run=0;seq_select();seq_publish();}draw_seq();return;}
        if(x>=336&&x<432){seq_store(0,seq_record);draw_seq();return;}
        if(x>=448&&x<544){seq_store(0x40000000u,seq_record);draw_seq();return;}
        if(x>=560&&x<656){
            if(seq_confirm){u8 rec=seq_record;if(rec){seq_record=0;seq_publish();seq_wait();}
                seq_select();UI[54]=1;seq_wait();seq_cache();seq_confirm=0;if(rec){seq_record=1;seq_publish();}}
            else seq_confirm=1;draw_seq();return;
        }
        if(x>=672&&x<784){seq_settings=!seq_settings;rect_cells(0,8,100,12,0);draw_seq();return;}
    }
    if(!seq_settings&&y>=128&&y<224&&x>=16&&x<784){
        seq_step=(u8)(((y-128)/48)*8+(x-16)/96);seq_select();draw_seq();return;
    }
    if(((x>=16&&x<384)||(x>=416&&x<784))&&y>=128&&y<320){
        u8 right=x>=416;local=x-(right?416:16);
        if(seq_settings){
            if(y<176)row=right?5:4;else if(y<224)row=right?7:6;
            else if(y<272)row=right?2:3;else return;
        }else if(y>=224&&y<272)row=right?1:0;
        else if(y>=272)row=right?3:2;else return;
        if(local>=128&&local<176)d=-1;else if(local>=320&&local<368)d=1;
        else if(local>=184&&local<312&&(row==2||row==5))d=1;
        if(d){held_row=row;held_kind=d<0?1:2;held_t=now();held_count=0;seq_adj(row,d);}
    }
}
static void seq_poll(void){u32 st;
    if((u32)(now()-seq_last_poll)<100000u)return;seq_last_poll=now();st=UI[49];
    if((seq_run&&!(st&1u))||(seq_record&&!(st&2u)))seq_stop();
    if(page!=PAGE_SEQ){seq_confirm=0;return;}
    if(seq_record){seq_step=(u8)(UI[47]&15u);seq_cache();}
    if(!seq_settings)draw_seq_grid();draw_seq_status();
}
