// Select GT911/GT9147 7-bit I2C address 0x14 using the reset sequence that
// was verified by the standalone touch test:
//   RST=0, INT=0 for 20 ms
//   RST=0, INT=1 for 1 ms (select address 0x14)
//   RST=1, INT=1 for 6 ms
//   RST=1, INT=0 for 50 ms
//   release INT and wait 100 ms before software starts I2C traffic
// The bidirectional pad is instantiated in the top level.
module gt9147_reset(
    input  wire clk,
    input  wire reset_n,
    output wire tp_int_o,
    output wire tp_int_t,
    output reg  tp_rst,
    output reg  ready
);
    reg drive_int;
    reg int_value;
    reg [22:0] count;
    reg [2:0] state;
    assign tp_int_o = int_value;
    assign tp_int_t = ~drive_int;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state <= 0;
            count <= 0;
            drive_int <= 1;
            int_value <= 0;
            tp_rst <= 0;
            ready <= 0;
        end else case(state)
            0: begin // RST=0, INT=0, 20 ms
                drive_int <= 1;
                int_value <= 0;
                tp_rst <= 0;
                if(count == 23'd999999) begin count <= 0; state <= 1; end
                else count <= count + 1'b1;
            end
            1: begin // Select address 0x14, 1 ms
                int_value <= 1;
                if(count == 23'd49999) begin count <= 0; state <= 2; end
                else count <= count + 1'b1;
            end
            2: begin // Release reset while INT remains high, 6 ms
                tp_rst <= 1;
                if(count == 23'd299999) begin count <= 0; state <= 3; end
                else count <= count + 1'b1;
            end
            3: begin // Goodix post-reset synchronization, 50 ms
                int_value <= 0;
                if(count == 23'd2499999) begin count <= 0; state <= 4; end
                else count <= count + 1'b1;
            end
            4: begin // Release INT and allow the controller to boot, 100 ms
                drive_int <= 0;
                if(count == 23'd4999999) begin
                    count <= 0;
                    ready <= 1;
                    state <= 5;
                end else count <= count + 1'b1;
            end
            default: begin
                drive_int <= 0;
                tp_rst <= 1;
                ready <= 1;
            end
        endcase
    end
endmodule
