// Two complementary modulated taps, with fractional-delay interpolation.
// Four reads are time-multiplexed through one synchronous RAM read port.
module audio_chorus (
    input wire clk, reset_n, sample_tick,
    input wire signed [15:0] in_sample,
    input wire enable,
    input wire [6:0] freq, depth, mix,
    output reg signed [15:0] out_sample
);
    function signed [15:0] sat16;
        input signed [31:0] value;
        begin
            if (value > 32'sd32767) sat16 = 16'sd32767;
            else if (value < -32'sd32768) sat16 = -16'sd32768;
            else sat16 = value[15:0];
        end
    endfunction

    reg signed [15:0] mem [0:2047];
    reg [10:0] wptr, raddr;
    reg signed [15:0] ram_data;
    reg [31:0] lfo_phase;
    reg [3:0] st;
    reg signed [15:0] in_q, a0, a1, b0, b1, wet_q;
    reg [18:0] delay_a_q8, delay_b_q8;
    reg signed [31:0] interp_a, interp_b, mix_prod;
    reg signed [15:0] mix_q;
    reg [11:0] warm_count;

    reg [31:0] inc_tab [0:99];
    reg signed [15:0] mix_tab [0:99];
    initial begin
        $readmemh("src/generated/fx_chorus_inc.mem", inc_tab);
        $readmemh("src/generated/fx_level_gain.mem", mix_tab);
    end

    wire [6:0] freq_i = (freq > 7'd99) ? 7'd99 : freq;
    wire [6:0] depth_i = (depth > 7'd99) ? 7'd99 : depth;
    wire [6:0] mix_i = (mix > 7'd99) ? 7'd99 : mix;
    // Keep 16 fractional phase bits: an 8-bit LFO steps the delay by up
    // to 1.5 samples at maximum DEPTH, even with audio interpolation.
    wire [15:0] triangle = lfo_phase[31]
        ? (16'hffff - lfo_phase[30:15]) : lfo_phase[30:15];
    wire [8:0] span = {depth_i, 2'b00}; // 0..396 samples
    wire [24:0] mod_product = triangle * span;
    wire [16:0] offset_q8 = mod_product[24:8];
    wire [18:0] full_span_q8 = {span, 8'b0};
    wire valid_a = warm_count > ({1'b0,delay_a_q8[18:8]} +
                                  (delay_a_q8[7:0] != 0));
    wire valid_b = warm_count > ({1'b0,delay_b_q8[18:8]} +
                                  (delay_b_q8[7:0] != 0));
    wire signed [31:0] wet_sum =
        (valid_a ? $signed(interp_a >>> 8) : 32'sd0) +
        (valid_b ? $signed(interp_b >>> 8) : 32'sd0);

    always @(posedge clk) begin
        ram_data <= mem[raddr];
        if (st == 4'd10) mem[wptr] <= in_q;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wptr<=0; raddr<=0; lfo_phase<=0; st<=0; warm_count<=0;
            in_q<=0; a0<=0; a1<=0; b0<=0; b1<=0; wet_q<=0;
            delay_a_q8<=0; delay_b_q8<=0;
            interp_a<=0; interp_b<=0; mix_prod<=0; mix_q<=0; out_sample<=0;
        end else begin
            case (st)
                4'd0: if (sample_tick) begin
                    in_q <= in_sample;
                    mix_q <= mix_tab[mix_i];
                    lfo_phase <= lfo_phase + inc_tab[freq_i];
                    delay_a_q8 <= (19'd400 << 8) + {2'b00, offset_q8};
                    delay_b_q8 <= (19'd400 << 8) + full_span_q8 - {2'b00, offset_q8};
                    st <= 4'd1;
                end
                4'd1: begin raddr <= wptr - delay_a_q8[18:8]; st<=4'd2; end
                4'd2: st<=4'd3;
                4'd3: begin a0<=ram_data; raddr<=wptr-delay_a_q8[18:8]-11'd1; st<=4'd4; end
                4'd4: st<=4'd5;
                4'd5: begin a1<=ram_data; raddr<=wptr-delay_b_q8[18:8]; st<=4'd6; end
                4'd6: st<=4'd7;
                4'd7: begin b0<=ram_data; raddr<=wptr-delay_b_q8[18:8]-11'd1; st<=4'd8; end
                4'd8: st<=4'd9;
                4'd9: begin b1<=ram_data; st<=4'd10; end
                4'd10: begin
                    interp_a <= (delay_a_q8[7:0] == 0) ? ($signed(a0) <<< 8) :
                                ($signed(a0) <<< 8) +
                                ($signed({a1[15],a1})-$signed({a0[15],a0})) *
                                $signed({1'b0,delay_a_q8[7:0]});
                    interp_b <= (delay_b_q8[7:0] == 0) ? ($signed(b0) <<< 8) :
                                ($signed(b0) <<< 8) +
                                ($signed({b1[15],b1})-$signed({b0[15],b0})) *
                                $signed({1'b0,delay_b_q8[7:0]});
                    wptr <= wptr + 1'b1;
                    if (warm_count != 12'hfff) warm_count <= warm_count + 1'b1;
                    st<=4'd11;
                end
                4'd11: begin
                    // Suppress each tap until its own delay line is filled.
                    wet_q <= sat16(wet_sum >>> 1);
                    st<=4'd12;
                end
                4'd12: begin
                    mix_prod <= ($signed({wet_q[15],wet_q})-
                                 $signed({in_q[15],in_q})) * $signed(mix_q);
                    st<=4'd13;
                end
                default: begin
                    out_sample <= (enable && mix_q != 0)
                        ? sat16($signed(in_q)+(mix_prod >>> 15)) : in_q;
                    st<=4'd0;
                end
            endcase
        end
    end
endmodule
