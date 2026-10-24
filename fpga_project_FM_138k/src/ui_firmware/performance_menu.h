/* Passive RTL telemetry. Snapshot refresh is independent of audio scheduling. */
static u32 metrics[18],metrics_last_poll;
static u8 metrics_frozen;
static char metrics_number[12],metrics_pair[40];
static const char *metrics_u32(u32 v){char reverse[10];u8 n=0,i=0;
    do{reverse[n++]=(char)('0'+v%10u);v/=10u;}while(v);
    while(n)metrics_number[i++]=reverse[--n];metrics_number[i]=0;return metrics_number;
}
static void metrics_append(char *out,u8 *n,const char *s){while(*s&&*n<38)out[(*n)++]=*s++;out[*n]=0;}
static const char *metrics_two(u32 a,u32 b){u8 n=0;metrics_pair[0]=0;
    metrics_append(metrics_pair,&n,metrics_u32(a));metrics_append(metrics_pair,&n," / ");
    metrics_append(metrics_pair,&n,metrics_u32(b));return metrics_pair;
}
static void metrics_decimal(char *out,u8 *n,u32 v,u32 scale){u32 f=v%scale;
    metrics_append(out,n,metrics_u32(v/scale));metrics_append(out,n,".");
    if(scale==100&&f<10)metrics_append(out,n,"0");metrics_append(out,n,metrics_u32(f));
}
static const char *metrics_time(u32 packed){u8 n=0;u32 mhz=metrics[1]/1000000u;if(!mhz)mhz=50;
    metrics_pair[0]=0;metrics_decimal(metrics_pair,&n,(packed&65535u)*100u/mhz,100);
    metrics_append(metrics_pair,&n," / ");metrics_decimal(metrics_pair,&n,(packed>>16)*100u/mhz,100);
    metrics_append(metrics_pair,&n," us");return metrics_pair;
}
static const char *metrics_load(void){u8 n=0;u32 budget=metrics[3]?metrics[3]:metrics[2];u32 a,b;
    if(!budget)budget=1024;a=(metrics[7]&65535u)*1000u/budget;b=(metrics[7]>>16)*1000u/budget;
    metrics_pair[0]=0;metrics_decimal(metrics_pair,&n,a,10);metrics_append(metrics_pair,&n," / ");
    metrics_decimal(metrics_pair,&n,b,10);metrics_append(metrics_pair,&n," %");return metrics_pair;
}
static void metrics_read(void){u8 i;UI[58]=1;for(i=0;i<18;i++){UI[56]=i;metrics[i]=UI[57];}}
static void draw_metrics_values(void){u32 v=metrics[13];
    if(metrics[0]!=0x50455231u){text(3,9,"TELEMETRY NOT CONNECTED",2,0);return;}
    row_box(2,8,46,3,"VOICES NOW / PEAK",metrics_two(v&255u,(v>>8)&255u),0);
    row_box(2,11,46,3,"RENDER NOW / MAX",metrics_time(metrics[5]),0);
    row_box(2,14,46,3,"READY NOW / MAX",metrics_time(metrics[6]),0);
    row_box(2,17,46,3,"BUSY NOW / PEAK",metrics_load(),0);
    row_box(2,20,46,3,"SAMPLE PERIOD CLKS",metrics_u32(metrics[3]),0);
    row_box(2,23,46,3,"RENDERED FRAMES",metrics_u32(metrics[4]),0);
    row_box(52,8,46,3,"DEADLINE MISSES",metrics_u32(metrics[8]),metrics[8]!=0);
    row_box(52,11,46,3,"LOST SAMPLE TICKS",metrics_u32(metrics[9]),metrics[9]!=0);
    row_box(52,14,46,3,"VOICE STEALS",metrics_u32(metrics[10]),0);
    row_box(52,17,46,3,"BRIDGE DROPS",metrics_u32(metrics[11]),metrics[11]!=0);
    row_box(52,20,46,3,"MIDI ACCEPTED",metrics_u32(metrics[12]),0);
    row_box(52,23,46,3,"MIDI STALL CLKS",metrics_u32(metrics[14]),0);
}
static void draw_metrics(void){
    text(3,5,"AUDIO PERFORMANCE / RTL COUNTERS",2,0);
    text(3,6,"50 MHz / 48.828 kHz /",2,0);text(24,6,metrics_u32(UI[59]),2,0);text(27,6,"VOICES",2,0);
    text(53,5,"RENDER: COMPUTE / READY: TICK TO RESULT",2,0);
    text(53,6,"DIGITAL ENGINE ONLY / NOT KEY-TO-EAR LATENCY",2,0);
    draw_metrics_values();
    button_box(2,27,24,3,"< SETUP",0);
    button_box(28,27,32,3,metrics_frozen?"RESUME METRICS":"FREEZE METRICS",metrics_frozen);
    button_box(62,27,36,3,"CLEAR COUNTERS",0);
}
static void metrics_press(int x,int y){
    if(y<432||y>=480)return;
    if(x>=16&&x<208){page_enter(7);return;}
    if(x>=224&&x<480)metrics_frozen=!metrics_frozen;
    else if(x>=496&&x<784){UI[58]=2;metrics_read();}
    draw_metrics();
}
static void metrics_poll(void){
    if(page!=PAGE_METRICS||metrics_frozen||(u32)(now()-metrics_last_poll)<500000u)return;
    metrics_last_poll=now();metrics_read();draw_metrics_values();
}
