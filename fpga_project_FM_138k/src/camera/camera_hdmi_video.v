// 640x480/59.52 Hz at the existing 25 MHz HDMI clock. Registered RGB/sync
// align with the synchronous framebuffer read; nearest-neighbour 4x preview.
module camera_hdmi_video #(parameter integer STALE_FRAMES=60,GESTURE_ENABLED=0,GRAY_PREVIEW=0)(
    input wire pixel_clk,reset_n,config_ready,input wire [2:0] config_fault,
    input wire buffer_valid,present_pulse,input wire [7:0] pixel_data,
    input wire bad_toggle,drop_toggle,
    input wire camera_pclk,camera_href,camera_vsync,
    input wire [15:0] chip_id,input wire debug_request,
    input wire [71:0] debug_packet,output wire debug_ack,input wire [7:0] capture_status,
    output wire frame_latch,output wire [14:0] read_address,
    output reg [7:0] red,green,blue,output reg de,hsync,vsync,
    output wire stream_stale,
    input wire [31:0] gesture_status,gesture_detail,
    input wire [255:0] gesture_mask,input wire [3:0] gesture_reason,input wire [2047:0] gesture_gray
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
    wire diagnostic_area,diagnostic_ink;
    camera_diagnostics #(.GESTURE_ENABLED(GESTURE_ENABLED),.GRAY_PREVIEW(GRAY_PREVIEW)) u_diagnostics(.pixel_clk(pixel_clk),.reset_n(reset_n),
        .gesture_status(gesture_status),.gesture_detail(gesture_detail),
        .gesture_reason(gesture_reason),
        .camera_pclk(camera_pclk),.camera_href(camera_href),.camera_vsync(camera_vsync),
        .config_ready(config_ready),.config_fault(config_fault),.chip_id(chip_id),
        .frame_count(frames),.error_count(errors),.drop_count(drops),
        .debug_request(debug_request),.debug_packet(debug_packet),.debug_ack(debug_ack),.capture_status(capture_status),
        .frame_latch(frame_latch),.prefetch_x(hcount),.prefetch_y(vcount),.x(x1),.y(y1),
        .area(diagnostic_area),.ink(diagnostic_ink));
    wire [7:0] r332={pixel_data[7:5],pixel_data[7:5],pixel_data[7:6]};
    wire [7:0] g332={pixel_data[4:2],pixel_data[4:2],pixel_data[4:3]};
    wire [7:0] b332={4{pixel_data[1:0]}};
    reg [23:0] color;reg [2:0] bit_sel;
    wire [9:0] mask_y=y1-10'd32;
    wire [7:0] gray_pixel=gesture_gray[{mask_index,3'b000}+:8];
    wire [7:0] mask_index={mask_y[6:3],x1[6:3]};
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
        if(GESTURE_ENABLED&&gesture_status[0]&&
           (((x1==128||x1==511)&&y1>=48&&y1<=431)||((y1==48||y1==431)&&x1>=128&&x1<=511)))
            color=gesture_status[6]?24'h36a8cc:24'h9caab8;
        // Exact MLP input: sixteen rows, sixteen columns, 8x nearest-neighbor.
        // The panel fits entirely to the left of the central camera ROI.
        if(GESTURE_ENABLED&&gesture_status[0]&&x1<128&&y1>=32&&y1<160)begin
            color=!gesture_status[5]?24'h303844:GRAY_PREVIEW?{gray_pixel,gray_pixel,gray_pixel}:gesture_mask[mask_index]?24'hffffff:24'h080808;
            if(x1==0||x1==127||y1==32||y1==159)color=24'h738395;
        end
        if(diagnostic_area)color=diagnostic_ink?24'he0f0ff:24'h081018;
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
            // Capture toggles return to zero during automatic reconfiguration.
            // That reset edge is not an additional malformed/dropped frame.
            if(ready_sync[1])begin
                if(bad_prev!=bad_sync[1]&&errors!=255)errors<=errors+1'b1;
                if(drop_prev!=drop_sync[1]&&drops!=255)drops<=drops+1'b1;
            end
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
