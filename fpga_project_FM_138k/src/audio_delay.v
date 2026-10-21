// Parameterised mono delay: 40..670 ms line, feedback and wet/dry mix.
// Structure follows the original audio_effects.v delay conventions (single
// write port, registered read port, saturating additions).
module audio_delay (
    input  wire               clk,
    input  wire               reset_n,
    input  wire               sample_tick,
    input  wire signed [15:0] in_sample,
    input  wire               enable,
    input  wire [6:0]         decay,    // 0..99 -> feedback 0.30..0.90
    input  wire [6:0]         rate,     // 0..99 -> 40..670 ms
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

    reg signed [15:0] mem [0:32767];
    reg [14:0] wptr, raddr;
    reg [16:0] wcount;
    reg [6:0]  st;
    reg signed [15:0] in_q, tap, tap_g, wdat;
    reg [14:0] dly;
    reg signed [15:0] fb_q, mix_q;
    reg signed [39:0] prod;

    reg [15:0] len_tab [0:99];
    reg signed [15:0] fb_tab [0:99];
    reg signed [15:0] mix_tab [0:99];
    initial begin
        $readmemh("src/generated/fx_delay_len.mem", len_tab);
        $readmemh("src/generated/fx_delay_fb.mem", fb_tab);
        $readmemh("src/generated/fx_level_gain.mem", mix_tab);
    end

    wire [6:0] decay_i = (decay > 7'd99) ? 7'd99 : decay;
    wire [6:0] rate_i  = (rate  > 7'd99) ? 7'd99 : rate;
    wire [6:0] mix_i   = (mix   > 7'd99) ? 7'd99 : mix;

    always @(posedge clk) begin
        if (st == 6'd5) mem[wptr] <= wdat;
    end
    always @(posedge clk) begin
        tap <= mem[raddr];
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wptr <= 15'd0; raddr <= 15'd0; wcount <= 17'd0; st <= 6'd0;
            in_q <= 16'sd0; wdat <= 16'sd0; dly <= 15'd2000;
            tap_g <= 16'sd0;
            fb_q <= 16'sd0; mix_q <= 16'sd0; prod <= 40'sd0;
            out_sample <= 16'sd0;
        end else begin
            case (st)
                6'd0: if (sample_tick) begin
                    in_q <= in_sample;
                    dly <= len_tab[rate_i][14:0];
                    fb_q <= fb_tab[decay_i];
                    mix_q <= mix_tab[mix_i];
                    st <= 6'd1;
                end
                6'd1: begin
                    raddr <= wptr - dly;
                    st <= 6'd2;
                end
                6'd2: begin
                    st <= 6'd3;              // registered tap available next cycle
                end
                6'd3: begin
                    tap_g <= (wcount >= {2'b0, dly}) ? tap : 16'sd0;
                    if (wcount >= {2'b0, dly})
                        prod <= $signed(tap) * $signed(fb_q);
                    else
                        prod <= 40'sd0;
                    st <= 6'd4;
                end
                6'd4: begin
                    wdat <= sat16($signed(in_q) + (prod >>> 15));
                    prod <= ($signed({tap_g[15], tap_g}) - $signed({in_q[15], in_q})) *
                            $signed(mix_q);
                    st <= 6'd5;
                end
                6'd5: begin
                    wptr <= wptr + 1'b1;
                    if (wcount < 17'h1FFFF) wcount <= wcount + 1'b1;
                    st <= 6'd6;
                end
                default: begin
                    out_sample <= enable ? sat16($signed(in_q) + (prod >>> 15)) : in_q;
                    st <= 6'd0;
                end
            endcase
        end
    end
endmodule
