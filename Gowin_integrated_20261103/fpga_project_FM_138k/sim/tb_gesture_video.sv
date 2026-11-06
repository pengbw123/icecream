`timescale 1ns/1ps
module tb_gesture_video;
    reg clk=0,pixel_clk=0;always #10 clk=~clk;always #20 pixel_clk=~pixel_clk;
    reg reset_n=0;
    function [255:0] pattern;
        for(integer k=0;k<256;k=k+1)pattern[k]=((k*13+(k/16)*7)%17)<6;
    endfunction
    reg [323:0] source_data;
    reg [255:0] reference_mask;
    initial reference_mask=pattern();
    initial source_data={4'd0,pattern(),64'h12348001_0000046d};
    wire [323:0] video_data;
    wire frame_latch,stale;wire [7:0] r,g,b;wire de,hs,vs;
    gesture_video_snapshot #(.WIDTH(324)) snapshot(clk,pixel_clk,reset_n,frame_latch,source_data,video_data);
    camera_hdmi_video #(.GESTURE_ENABLED(1)) video(.pixel_clk(pixel_clk),.reset_n(reset_n),
        .config_ready(1'b1),.config_fault(3'd0),.buffer_valid(1'b1),.present_pulse(1'b1),.pixel_data(8'd0),
        .bad_toggle(1'b0),.drop_toggle(1'b0),.camera_pclk(clk),.camera_href(1'b0),.camera_vsync(1'b0),
        .chip_id(16'h5640),.debug_request(1'b0),.debug_packet(72'd0),.capture_status(8'd0),
        .gesture_status(video_data[31:0]),.gesture_detail(video_data[63:32]),
        .gesture_mask(video_data[319:64]),.gesture_reason(video_data[323:320]),
        .frame_latch(frame_latch),.red(r),.green(g),.blue(b),.de(de),.hsync(hs),.vsync(vs),.stream_stale(stale));
    integer hits=0;reg [9:0] x,y;
    reg check=0;
    always @(posedge pixel_clk)begin x<=video.x1;y<=video.y1;end
    always @(negedge pixel_clk)if(check&&de)begin
        if(x>0&&x<127&&y>32&&y<159)begin
            if({r,g,b}!==(reference_mask[((y-32)/8)*16+x/8]?24'hffffff:24'h080808))
                $fatal(1,"mask ordering/tearing at %0d,%0d",x,y);
        end
        if(((x==128||x==511)&&y>=48&&y<=431)||((y==48||y==431)&&x>=128&&x<=511))begin
            if({r,g,b}!==24'h36a8cc)$fatal(1,"ROI border alignment %0d,%0d %h",x,y,{r,g,b});hits=hits+1;
        end
        if(video.y1==400&&video.x1<640&&video.u_diagnostics.area)$fatal(1,"legacy diagnostics obscures hand ROI");
        if(video.y1==450&&video.x1<640&&!video.u_diagnostics.area)$fatal(1,"missing compact diagnostics");
    end
    initial begin
        repeat(5)@(negedge clk);reset_n=1;
        wait(video_data==source_data);wait(video.vcount==0&&video.hcount==0);check=1;
        // The snapshot is stable for the active frame even if source changes.
        source_data={4'd4,~pattern(),64'h56788001_00000a6d};
        wait(frame_latch);@(negedge pixel_clk);check=0;
        if(hits!=1532)$fatal(1,"ROI border pixel count %0d",hits);
        wait(video_data==source_data);
        // Verify exact character positions with the reused production font ROM.
        wait(video.vcount==448&&video.hcount==0);#1;
        if(video.u_diagnostics.character!=="N")$fatal(1,"gesture label alignment");
        wait(video.hcount==3*16);#1;if(video.u_diagnostics.character!=="V")$fatal(1,"stable V name");
        wait(video.hcount==32*16);#1;if(video.u_diagnostics.character!=="N")$fatal(1,"NOISE reason label");
        source_data=0;wait(frame_latch);wait(video_data==0);
        wait(video.vcount==352&&video.hcount==20);#1;
        if(!video.u_diagnostics.area)$fatal(1,"disabled recognition did not restore full diagnostics");
        $display("PASS gesture_video: coherent 324-bit mask/status snapshot, all displayed input pixels and ordering, no active-frame tearing, ROI alignment, reason text, OFF restoration");$finish;
    end
    initial begin #250000000;$fatal(1,"timeout");end
endmodule
