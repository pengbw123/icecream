`timescale 1ns/1ps
module tb_camera_recovery;
    reg pixel_clk=0,pclk=0,cam_clock_on=1;
    always #20 pixel_clk=~pixel_clk;
    always #13 if(cam_clock_on)pclk=~pclk;
    reg reset_n=0,config_ready=0,bad_toggle=0,drop_toggle=0,buffer_reset_n=0;
    wire stale;wire [7:0] red,green,blue;
    camera_hdmi_video video(.pixel_clk(pixel_clk),.reset_n(reset_n),.config_ready(config_ready),
        .config_fault(3'd0),.buffer_valid(1'b0),.present_pulse(1'b0),.pixel_data(8'hxx),
        .bad_toggle(bad_toggle),.drop_toggle(drop_toggle),.stream_stale(stale),
        .red(red),.green(green),.blue(blue));
    camera_framebuffer #(.PIXELS(8)) fb(.pclk(pclk),.pixel_clk(pixel_clk),.reset_n(buffer_reset_n),
        .frame_start(1'b0),.frame_good(1'b0),.pixel_write(1'b0),.pixel_address(15'd0),
        .pixel_data(8'd0),.frame_latch(1'b1),.read_address(15'd0));
    task wait_pixels;begin repeat(10)@(negedge pixel_clk);end endtask
    initial begin
        wait_pixels;reset_n=1;config_ready=1;buffer_reset_n=1;wait_pixels;
        bad_toggle=1;drop_toggle=1;wait_pixels;
        if(video.errors!=1||video.drops!=1)$fatal(1,"Event not counted");
        // Sensor reset returns both toggles to zero alongside ready. It must
        // not be mistaken for a second event by the independently running HDMI.
        config_ready=0;bad_toggle=0;drop_toggle=0;buffer_reset_n=0;
        cam_clock_on=0;wait_pixels;
        if(video.errors!=1||video.drops!=1)$fatal(1,"Reconfiguration falsely counted reset edge");
        if(fb.request_toggle||fb.ack_toggle||fb.valid||fb.cam_reset_sync||fb.video_reset_sync)
            $fatal(1,"Buffer not reset with PCLK stopped");
        buffer_reset_n=1;config_ready=1;wait_pixels;
        if(fb.valid||fb.cam_reset_sync)$fatal(1,"Stopped PCLK released capture reset");
        cam_clock_on=1;wait_pixels;
        if(!fb.cam_reset_n||fb.valid)$fatal(1,"PCLK restart did not safely release reset");
        bad_toggle=1;drop_toggle=1;wait_pixels;
        if(video.errors!=2||video.drops!=2)$fatal(1,"Events lost after recovery");
        $display("PASS independent HDMI/capture recovery: no false diagnostic events on sensor reconfiguration, async reset with stopped PCLK, synchronous release and no stale buffer exposure");$finish;
    end
endmodule
