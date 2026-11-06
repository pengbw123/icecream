// -----------------------------------------------------------------------------
// uart_tx.v
//
// 8-N-1 UART transmitter, LSB first, idle line high.
//
// Handshake:
//   * A byte is accepted only on a clock where valid && ready are both high.
//   * ready is high while the transmitter is idle and low for the whole frame,
//     so one valid pulse can never launch the same byte twice.  valid is
//     expected to be a single-cycle pulse from the external logic.
//   * Each start / data / stop bit is held for exactly CLKS_PER_BIT clocks.
//   * Reset returns immediately to the idle state (ready high, tx high) and a
//     new byte may be accepted on the first clock after reset is released.
//
// clk_count is 16 bits wide, which covers the largest supported divisor (5208
// clocks per bit, e.g. 9600 baud from a 50 MHz clock).
// -----------------------------------------------------------------------------
module uart_tx #(
    parameter integer CLKS_PER_BIT = 434
) (
    input  wire       clk,
    input  wire       reset_n,
    input  wire [7:0] data,
    input  wire       valid,
    output reg        tx,
    output wire       ready
);

    localparam [1:0] TX_IDLE  = 2'd0;
    localparam [1:0] TX_START = 2'd1;
    localparam [1:0] TX_DATA  = 2'd2;
    localparam [1:0] TX_STOP  = 2'd3;

    reg  [1:0]  state;
    reg  [15:0] clk_count;
    reg  [2:0]  bit_index;
    reg  [7:0]  shift_reg;

    assign ready = (state == TX_IDLE);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state     <= TX_IDLE;
            clk_count <= 16'd0;
            bit_index <= 3'd0;
            shift_reg <= 8'd0;
            tx        <= 1'b1;
        end else begin
            case (state)
                TX_IDLE: begin
                    tx        <= 1'b1;
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;
                    if (valid && ready) begin
                        shift_reg <= data;
                        tx        <= 1'b0;      // start bit
                        state     <= TX_START;
                    end
                end

                TX_START: begin
                    if (clk_count == (CLKS_PER_BIT - 1)) begin
                        clk_count <= 16'd0;
                        bit_index <= 3'd0;
                        tx        <= shift_reg[0];
                        state     <= TX_DATA;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                TX_DATA: begin
                    if (clk_count == (CLKS_PER_BIT - 1)) begin
                        clk_count <= 16'd0;
                        if (bit_index == 3'd7) begin
                            tx    <= 1'b1;      // stop bit
                            state <= TX_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                            tx        <= shift_reg[bit_index + 1'b1];
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                TX_STOP: begin
                    tx <= 1'b1;
                    if (clk_count == (CLKS_PER_BIT - 1)) begin
                        clk_count <= 16'd0;
                        state     <= TX_IDLE;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                default: begin
                    state <= TX_IDLE;
                    tx    <= 1'b1;
                end
            endcase
        end
    end

endmodule
