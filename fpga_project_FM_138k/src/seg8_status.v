// ACG720: segment byte then digit select, MSB first. DP is active low too.
// Glyphs: 0..9 decimal, A=L, B=P, F=blank. Only clock enables, no new clock.
module seg8_status #(parameter integer SCAN_DIV=500)(input wire clk,reset_n,input wire [31:0] bcd,
    output reg data,shift_clk,latch_clk);
    localparam integer DIV_BITS=SCAN_DIV>1 ? $clog2(SCAN_DIV) : 1;
    reg [DIV_BITS-1:0] divider;reg [5:0] bit_cycle;reg [2:0] digit;
    reg [15:0] serial_word;reg [31:0] frame_value;
    wire [31:0] scan_value=digit==0 ? bcd : frame_value;
    function [6:0] decode(input [3:0] n);
        begin case(n)0:decode=7'h40;1:decode=7'h79;2:decode=7'h24;3:decode=7'h30;
        4:decode=7'h19;5:decode=7'h12;6:decode=7'h02;7:decode=7'h78;
        8:decode=0;9:decode=7'h10;10:decode=7'h47;11:decode=7'h0c;
        default:decode=7'h7f;endcase end
    endfunction
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin divider<=0;bit_cycle<=0;digit<=0;serial_word<=16'hff00;
            data<=0;shift_clk<=0;latch_clk<=0;frame_value<=32'hffffffff;end
        else begin
            if(divider==SCAN_DIV-1)begin divider<=0;
                if(bit_cycle==0)begin
                    if(digit==0)frame_value<=bcd;
                    // First digit must use the new snapshot, not last frame.
                    serial_word<={1'b1,decode(scan_value>>(digit*4)),8'b1<<digit};
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

// 40 ms peak windows of final PCM, after effects/master volume and before route.
// Linear percentage of digital full scale; not acoustic loudness or dB SPL.
// Clock-based windows return to zero even if sample_tick stops.
module seg8_audio_status #(
    parameter integer WINDOW_CYCLES=2000000,
    parameter integer SCAN_DIV=500
)(
    input wire clk,reset_n,sample_tick,
    input wire signed [15:0] audio_sample,
    input wire [7:0] active_voices,
    output wire data,shift_clk,latch_clk
);
    localparam integer WINDOW_BITS=WINDOW_CYCLES>1 ? $clog2(WINDOW_CYCLES) : 1;
    reg [WINDOW_BITS-1:0] window_count;
    reg [15:0] peak;
    wire [15:0] magnitude=audio_sample[15] ? (~audio_sample+16'd1) : audio_sample;
    wire [15:0] peak_now=sample_tick && magnitude>peak ? magnitude : peak;
    wire [22:0] peak_wide={7'd0,peak_now};
    reg [22:0] scaled_peak;
    reg scale_valid;
    reg [6:0] level;
    // 99*x = 64*x + 32*x + 2*x + x; rounding maps full scale to 99.
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            window_count<=0;peak<=0;scaled_peak<=0;scale_valid<=0;level<=0;
        end else begin
            scale_valid<=0;
            if(window_count==WINDOW_CYCLES-1) begin
                window_count<=0;peak<=0;
                scaled_peak<=(peak_wide<<6)+(peak_wide<<5)+(peak_wide<<1)+peak_wide+23'd16384;
                scale_valid<=1;
            end else begin
                window_count<=window_count+1'b1;peak<=peak_now;
            end
            if(scale_valid) level<=scaled_peak[21:15];
        end
    end
    // Separate population-count fanout from decimal conversion by a register.
    reg [7:0] voices;
    always @(posedge clk or negedge reset_n)
        if(!reset_n) voices<=0;
        else voices<=active_voices>99 ? 8'd99 : active_voices;
    wire [3:0] lt=level/10,lo=level%10,vt=voices/10,vo=voices%10;
    reg [31:0] digits;
    always @(posedge clk or negedge reset_n)
        if(!reset_n) digits<=32'haf00bf00;
        else digits<={4'ha,4'hf,lt,lo,4'hb,4'hf,vt,vo};
    seg8_status #(.SCAN_DIV(SCAN_DIV)) u_scan(
        .clk(clk),.reset_n(reset_n),.bcd(digits),
        .data(data),.shift_clk(shift_clk),.latch_clk(latch_clk));
endmodule
