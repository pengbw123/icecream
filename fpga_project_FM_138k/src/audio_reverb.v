// Three-comb + all-pass reverb derived from audio_effects.v, with the comb
// lengths selected by REVERB TYPE (ROOM/HALL/PLATE) and decay by the DECAY
// register.  All memories are simple dual-port (one write, registered reads).
module audio_reverb (
    input  wire               clk,
    input  wire               reset_n,
    input  wire               sample_tick,
    input  wire signed [15:0] in_sample,
    input  wire               enable,
    input  wire [1:0]         rtype,    // 0 room, 1 hall, 2 plate
    input  wire [6:0]         decay,    // 0..99 -> 0.30..0.95
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
    reg signed [15:0] ap_mem [0:4095];

    reg [11:0] w1, w2, w3, wap;
    reg [16:0] wcount;
    reg [11:0] r1, r2, r3, rap;
    reg [11:0] l1, l2, l3, lap;
    reg [6:0]  st;
    reg signed [15:0] in_q, t1, t2, t3, ap_in, ap_in_prev, tap_ap;
    reg signed [15:0] ap_out, ap_wdat, wet;
    reg signed [31:0] s12, s123, prod, mix_prod;
    reg signed [15:0] fb_q, mix_q;

    reg signed [15:0] fb_tab [0:99];
    reg signed [15:0] mix_tab [0:99];
    initial begin
        $readmemh("src/generated/fx_reverb_fb.mem", fb_tab);
        $readmemh("src/generated/fx_level_gain.mem", mix_tab);
    end

    wire [6:0] decay_i = (decay > 7'd99) ? 7'd99 : decay;
    wire [6:0] mix_i   = (mix   > 7'd99) ? 7'd99 : mix;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            w1 <= 0; w2 <= 0; w3 <= 0; wap <= 0;
            r1 <= 0; r2 <= 0; r3 <= 0; rap <= 0;
            l1 <= 1499; l2 <= 1777; l3 <= 2137; lap <= 521;
            st <= 0; in_q <= 0; t1 <= 0; t2 <= 0; t3 <= 0; wcount <= 0;
            ap_in <= 0; ap_in_prev <= 0; tap_ap <= 0;
            ap_out <= 0; ap_wdat <= 0; wet <= 0;
            s12 <= 0; s123 <= 0; prod <= 0; mix_prod <= 0;
            fb_q <= 0; mix_q <= 0; out_sample <= 0;
        end else begin
            case (st)
                7'd0: if (sample_tick) begin
                    in_q <= in_sample;
                    fb_q <= fb_tab[decay_i];
                    mix_q <= mix_tab[mix_i];
                    case (rtype)
                        2'd1: begin l1 <= 2101; l2 <= 2491; l3 <= 3001; lap <= 733; end
                        2'd2: begin l1 <= 1139; l2 <= 1301; l3 <= 1607; lap <= 389; end
                        default: begin l1 <= 1499; l2 <= 1777; l3 <= 2137; lap <= 521; end
                    endcase
                    st <= 7'd1;
                end
                7'd1: begin r1 <= w1 - l1; st <= 7'd2; end
                7'd2: begin t1 <= comb1[r1]; r2 <= w2 - l2; st <= 7'd3; end
                7'd3: begin t2 <= comb2[r2]; r3 <= w3 - l3; st <= 7'd4; end
                7'd4: begin
                    t3 <= comb3[r3];
                    s12 <= ((wcount >= {4'd0, l1}) ? t1 : 16'sd0) +
                           ((wcount >= {4'd0, l2}) ? t2 : 16'sd0);
                    st <= 7'd5;
                end
                7'd5: begin
                    s123 <= s12 + ((wcount >= {4'd0, l3}) ? t3 : 16'sd0);
                    st <= 7'd6;
                end
                7'd6: begin prod <= s123 * $signed(fb_q); st <= 7'd7; end
                7'd7: begin
                    wet <= sat16($signed(in_q) + (prod >>> 15));
                    comb1[w1] <= sat16($signed(in_q) + (prod >>> 15));
                    comb2[w2] <= sat16($signed(in_q) + (prod >>> 15));
                    comb3[w3] <= sat16($signed(in_q) + (prod >>> 15));
                    w1 <= w1 + 1'b1; w2 <= w2 + 1'b1; w3 <= w3 + 1'b1;
                    if (wcount < 17'h1FFFF) wcount <= wcount + 1'b1;
                    rap <= wap - lap;
                    st <= 7'd8;
                end
                7'd8: st <= 7'd9;
                7'd9: begin
                    tap_ap <= (wcount >= {4'd0, lap}) ? ap_mem[rap] : 16'sd0;
                    ap_in_prev <= (wcount >= {4'd0, lap}) ? wet : 16'sd0;
                    st <= 7'd10;
                end
                7'd10: begin
                    ap_out <= tap_ap - (ap_in_prev >>> 1);
                    ap_wdat <= ap_in_prev + ((tap_ap - (ap_in_prev >>> 1)) >>> 1);
                    st <= 7'd11;
                end
                7'd11: begin
                    ap_mem[wap] <= ap_wdat;
                    wap <= wap + 1'b1;
                    mix_prod <= $signed(ap_out - in_q) * $signed(mix_q);
                    st <= 7'd12;
                end
                default: begin
                    out_sample <= enable ? sat16($signed(in_q) + (mix_prod >>> 15)) : in_q;
                    st <= 7'd0;
                end
            endcase
        end
    end
endmodule
