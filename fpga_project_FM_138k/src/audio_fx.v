// Post-mix effects engine, step 1: configuration register file, readback and
// an exact dry bypass.  Later steps replace `chain_out` with the real 6-effect
// chain (distortion -> filter -> phaser -> chorus -> delay -> reverb).
//
// Register map (6-bit address, 16-bit value):
//   0      GLOBAL: bit0 master enable, bit1 bypass
//   1..4   FILTER:   enable, type, cutoff, Q
//   5..8   DISTORTION: enable, gain, tone, level
//   9..12  CHORUS:  enable, freq, depth, mix
//   13..16 PHASER:  enable, freq, depth, mix
//   17..20 DELAY:   enable, decay, rate, mix
//   21..24 REVERB:  enable, type, decay, mix
//   25..31 reserved
module audio_fx (
    input  wire               clk,
    input  wire               reset_n,
    input  wire               sample_tick,
    input  wire signed [15:0] dry_sample,
    // configuration port (from fm_uart_control, command 0x70)
    input  wire               cfg_write,
    input  wire [5:0]         cfg_addr,
    input  wire [15:0]        cfg_value,
    // readback port (0x69 address 0x200 + cfg address)
    input  wire [5:0]         read_addr,
    output wire [15:0]        read_value,
    output reg  signed [15:0] sample_out
);
    reg [15:0] cfg [0:31];
    integer i;

    assign read_value = cfg[read_addr];

    // Step 1: the effects chain is a wire; the real chain lands in later steps.
    wire signed [15:0] chain_out = dry_sample;
    wire global_on = cfg[0][0];
    wire bypass    = cfg[0][1];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < 32; i = i + 1) cfg[i] <= 16'd0;
            cfg[0]  <= 16'h0001;   // master on, not bypassed
            cfg[1]  <= 16'd0;      // filter off
            cfg[2]  <= 16'd0;      // LP
            cfg[3]  <= 16'd99;     // cutoff open
            cfg[4]  <= 16'd20;     // Q
            cfg[5]  <= 16'd0;      // distortion off
            cfg[6]  <= 16'd20;     // gain
            cfg[7]  <= 16'd50;     // tone
            cfg[8]  <= 16'd80;     // level
            cfg[9]  <= 16'd0;      // chorus off
            cfg[10] <= 16'd30;     // freq
            cfg[11] <= 16'd40;     // depth
            cfg[12] <= 16'd30;     // mix
            cfg[13] <= 16'd0;      // phaser off
            cfg[14] <= 16'd25;
            cfg[15] <= 16'd40;
            cfg[16] <= 16'd30;
            cfg[17] <= 16'd0;      // delay off
            cfg[18] <= 16'd35;
            cfg[19] <= 16'd40;
            cfg[20] <= 16'd30;
            cfg[21] <= 16'd0;      // reverb off
            cfg[22] <= 16'd0;      // room
            cfg[23] <= 16'd45;
            cfg[24] <= 16'd30;
            sample_out <= 16'sd0;
        end else begin
            if (cfg_write) cfg[cfg_addr] <= cfg_value;
            if (!sample_tick)
                ; // keep the output register stable between samples
            else
                sample_out <= (!global_on || bypass) ? dry_sample : chain_out;
        end
    end
endmodule
