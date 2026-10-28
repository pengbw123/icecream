`timescale 1ns/1ps
module tb_gesture_video;
    reg clk=0,pixel_clk=0;always #10 clk=~clk;always #20 pixel_clk=~pixel_clk;
    reg reset_n=0;
    reg [63:0] source_data=64'h12348001_0000046d;
    wire [63:0] video_data;
    wire frame_latch,stale;wire [7:0] r,g,b;wire de,hs,vs;
    gesture_video_snapshot snapshot(clk,pixel_clk,reset_n,frame_latch,source_data,video_data);
    camera_hdmi_video #(.GESTURE_ENABLED(1)) video(.pixel_clk(pixel_clk),.reset_n(reset_n),
        .config_ready(1'b1),.config_fault(3'd0),.buffer_valid(1'b1),.present_pulse(1'b1),.pixel_data(8'd0),
        .bad_toggle(1'b0),.drop_toggle(1'b0),.camera_pclk(clk),.camera_href(1'b0),.camera_vsync(1'b0),
        .chip_id(16'h5640),.debug_request(1'b0),.debug_packet(72'd0),.capture_status(8'd0),
        .gesture_status(video_data[31:0]),.gesture_detail(video_data[63:32]),
        .frame_latch(frame_latch),.red(r),.green(g),.blue(b),.de(de),.hsync(hs),.vsync(vs),.stream_stale(stale));
    integer hits=0;reg [9:0] x,y;
    reg check=0;
    always @(posedge pixel_clk)begin x<=video.x1;y<=video.y1;end
    always @(negedge pixel_clk)if(check&&de)begin
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
        source_data=64'h56788001_0000086d;
        wait(frame_latch);@(negedge pixel_clk);check=0;
        if(hits!=1532)$fatal(1,"ROI border pixel count %0d",hits);
        wait(video_data==source_data);
        // Verify exact character positions with the reused production font ROM.
        wait(video.vcount==448&&video.hcount==0);#1;
        if(video.u_diagnostics.character!=="N")$fatal(1,"gesture label alignment");
        wait(video.hcount==3*16);#1;if(video.u_diagnostics.character!=="V")$fatal(1,"stable V name");
        source_data=0;wait(frame_latch);wait(video_data==0);
        wait(video.vcount==352&&video.hcount==20);#1;
        if(!video.u_diagnostics.area)$fatal(1,"disabled recognition did not restore full diagnostics");
        $display("PASS gesture_video: atomic frame snapshot, ROI alignment, compact/reused font diagnostics, OFF restoration");$finish;
    end
    initial begin #100000000;$fatal(1,"timeout");end
endmodule
