// 20..1000 ms mono feedback delay; two-tap crossfade on time changes.
// One synchronous memory read port; finishes in <32 system clocks.
module audio_delay (
    input wire clk,reset_n,sample_tick,
    input wire signed [15:0] in_sample,
    input wire enable,
    input wire [6:0] decay,rate,mix,
    output reg signed [15:0] out_sample
);
    function signed [15:0] sat16;
        input signed [47:0] v;
        begin
            if(v>32767) sat16=32767;
            else if(v< -32768) sat16=-32768;
            else sat16=v[15:0];
        end
    endfunction
    // Feedback must decay towards zero in BOTH polarities. Arithmetic
    // shift alone leaves negative one-LSB echoes circulating forever.
    function signed [31:0] trunc15;
        input signed [47:0] v;
        begin trunc15=(v<0)?-((-v)>>>15):(v>>>15);end
    endfunction
    reg signed [15:0] mem[0:65535];
    reg [15:0] wptr,raddr,delay_a,delay_b;
    reg [16:0] wcount;
    reg [4:0] st;
    reg [9:0] fade; // 0..512 = 10.49 ms
    reg fading,enabled_q;
    reg signed [15:0] in_q,tap,tap_a,tap_b,wet,wdat,fb_q,mix_q;
    reg signed [31:0] damp_q12;
    reg signed [47:0] prod,mix_prod;
    reg [15:0] len_tab[0:99];
    reg signed [15:0] fb_tab[0:99],mix_tab[0:99];
    initial begin
        $readmemh("src/generated/fx_delay_len.mem",len_tab);
        $readmemh("src/generated/fx_delay_fb.mem",fb_tab);
        $readmemh("src/generated/fx_level_gain.mem",mix_tab);
    end
    wire [6:0] decay_i=(decay>99)?7'd99:decay;
    wire [6:0] rate_i=(rate>99)?7'd99:rate;
    wire [6:0] mix_i=(mix>99)?7'd99:mix;
    wire signed [31:0] damp_target=$signed(wet)*32'sd4096;
    wire signed [31:0] damp_next=damp_q12+((damp_target-damp_q12)>>>1);
    wire signed [31:0] damp_integer=(damp_next<0)?-((-damp_next)>>>12):(damp_next>>>12);
    always @(posedge clk) begin
        if(st==12) mem[wptr]<=wdat;
        tap<=mem[raddr];
    end
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            wptr<=0;raddr<=0;wcount<=0;st<=0;
            delay_a<=976;delay_b<=976;fade<=0;fading<=0;enabled_q<=0;
            in_q<=0;tap_a<=0;tap_b<=0;wet<=0;wdat<=0;
            fb_q<=0;mix_q<=0;prod<=0;mix_prod<=0;damp_q12<=0;out_sample<=0;
        end else case(st)
            0: if(sample_tick) begin
                in_q<=in_sample;enabled_q<=enable;
                fb_q<=fb_tab[decay_i];mix_q<=mix_tab[mix_i];
                // Both read heads remain fixed during a fade. Pick up the
                // latest requested time only after the previous fade ends.
                if(wcount==0) begin
                    delay_a<=len_tab[rate_i];delay_b<=len_tab[rate_i];
                end else if(!fading && len_tab[rate_i]!=delay_a) begin
                    delay_b<=len_tab[rate_i];fade<=0;fading<=1;
                end
                st<=1;
            end
            1: begin raddr<=wptr-delay_a;st<=2;end
            2: st<=3;
            3: begin
                tap_a<=(wcount>={1'b0,delay_a})?tap:16'sd0;
                raddr<=wptr-delay_b;st<=4;
            end
            4: st<=5;
            5: begin tap_b<=(wcount>={1'b0,delay_b})?tap:16'sd0;st<=6;end
            6: begin
                prod<=($signed({tap_b[15],tap_b})-$signed({tap_a[15],tap_a}))*$signed({1'b0,fade});
                st<=7;
            end
            7: begin wet<=fading?sat16($signed(tap_a)+(prod>>>9)):tap_a;st<=8;end
            8: begin damp_q12<=damp_next;prod<=damp_integer*$signed(fb_q);st<=9;end
            9: begin
                wdat<=sat16($signed(in_q)+trunc15(prod));
                mix_prod<=($signed({wet[15],wet})-$signed({in_q[15],in_q}))*$signed(mix_q);
                st<=10;
            end
           10: begin
                if(fading) begin
                    if(fade==512) begin delay_a<=delay_b;fading<=0;fade<=0;end
                    else fade<=fade+1'b1;
                end
                st<=11;
            end
           11: st<=12;
           12: begin
                wptr<=wptr+1'b1;
                if(wcount<17'd65536) wcount<=wcount+1'b1;
                out_sample<=enabled_q?sat16($signed(in_q)+(mix_prod>>>15)):in_q;
                st<=0;
            end
            default:st<=0;
        endcase
    end
endmodule
