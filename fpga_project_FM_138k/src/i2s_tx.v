// Standard I2S transmitter, 16-bit stereo, MSB first.
// Data changes on BCLK falling edges and is sampled by MAX98357 on rising edges.
module i2s_tx #(
    parameter integer BCLK_HALF_DIV = 8,
    parameter integer OUTPUT_SELECT_ENABLED = 0
) (
    input  wire               clk,
    input  wire               reset_n,
    input wire headphone_select,
    output wire headphone_din,
    input  wire signed [15:0] sample_left,
    input  wire signed [15:0] sample_right,
    output reg                sample_tick,
    output reg                i2s_bclk,
    output reg                i2s_lrclk,
    output reg                i2s_din
);

    reg route_frame;
    reg serial_data;
    assign headphone_din = OUTPUT_SELECT_ENABLED ? (route_frame ? serial_data : 1'b0) : serial_data;
    reg [7:0]  bclk_div;
    reg [5:0]  slot_count;
    reg signed [15:0] left_latch;
    reg signed [15:0] right_latch;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bclk_div   <= 8'd0;
            slot_count <= 6'd0;
            sample_tick <= 1'b0;
            i2s_bclk   <= 1'b0;
            i2s_lrclk  <= 1'b0;
            i2s_din    <= 1'b0;
            serial_data <= 1'b0;route_frame<=1'b0;
            left_latch <= 16'sd0;
            right_latch <= 16'sd0;
        end else begin
            sample_tick <= 1'b0;

            if (bclk_div == BCLK_HALF_DIV - 1) begin
                bclk_div <= 8'd0;

                // Drive new serial data at each BCLK falling edge.
                if (i2s_bclk) begin
                    i2s_bclk <= 1'b0;

                    if (slot_count == 6'd0) begin
                        // I2S requires one BCLK delay after LRCLK changes.
                        i2s_lrclk <= 1'b0;
                        i2s_din   <= 1'b0;serial_data<=1'b0;
                    end else if ((slot_count >= 6'd1) && (slot_count <= 6'd16)) begin
                        serial_data <= left_latch[6'd16 - slot_count];
                        i2s_din <= (OUTPUT_SELECT_ENABLED && route_frame) ? 1'b0 : left_latch[6'd16 - slot_count];
                    end else if (slot_count == 6'd32) begin
                        i2s_lrclk <= 1'b1;
                        i2s_din   <= 1'b0;serial_data<=1'b0;
                    end else if ((slot_count >= 6'd33) && (slot_count <= 6'd48)) begin
                        serial_data <= right_latch[6'd48 - slot_count];
                        i2s_din <= (OUTPUT_SELECT_ENABLED && route_frame) ? 1'b0 : right_latch[6'd48 - slot_count];
                    end else begin
                        i2s_din <= 1'b0;serial_data<=1'b0;
                    end

                    if (slot_count == 6'd63) begin
                        slot_count <= 6'd0;
                        route_frame <= OUTPUT_SELECT_ENABLED ? headphone_select : 1'b0;
                        sample_tick <= 1'b1;
                        // Latch a complete stereo frame.  The synthesizer may
                        // now spend tens of system clocks calculating the next
                        // sample without changing bits already being shifted.
                        left_latch <= sample_left;
                        right_latch <= sample_right;
                    end else begin
                        slot_count <= slot_count + 1'b1;
                    end
                end else begin
                    i2s_bclk <= 1'b1;
                end
            end else begin
                bclk_div <= bclk_div + 1'b1;
            end
        end
    end

endmodule
