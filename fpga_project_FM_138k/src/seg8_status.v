// Matches ACG720's two cascaded HC595s: {DP, active-low segments, digit select}.
// Everything uses clk enables; no fabric-generated scanning clock.
module seg8_status(input wire clk,reset_n,input wire [31:0] bcd,
    output reg data,shift_clk,latch_clk);
    reg [15:0] divider;reg [5:0] bit_cycle;reg [2:0] digit;
    reg [15:0] serial_word;reg [31:0] frame_value;
    function [6:0] decode(input [3:0] n);
        begin case(n)0:decode=7'h40;1:decode=7'h79;2:decode=7'h24;3:decode=7'h30;
        4:decode=7'h19;5:decode=7'h12;6:decode=7'h02;7:decode=7'h78;
        8:decode=0;9:decode=7'h10;10:decode=7'h08;11:decode=7'h03;
        12:decode=7'h46;13:decode=7'h21;14:decode=7'h06;default:decode=7'h7f;endcase end
    endfunction
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin divider<=0;bit_cycle<=0;digit<=0;serial_word<=0;
            data<=0;shift_clk<=0;latch_clk<=0;frame_value<=0;end
        else begin
            if(divider==499)begin divider<=0;
                if(bit_cycle==0)begin
                    if(digit==0)frame_value<=bcd;
                    serial_word<={1'b0,decode(frame_value>>(digit*4)),8'b1<<digit};
                    latch_clk<=0;bit_cycle<=1;
                end else if(bit_cycle<=32)begin
                    if(bit_cycle[0])begin shift_clk<=0;data<=serial_word[15];end
                    else begin shift_clk<=1;serial_word<={serial_word[14:0],1'b0};end
                    bit_cycle<=bit_cycle+1'b1;
                end else if(bit_cycle==33)begin shift_clk<=0;latch_clk<=1;bit_cycle<=34;end
                else begin latch_clk<=0;bit_cycle<=0;digit<=digit+1'b1;end
            end else divider<=divider+1'b1;
        end
    end
endmodule
