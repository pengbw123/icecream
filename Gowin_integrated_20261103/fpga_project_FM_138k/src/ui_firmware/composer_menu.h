static u8 gesture_timbre=1;
/* Phase 1: lead creation, volatile theme/phrase and learned pad controls. */
static u16 composer_bpm=120;
static u8 composer_key,composer_minor,composer_form,composer_density=64,composer_direction=64;
static u8 composer_variation=64,composer_strength=100,composer_settings,composer_saved_glide;
static u32 composer_last_draw,composer_last_status=~0u;
static u8 composer_x=34,composer_y=13;
static const char *const composer_forms[3]={"LONG PHRASE","SHORT NOTES","PENTATONIC"};
static void composer_command(u8 a){backing_word(0x3c5,a);}
static void composer_publish(void){u32 period=15000000u/composer_bpm;
    backing_word(0x3c1,(u16)period);backing_word(0x3c2,(u16)(period>>16));
    backing_word(0x3c3,(u16)(composer_key|((u16)composer_minor<<4)|((u16)composer_form<<5)));
    backing_word(0x3c4,(u16)(composer_density|((u16)composer_direction<<8)));
    backing_word(0x3c6,(u16)(composer_variation|((u16)composer_strength<<8)));
    backing_word(0x3c0,composer_session);
}
static void composer_stop(void){u32 t;
    if(!composer_session)return;
    composer_session=0;backing_word(0x3c0,0);t=now();
    while((UI[61]&12u)&&(u32)(now()-t)<20000u){}
    set_glide(composer_saved_glide);
}
static void composer_enter(void){
    if(composer_session)return;
    ai_stop();seq_stop();if(arp_on)arp_enable(0);release_all();
    composer_saved_glide=(u8)(rd(0x00c)!=0);set_glide(0);
    backing_capture(&ai_patch);backing_upload(&ai_patch);
    composer_session=1;composer_publish();composer_last_status=~0u;
}
static __attribute__((noinline)) void composer_text(u8 c,u8 r,const char *s){pair_text(c,r,s,5,0);}
static const char *gesture_name(u32 n){return n==0?"FIST":n==1?"PALM":n==2?"V SIGN":"OTHER";}
static void draw_gesture_status(void){u32 st=UI[63],n=st>>16,xy=UI[36];
    rect_cells(2,12,96,5,5);
    composer_text(4,12,!(st&4u)?"UNAVAILABLE":!(st&1u)?"RECOGNITION OFF":!(st&8u)||(st&16u)?"CAMERA NOT READY":!(st&32u)?"WAITING FOR FRAME":(st&64u)?"TRACKING":"UNKNOWN / UNSTABLE");
    composer_text(62,12,(st&8192u)?"CONTROL ACTIVE":(st&2u)?"CONTROL ARMED":"CONTROL OFF");
    composer_text(4,14,"RAW");composer_text(10,14,(st&32u)?gesture_name((st>>8)&3u):"--");
    composer_text(26,14,"STABLE");composer_text(35,14,(st&64u)?gesture_name((st>>10)&3u):"--");
    composer_text(54,14,"FRAMES");composer_text(62,14,n>999?"999+":u3d(n));
    composer_text(72,14,"GAP/256");composer_text(82,14,u3d(UI[35]>>24));
    composer_text(4,16,gesture_timbre?"PALM: ORGAN / FIST: BRASS / V: GLOCKEN":"PALM: NORMAL / FIST: CHOP / V: ARP");
    rect_cells(2,18,96,3,5);
    if(gesture_timbre){
        composer_text(4,19,(xy&0x60000u)?"RELEASE / WAIT TAIL":"LIVE PATCH");composer_text(30,19,cur_name);
        composer_text(54,19,"BRIGHT");composer_text(62,19,u3d(xy&127u));
        composer_text(72,19,"VIB");composer_text(78,19,u3d((xy>>8)&127u));
    }else{composer_text(4,19,"SOUND MODE");composer_text(20,19,((st>>14)&3u)==1?"CHOP":((st>>14)&3u)==2?"ARPEGGIO":"NORMAL");}
}
static void draw_composer_status(void){u32 st=UI[61],dt=UI[62];const char *state;
    state=(st&2048u)?"PANIC":(st&64u)?"LEARN PADS":(st&16u)?"THEME INPUT":(dt>>30)==1?"COUNT IN":(dt>>30)==2?"TAP RHYTHM":(st&512u)?"ENDING":(st&128u)?"LOCKED":(st&256u)?"LOCK AT END":(st&2u)?"PLAYING":"READY";
    rect_cells(0,19,100,3,5);composer_text(2,19,state);
    composer_text(24,19,(dt>>30)==1?"BEAT":"BAR");composer_text(29,19,u1d((dt>>30)==1?((((st>>16)&63u)-1u)>>2)%4u+1u:((st>>20)&3u)+1u));
    composer_text(34,19,"SEED");composer_text(40,19,u1d((st>>12)&15u));
    composer_text(48,19,"RHYTHM");composer_text(56,19,(st&1024u)?"LOCKED":"FREE");
    composer_text(68,19,"MISSED");composer_text(76,19,(dt&65535u)>999?"999+":u3d(dt&65535u));
    if(st&64u){composer_text(2,20,"HIT PAD");composer_text(11,20,u1d(((st>>29)&7u)+1u));composer_text(16,20,"PLAY / VAR / REPEAT / CONTRAST / END / LOCK / REC / CLEAR");}
    else if((dt>>30)==1)composer_text(2,20,"ONE BAR COUNT-IN: 1 - 2 - 3 - 4");
    else if((dt>>30)==2)composer_text(2,20,"TAP ANY PAD OR TAP BUTTON / TWO BARS");
    else if(st&16u)composer_text(2,20,"PLAY 1..8 NOTES BELOW / PRESS THEME AGAIN WHEN DONE");
    else composer_text(2,20,"UP: HIGHER / RIGHT: DENSER / RHYTHM LOCK OVERRIDES DENSITY");
    composer_text(2,21,"KEY");composer_text(6,21,ai_keys[composer_key]);composer_text(10,21,composer_minor?"MINOR":"MAJOR");
    composer_text(22,21,"BPM");composer_text(27,21,u3d(composer_bpm));composer_text(34,21,composer_forms[composer_form]);
    composer_text(62,21,backing_name[0]?backing_name:"LIVE AT ENTRY");
}
static void composer_marker(void){u8 x=(u8)(3u+(u32)composer_density*62u/127u),y=(u8)(16u-(u32)composer_direction*6u/127u);
    c_at(composer_x,composer_y,' ',5,0);composer_x=x;composer_y=y;c_at(x,y,'+',3,9);
}
static void draw_composer(void){u32 st=UI[61];
    button_box(2,5,16,3,(st&2u)?"STOP":"START",st&2u);
    button_box(19,5,16,3,"THEME",st&16u);button_box(36,5,16,3,"REC RHYTHM",st&32u);
    button_box(53,5,14,3,"LOCK",st&384u);button_box(68,5,14,3,"END",st&512u);
    button_box(83,5,15,3,composer_settings?"SURFACE":"SETTINGS",composer_settings);
    rect_cells(0,8,100,11,0);
    if(composer_settings){
        arp_row(2,8,"BPM",u3d(composer_bpm));arp_row(52,8,"KEY",ai_keys[composer_key]);
        arp_row(2,11,"FORM",composer_forms[composer_form]);arp_row(52,11,"SCALE",composer_minor?"MINOR":"MAJOR");
        arp_row(2,14,"VARIATION",u3d(composer_variation));arp_row(52,14,"STRENGTH",u3d(composer_strength));
        button_box(2,17,22,2,"LEARN 8 PADS",st&64u);button_box(26,17,22,2,"DEFAULT THEME",0);
        button_box(52,17,22,2,"CLEAR RHYTHM",0);button_box(76,17,22,2,"EXIT MODE",0);
    }else{
        rect_cells(2,9,65,9,5);composer_text(4,9,"HIGHER");composer_text(4,17,"LOWER");
        composer_text(26,9,"MELODY SCULPT");composer_text(50,17,"DENSER >");
        composer_x=34;composer_y=13;composer_marker();
        button_box(69,8,14,3,"VARIATION",0);button_box(84,8,14,3,"REPEAT",0);
        button_box(69,11,29,3,"CONTRAST PHRASE",0);
        button_box(69,14,14,3,"TAP",0);button_box(84,14,14,3,"NEW",0);
    }
    draw_composer_status();
}
static void composer_adj(u8 row,int d){int n;
    if(row==0){n=composer_bpm+d;composer_bpm=(u16)(n<30?30:n>240?240:n);}
    else if(row==1)composer_key=(u8)(((int)composer_key+d+12)%12);
    else if(row==2)composer_form=(u8)(((int)composer_form+d+3)%3);
    else if(row==3)composer_minor=!composer_minor;
    else if(row==4){n=composer_variation+d;composer_variation=(u8)(n<0?0:n>127?127:n);}
    else {n=composer_strength+d;composer_strength=(u8)(n<1?1:n>127?127:n);}
    composer_publish();draw_composer();
}
static void composer_drag(int x,int y){int a,b;
    if(composer_settings||x<16||x>=536||y<144||y>=288)return;
    a=(x-16)*127/519;b=(287-y)*127/143;
    if(a==composer_density&&b==composer_direction)return;
    composer_density=(u8)a;composer_direction=(u8)b;
    backing_word(0x3c4,(u16)(a|((u16)b<<8)));composer_marker();
}
static void composer_press(int x,int y){int row,local,d=0;u8 action=0;
    if(y>=80&&y<128){
        if(x>=16&&x<144)action=1;else if(x>=152&&x<280)action=9;
        else if(x>=288&&x<416)action=10;else if(x>=424&&x<536)action=8;
        else if(x>=544&&x<656)action=7;else if(x>=664&&x<784){composer_settings=!composer_settings;draw_composer();return;}
    }else if(composer_settings){
        if(y>=272&&y<304){if(x>=16&&x<192)action=12;else if(x>=208&&x<384)action=13;
            else if(x>=416&&x<592)action=11;else if(x>=608&&x<784){composer_stop();page_enter(7);return;}}
        else if(y>=128&&y<272&&((x>=16&&x<384)||(x>=416&&x<784))){
            row=((y-128)/48)*2+(x>=416);local=x-(x>=416?416:16);
            if(local>=128&&local<176)d=-1;else if(local>=320&&local<368)d=1;
            else if(local>=184&&local<312&&(row==2||row==3))d=1;
            if(d){held_row=(u8)row;held_kind=(row==3)?0:d<0?1:2;held_t=now();held_count=0;composer_adj((u8)row,d);}return;
        }
    }else{
        if(x>=16&&x<536&&y>=144&&y<288){composer_drag(x,y);held_kind=4;return;}
        if(y>=128&&y<176){if(x>=552&&x<664)action=4;else if(x>=672&&x<784)action=5;}
        else if(y>=176&&y<224&&x>=552&&x<784)action=6;
        else if(y>=224&&y<272){if(x>=552&&x<664)action=15;else if(x>=672&&x<784)action=14;}
    }
    if(action){composer_command(action);composer_last_status=~0u;}
}
static void composer_poll(void){u32 st;
    if((page!=PAGE_COMPOSER&&page!=PAGE_GESTURE)||(u32)(now()-composer_last_draw)<100000u)return;
    composer_last_draw=now();if(page==PAGE_GESTURE){draw_gesture_status();return;}st=UI[61];
    if((st^composer_last_status)&0xe000fff3u){composer_last_status=st;draw_composer();}
    else draw_composer_status();
}

/* Independent gesture instrument page; never enters a composer session. */
static void draw_gesture(void){u32 gs=UI[63];
    button_box(2,5,46,3,(gs&1u)?"RECOGNITION ON":"RECOGNITION OFF",gs&1u);
    button_box(52,5,46,3,(gs&2u)?"CONTROL ON":"CONTROL OFF",gs&2u);
    button_box(2,8,46,2,gesture_timbre?"MODE: TIMBRE":"MODE: RHYTHM",gesture_timbre);
    composer_text(4,10,"CHANGE GESTURE, RELEASE KEYS TO CHANGE PATCH");
    composer_text(4,21,gesture_timbre?"LEFT/RIGHT: BRIGHTNESS / UP: VIBRATO":"CHOP 1/16 / ARP 1/8 / 120 BPM");
    draw_gesture_status();
}
static void gesture_press(int x,int y){u32 gs=UI[63];
    if(y>=80&&y<128&&(gs&4u)){
        if(x>=16&&x<384)UI[63]=((gs&1u)?0:1)|(gesture_timbre?4u:0u);
        else if(x>=416&&x<784&&(gs&1u))UI[63]=((gs&3u)^2u)|(gesture_timbre?4u:0u);
        draw_gesture();
    }else if(y>=128&&y<160&&x>=16&&x<384){
        gesture_timbre=!gesture_timbre;UI[63]=(gs&1u)|(gesture_timbre?4u:0u);draw_gesture();
    }
}
