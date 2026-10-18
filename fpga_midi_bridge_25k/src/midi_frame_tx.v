// 12-byte framed MIDI event transport, 1 Mbaud/8N1 at 50 MHz.
// A5 5A 30 status data1 data2 brightness 00 00 00 00 checksum.
module midi_frame_tx #(
    parameter integer CLKS_PER_BIT = 50
) (
    input wire clk, input wire reset_n,
    input wire [31:0] event_data,
    input wire event_valid,
    output wire event_ready,
    output wire tx
);
    reg busy;
    reg [95:0] remaining;
    reg [9:0] shift;
    reg [15:0] timer;
    reg [3:0] bit_index,byte_index;
    wire [7:0] checksum=8'h30 ^ event_data[23:16] ^ event_data[15:8];
    wire [95:0] packet={checksum,32'd0,event_data[7:0],event_data[7:0],
                       event_data[15:8],event_data[23:16],8'h30,8'h5A,8'hA5};
    assign event_ready=~busy;
    assign tx=busy ? shift[0] : 1'b1;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            busy<=0;remaining<=0;shift<=10'h3FF;timer<=0;bit_index<=0;byte_index<=0;
        end else if (!busy) begin
            if (event_valid) begin
                busy<=1;remaining<=packet>>8;shift<={1'b1,8'hA5,1'b0};
                timer<=0;bit_index<=0;byte_index<=0;
            end
        end else if (timer==CLKS_PER_BIT-1) begin
            timer<=0;
            if (bit_index==9) begin
                bit_index<=0;
                if (byte_index==11) busy<=0;
                else begin
                    byte_index<=byte_index+1'b1;
                    shift<={1'b1,remaining[7:0],1'b0};remaining<=remaining>>8;
                end
            end else begin bit_index<=bit_index+1'b1;shift<={1'b1,shift[9:1]};end
        end else timer<=timer+1'b1;
    end
endmodule
