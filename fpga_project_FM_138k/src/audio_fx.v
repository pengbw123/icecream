// Post-mix effects engine.
//
// Step 2: DISTORTION -> FILTER (state-variable) -> output.  Later steps add
// phaser / chorus / delay / reverb between these blocks.
//
// Register map (6-bit address, 16-bit value):
//   0      GLOBAL: bit0 master enable, bit1 bypass
//   1..4   FILTER:   enable, type (0 LP / 1 BP / 2 HP), cutoff 0..99, Q 0..99
//   5..8   DISTORTION: enable, gain 0..99, tone 0..99, level 0..99
//   9..12  CHORUS   (reserved for step 3)
//   13..16 PHASER   (reserved for step 3)
//   17..20 DELAY    (reserved for step 4)
//   21..24 REVERB   (reserved for step 4)
//
// The audio path is a small multi-cycle FSM inside one sample period
// (1024 clocks at 50 MHz), so each step uses a single multiply and the
// 50 MHz timing does not depend on how many effects are compiled in.
module audio_fx (
    input  wire               clk,
    input  wire               reset_n,
    input  wire               sample_tick,
    input  wire signed [15:0] dry_sample,
    input  wire               cfg_write,
    input  wire [5:0]         cfg_addr,
    input  wire [15:0]        cfg_value,
    input  wire [5:0]         read_addr,
    output wire [15:0]        read_value,
    output reg  signed [15:0] sample_out
);

    reg [15:0] cfg [0:31];
    integer i;
    assign read_value = cfg[read_addr];

    // Parameter tables (tools/generators/generate_audio_fx_tables.py)
    reg signed [15:0] filter_f [0:99];
    reg signed [15:0] filter_q [0:99];
    reg signed [15:0] tone_tab [0:99];
    reg signed [15:0] level_tab [0:99];
    reg [7:0]         dist_gain [0:99];
    initial begin
        $readmemh("src/generated/fx_filter_f.mem", filter_f);
        $readmemh("src/generated/fx_filter_q.mem", filter_q);
        $readmemh("src/generated/fx_tone_coeff.mem", tone_tab);
        $readmemh("src/generated/fx_level_gain.mem", level_tab);
        $readmemh("src/generated/fx_dist_gain.mem", dist_gain);
    end

    function signed [15:0] sat16;
        input signed [31:0] v;
        begin
            if (v > 32'sd32767) sat16 = 16'sd32767;
            else if (v < -32'sd32768) sat16 = -16'sd32768;
            else sat16 = v[15:0];
        end
    endfunction

    function signed [23:0] sat24;
        input signed [31:0] v;
        begin
            if (v > 32'sd8388607) sat24 = 24'sd8388607;
            else if (v < -32'sd8388608) sat24 = -24'sd8388608;
            else sat24 = v[23:0];
        end
    endfunction

    function signed [15:0] soft_clip;
        input signed [31:0] v;
        begin
            if (v > 32'sd16384)
                soft_clip = sat16(32'sd16384 + ((v - 32'sd16384) >>> 2));
            else if (v < -32'sd16384)
                soft_clip = sat16(-32'sd16384 + ((v + 32'sd16384) >>> 2));
            else
                soft_clip = sat16(v);
        end
    endfunction

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < 32; i = i + 1) cfg[i] <= 16'd0;
            cfg[0]  <= 16'h0001;
            cfg[3]  <= 16'd99;  cfg[4]  <= 16'd20;
            cfg[6]  <= 16'd20;  cfg[7]  <= 16'd50;  cfg[8]  <= 16'd80;
            cfg[10] <= 16'd30;  cfg[11] <= 16'd40;  cfg[12] <= 16'd30;
            cfg[14] <= 16'd25;  cfg[15] <= 16'd40;  cfg[16] <= 16'd30;
            cfg[18] <= 16'd35;  cfg[19] <= 16'd40;  cfg[20] <= 16'd30;
            cfg[22] <= 16'd0;   cfg[23] <= 16'd45;  cfg[24] <= 16'd30;
        end else if (cfg_write) begin
            cfg[cfg_addr] <= cfg_value;
        end
    end

    localparam [4:0] S_IDLE=5'd0, S_CLIP=5'd1, S_TONE_A=5'd2, S_TONE_B=5'd3,
                     S_LEVEL=5'd4, S_LEVEL2=5'd5, S_OUTD=5'd6,
                     S_FLP1=5'd7, S_FLP2=5'd8, S_FHP1=5'd9, S_FBP1=5'd10,
                     S_FSEL=5'd11, S_OUT=5'd12, S_DFIN=5'd13;

    reg [4:0] state;
    reg signed [15:0] dry_q, d_out, chain_q, df_out, tone_state, clipped;
    reg signed [31:0] driven, prod;
    reg signed [23:0] lp, bp, lp_tmp, hp_tmp, bp_new;
    reg signed [39:0] prod1, prod2, prod3;

    reg        dist_en, filt_en;
    reg [1:0]  ftype;
    reg [7:0]  dgain;
    reg signed [15:0] tcoef, lgain, fcoef, qcoef;

    wire global_on = cfg[0][0];
    wire bypass    = cfg[0][1];

    wire [6:0] cutoff_i = (cfg[3] > 16'd99) ? 7'd99 : cfg[3][6:0];
    wire [6:0] q_i      = (cfg[4] > 16'd99) ? 7'd99 : cfg[4][6:0];
    wire [6:0] gain_i   = (cfg[6] > 16'd99) ? 7'd99 : cfg[6][6:0];
    wire [6:0] tone_i   = (cfg[7] > 16'd99) ? 7'd99 : cfg[7][6:0];
    wire [6:0] level_i  = (cfg[8] > 16'd99) ? 7'd99 : cfg[8][6:0];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE;
            dry_q <= 16'sd0; d_out <= 16'sd0; chain_q <= 16'sd0; df_out <= 16'sd0;
            tone_state <= 16'sd0; clipped <= 16'sd0;
            driven <= 32'sd0; prod <= 32'sd0;
            lp <= 24'sd0; bp <= 24'sd0; lp_tmp <= 24'sd0; hp_tmp <= 24'sd0;
            bp_new <= 24'sd0; prod1 <= 40'sd0; prod2 <= 40'sd0; prod3 <= 40'sd0;
            dist_en <= 1'b0; filt_en <= 1'b0; ftype <= 2'd0; dgain <= 8'd1;
            tcoef <= 16'sd0; lgain <= 16'sd0; fcoef <= 16'sd0; qcoef <= 16'sd0;
        end else begin
            case (state)
                S_IDLE: if (sample_tick) begin
                    dry_q <= dry_sample;
                    dist_en <= cfg[5][0];
                    filt_en <= cfg[1][0];
                    ftype <= cfg[2][1:0];
                    dgain <= dist_gain[gain_i];
                    tcoef <= tone_tab[tone_i];
                    lgain <= level_tab[level_i];
                    fcoef <= filter_f[cutoff_i];
                    qcoef <= filter_q[q_i];
                    state <= S_CLIP;
                end
                S_CLIP: begin
                    driven <= $signed(dry_q) * $signed({1'b0, dgain});
                    state <= S_TONE_A;
                end
                S_TONE_A: begin
                    if (!dist_en) begin
                        d_out <= dry_q;
                        state <= S_OUTD;
                    end else begin
                        clipped <= soft_clip(driven);
                        state <= S_TONE_B;
                    end
                end
                S_TONE_B: begin
                    prod <= $signed(tcoef) * $signed(clipped - tone_state);
                    state <= S_LEVEL;
                end
                S_LEVEL: begin
                    tone_state <= sat16($signed(tone_state) + (prod >>> 15));
                    state <= S_LEVEL2;
                end
                S_LEVEL2: begin
                    prod <= $signed(tone_state) * $signed(lgain);
                    state <= S_OUTD;
                end
                S_OUTD: begin
                    if (dist_en) d_out <= sat16(prod >>> 15);
                    else d_out <= dry_q;
                    state <= S_DFIN;
                end
                S_DFIN: begin
                    if (!filt_en) begin chain_q <= d_out; state <= S_OUT; end
                    else state <= S_FLP1;
                end
                S_FLP1: begin
                    prod1 <= $signed(fcoef) * $signed(bp);
                    state <= S_FLP2;
                end
                S_FLP2: begin
                    lp_tmp <= sat24($signed(lp) + (prod1 >>> 14));
                    prod2 <= $signed(qcoef) * $signed(bp);
                    state <= S_FHP1;
                end
                S_FHP1: begin
                    hp_tmp <= sat24(($signed(d_out) <<< 8) - lp_tmp - (prod2 >>> 14));
                    state <= S_FBP1;
                end
                S_FBP1: begin
                    prod3 <= $signed(fcoef) * $signed(hp_tmp);
                    state <= S_FSEL;
                end
                S_FSEL: begin
                    lp <= lp_tmp;
                    bp_new <= sat24($signed(bp) + (prod3 >>> 14));
                    bp <= sat24($signed(bp) + (prod3 >>> 14));
                    case (ftype)
                        2'd0: chain_q <= sat16(lp_tmp >>> 8);
                        2'd1: chain_q <= sat16(bp_new >>> 8);
                        default: chain_q <= sat16(hp_tmp >>> 8);
                    endcase
                    state <= S_OUT;
                end
                S_OUT: begin
                    df_out <= chain_q;      // DISTORTION/FILTER stage result
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
    wire signed [15:0] chorus_out, phaser_out;
    audio_chorus u_chorus(.clk(clk),.reset_n(reset_n),.sample_tick(sample_tick),
        .in_sample(df_out),.enable(cfg[9][0]),
        .freq(cfg[10][6:0]),.depth(cfg[11][6:0]),.mix(cfg[12][6:0]),
        .out_sample(chorus_out));
    audio_phaser u_phaser(.clk(clk),.reset_n(reset_n),.sample_tick(sample_tick),
        .in_sample(chorus_out),.enable(cfg[13][0]),
        .freq(cfg[14][6:0]),.depth(cfg[15][6:0]),.mix(cfg[16][6:0]),
        .out_sample(phaser_out));

    // No effect enabled -> exact dry (no pipeline latency).  Bypass and
    // master-off are also bit-exact.  The real chain has 2-3 samples latency.
    wire any_enabled = cfg[1][0]|cfg[5][0]|cfg[9][0]|cfg[13][0]|
                       cfg[17][0]|cfg[21][0];
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) sample_out <= 16'sd0;
        else sample_out <= (!global_on || bypass || !any_enabled) ? dry_sample : phaser_out;
    end
endmodule

