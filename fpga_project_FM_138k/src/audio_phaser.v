// Four-stage first-order all-pass phaser with LFO-modulated coefficient.
// FREQ drives the LFO rate, DEPTH the coefficient swing and MIX the wet level.
module audio_phaser (
    input  wire               clk,
    input  wire               reset_n,
    input  wire               sample_tick,
    input  wire signed [15:0] in_sample,
    input  wire               enable,
    input  wire [6:0]         freq,
    input  wire [6:0]         depth,
    input  wire [6:0]         mix,
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

    reg [31:0] inc_tab [0:99];
    reg signed [15:0] mix_tab [0:99];
    initial begin
        $readmemh("src/generated/fx_phaser_inc.mem", inc_tab);
        $readmemh("src/generated/fx_level_gain.mem", mix_tab);
    end

    reg [31:0] lfo_phase;
    reg [3:0]  st;
    reg [1:0]  stage;
    reg signed [15:0] in_q, cur;
    reg signed [15:0] x1 [0:3];
    reg signed [15:0] y1 [0:3];
    reg signed [15:0] a_q15;
    reg signed [39:0] prod1, prod2;

    wire [6:0] freq_i  = (freq  > 7'd99) ? 7'd99 : freq;
    wire [6:0] depth_i = (depth > 7'd99) ? 7'd99 : depth;
    wire [6:0] mix_i   = (mix   > 7'd99) ? 7'd99 : mix;
    wire [7:0] lfo_tri = lfo_phase[31]
        ? (8'hff - lfo_phase[30:23]) : lfo_phase[30:23];
    wire [14:0] depth_gain = depth_i * 15'd280;   // max 27720
    wire [22:0] a_prod = {15'd0, lfo_tri} * depth_gain;

    wire signed [15:0] y_new = sat16((prod1 >>> 15) + $signed(x1[stage]) - (prod2 >>> 15));

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            lfo_phase <= 32'd0; st <= 4'd0; stage <= 2'd0;
            in_q <= 16'sd0; cur <= 16'sd0; a_q15 <= 16'sd0;
            prod1 <= 40'sd0; prod2 <= 40'sd0; out_sample <= 16'sd0;
            x1[0] <= 0; x1[1] <= 0; x1[2] <= 0; x1[3] <= 0;
            y1[0] <= 0; y1[1] <= 0; y1[2] <= 0; y1[3] <= 0;
        end else begin
            case (st)
                4'd0: if (sample_tick) begin
                    in_q <= in_sample;
                    cur <= in_sample;
                    lfo_phase <= lfo_phase + inc_tab[freq_i];
                    stage <= 2'd0;
                    st <= 4'd1;
                end
                4'd1: begin
                    a_q15 <= 16'sd1638 + $signed({1'b0, a_prod[22:8]});
                    st <= 4'd2;
                end
                4'd2: begin
                    prod1 <= $signed(a_q15) * $signed(cur);
                    st <= 4'd3;
                end
                4'd3: begin
                    prod2 <= $signed(a_q15) * $signed(y1[stage]);
                    st <= 4'd4;
                end
                4'd4: begin
                    x1[stage] <= cur;
                    y1[stage] <= y_new;
                    cur <= y_new;
                    if (stage == 2'd3) st <= 4'd5;
                    else begin stage <= stage + 1'b1; st <= 4'd2; end
                end
                4'd5: begin
                    prod1 <= ($signed({cur[15], cur}) - $signed({in_q[15], in_q})) *
                             $signed(mix_tab[mix_i]);
                    st <= 4'd6;
                end
                default: begin
                    out_sample <= enable ? sat16($signed(in_q) + (prod1 >>> 15)) : in_q;
                    st <= 4'd0;
                end
            endcase
        end
    end
endmodule
