// Six-byte FPGA response: A5 5A F0 command status XOR(F0,command,status).
// 0=accepted, 1=unsupported/invalid payload, 2=CRC error, 3=timeout, 4=decoder timeout.
// A reply acknowledges one parameter command, not atomic preset commit or audio.
module uart_status_reply #(
    parameter integer CLKS_PER_BIT=5208,
    parameter integer SCORE_MAX_EVENTS=2048,
    parameter integer SYNTH_VOICE_COUNT=8,
    parameter integer CLK_HZ=50000000,
    parameter integer ENABLE_RELIABLE=0,
    parameter integer ENABLE_PHONE=0,
    parameter integer ENABLE_KEY_PLAN=0
) (
    input wire clk, reset_n, valid,
    input wire [7:0] command, status,
    input wire capability_valid,
    input wire [31:0] capability_nonce,
    input wire reliable_valid,
    input wire [255:0] reliable_frame,
    output wire reliable_ready,
    input wire phone_valid,input wire [71:0] phone_frame,
    output wire tx,
    output reg overflow
);
    // Store metadata, not eight copies of the constant capability frame.
    reg [257:0] fifo [0:7];
    reg [2:0] read_index, write_index;
    reg [3:0] count;
    reg sending;
    reg [4:0] byte_index, message_last;
    reg [255:0] message_shift;
    reg phone_pending;
    reg [71:0] phone_pending_frame;
    wire ready;
    wire pop = !sending && count != 0;
    wire has_reliable = ENABLE_RELIABLE && reliable_valid;
    wire has_phone=ENABLE_PHONE && (phone_pending || phone_valid);
    wire select_phone=has_phone && !valid && !capability_valid && !has_reliable;
    wire push = (valid || capability_valid || has_reliable || has_phone) && (count < 8 || pop);
    assign reliable_ready = ENABLE_RELIABLE && !valid && !capability_valid && (count < 8 || pop);
    localparam [15:0] CAPACITY=SCORE_MAX_EVENTS;
    localparam [7:0] VOICES=SYNTH_VOICE_COUNT;
    localparam [31:0] UART_BAUD=
        (CLKS_PER_BIT == (CLK_HZ+57600)/115200) ? 32'd115200 :
        (CLKS_PER_BIT == (CLK_HZ+28800)/57600) ? 32'd57600 :
        (CLKS_PER_BIT == (CLK_HZ+4800)/9600) ? 32'd9600 :
        (CLK_HZ + CLKS_PER_BIT/2)/CLKS_PER_BIT;
    // A5 5A F1 rev=1 cmd=57 nonce32 capacity16 voices group flags baud32 v1 XOR.
    localparam [7:0] SCORE_VERSION=ENABLE_RELIABLE?8'd2:8'd1;
    localparam [7:0] LINK_FLAGS=(ENABLE_RELIABLE?8'd3:8'd1) | (ENABLE_KEY_PLAN?8'd4:8'd0);
    wire [151:0] capability_bytes={SCORE_VERSION,UART_BAUD,LINK_FLAGS,8'd8,VOICES,CAPACITY,
                                  fifo[read_index][31:0],8'h57,8'd1,8'hF1,8'h5A,8'hA5};
    function [7:0] capability_xor;
        input [151:0] bytes_in;
        integer k;
        begin
            capability_xor=8'd0;
            for(k=2;k<19;k=k+1) capability_xor=capability_xor ^ bytes_in[k*8+:8];
        end
    endfunction
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .reset_n(reset_n), .data(message_shift[7:0]),
        .valid(sending), .ready(ready), .tx(tx)
    );
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            read_index <= 0; write_index <= 0; count <= 0;
            sending <= 0; byte_index <= 0; message_last <= 0; message_shift <= 0; overflow <= 0;
            phone_pending<=0;phone_pending_frame<=0;
        end else begin
            if ((valid || capability_valid) && !push) overflow <= 1'b1;
            if (valid && capability_valid) overflow <= 1'b1;
            if (push) begin
                if(valid) fifo[write_index] <= {2'd0,240'd0,command,status};
                else if(capability_valid) fifo[write_index] <= {2'd1,224'd0,capability_nonce};
                else if(has_reliable) fifo[write_index] <= {2'd2,reliable_frame};
                else fifo[write_index] <= {2'd3,184'd0,phone_pending ? phone_pending_frame : phone_frame};
                write_index <= write_index + 1'b1;
            end
            // A phone completion can coincide with a legacy reply. Keep it
            // until the metadata FIFO accepts it rather than dropping either.
            if (ENABLE_PHONE && phone_valid) begin
                if (phone_pending && !(select_phone && push)) overflow<=1'b1;
                else if (phone_pending || !(select_phone && push)) begin
                    phone_pending<=1;phone_pending_frame<=phone_frame;
                end
            end else if (phone_pending && select_phone && push) phone_pending<=0;
            if (pop) begin
                if(fifo[read_index][257:256]==2'd3) begin
                    message_shift <= fifo[read_index][255:0];
                    message_last <= 5'd8;
                end else if(fifo[read_index][257:256]==2'd2) begin
                    message_shift <= fifo[read_index][255:0];
                    message_last <= 5'd31;
                end else if(fifo[read_index][257:256]==2'd1) begin
                    message_shift <= {96'd0,capability_xor(capability_bytes),capability_bytes};
                    message_last <= 5'd19;
                end else begin
                    message_shift <= {208'd0,8'hF0 ^ fifo[read_index][15:8] ^ fifo[read_index][7:0],
                                      fifo[read_index][7:0], fifo[read_index][15:8], 8'hF0, 8'h5A, 8'hA5};
                    message_last <= 5'd5;
                end
                read_index <= read_index + 1'b1;
                sending <= 1'b1;
                byte_index <= 0;
            end
            case ({push,pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
            if (sending && ready) begin
                message_shift <= {8'd0,message_shift[255:8]};
                if (byte_index == message_last) sending <= 1'b0;
                else byte_index <= byte_index + 1'b1;
            end
        end
    end
endmodule
