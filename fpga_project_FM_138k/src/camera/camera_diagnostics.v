// Readable bring-up telemetry. Capture uses a held packet/toggle handshake;
// a Gray counter measures PCLK independently of sensor configuration/reset.
// Everything shown is latched at HDMI vertical blank, so digits stay coherent.
module camera_diagnostics #(parameter integer PIXEL_CLOCKS_PER_MS=25000)(
    input wire pixel_clk,reset_n,camera_pclk,camera_href,camera_vsync,config_ready,
    input wire [2:0] config_fault,input wire [15:0] chip_id,
    input wire [7:0] frame_count,error_count,drop_count,capture_status,
    input wire debug_request,input wire [71:0] debug_packet,output reg debug_ack,
    input wire frame_latch,input wire [9:0] prefetch_x,prefetch_y,x,y,
    output wire area,ink
);
    reg [19:0] pclk_count,pclk_gray;
    reg [2:0] pclk_reset_sync;
    always @(posedge camera_pclk or negedge reset_n)
        if(!reset_n)pclk_reset_sync<=0;else pclk_reset_sync<={pclk_reset_sync[1:0],1'b1};
    wire [19:0] pclk_next=pclk_count+1'b1;
    always @(posedge camera_pclk or negedge pclk_reset_sync[2])
        if(!pclk_reset_sync[2])begin pclk_count<=0;pclk_gray<=0;end
        else begin pclk_count<=pclk_next;pclk_gray<=pclk_next^(pclk_next>>1);end
    reg [19:0] gray_meta,gray_sync;
    function [19:0] decode_gray(input [19:0] g);
        integer i;begin decode_gray[19]=g[19];
            for(i=18;i>=0;i=i-1)decode_gray[i]=decode_gray[i+1]^g[i];end
    endfunction
    wire [19:0] clock_count=decode_gray(gray_sync);
    reg [15:0] window_count,href_count,vsync_count;
    reg [19:0] previous_clock,pclk_khz;
    reg [1:0] href_sync,vsync_sync,ready_sync,request_sync;
    reg href_prev,vsync_prev;
    reg [15:0] id_meta,id_sync;
    reg [2:0] fault_meta,fault_sync;
    reg [71:0] measured_packet,display_packet;
    reg [19:0] display_clock;
    reg [15:0] display_href,display_vsync,display_id;
    reg [2:0] display_fault;reg display_ready;reg [7:0] display_levels;
    reg [23:0] display_counts;reg [7:0] state_meta,state_sync;
    always @(posedge pixel_clk or negedge reset_n)begin
        if(!reset_n)begin
            gray_meta<=0;gray_sync<=0;window_count<=0;previous_clock<=0;pclk_khz<=0;
            href_sync<=0;vsync_sync<=0;ready_sync<=0;request_sync<=0;debug_ack<=0;
            href_prev<=0;vsync_prev<=0;href_count<=0;vsync_count<=0;id_meta<=0;id_sync<=0;fault_meta<=0;fault_sync<=0;
            measured_packet<=0;display_packet<=0;display_clock<=0;display_href<=0;display_vsync<=0;display_id<=0;
            display_fault<=0;display_ready<=0;display_levels<=0;
            display_counts<=0;state_meta<=0;state_sync<=0;
        end else begin
            gray_meta<=pclk_gray;gray_sync<=gray_meta;
            href_sync<={href_sync[0],camera_href};vsync_sync<={vsync_sync[0],camera_vsync};
            href_prev<=href_sync[1];vsync_prev<=vsync_sync[1];
            if(href_sync[1]&&!href_prev)href_count<=href_count+1'b1;
            if(vsync_sync[1]&&!vsync_prev)vsync_count<=vsync_count+1'b1;
            ready_sync<={ready_sync[0],config_ready};id_meta<=chip_id;id_sync<=id_meta;
            fault_meta<=config_fault;fault_sync<=fault_meta;state_meta<=capture_status;state_sync<=state_meta;
            request_sync<={request_sync[0],debug_request};
            if(!ready_sync[1])begin request_sync<=0;debug_ack<=0;end
            else if(request_sync[1]!=debug_ack)begin measured_packet<=debug_packet;debug_ack<=request_sync[1];end
            if(window_count==PIXEL_CLOCKS_PER_MS-1)begin
                window_count<=0;pclk_khz<=clock_count-previous_clock;previous_clock<=clock_count;
            end else window_count<=window_count+1'b1;
            if(frame_latch)begin
                display_packet<=measured_packet;display_clock<=pclk_khz;display_href<=href_count;display_vsync<=vsync_count;
                display_id<=id_sync;display_fault<=fault_sync;display_ready<=ready_sync[1];display_levels<={state_sync[7:2],vsync_sync[1],href_sync[1]};
                display_counts<={frame_count,error_count,drop_count};
            end
        end
    end
    function [6:0] hex_char(input [3:0] n);
        hex_char=n<10 ? 7'd48+{3'd0,n}:7'd55+{3'd0,n};
    endfunction
    reg [6:0] character;reg [255:0] line_text;reg [19:0] value;
    wire [5:0] col=prefetch_x[9:4];
    wire [1:0] row=prefetch_y[6:5]-2'd3; // y352..479 -> rows0..3
    integer shift;
    always @*begin
        case(row)
            0:line_text="ID:0000 E:0 READY:0             ";
            1:line_text="P:00000 H:0000 V:0000           ";
            2:line_text="R:0000 B:0000-0000              ";
            default:line_text="N:0000 F:00 S:00 G:00 D:00 B:00 ";
        endcase
        character=col<32 ? (line_text>>((31-col)*8)):7'd32;
        value=0;shift=0;
        case(row)
            0:begin
                if(col>=3&&col<=6)begin value=display_id;shift=(6-col)*4;character=hex_char(value>>shift);end
                if(col==10)character=hex_char({1'b0,display_fault});
                if(col==18)character=display_ready?7'd49:7'd48;
            end
            1:begin
                if(col>=2&&col<=6)begin value=display_clock;shift=(6-col)*4;character=hex_char(value>>shift);end
                if(col>=10&&col<=13)begin value=display_href;shift=(13-col)*4;character=hex_char(value>>shift);end
                if(col>=17&&col<=20)begin value=display_vsync;shift=(20-col)*4;character=hex_char(value>>shift);end
            end
            2:begin
                if(col>=2&&col<=5)begin value=display_packet[31:16];shift=(5-col)*4;character=hex_char(value>>shift);end
                if(col>=9&&col<=12)begin value=display_packet[47:32];shift=(12-col)*4;character=hex_char(value>>shift);end
                if(col>=14&&col<=17)begin value=display_packet[63:48];shift=(17-col)*4;character=hex_char(value>>shift);end
            end
            3:begin
                if(col>=2&&col<=5)begin value=display_packet[15:0];shift=(5-col)*4;character=hex_char(value>>shift);end
                if(col==9)character=hex_char(display_packet[71:68]);
                if(col==10)character=hex_char(display_packet[67:64]);
                if(col==14)character=hex_char(display_levels[7:4]);
                if(col==15)character=hex_char(display_levels[3:0]);
                if(col==19)character=hex_char(display_counts[23:20]);
                if(col==20)character=hex_char(display_counts[19:16]);
                if(col==24)character=hex_char(display_counts[7:4]);
                if(col==25)character=hex_char(display_counts[3:0]);
                if(col==29)character=hex_char(display_counts[15:12]);
                if(col==30)character=hex_char(display_counts[11:8]);
            end
        endcase
    end
    reg [7:0] font[0:2047] /* synthesis syn_ramstyle="block_ram" */;
    initial $readmemh("src/generated/font8x16.mem",font);
    reg [7:0] font_row;
    always @(posedge pixel_clk)font_row<=font[{character,prefetch_y[4:1]}];
    assign area=y>=352&&y<480&&x<640;
    assign ink=area&&font_row[7-x[3:1]];
endmodule
