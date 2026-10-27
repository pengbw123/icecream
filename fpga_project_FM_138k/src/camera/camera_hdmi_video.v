// 640x480/59.52 Hz at the existing 25 MHz HDMI clock. Registered RGB/sync
// align with the synchronous framebuffer read; nearest-neighbour 4x preview.
module camera_hdmi_video #(parameter integer STALE_FRAMES=60)(
    input wire pixel_clk,reset_n,config_ready,input wire [2:0] config_fault,
    input wire buffer_valid,present_pulse,input wire [7:0] pixel_data,
    input wire bad_toggle,drop_toggle,
    output wire frame_latch,output wire [14:0] read_address,
    output reg [7:0] red,green,blue,output reg de,hsync,vsync,
    output wire stream_stale
);
    reg [9:0] hcount,vcount,x1,y1;
    reg [1:0] ready_sync,bad_sync,drop_sync;
    reg [2:0] fault_meta,fault_sync;
    reg bad_prev,drop_prev;reg [7:0] frames,errors,drops;
    reg [6:0] silent_frames;
    assign frame_latch=hcount==0&&vcount==480;
    wire active=hcount<640&&vcount<480;
    wire [14:0] row_address=({8'd0,vcount[8:2]}<<7)+({8'd0,vcount[8:2]}<<5);
    assign read_address=active?row_address+{7'd0,hcount[9:2]}:15'd0;
    assign stream_stale=!buffer_valid||silent_frames>=STALE_FRAMES;
    wire [7:0] r332={pixel_data[7:5],pixel_data[7:5],pixel_data[7:6]};
    wire [7:0] g332={pixel_data[4:2],pixel_data[4:2],pixel_data[4:3]};
    wire [7:0] b332={4{pixel_data[1:0]}};
    reg [23:0] color;reg [2:0] bit_sel;
    always @*begin
        color={r332,g332,b332};bit_sel=x1[6:4];
        if(stream_stale||!ready_sync[1])begin
            color=((x1[5]^y1[5])?24'h18202c:24'h101820);
            if(x1==320||y1==240)color=24'h405060;
        end
        // Status strip: red=config failure; amber=initializing; blue=no valid
        // or fresh frame; green=complete live frames. Bottom: frame/error/drop
        // binary counters, each group has eight blocks (LSB on the left).
        if(y1<8)color=fault_sync!=0?24'hd02020:!ready_sync[1]?24'hd09010:
            stream_stale?24'h2050c0:24'h20a060;
        if(y1>=472)begin
            if(x1<128)color=frames[bit_sel]?24'h20a060:24'h081810;
            else if(x1<256)color=errors[bit_sel]?24'hd02020:24'h180808;
            else if(x1<384)color=drops[bit_sel]?24'hd09010:24'h181008;
        end
        if(x1>=640||y1>=480)color=0;
    end
    always @(posedge pixel_clk or negedge reset_n)begin
        if(!reset_n)begin
            hcount<=0;vcount<=0;x1<=0;y1<=0;red<=0;green<=0;blue<=0;de<=0;hsync<=1;vsync<=1;
            ready_sync<=0;fault_meta<=0;fault_sync<=0;bad_sync<=0;drop_sync<=0;bad_prev<=0;drop_prev<=0;
            frames<=0;errors<=0;drops<=0;silent_frames<=STALE_FRAMES;
        end else begin
            ready_sync<={ready_sync[0],config_ready};fault_meta<=config_fault;fault_sync<=fault_meta;
            bad_sync<={bad_sync[0],bad_toggle};drop_sync<={drop_sync[0],drop_toggle};
            bad_prev<=bad_sync[1];drop_prev<=drop_sync[1];
            if(bad_prev!=bad_sync[1]&&errors!=255)errors<=errors+1'b1;
            if(drop_prev!=drop_sync[1]&&drops!=255)drops<=drops+1'b1;
            if(present_pulse)begin silent_frames<=0;frames<=frames+1'b1;end
            else if(frame_latch&&silent_frames<STALE_FRAMES)silent_frames<=silent_frames+1'b1;
            x1<=hcount;y1<=vcount;
            if(hcount==799)begin hcount<=0;vcount<=vcount==524?10'd0:vcount+1'b1;end
            else hcount<=hcount+1'b1;
            {red,green,blue}<=color;
            de<=x1<640&&y1<480;
            hsync<=!(x1>=656&&x1<752);vsync<=!(y1>=490&&y1<492);
        end
    end
endmodule
