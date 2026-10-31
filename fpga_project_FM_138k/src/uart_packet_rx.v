// -----------------------------------------------------------------------------
// uart_packet_rx.v
//
// 12-byte packet receiver for the JDY-23 / synth configuration link.
//
// Frame:  A5 5A CMD DATA0 DATA1 ... DATA7 SUM
//         SUM = XOR(CMD, DATA0..DATA7)
//         DATA0 is payload[7:0] (little endian).
//
// Behaviour:
//   * packet_valid is a one-clock pulse asserted only when a complete frame
//     with a matching checksum has been received.  command / payload /
//     checksum are updated at the same clock edge, so they already hold the
//     new values during the cycle in which packet_valid is high.
//   * packet_error is a one-clock pulse.  error_code == 3'd1 for a checksum
//     mismatch, error_code == 3'd2 when a frame that has already started sees
//     no new byte for more than TIMEOUT_CLKS clocks.  A timeout while no frame
//     is in progress (idle) is not reported.
//   * Command codes are not validated here; unknown commands are forwarded to
//     synth_uart_control, which owns the command semantics.
//   * A repeated A5 (A5 A5 5A) keeps the frame sync search alive.
//   * payload keeps its last accepted value until the next accepted frame.
// -----------------------------------------------------------------------------
module uart_packet_rx #(
    parameter integer CLKS_PER_BIT = 434,
    parameter integer TIMEOUT_CLKS = 10000000,
    parameter integer ENABLE_RELIABLE = 0
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        rx,

    output reg         packet_valid,
    output reg         packet_error,
    output reg  [7:0]  command,
    output reg  [63:0] payload,
    output reg  [7:0]  checksum,
    output reg  [2:0]  error_code,
    output reg         reliable_valid,
    input wire         reliable_ready,
    output reg [479:0] reliable_body,
    output reg [31:0]  reliable_digest
);

    localparam [2:0] ST_WAIT_A5 = 3'd0;
    localparam [2:0] ST_WAIT_5A = 3'd1;
    localparam [2:0] ST_CMD     = 3'd2;
    localparam [2:0] ST_DATA    = 3'd3;
    localparam [2:0] ST_SUM     = 3'd4;
    localparam [2:0] ST_RELIABLE = 3'd5;

    localparam [2:0] ERR_NONE    = 3'd0;
    localparam [2:0] ERR_CRC     = 3'd1;
    localparam [2:0] ERR_TIMEOUT = 3'd2;

    // Enough bits to represent TIMEOUT_CLKS exactly.
    localparam integer TMO_WIDTH = (TIMEOUT_CLKS < 2) ? 1 : $clog2(TIMEOUT_CLKS + 1);
    localparam [TMO_WIDTH-1:0] TIMEOUT_LAST = TMO_WIDTH'(TIMEOUT_CLKS - 1);

    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx #(
        .CLKS_PER_BIT (CLKS_PER_BIT)
    ) u_uart_rx (
        .clk     (clk),
        .reset_n (reset_n),
        .rx      (rx),
        .data    (rx_data),
        .valid   (rx_valid)
    );

    reg  [2:0]  state;
    reg  [2:0]  data_index;
    reg  [7:0]  calc_sum;
    reg  [7:0]  stage_cmd;
    reg  [63:0] stage_payload;
    reg [5:0] reliable_index;
    reg [479:0] stage_reliable;
    reg [31:0] reliable_crc, reliable_check;
    // A timed-out v2 envelope has no escaped delimiter: its late tail cannot
    // be distinguished from a new legacy frame. Stay in v2-only sync search
    // until a complete CRC-valid v2 envelope restores a known frame boundary.
    reg reliable_quarantine;
    reg  [TMO_WIDTH-1:0] timeout_count;

    wire frame_active = (state != ST_WAIT_A5);
    function [31:0] crc_byte;
        input [31:0] current;
        input [7:0] value;
        integer k;
        begin
            crc_byte=current;
            for(k=0;k<8;k=k+1) crc_byte=(crc_byte>>1)^((crc_byte[0]^value[k])?32'hedb88320:32'd0);
        end
    endfunction

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state         <= ST_WAIT_A5;
            data_index    <= 3'd0;
            calc_sum      <= 8'd0;
            stage_cmd     <= 8'd0;
            stage_payload <= 64'd0;
            timeout_count <= {TMO_WIDTH{1'b0}};

            packet_valid  <= 1'b0;
            packet_error  <= 1'b0;
            command       <= 8'd0;
            payload       <= 64'd0;
            checksum      <= 8'd0;
            error_code    <= ERR_NONE;
            reliable_valid <= 0; reliable_body <= 0; reliable_digest <= 0;
            reliable_index <= 0; stage_reliable <= 0; reliable_crc <= 0; reliable_check <= 0;
            reliable_quarantine <= 0;
        end else begin
            // Single-cycle pulses by default.
            packet_valid <= 1'b0;
            packet_error <= 1'b0;
            if(reliable_valid && reliable_ready) reliable_valid <= 1'b0;

            if (rx_valid) begin
                // Any received byte restarts the inter-byte timeout.
                timeout_count <= {TMO_WIDTH{1'b0}};

                case (state)
                    ST_WAIT_A5: begin
                        if (rx_data == 8'hA5) begin
                            state <= ST_WAIT_5A;
                            stage_cmd <= 0;
                        end
                    end

                    ST_WAIT_5A: begin
                        if (rx_data == 8'h5A)
                            state <= ST_CMD;
                        else if (rx_data != 8'hA5)
                            state <= ST_WAIT_A5;
                        // rx_data == A5: stay here, so A5 A5 5A still syncs.
                    end

                    ST_CMD: begin
                        stage_cmd  <= rx_data;
                        calc_sum   <= rx_data;
                        data_index <= 3'd0;
                        if(ENABLE_RELIABLE && rx_data==8'h60) begin
                            state <= ST_RELIABLE;
                            reliable_index <= 0;
                            reliable_crc <= crc_byte(32'hffffffff,8'h60);
                        end else if (reliable_quarantine) state <= ST_WAIT_A5;
                        else state <= ST_DATA;
                    end

                    ST_DATA: begin
                        stage_payload[data_index*8 +: 8] <= rx_data;
                        calc_sum                         <= calc_sum ^ rx_data;
                        if (data_index == 3'd7)
                            state <= ST_SUM;
                        else
                            data_index <= data_index + 1'b1;
                    end

                    ST_SUM: begin
                        state <= ST_WAIT_A5;
                        if (rx_data == calc_sum) begin
                            // Commit coherent data together with the pulse.
                            packet_valid <= 1'b1;
                            error_code   <= ERR_NONE;
                            command      <= stage_cmd;
                            payload      <= stage_payload;
                            checksum     <= rx_data;
                        end else begin
                            packet_error <= 1'b1;
                            error_code   <= ERR_CRC;
                            command      <= stage_cmd;
                        end
                    end

                    ST_RELIABLE: begin
                        // Fixed 64-byte body+CRC after A5 5A 60. Once recognized,
                        // payload bytes (including A5 5A) never go through v1 parsing.
                        if(reliable_index<60) begin
                            stage_reliable[reliable_index*8+:8] <= rx_data;
                            reliable_crc <= crc_byte(reliable_crc,rx_data);
                        end else reliable_check[(reliable_index-60)*8+:8] <= rx_data;
                        if(reliable_index==63) begin
                            state <= ST_WAIT_A5;
                            command <= 8'h60;
                            if({rx_data,reliable_check[23:0]} != ~reliable_crc) begin
                                packet_error <= 1'b1; error_code <= ERR_CRC;
                                // A deleted byte may have made this envelope
                                // consume the next frame's first sync byte.
                                // The remaining tail must stay v2-only too.
                                reliable_quarantine <= 1;
                            end else begin
                                reliable_quarantine <= 0;
                                if(reliable_valid && !reliable_ready) begin
                                    packet_error <= 1'b1; error_code <= 3'd3;
                                end else begin
                                    reliable_body <= stage_reliable;
                                    reliable_digest <= ~reliable_crc;
                                    reliable_valid <= 1'b1;
                                end
                            end
                        end else reliable_index <= reliable_index+1'b1;
                    end

                    default: state <= ST_WAIT_A5;
                endcase
            end else if (frame_active) begin
                if (timeout_count == TIMEOUT_LAST) begin
                    timeout_count <= {TMO_WIDTH{1'b0}};
                    state         <= ST_WAIT_A5;
                    data_index    <= 3'd0;
                    packet_error  <= 1'b1;
                    error_code    <= ERR_TIMEOUT;
                    command       <= stage_cmd;
                    if (state == ST_RELIABLE) reliable_quarantine <= 1;
                end else begin
                    timeout_count <= timeout_count + 1'b1;
                end
            end
        end
    end

endmodule
