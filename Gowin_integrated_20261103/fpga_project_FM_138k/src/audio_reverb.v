// Four parallel damped combs followed by two serial all-pass diffusers.
// Each comb feeds back only its own damped tap. The 29-bit Q12 DC blocker
// prevents the integer-rounding bias that once left a permanent tail offset.
module audio_reverb (
    input  wire               clk,
    input  wire               reset_n,
    input  wire               sample_tick,
    input  wire signed [15:0] in_sample,
    input  wire               enable,
    input  wire [1:0]         rtype,    // 0 room, 1 hall, 2 plate
    input  wire [6:0]         decay,    // 0..99 -> 0.50..0.90 plus type offset
    input  wire [6:0]         mix,      // 0..99
    output reg  signed [15:0] out_sample
);
    function signed [15:0] sat16;
        input signed [31:0] v;
        begin
            if (v > 32'sd32767) sat16 = 16'sd32767;
            else if (v < -32'sd32768) sat16 = -16'sd32768;
            else sat16 = v[15:0];
        end
    endfunction

    reg signed [15:0] comb1 [0:4095];
    reg signed [15:0] comb2 [0:4095];
    reg signed [15:0] comb3 [0:4095];
    reg signed [15:0] comb4 [0:4095];
    reg signed [15:0] ap_mem [0:4095];
    reg signed [15:0] ap_mem2 [0:4095];

    reg [11:0] w1, w2, w3, w4, wap, wap2;
    reg [11:0] r1, r2, r3, r4, rap, rap2;
    reg [11:0] l1, l2, l3, l4, lap, lap2;
    reg [16:0] wcount;
    reg [4:0]  st;
    reg signed [15:0] in_q, t1, t2, t3, t4, tap_ap, tap_ap2;
    reg signed [15:0] ap_in_prev, ap_out, ap_wdat, ap2_in, ap2_out, ap2_wdat;
    reg signed [15:0] wd1, wd2, wd3, wd4, damp1, damp2, damp3, damp4;
    reg signed [31:0] prod1, prod2, prod3, prod4, sum12, sum34, sum4;
    reg signed [47:0] mix_prod;
    reg signed [28:0] dc_state;
    reg signed [15:0] fb_q, mix_q;

    reg signed [15:0] fb_tab [0:99];
    reg signed [15:0] mix_tab [0:99];
    initial begin
        $readmemh("src/generated/fx_reverb_fb.mem", fb_tab);
        $readmemh("src/generated/fx_level_gain.mem", mix_tab);
    end

    wire [6:0] decay_i = (decay > 7'd99) ? 7'd99 : decay;
    wire [6:0] mix_i   = (mix   > 7'd99) ? 7'd99 : mix;
    wire signed [31:0] ap_y = $signed(tap_ap) - ($signed(ap_in_prev) >>> 1);
    wire signed [31:0] ap2_y = $signed(tap_ap2) - ($signed(ap2_in) >>> 1);
    wire signed [28:0] dc_target = $signed({ap2_out[15],ap2_out,12'b0});
    wire signed [28:0] dc_error = dc_target - dc_state;
    wire signed [31:0] wet_hp = $signed({ap2_out[15], ap2_out}) -
                                  $signed(dc_state >>> 12);
    wire signed [17:0] feedback_adjusted = $signed(fb_tab[decay_i]) +
        ((rtype == 2'd1) ? 18'sd1311 : (rtype == 2'd2) ? 18'sd655 : 18'sd0);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            w1<=0; w2<=0; w3<=0; w4<=0; wap<=0; wap2<=0;
            r1<=0; r2<=0; r3<=0; r4<=0; rap<=0; rap2<=0;
            l1<=1499; l2<=1777; l3<=2137; l4<=2677; lap<=521; lap2<=337;
            wcount<=0; st<=0;
            in_q<=0; t1<=0; t2<=0; t3<=0; t4<=0; tap_ap<=0; tap_ap2<=0;
            ap_in_prev<=0; ap_out<=0; ap_wdat<=0;
            ap2_in<=0; ap2_out<=0; ap2_wdat<=0;
            wd1<=0; wd2<=0; wd3<=0; wd4<=0;
            damp1<=0; damp2<=0; damp3<=0; damp4<=0;
            prod1<=0; prod2<=0; prod3<=0; prod4<=0;
            sum12<=0; sum34<=0; sum4<=0; mix_prod<=0;
            dc_state<=0; fb_q<=0; mix_q<=0; out_sample<=0;
        end else begin
            case (st)
                4'd0: if (sample_tick) begin
                    in_q <= in_sample;
                    fb_q <= (feedback_adjusted > 18'sd31457)
                        ? 16'sd31457 : feedback_adjusted[15:0];
                    mix_q <= mix_tab[mix_i];
                    case (rtype)
                        2'd1: begin l1<=2101; l2<=2491; l3<=3001; l4<=3607;
                                      lap<=733; lap2<=487; end
                        2'd2: begin l1<=1139; l2<=1301; l3<=1607; l4<=1901;
                                      lap<=389; lap2<=263; end
                        default: begin l1<=1499; l2<=1777; l3<=2137; l4<=2677;
                                       lap<=521; lap2<=337; end
                    endcase
                    st <= 4'd1;
                end
                4'd1: begin r1<=w1-l1; st<=4'd2; end
                4'd2: begin t1<=comb1[r1]; r2<=w2-l2; st<=4'd3; end
                4'd3: begin t2<=comb2[r2]; r3<=w3-l3; r4<=w4-l4; st<=4'd4; end
                4'd4: begin t3<=comb3[r3]; t4<=comb4[r4]; st<=4'd5; end
                4'd5: begin
                    if (wcount >= {5'd0, l1}) prod1 <= $signed(damp1) * $signed(fb_q);
                    else prod1 <= 0;
                    if (wcount >= {5'd0, l2}) prod2 <= $signed(damp2) * $signed(fb_q);
                    else prod2 <= 0;
                    if (wcount >= {5'd0, l3}) prod3 <= $signed(damp3) * $signed(fb_q);
                    else prod3 <= 0;
                    if (wcount >= {5'd0, l4}) prod4 <= $signed(damp4) * $signed(fb_q);
                    else prod4 <= 0;
                    damp1 <= (wcount >= {5'd0,l1}) ?
                        sat16($signed(damp1) + (($signed(t1)-$signed(damp1)) >>> 2)) : 0;
                    damp2 <= (wcount >= {5'd0,l2}) ?
                        sat16($signed(damp2) + (($signed(t2)-$signed(damp2)) >>> 2)) : 0;
                    damp3 <= (wcount >= {5'd0,l3}) ?
                        sat16($signed(damp3) + (($signed(t3)-$signed(damp3)) >>> 2)) : 0;
                    damp4 <= (wcount >= {5'd0,l4}) ?
                        sat16($signed(damp4) + (($signed(t4)-$signed(damp4)) >>> 2)) : 0;
                    sum12 <= ((wcount >= {5'd0, l1}) ? $signed(t1) : 32'sd0) +
                             ((wcount >= {5'd0, l2}) ? $signed(t2) : 32'sd0);
                    sum34 <= ((wcount >= {5'd0, l3}) ? $signed(t3) : 32'sd0) +
                             ((wcount >= {5'd0, l4}) ? $signed(t4) : 32'sd0);
                    st <= 4'd6;
                end
                4'd6: begin
                    sum4 <= sum12 + sum34;
                    wd1 <= sat16(($signed(in_q) >>> 1) + (prod1 >>> 15));
                    wd2 <= sat16(($signed(in_q) >>> 1) + (prod2 >>> 15));
                    wd3 <= sat16(($signed(in_q) >>> 1) + (prod3 >>> 15));
                    wd4 <= sat16(($signed(in_q) >>> 1) + (prod4 >>> 15));
                    st <= 4'd7;
                end
                4'd7: begin
                    comb1[w1] <= wd1; comb2[w2] <= wd2;
                    comb3[w3] <= wd3; comb4[w4] <= wd4;
                    w1<=w1+1'b1; w2<=w2+1'b1; w3<=w3+1'b1; w4<=w4+1'b1;
                    rap<=wap-lap;
                    st<=4'd8;
                end
                4'd8: st<=4'd9;
                4'd9: begin
                    tap_ap <= (wcount >= {5'd0, lap}) ? ap_mem[rap] : 16'sd0;
                    ap_in_prev <= sat16(sum4 >>> 1);
                    st<=4'd10;
                end
                4'd10: begin
                    ap_out <= sat16(ap_y);
                    ap_wdat <= sat16($signed(ap_in_prev) + (ap_y >>> 1));
                    st<=4'd11;
                end
                4'd11: begin
                    ap_mem[wap] <= ap_wdat;
                    wap <= wap + 1'b1;
                    if (wcount < 17'h1FFFF) wcount <= wcount + 1'b1;
                    rap2 <= wap2-lap2;
                    st<=4'd12;
                end
                4'd12: st<=4'd13;
                4'd13: begin
                    // wcount was advanced at state 11, before this read.
                    tap_ap2 <= (wcount > {5'd0, lap2}) ? ap_mem2[rap2] : 16'sd0;
                    ap2_in <= ap_out;
                    st<=4'd14;
                end
                4'd14: begin
                    ap2_out <= sat16(ap2_y);
                    ap2_wdat <= sat16($signed(ap2_in) + (ap2_y >>> 1));
                    st<=4'd15;
                end
                4'd15: begin
                    ap_mem2[wap2] <= ap2_wdat;
                    wap2 <= wap2 + 1'b1;
                    // DC blocker on the final wet path.
                    dc_state <= dc_state + (dc_error >>> 8);
                    mix_prod <= (wet_hp - $signed({in_q[15], in_q})) * $signed(mix_q);
                    st<=5'd16;
                end
                default: begin
                    out_sample <= (enable && mix_q != 0)
                        ? sat16($signed(in_q) + (mix_prod >>> 15)) : in_q;
                    st<=4'd0;
                end
            endcase
        end
    end
endmodule
