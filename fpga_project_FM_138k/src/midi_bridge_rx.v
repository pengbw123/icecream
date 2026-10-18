// A second, independent 1-Mbaud UART for the temporary 25K MIDI bridge.
// Frame: A5 5A 30 STATUS DATA1 DATA2 BRIGHTNESS 00 00 00 00 XOR(CMD..D7).
// The existing PC-facing CH340 UART keeps its own parser and COM port.
module midi_bridge_rx #(
    parameter integer CLKS_PER_BIT = 50
) (
    input  wire clk,
    input  wire reset_n,
    input  wire rx_pin,
    output reg [31:0] midi_event_data,
    output reg midi_event_valid,
    input  wire midi_event_ready,
    output reg [15:0] dropped_events
);
    wire [7:0] rx_byte;
    wire rx_valid;
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .reset_n(reset_n), .rx(rx_pin),
        .data(rx_byte), .valid(rx_valid)
    );
    localparam [3:0] WAIT_A5=0, WAIT_5A=1, READ_CMD=2,
                     READ_D0=3, READ_D1=4, READ_D2=5, READ_D3=6,
                     READ_D4=7, READ_D5=8, READ_D6=9, READ_D7=10,
                     READ_SUM=11;
    reg [3:0] state;
    reg [7:0] command, status, data1, data2, brightness, checksum;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= WAIT_A5;
            command <= 0; status <= 0; data1 <= 0; data2 <= 0;
            brightness <= 0; checksum <= 0;
            midi_event_data <= 0;
            midi_event_valid <= 0;
            dropped_events <= 0;
        end else begin
            if (midi_event_valid && midi_event_ready)
                midi_event_valid <= 1'b0;
            if (rx_valid) begin
                case (state)
                    WAIT_A5: if (rx_byte == 8'hA5) state <= WAIT_5A;
                    WAIT_5A: if (rx_byte == 8'h5A) state <= READ_CMD;
                             else if (rx_byte != 8'hA5) state <= WAIT_A5;
                    READ_CMD: begin command <= rx_byte; checksum <= rx_byte; state <= READ_D0; end
                    READ_D0: begin status <= rx_byte; checksum <= checksum ^ rx_byte; state <= READ_D1; end
                    READ_D1: begin data1 <= rx_byte; checksum <= checksum ^ rx_byte; state <= READ_D2; end
                    READ_D2: begin data2 <= rx_byte; checksum <= checksum ^ rx_byte; state <= READ_D3; end
                    READ_D3: begin brightness <= rx_byte; checksum <= checksum ^ rx_byte; state <= READ_D4; end
                    READ_D4: begin checksum <= checksum ^ rx_byte; state <= READ_D5; end
                    READ_D5: begin checksum <= checksum ^ rx_byte; state <= READ_D6; end
                    READ_D6: begin checksum <= checksum ^ rx_byte; state <= READ_D7; end
                    READ_D7: begin checksum <= checksum ^ rx_byte; state <= READ_SUM; end
                    READ_SUM: begin
                        state <= WAIT_A5;
                        if (rx_byte == checksum && command == 8'h30) begin
                            if (!midi_event_valid || midi_event_ready) begin
                                midi_event_data <= {8'd0, status, 1'b0, data1[6:0],
                                                    1'b0, data2[6:0]};
                                midi_event_valid <= 1'b1;
                            end else dropped_events <= dropped_events + 1'b1;
                        end
                    end
                    default: state <= WAIT_A5;
                endcase
            end
        end
    end
endmodule
