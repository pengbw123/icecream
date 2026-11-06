// Compact ordered rectangles in one 36-bit BSRAM, rendered one scanline ahead.
// Two 512x2-bit register line buffers replace both the framebuffer and the
// previous 256-way per-pixel comparator array. Byte upload: index*8 + 0..4;
// low four bytes first, byte4 commits. Count at 0x7ff8/9. Later rectangles win.
// Firmware disables and drains before upload, enabling after the final count.
// Actual six-operator lists take <=401 pclk cycles/line (1056 are available).
module ui_algo_map #(parameter integer PANEL_X=144, PANEL_Y=160)(
    input wire pclk,input wire video_reset_n,
    input wire [10:0] h,input wire [9:0] v,input wire enable,
    input wire wclk,input wire we,input wire [14:0] waddr,
    input wire [7:0] wdata,output wire ink,output wire [1:0] cls
);
    reg [35:0] rectangles[0:255] /* synthesis syn_ramstyle = "block_ram" */;
    reg [31:0] staging;
    reg [8:0] count=0;
    always @(posedge wclk)if(we)begin
        if(waddr==15'h7ff8)count[7:0]<=wdata;
        else if(waddr==15'h7ff9)count[8]<=wdata[0];
        else if(waddr<2048)case(waddr[2:0])
            0:staging[7:0]<=wdata;
            1:staging[15:8]<=wdata;
            2:staging[23:16]<=wdata;
            3:staging[31:24]<=wdata;
            4:rectangles[waddr[10:3]]<={wdata[3:0],staging};
        endcase
    end
    reg en_meta=0,en_sync=0;
    always @(posedge pclk)begin
        if(!video_reset_n)begin en_meta<=0;en_sync<=0;end
        else begin en_meta<=enable;en_sync<=en_meta;end
    end
    reg [15:0] line0[0:63] /* synthesis syn_ramstyle = "registers" */;
    reg [15:0] line1[0:63] /* synthesis syn_ramstyle = "registers" */;
    reg [35:0] rect_read;
    reg [7:0] rect_index;
    always @(posedge pclk)rect_read<=rectangles[rect_index];
    localparam IDLE=0,CLEAR=1,WAIT_RAM=2,CHECK=3,FILL=4,DONE=5;
    reg [2:0] state=IDLE;
    reg [7:0] render_y;
    reg work_bank,ready=0,display_valid=0;
    reg [8:0] span_first,span_last;
    reg [1:0] span_cls;
    reg [5:0] column;
    wire last_rect=({1'b0,rect_index}+9'd1)>=count;
    reg [15:0] mask,paint;
    integer b;
    always @*begin
        mask=0;paint=0;
        for(b=0;b<8;b=b+1)if(({column,3'b000}+b)>=span_first&&({column,3'b000}+b)<=span_last)begin
            mask[b*2+:2]=2'b11;paint[b*2+:2]=span_cls;
        end
    end
    integer i;
    always @(posedge pclk)begin
        if(!video_reset_n||!en_sync)begin
            state<=IDLE;ready<=0;display_valid<=0;rect_index<=0;
            render_y<=0;work_bank<=0;span_first<=0;span_last<=0;span_cls<=0;column<=0;
        end else if(h==0)begin
            // Swap only complete rows. An unsupported oversized list blanks a
            // row instead of exposing a partially overwritten line buffer.
            display_valid<=v>=PANEL_Y&&v<PANEL_Y+256&&ready&&render_y==v-PANEL_Y;
            if(v>=PANEL_Y-1&&v<PANEL_Y+255)begin
                render_y<=v+1-PANEL_Y;work_bank<=(v+1-PANEL_Y)&1;
                ready<=0;rect_index<=0;state<=CLEAR;
            end
        end else case(state)
            CLEAR:begin
                for(i=0;i<64;i=i+1)begin
                    if(work_bank)line1[i]<=0;else line0[i]<=0;
                end
                state<=WAIT_RAM;
            end
            WAIT_RAM:state<=CHECK;
            CHECK:begin
                if(count==0)begin ready<=1;state<=DONE;end
                else if(render_y>=rect_read[25:18]&&render_y<=rect_read[33:26]&&rect_read[8:0]<=rect_read[17:9])begin
                    span_first<=rect_read[8:0];span_last<=rect_read[17:9];span_cls<=rect_read[35:34];
                    column<=rect_read[8:3];state<=FILL;
                end else if(last_rect)begin ready<=1;state<=DONE;end
                else begin rect_index<=rect_index+1'b1;state<=WAIT_RAM;end
            end
            FILL:begin
                if(work_bank)line1[column]<=(line1[column]&~mask)|paint;
                else line0[column]<=(line0[column]&~mask)|paint;
                if(column==span_last[8:3])begin
                    if(last_rect)begin ready<=1;state<=DONE;end
                    else begin rect_index<=rect_index+1'b1;state<=WAIT_RAM;end
                end else column<=column+1'b1;
            end
            default:;
        endcase
    end
    wire inside_panel=h>=PANEL_X&&h<PANEL_X+512&&v>=PANEL_Y&&v<PANEL_Y+256;
    wire [8:0] x=h-PANEL_X;
    wire bank=(v-PANEL_Y)&1;
    reg [15:0] word1;
    reg [2:0] select1;
    reg [1:0] pixel2;
    reg valid1=0,valid2=0;
    always @(posedge pclk)begin
        if(!video_reset_n)begin valid1<=0;valid2<=0;word1<=0;pixel2<=0;select1<=0;end
        else begin
            if(en_sync&&inside_panel&&display_valid)word1<=bank?line1[x[8:3]]:line0[x[8:3]];
            else word1<=0;
            select1<=x[2:0];pixel2<=word1[{select1,1'b0}+:2];
            valid1<=en_sync&&inside_panel&&display_valid;valid2<=valid1&&en_sync;
        end
    end
    assign cls=valid2?pixel2:2'd0;
    assign ink=|cls;
endmodule
