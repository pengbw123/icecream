// 16x32 fixed text over a solid panel, pipelined to match the RGB compositor.
module calibration_banner(input wire pclk,reset_n,enabled,input wire [10:0] h,input wire [9:0] v,
                          output wire panel_on,ink);
    // Four 32x32 monochrome glyphs: ÐÞ¸ÄÍê³É, generated from Windows
    // Microsoft YaHei; see tools/generate_calibration_glyphs.py.
    reg [31:0] font[0:127];
    initial $readmemh("src/generated/calibration_success_32.mem",font);
    wire panel=h>=200 && h<600 && v>=168 && v<312;
    wire text_area=h>=336 && h<464 && v>=224 && v<256;
    wire [10:0] tx=h-336;
    wire [9:0] ty=v-224;
    reg [31:0] glyph1,glyph2;
    reg [4:0] col1,col2;
    reg text1,text2,panel1,panel2;
    always @(posedge pclk) begin
        glyph1<=font[{tx[6:5],ty[4:0]}];col1<=tx[4:0];
        text1<=reset_n && enabled && text_area;panel1<=reset_n && enabled && panel;
        glyph2<=glyph1;col2<=col1;text2<=text1 && reset_n;panel2<=panel1 && reset_n;
    end
    assign panel_on=panel2;assign ink=text2 && glyph2[31-col2];
endmodule

// The producer holds notice_async for seconds, so a two-flop level synchronizer
// captures it safely; the display changes only during vertical blanking.
module calibration_notice_sync(input wire pclk,reset_n,notice_async,frame_latch,output reg notice_frame);
    reg meta,sync;
    always @(posedge pclk or negedge reset_n) begin
        if(!reset_n) begin meta<=0;sync<=0;notice_frame<=0;end
        else begin meta<=notice_async;sync<=meta;if(frame_latch)notice_frame<=sync;end
    end
endmodule
