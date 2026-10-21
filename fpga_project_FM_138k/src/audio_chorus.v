// Parameterised chorus, derived from the original audio_effects.v chorus:
// 2048-sample delay line, triangle LFO and wet/dry blend.  The original fixed
// ~0.35 Hz LFO and fixed 9..19 ms sweep are now driven by the FX registers.
module audio_chorus (
    input  wire               clk,
    input  wire               reset_n,
    input  wire               sample_tick,
    input  wire signed [15:0] in_sample,
    input  wire               enable,
    input  wire [6:0]         freq,     // 0..99
    input  wire [6:0]         depth,    // 0..99 -> 0..396 samples of sweep
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

    reg signed [15:0] mem [0:2047];
    reg [10:0] wptr, raddr;
    reg [31:0] lfo_phase;
    reg [2:0]  st;
    reg signed [15:0] in_q, tap;
    reg [10:0] delay;
    reg signed [39:0] prod;

    reg [31:0] inc_tab [0:99];
    reg signed [15:0] mix_tab [0:99];
    initial begin
        $readmemh("src/generated/fx_chorus_inc.mem", inc_tab);
        $readmemh("src/generated/fx_level_gain.mem", mix_tab);
    end

    wire [6:0] freq_i  = (freq  > 7'd99) ? 7'd99 : freq;
    wire [6:0] depth_i = (depth > 7'd99) ? 7'd99 : depth;
    wire [6:0] mix_i   = (mix   > 7'd99) ? 7'd99 : mix;
    wire [7:0] lfo_tri = lfo_phase[31]
        ? (8'hff - lfo_phase[30:23]) : lfo_phase[30:23];
    wire [10:0] mod_span = {3'b000, depth_i, 2'b00};   // depth*4, max 396
    wire [16:0] mod_prod = {9'd0, lfo_tri} * mod_span;

    // Simple dual-port delay line: one write port and one registered read port.
    always @(posedge clk) begin
        if (st == 3'd3) mem[wptr] <= in_q;
    end
    always @(posedge clk) begin
        tap <= mem[raddr];
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wptr <= 11'd0; raddr <= 11'd0; lfo_phase <= 32'd0; st <= 3'd0;
            in_q <= 16'sd0; delay <= 11'd400;
            prod <= 40'sd0; out_sample <= 16'sd0;
        end else begin
            case (st)
                3'd0: if (sample_tick) begin
                    in_q <= in_sample;
                    lfo_phase <= lfo_phase + inc_tab[freq_i];
                    st <= 3'd1;
                end
                3'd1: begin
                    delay <= 11'd400 + mod_prod[16:8];
                    st <= 3'd2;
                end
                3'd2: begin
                    raddr <= wptr - delay;
                    st <= 3'd3;
                end
                3'd3: begin
                    wptr <= wptr + 1'b1;
                    st <= 3'd4;
                end
                3'd4: begin
                    prod <= $signed(tap - in_q) * $signed(mix_tab[mix_i]);
                    st <= 3'd5;
                end
                default: begin
                    out_sample <= enable ? sat16($signed(in_q) + (prod >>> 15)) : in_q;
                    st <= 3'd0;
                end
            endcase
        end
    end
endmodule
