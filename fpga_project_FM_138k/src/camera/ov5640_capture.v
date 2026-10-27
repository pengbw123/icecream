// PCLK-domain RGB565 receiver. Validate every row and whole frame before
// publication; decimate 2x2 to RGB332 for a bounded, low-memory preview.
module ov5640_capture #(parameter integer WIDTH=320,HEIGHT=240,WARMUP_FRAMES=4)(
    input wire pclk,reset_n,input wire [7:0] data,input wire href,vsync,
    output reg pixel_write,output reg [14:0] pixel_address,
    output reg [7:0] pixel_data,output reg frame_start,frame_good,frame_bad,
    output reg frame_toggle,bad_toggle
);
    reg [7:0] data_q,high_byte;reg href_q,vsync_q,href_prev,vsync_prev;
    reg seen_sync,phase,bad;
    reg [10:0] line_bytes;reg [9:0] column,rows;
    reg [14:0] pixels;reg [3:0] warmup;
    wire [15:0] rgb565={high_byte,data_q};
    always @(posedge pclk or negedge reset_n)begin
        if(!reset_n)begin
            data_q<=0;high_byte<=0;href_q<=0;vsync_q<=0;href_prev<=0;vsync_prev<=0;
            seen_sync<=0;phase<=0;bad<=0;line_bytes<=0;column<=0;rows<=0;pixels<=0;warmup<=0;
            pixel_write<=0;pixel_address<=0;pixel_data<=0;frame_start<=0;frame_good<=0;frame_bad<=0;frame_toggle<=0;bad_toggle<=0;
        end else begin
            data_q<=data;href_q<=href;vsync_q<=vsync;href_prev<=href_q;vsync_prev<=vsync_q;
            pixel_write<=0;frame_start<=0;frame_good<=0;frame_bad<=0;
            if(vsync_q&&!vsync_prev)begin
                frame_start<=1;
                if(seen_sync)begin
                    if(!bad&&rows==HEIGHT&&pixels==(WIDTH/2)*(HEIGHT/2)&&!href_prev)begin
                        if(warmup<WARMUP_FRAMES)warmup<=warmup+1'b1;
                        else begin frame_good<=1;frame_toggle<=!frame_toggle;end
                    end else begin frame_bad<=1;bad_toggle<=!bad_toggle;warmup<=0;end
                end
                seen_sync<=1;phase<=0;bad<=0;line_bytes<=0;column<=0;rows<=0;pixels<=0;
            end else if(!vsync_q&&seen_sync)begin
                if(href_q)begin
                    if(!href_prev)begin high_byte<=data_q;phase<=1;line_bytes<=1;column<=0;end
                    else begin
                        if(line_bytes<2047)line_bytes<=line_bytes+1'b1;else bad<=1;
                        if(!phase)begin high_byte<=data_q;phase<=1;end
                        else begin
                            phase<=0;if(column<1023)column<=column+1'b1;else bad<=1;
                            if(column<WIDTH&&rows<HEIGHT&&!column[0]&&!rows[0])begin
                                pixel_write<=1;pixel_address<=pixels;
                                pixel_data<={rgb565[15:13],rgb565[10:8],rgb565[4:3]};
                                pixels<=pixels+1'b1;
                            end
                        end
                    end
                end else if(href_prev)begin
                    if(phase||line_bytes!=WIDTH*2||rows>=HEIGHT)bad<=1;
                    if(rows<1023)rows<=rows+1'b1;else bad<=1;
                    phase<=0;line_bytes<=0;
                end
            end
        end
    end
endmodule
