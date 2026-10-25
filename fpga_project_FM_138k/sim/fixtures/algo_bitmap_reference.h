// Frozen pre-optimization rasterizer; golden test reference only.
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
