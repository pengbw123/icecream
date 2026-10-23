// Post-mix effects engine.
//
// Chain (matches the FM-1 panel order):
//   FILTER -> REVERB -> DELAY -> DISTORTION -> CHORUS -> PHASER
//
// Register map (6-bit address, 16-bit value, UI order is independent):
//   0      GLOBAL: bit0 master enable, bit1 bypass
//   1..4   FILTER:   enable, type (0 LP / 1 BP / 2 HP), cutoff 0..99, Q 0..99
//   5..8   DISTORTION: enable, gain 0..99, tone 0..99, wet mix 0..99
//   9..12  CHORUS: enable, freq, depth, mix
//   13..16 PHASER: enable, freq, depth, mix
//   17..20 DELAY: enable, decay, rate, mix
//   21..24 REVERB: enable, type, decay, mix
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
    reg [15:0]        dist_drive [0:99];
    reg [15:0]        dist_makeup [0:99];
    reg [15:0]        dist_initial_gain [0:99];
    reg signed [15:0] tanh_lut [0:511];
    initial begin
        $readmemh("src/generated/fx_filter_f.mem", filter_f);
        $readmemh("src/generated/fx_filter_q.mem", filter_q);
        $readmemh("src/generated/fx_tone_coeff.mem", tone_tab);
        $readmemh("src/generated/fx_level_gain.mem", level_tab);
        $readmemh("src/generated/fx_dist_drive.mem", dist_drive);
        $readmemh("src/generated/fx_dist_makeup.mem", dist_makeup);
        $readmemh("src/generated/fx_dist_initial_gain.mem", dist_initial_gain);
        $readmemh("src/generated/fx_tanh_lut.mem", tanh_lut);
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

    // One-pole parameter smoothing in Q8, ~5 ms at 48.8 kHz (shift 8).
    function [23:0] smooth24;
        input [23:0] cur;
        input [15:0] tgt;
        reg signed [24:0] d;
        reg signed [24:0] step;
        reg signed [24:0] next_value;
        begin
            d = $signed({1'b0, tgt, 8'b0}) - $signed({1'b0, cur});
            // Keep the shift and addition signed. With unsigned cur in the
            // original expression, a negative d shifted as a large positive
            // number, so lowering a parameter made its Q8 state wrap.
            // An upward difference smaller than one Q8 parameter unit
            // otherwise rounds to zero forever (99 stops at integer 98).
            // Move one fractional LSB until the exact target is reached.
            step = (d > 25'sd0 && d < 25'sd256) ? 25'sd1 : (d >>> 8);
            next_value = $signed({1'b0, cur}) + step;
            smooth24 = next_value[23:0];
        end
    endfunction

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < 32; i = i + 1) cfg[i] <= 16'd0;
            cfg[0]  <= 16'h0001;             // master on, bypass off
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

    localparam [4:0] S_IDLE=5'd0, S_FLP1=5'd1, S_FLP2=5'd2, S_FHP1=5'd3,
                     S_FBP1=5'd4, S_FSEL=5'd5, S_DSTART=5'd6, S_DIDX=5'd7,
                     S_DLUT=5'd8, S_DMAKE=5'd9, S_DTONE=5'd10, S_DFIN=5'd11,
                     S_DLEVEL=5'd12, S_DOUT=5'd13, S_OUT=5'd14,
                     S_DINTERP=5'd15, S_DSHAPE=5'd16;

    reg [4:0] state;
    reg signed [15:0] dry_q, delay_q, filt_out, dist_out, tone_state, dist_shaped;
    reg signed [23:0] lp, bp, lp_tmp, hp_tmp, bp_new;
    reg signed [39:0] prod1, prod2, prod3;
    reg signed [47:0] prod_tone;
    reg signed [31:0] prod;
    reg signed [32:0] mix_prod;
    reg [23:0] sm_dry_abs, sm_wet_abs;
    reg [15:0] agc_gain;

    reg        dist_en, filt_en;
    reg [1:0]  ftype;
    reg [15:0] ddrive, makeup_q;
    reg signed [15:0] tcoef, lgain, fcoef, qcoef;
    reg [15:0] tval, tval_next;
    reg [31:0] interp_prod;

    // Smoothed continuous parameters; switches and type fields stay direct.
    reg [23:0] sm_cut, sm_q, sm_gain, sm_tone, sm_level;
    reg [23:0] sm_cfreq, sm_cdepth, sm_cmix;
    reg [23:0] sm_pfreq, sm_pdepth, sm_pmix;
    reg [23:0] sm_ddecay, sm_drate, sm_dmix;
    reg [23:0] sm_rdecay, sm_rmix;

    wire global_on = cfg[0][0];
    wire bypass    = cfg[0][1];

    wire [15:0] sm_cut_i = sm_cut[15:8], sm_q_i = sm_q[15:8];
    wire [15:0] sm_gain_i = sm_gain[15:8], sm_tone_i = sm_tone[15:8];
    wire [15:0] sm_level_i = sm_level[15:8];
    wire [6:0] cut_i   = (sm_cut_i   > 16'd99) ? 7'd99 : sm_cut_i[6:0];
    wire [6:0] q_i     = (sm_q_i     > 16'd99) ? 7'd99 : sm_q_i[6:0];
    wire [6:0] gain_i  = (sm_gain_i  > 16'd99) ? 7'd99 : sm_gain_i[6:0];
    wire [6:0] tone_i  = (sm_tone_i  > 16'd99) ? 7'd99 : sm_tone_i[6:0];
    wire [6:0] level_i = (sm_level_i > 16'd99) ? 7'd99 : sm_level_i[6:0];

    wire signed [15:0] reverb_out, delay_out, chorus_out, phaser_out;

    // Distortion lookup index: |x| * drive, mapped to z=0..8 over 512 entries.
    wire signed [16:0] dist_sx = {delay_q[15], delay_q};
    wire [16:0] dist_mag = dist_sx[16] ? (17'd0 - dist_sx)
                                       : dist_sx;
    wire [32:0] dist_scaled = dist_mag * ddrive;
    wire [32:0] dist_shift = dist_scaled >> 17;
    wire [8:0] dist_idx = (dist_shift >= 33'd511) ? 9'd511 : dist_shift[8:0];
    wire [8:0] dist_next_idx = (dist_idx == 9'd511) ? 9'd511 : dist_idx + 1'b1;
    wire [16:0] dist_frac = (dist_shift >= 33'd511) ? 17'd0 : dist_scaled[16:0];
    wire [16:0] interp_value = {1'b0, tval} + (interp_prod >> 17);
    wire [32:0] shaped_mag = interp_value * makeup_q;
    wire [15:0] dist_dry_abs = delay_q[15] ? (~delay_q + 16'd1) : delay_q;
    wire [15:0] dist_wet_abs = tone_state[15] ? (~tone_state + 16'd1) : tone_state;
    wire [31:0] agc_wet_product = sm_wet_abs[23:8] * agc_gain;
    wire [15:0] agc_wet_after = agc_wet_product >> 15;
    wire signed [17:0] agc_error =
        $signed({2'b00, sm_dry_abs[23:8]}) - $signed({2'b00, agc_wet_after});
    wire signed [17:0] agc_next = $signed({2'b00, agc_gain}) + (agc_error >>> 1);
    wire signed [15:0] dist_wet_scaled = sat16(prod >>> 15);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE;
            dry_q <= 16'sd0; delay_q <= 16'sd0;
            filt_out <= 16'sd0; dist_out <= 16'sd0;
            tone_state <= 16'sd0; dist_shaped <= 16'sd0;
            lp <= 24'sd0; bp <= 24'sd0; lp_tmp <= 24'sd0; hp_tmp <= 24'sd0;
            bp_new <= 24'sd0; prod1 <= 40'sd0; prod2 <= 40'sd0; prod3 <= 40'sd0;
            prod_tone <= 48'sd0; prod <= 32'sd0; mix_prod <= 33'sd0;
            sm_dry_abs <= 24'd0; sm_wet_abs <= 24'd0;
            agc_gain <= 16'd24952; // tanh(1)/1, until the first silent reset
            dist_en <= 1'b0; filt_en <= 1'b0; ftype <= 2'd0;
            ddrive <= 16'd256; makeup_q <= 16'd32767;
            tval <= 16'd0; tval_next <= 16'd0; interp_prod <= 32'd0;
            tcoef <= 16'sd0; lgain <= 16'sd0; fcoef <= 16'sd0; qcoef <= 16'sd0;
            sm_cut <= 24'd99 << 8; sm_q <= 24'd20 << 8;
            sm_gain <= 24'd20 << 8; sm_tone <= 24'd50 << 8; sm_level <= 24'd80 << 8;
            sm_cfreq <= 24'd30 << 8; sm_cdepth <= 24'd40 << 8; sm_cmix <= 24'd30 << 8;
            sm_pfreq <= 24'd25 << 8; sm_pdepth <= 24'd40 << 8; sm_pmix <= 24'd30 << 8;
            sm_ddecay <= 24'd35 << 8; sm_drate <= 24'd40 << 8; sm_dmix <= 24'd30 << 8;
            sm_rdecay <= 24'd45 << 8; sm_rmix <= 24'd30 << 8;
        end else begin
            case (state)
                S_IDLE: if (sample_tick) begin
                    dry_q <= dry_sample;
                    delay_q <= delay_out;
                    dist_en <= cfg[5][0];
                    filt_en <= cfg[1][0];
                    ftype <= cfg[2][1:0];
                    ddrive <= dist_drive[gain_i];
                    makeup_q <= dist_makeup[gain_i];
                    tcoef <= tone_tab[tone_i];
                    lgain <= level_tab[level_i];
                    fcoef <= filter_f[cut_i];
                    qcoef <= filter_q[q_i];
                    sm_cut <= smooth24(sm_cut, cfg[3]);
                    sm_q <= smooth24(sm_q, cfg[4]);
                    sm_gain <= smooth24(sm_gain, cfg[6]);
                    sm_tone <= smooth24(sm_tone, cfg[7]);
                    sm_level <= smooth24(sm_level, cfg[8]);
                    sm_cfreq <= smooth24(sm_cfreq, cfg[10]);
                    sm_cdepth <= smooth24(sm_cdepth, cfg[11]);
                    sm_cmix <= smooth24(sm_cmix, cfg[12]);
                    sm_pfreq <= smooth24(sm_pfreq, cfg[14]);
                    sm_pdepth <= smooth24(sm_pdepth, cfg[15]);
                    sm_pmix <= smooth24(sm_pmix, cfg[16]);
                    sm_ddecay <= smooth24(sm_ddecay, cfg[18]);
                    sm_drate <= smooth24(sm_drate, cfg[19]);
                    sm_dmix <= smooth24(sm_dmix, cfg[20]);
                    sm_rdecay <= smooth24(sm_rdecay, cfg[23]);
                    sm_rmix <= smooth24(sm_rmix, cfg[24]);
                    if (!filt_en) begin
                        filt_out <= dry_q;
                        state <= S_DSTART;
                    end else state <= S_FLP1;
                end
                // ---------------- FILTER (first in the chain) ----------------
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
                    hp_tmp <= sat24(($signed(dry_q) <<< 8) - lp_tmp - (prod2 >>> 14));
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
                        2'd0: filt_out <= sat16(lp_tmp >>> 8);
                        2'd1: filt_out <= sat16(bp_new >>> 8);
                        default: filt_out <= sat16(hp_tmp >>> 8);
                    endcase
                    state <= S_DSTART;
                end
                // ---------------- DISTORTION (after delay) ------------------
                S_DSTART: begin
                    if (!dist_en) begin
                        dist_out <= delay_q;
                        state <= S_OUT;
                    end else state <= S_DIDX;
                end
                S_DIDX: begin
                    tval <= tanh_lut[dist_idx];
                    state <= S_DLUT;
                end
                S_DLUT: begin
                    tval_next <= tanh_lut[dist_next_idx];
                    state <= S_DINTERP;
                end
                S_DINTERP: begin
                    // The 512-entry LUT alone produces visible steps at low
                    // amplitudes. Interpolate with the 17 fractional bits.
                    interp_prod <= ({1'b0, tval_next} - {1'b0, tval}) * dist_frac;
                    state <= S_DSHAPE;
                end
                S_DSHAPE: begin
                    dist_shaped <= delay_q[15]
                        ? -sat16($signed(shaped_mag >> 14))
                        :  sat16($signed(shaped_mag >> 14));
                    state <= S_DMAKE;
                end
                S_DMAKE: begin
                    prod_tone <= $signed(tcoef) *
                        ($signed({dist_shaped[15], dist_shaped}) -
                         $signed({tone_state[15], tone_state}));
                    state <= S_DTONE;
                end
                S_DTONE: begin
                    tone_state <= sat16($signed(tone_state) +
                                          $signed(prod_tone >>> 15));
                    state <= S_DFIN;
                end
                S_DFIN: begin
                    sm_dry_abs <= smooth24(sm_dry_abs, dist_dry_abs);
                    sm_wet_abs <= smooth24(sm_wet_abs, dist_wet_abs);
                    prod <= $signed(tone_state) * $signed(agc_gain);
                    state <= S_DLEVEL;
                end
                S_DLEVEL: begin
                    // LEVEL is a dry/wet control. Loudness matching is
                    // independent of it, so zero gives the original signal.
                    mix_prod <= ($signed({dist_wet_scaled[15], dist_wet_scaled}) -
                                 $signed({delay_q[15], delay_q})) * $signed(lgain);
                    state <= S_DOUT;
                end
                S_DOUT: begin
                    dist_out <= sat16($signed(delay_q) + (mix_prod >>> 15));
                    state <= S_OUT;
                end
                S_OUT: begin
                    // Match the smoothed absolute loudness of wet and dry.
                    // The old peak-only makeup made small signals 4x louder
                    // at mid GAIN. Limit the correction to attenuation.
                    if (dist_en) begin
                        // After silence, start with unity small-signal gain.
                        // An attack must not play at the uncorrected 4x slope
                        // while the loudness envelope is still filling.
                        if (sm_dry_abs[23:8] < 16'd32 &&
                            sm_wet_abs[23:8] < 16'd32)
                            agc_gain <= dist_initial_gain[gain_i];
                        else if (agc_next < 18'sd0) agc_gain <= 16'd0;
                        else if (agc_next > 18'sd32767) agc_gain <= 16'd32767;
                        else agc_gain <= agc_next[15:0];
                    end
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    audio_reverb u_reverb(.clk(clk), .reset_n(reset_n), .sample_tick(sample_tick),
        .in_sample(filt_out), .enable(cfg[21][0]), .rtype(cfg[22][1:0]),
        .decay(sm_rdecay[14:8]), .mix(sm_rmix[14:8]),
        .out_sample(reverb_out));
    audio_delay u_delay(.clk(clk), .reset_n(reset_n), .sample_tick(sample_tick),
        .in_sample(reverb_out), .enable(cfg[17][0]),
        .decay(sm_ddecay[14:8]), .rate(sm_drate[14:8]), .mix(sm_dmix[14:8]),
        .out_sample(delay_out));
    audio_chorus u_chorus(.clk(clk), .reset_n(reset_n), .sample_tick(sample_tick),
        .in_sample(dist_out), .enable(cfg[9][0]),
        .freq(sm_cfreq[14:8]), .depth(sm_cdepth[14:8]), .mix(sm_cmix[14:8]),
        .out_sample(chorus_out));
    audio_phaser u_phaser(.clk(clk), .reset_n(reset_n), .sample_tick(sample_tick),
        .in_sample(chorus_out), .enable(cfg[13][0]),
        .freq(sm_pfreq[14:8]), .depth(sm_pdepth[14:8]), .mix(sm_pmix[14:8]),
        .out_sample(phaser_out));

    // Final soft limiter: keep the sum of six effects from hard clipping.
    function signed [15:0] limit16;
        input signed [15:0] v;
        reg signed [31:0] a;
        begin
            a = v;
            if (a > 32'sd24576) a = 32'sd24576 + ((a - 32'sd24576) >>> 2);
            else if (a < -32'sd24576) a = -32'sd24576 + ((a + 32'sd24576) >>> 2);
            if (a > 32'sd32767) a = 32'sd32767;
            if (a < -32'sd32768) a = -32'sd32768;
            limit16 = a[15:0];
        end
    endfunction

    // No effect enabled -> exact dry (no pipeline latency).  Bypass and
    // master-off are also bit-exact.  The real chain has 5-6 samples latency.
    wire any_enabled = cfg[1][0]|cfg[5][0]|cfg[9][0]|cfg[13][0]|
                       cfg[17][0]|cfg[21][0];
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) sample_out <= 16'sd0;
        else sample_out <= (!global_on || bypass || !any_enabled)
                           ? dry_sample : limit16(phaser_out);
    end
endmodule
