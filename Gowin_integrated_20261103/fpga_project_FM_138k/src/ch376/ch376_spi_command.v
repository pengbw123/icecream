// CH376 passive SPI, mode 0, MSB first. Not the CH376 SD-card SPI port.
// WCH CH376DS1 sections 6.3/7.3: pause >=2 us after opcode; SET_USB_MODE
// additionally needs time to finish before its returned status is clocked.
module ch376_spi_command #(
    parameter integer CLK_HZ = 50000000,
    parameter integer HALF_PERIOD = 20
) (
    input wire clk, reset_n,
    input wire request_valid,
    output wire request_ready,
    input wire [7:0] command,
    input wire [3:0] write_length,
    input wire [71:0] write_data, // first byte in [7:0], maximum nine bytes
    input wire [1:0] read_mode,   // 0:none, 1:one byte, 2:length-prefixed USB block
    output reg done,
    output reg [7:0] response_length,
    output reg [511:0] response_data,
    output reg response_overflow,
    output reg spi_cs_n, spi_sck, spi_mosi,
    input wire spi_miso
);
    localparam integer COMMAND_GAP = (CLK_HZ/1000000)*3;
    localparam integer MODE_WAIT = (CLK_HZ/1000000)*30;
    localparam [3:0] IDLE=0, LOW=1, HIGH=2, BYTE_END=3, PAUSE=4, RELEASE=5;
    localparam [1:0] OPCODE=0, WRITE=1, LENGTH=2, READ=3;
    reg [3:0] state;
    reg [1:0] phase, mode;
    reg [7:0] opcode, tx_shift, rx_shift, read_goal, read_index;
    reg [3:0] write_goal, write_index;
    reg [71:0] payload;
    reg [2:0] bit_index;
    reg [31:0] delay_count;
    reg [1:0] miso_sync;
    assign request_ready = state == IDLE;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) miso_sync <= 2'b11;
        else miso_sync <= {miso_sync[0],spi_miso};
    end
    task begin_byte;
        input [7:0] value;
        begin
            tx_shift <= value; spi_mosi <= value[7]; rx_shift <= 0;
            bit_index <= 7; delay_count <= HALF_PERIOD-1; state <= LOW;
        end
    endtask
    task begin_read;
        begin
            phase <= mode==2 ? LENGTH : READ;
            read_goal <= 1; read_index <= 0;
            tx_shift <= 0; spi_mosi <= 0; rx_shift <= 0; bit_index <= 7;
            delay_count <= opcode==8'h15 ? MODE_WAIT-1 : COMMAND_GAP-1;
            state <= PAUSE;
        end
    endtask
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state<=IDLE;phase<=OPCODE;mode<=0;opcode<=0;tx_shift<=0;rx_shift<=0;
            read_goal<=0;read_index<=0;write_goal<=0;write_index<=0;payload<=0;
            bit_index<=7;delay_count<=0;done<=0;response_length<=0;
            response_data<=0;response_overflow<=0;spi_cs_n<=1;spi_sck<=0;spi_mosi<=0;
        end else begin
            done <= 0;
            case (state)
                IDLE: if (request_valid) begin
                    opcode<=command;payload<=write_data;write_goal<=write_length;
                    write_index<=0;mode<=read_mode;phase<=OPCODE;
                    response_length<=0;response_data<=0;response_overflow<=0;
                    spi_cs_n<=0;spi_sck<=0;begin_byte(command);
                end
                LOW: if (delay_count!=0) delay_count<=delay_count-1'b1;
                    else begin
                        spi_sck<=1;rx_shift<={rx_shift[6:0],miso_sync[1]};
                        delay_count<=HALF_PERIOD-1;state<=HIGH;
                    end
                HIGH: if (delay_count!=0) delay_count<=delay_count-1'b1;
                    else begin
                        spi_sck<=0;
                        if (bit_index==0) state<=BYTE_END;
                        else begin
                            bit_index<=bit_index-1'b1;tx_shift<={tx_shift[6:0],1'b0};
                            spi_mosi<=tx_shift[6];delay_count<=HALF_PERIOD-1;state<=LOW;
                        end
                    end
                BYTE_END: case (phase)
                    OPCODE: if (write_goal!=0) begin
                        phase<=WRITE;tx_shift<=payload[7:0];spi_mosi<=payload[7];
                        rx_shift<=0;bit_index<=7;delay_count<=COMMAND_GAP-1;state<=PAUSE;
                    end else if (mode!=0) begin_read();
                    else begin spi_cs_n<=1;delay_count<=COMMAND_GAP-1;state<=RELEASE;end
                    WRITE: if (write_index+1<write_goal) begin
                        payload<=payload>>8;write_index<=write_index+1'b1;begin_byte(payload[15:8]);
                    end else if (mode!=0) begin_read();
                    else begin spi_cs_n<=1;delay_count<=COMMAND_GAP-1;state<=RELEASE;end
                    LENGTH: begin
                        response_length<=rx_shift;read_goal<=rx_shift;read_index<=0;
                        response_overflow<=rx_shift>64;
                        if (rx_shift==0) begin spi_cs_n<=1;delay_count<=COMMAND_GAP-1;state<=RELEASE;end
                        else begin phase<=READ;begin_byte(0);end
                    end
                    READ: begin
                        if (read_index<64) response_data[read_index*8+:8]<=rx_shift;
                        if (mode==1) response_length<=1;
                        if (read_index+1>=read_goal) begin
                            spi_cs_n<=1;delay_count<=COMMAND_GAP-1;state<=RELEASE;
                        end else begin read_index<=read_index+1'b1;begin_byte(0);end
                    end
                endcase
                PAUSE: if (delay_count!=0) delay_count<=delay_count-1'b1;
                    else begin delay_count<=HALF_PERIOD-1;state<=LOW;end
                RELEASE: if (delay_count!=0) delay_count<=delay_count-1'b1;
                    else begin done<=1;state<=IDLE;end
                default: begin state<=IDLE;spi_cs_n<=1;spi_sck<=0;end
            endcase
        end
    end
endmodule
