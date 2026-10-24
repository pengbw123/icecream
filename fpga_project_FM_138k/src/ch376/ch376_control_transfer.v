// USB endpoint-zero control transfers over CH376 ISSUE_TKN_X (WCH DS2 1.20/2.2).
// Supports IN data and no-data OUT requests needed for class-compliant MIDI.
// Full configurations are streamed, not limited by GET_DESCR's 64-byte buffer.
module ch376_control_transfer #(
    parameter integer CLK_HZ=50000000,
    parameter integer TIMEOUT_CYCLES=CLK_HZ/2,
    parameter integer RETRY_CYCLES=CLK_HZ/1000
) (
    input wire clk,reset_n,start,
    input wire [63:0] setup_packet,
    input wire [6:0] ep0_max_packet,
    input wire interrupt_n,
    output wire busy,
    output reg done,success,
    output reg [7:0] error_code,
    output reg data_valid,
    output reg [7:0] data_byte,
    output reg [15:0] data_address,received_length,
    output wire command_valid,
    input wire command_ready,
    output reg [7:0] command,
    output reg [3:0] write_length,
    output reg [71:0] write_data,
    output reg [1:0] read_mode,
    input wire command_done,
    input wire [7:0] response_length,
    input wire [511:0] response_data,
    input wire response_overflow
);
    localparam [4:0] IDLE=0,SEND=1,WAIT_COMMAND=2,SETUP_TOKEN=3,
        WAIT_IRQ=4,CHECK_STATUS=5,ISSUE=6,READ_PACKET=7,STREAM=8,
        NEXT_PACKET=9,STATUS_OUT=10,STATUS_OUT_TOKEN=11,FINISH=12,
        RETRY_WAIT=13,CHECK_PACKET=14;
    localparam [2:0] SETUP_STAGE=0,DATA_STAGE=1,IN_STATUS=2,OUT_STATUS=3;
    reg [4:0] state,next_state;
    reg [2:0] stage;
    reg [31:0] timeout_count,retry_count;
    reg [15:0] requested;
    reg [6:0] max_packet;
    reg data_toggle;
    reg [7:0] last_status,packet_length,stream_index;
    reg [511:0] packet;
    assign busy=state!=IDLE;
    assign command_valid=state==SEND;
    task issue_command;
        input [7:0] op;
        input [3:0] n;
        input [71:0] bytes;
        input [1:0] mode;
        input [4:0] resume;
        begin command<=op;write_length<=n;write_data<=bytes;read_mode<=mode;
            next_state<=resume;state<=SEND;end
    endtask
    task fail_transfer;
        input [7:0] reason;
        begin success<=0;error_code<=reason;state<=FINISH;end
    endtask
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state<=IDLE;next_state<=IDLE;stage<=SETUP_STAGE;timeout_count<=0;retry_count<=0;
            requested<=0;max_packet<=8;data_toggle<=1;last_status<=0;packet_length<=0;
            stream_index<=0;packet<=0;command<=0;write_length<=0;write_data<=0;read_mode<=0;
            done<=0;success<=0;error_code<=0;data_valid<=0;data_byte<=0;data_address<=0;received_length<=0;
        end else begin
            done<=0;data_valid<=0;
            if (state!=IDLE && state!=FINISH && timeout_count>=TIMEOUT_CYCLES-1)
                fail_transfer(8'he1);
            else begin
                if (state!=IDLE && state!=FINISH) timeout_count<=timeout_count+1'b1;
                case (state)
                    IDLE: if (start) begin
                        timeout_count<=0;success<=0;error_code<=0;received_length<=0;
                        requested<=setup_packet[63:48];max_packet<=ep0_max_packet;
                        stage<=SETUP_STAGE;data_toggle<=1;
                        if (!setup_packet[7] && setup_packet[63:48]!=0) fail_transfer(8'he2);
                        else issue_command(8'h2c,9,{setup_packet,8'd8},0,SETUP_TOKEN);
                    end
                    SEND: if (command_ready) state<=WAIT_COMMAND;
                    WAIT_COMMAND: if (command_done) begin
                        last_status<=response_data[7:0];packet<=response_data;
                        packet_length<=response_length;
                        if (response_overflow) fail_transfer(8'he3);
                        else state<=next_state;
                    end
                    SETUP_TOKEN: issue_command(8'h4e,2,72'h0d00,0,WAIT_IRQ);
                    WAIT_IRQ: if (!interrupt_n) issue_command(8'h22,0,0,1,CHECK_STATUS);
                    CHECK_STATUS: begin
                        if (last_status==8'h14) begin
                            case (stage)
                                SETUP_STAGE: begin
                                    stage<=requested!=0 ? DATA_STAGE : IN_STATUS;
                                    data_toggle<=1;state<=ISSUE;
                                end
                                DATA_STAGE,IN_STATUS: issue_command(8'h27,0,0,2,CHECK_PACKET);
                                OUT_STATUS: begin success<=1;state<=FINISH;end
                                default: fail_transfer(8'he4);
                            endcase
                        end else if ((last_status & 8'h2f)==8'h2a ||
                                     last_status==8'h23 || last_status==8'h2b) begin
                            // NAK/duplicate data: keep the same data PID and buffer position.
                            retry_count<=RETRY_CYCLES-1;state<=RETRY_WAIT;
                        end else fail_transfer(last_status);
                    end
                    RETRY_WAIT: if (retry_count!=0) retry_count<=retry_count-1'b1;
                        else if (stage==SETUP_STAGE) state<=SETUP_TOKEN;
                        else if (stage==OUT_STATUS) state<=STATUS_OUT;
                        else state<=ISSUE;
                    ISSUE: issue_command(8'h4e,2,{56'd0,8'h09,(data_toggle ? 8'h80 : 8'h00)},0,WAIT_IRQ);
                    CHECK_PACKET: begin
                        if (stage==IN_STATUS) begin
                            if (packet_length!=0) fail_transfer(8'he5);
                            else begin success<=1;state<=FINISH;end
                        end else if (packet_length>{1'b0,max_packet} ||
                                     {1'b0,received_length}+{9'd0,packet_length}>{1'b0,requested}) fail_transfer(8'he6);
                        else begin stream_index<=0;state<=packet_length==0 ? NEXT_PACKET : STREAM;end
                    end
                    STREAM: begin
                        data_valid<=1;data_byte<=packet[stream_index*8+:8];
                        data_address<=received_length+{8'd0,stream_index};
                        if (stream_index+1>=packet_length) state<=NEXT_PACKET;
                        else stream_index<=stream_index+1'b1;
                    end
                    NEXT_PACKET: begin
                        received_length<=received_length+{8'd0,packet_length};data_toggle<=!data_toggle;
                        if (packet_length<{1'b0,max_packet} || received_length+{8'd0,packet_length}>=requested)
                            state<=STATUS_OUT;
                        else state<=ISSUE;
                    end
                    STATUS_OUT: begin
                        stage<=OUT_STATUS;issue_command(8'h2c,1,0,0,STATUS_OUT_TOKEN);
                    end
                    STATUS_OUT_TOKEN: issue_command(8'h4e,2,72'h0140,0,WAIT_IRQ);
                    FINISH: begin done<=1;state<=IDLE;end
                    default: fail_transfer(8'he7);
                endcase
            end
        end
    end
endmodule
