`timescale 1ns/1ps
// Behavioral clocks/output cells only; production SCCB/capture/banks/raster/TMDS.
module video_pll #(parameter PIXEL_DIV=40,ENABLE_SERIAL=1)(input clkin,
    output reg pixel_clk=0,output reg serial_clk=0,output reg lock=0);
    always #20 pixel_clk=~pixel_clk;always #4 serial_clk=~serial_clk;
    initial #200 lock=1;
endmodule
module ODDR(output reg Q0,output Q1,input D0,D1,TX,CLK);
    always @(posedge CLK)Q0<=D0;always @(negedge CLK)Q0<=D1;assign Q1=TX;
endmodule
module tb_camera_pipeline;
    reg clk=0,pclk=0;always #10 clk=~clk;always #13 pclk=~pclk;
    reg reset_n=0,href=0,vsync=0;reg [7:0] data=0;
    tri1 scl,sda;wire stretch,ready,stale,cam_reset_n,oe,lock,cx,pwdn;
    wire [2:0] fault,dp,dn;wire cp,cn;
    assign scl=stretch?1'b0:1'bz;
    camera_hdmi_tx dut(.clk(clk),.reset_n(reset_n),.camera_pclk(pclk),.camera_href(href),.camera_vsync(vsync),
        .camera_data(data),.camera_scl(scl),.camera_sda(sda),.camera_xclk(cx),.camera_reset_n(cam_reset_n),.camera_pwdn(pwdn),
        .hdmi_clk_p(cp),.hdmi_clk_n(cn),.hdmi_data_p(dp),.hdmi_data_n(dn),.hdmi_oe(oe),.pll_locked(lock),
        .config_ready(ready),.stream_stale(stale),.config_fault(fault));
    defparam dut.u_config.QUARTER_CLOCKS=4;
    defparam dut.u_config.RESET_CLOCKS=20;
    defparam dut.u_config.BOOT_CLOCKS=50;
    defparam dut.u_config.SOFT_RESET_CLOCKS=30;
    defparam dut.u_config.RETRY_CLOCKS=100;
    defparam dut.u_video.STALE_FRAMES=2;
    ov5640_sccb_model model(.scl(scl),.sensor_reset_n(cam_reset_n),.present(1'b1),.wrong_id(1'b0),
        .corrupt_readback(1'b0),.nack_first(1'b0),.stretch_first(1'b0),.sda(sda),.stretch_low(stretch));
    function [15:0] source_pixel(input integer tag,x,y);
        source_pixel={tag[2:0],2'b0,x[7:5],3'b0,y[6:5],3'b0};
    endfunction
    task sync_frame;
        begin @(negedge pclk);href=0;vsync=1;repeat(8)@(negedge pclk);vsync=0;repeat(8)@(negedge pclk);end
    endtask
    task image(input integer tag,malformed);
        integer x,y,bytes;reg [15:0] rgb;
        begin
            for(y=0;y<240;y=y+1)begin
                @(negedge pclk);href=1;
                for(x=0;x<320;x=x+1)begin
                    rgb=source_pixel(tag,x,y);data=rgb[15:8];@(negedge pclk);
                    if(!(malformed&&y==100&&x==319))begin data=rgb[7:0];@(negedge pclk);end
                end
                href=0;repeat(12)@(negedge pclk);
            end
            sync_frame;
        end
    endtask
    integer good=0,bad=0,presentations=0,drops=0,checked=0,hs=0,vs=0,active=0,full_frames=0;
    integer px,py,tag=0,sx,sy;reg [7:0] sample;reg [23:0] expected;
    reg checking=0;reg [2:0] display_tag;
    always @(posedge pclk)if(dut.cam_reset_sync[2])begin
        if(dut.frame_good)good=good+1;if(dut.frame_bad)bad=bad+1;
        if(dut.u_buffer.write_allowed&&dut.u_buffer.valid&&dut.u_buffer.write_bank==dut.u_buffer.read_bank)
            $fatal(1,"Producer overwrote the displayed bank");
    end
    always @(posedge dut.pixel_clk)begin
        px=dut.u_video.x1;py=dut.u_video.y1;
        if(dut.present_pulse)begin
            presentations=presentations+1;
            display_tag=dut.u_buffer.read_bank?dut.u_buffer.bank1[0][7:5]:dut.u_buffer.bank0[0][7:5];
        end
        #1;
        if(oe&&(^({dut.de,dut.hsync,dut.vsync,dut.red,dut.green,dut.blue})===1'bx))$fatal(1,"Unknown HDMI output");
        if(pwdn!==1'b0)$fatal(1,"PWDN must be explicitly driven low");
        if(ready&&!stale&&dut.de&&py>=8&&py<352)begin
            sx=px/2;sy=py/2;sample={display_tag,sx[7:5],sy[6:5]};
            expected={{sample[7:5],sample[7:5],sample[7:6]},
                {sample[4:2],sample[4:2],sample[4:3]},{4{sample[1:0]}}};
            if({dut.red,dut.green,dut.blue}!==expected)$fatal(1,"Pixel mismatch at %d,%d got%h expected%h tag%d",px,py,{dut.red,dut.green,dut.blue},expected,display_tag);
            checked=checked+1;
        end
        if(checking)begin
            if(dut.de)active=active+1;if(!dut.hsync)hs=hs+1;if(!dut.vsync)vs=vs+1;
        end
    end
    integer i;reg [7:0] saved0;
    initial begin
        repeat(5)@(negedge clk);reset_n=1;wait(ready);repeat(20)@(negedge pclk);sync_frame;
        for(i=0;i<8;i=i+1)image(i,0);
        image(7,1); // odd byte count must never become a published frame
        for(i=0;i<8;i=i+1)image(i,0);
        repeat(20)@(negedge pclk);
        if(good<2||bad!=1||presentations<1||dut.u_video.drops==0)$fatal(1,"Missing capture/drop validation g%d b%d p%d d%d",good,bad,presentations,dut.u_video.drops);
        wait(dut.u_video.hcount==0&&dut.u_video.vcount==0);@(negedge dut.pixel_clk);checking=1;
        repeat(800*525)@(negedge dut.pixel_clk);checking=0;
        if(active!=640*480||hs!=96*525||vs!=2*800||checked<10000)$fatal(1,"Raster/coverage %d %d %d %d",active,hs,vs,checked);
        wait(stale);repeat(10)@(negedge dut.pixel_clk);
        force dut.u_video_pll.lock=0;#1;
        if(oe||cam_reset_n)$fatal(1,"PLL loss did not immediately disable capture/output");
        repeat(20)@(negedge clk);release dut.u_video_pll.lock;dut.u_video_pll.lock=1;
        wait(ready);if(dut.u_buffer.valid)$fatal(1,"PLL recovery exposed stale memory");
        sync_frame;for(i=0;i<7;i=i+1)image(i,0);wait(!stale);
        if(fault||checked<10000)$fatal(1,"Recovery failed");
        $display("PASS production camera pipeline: SCCB->320x240 RGB565->160x120 RGB332 dual banks->640x480 HDMI, %d checked pixels, %d presentations, bad frame rejected, faster producer whole-frame drops, no tearing, stale detection and PLL recovery",checked,presentations);$finish;
    end
    initial begin #250000000;$fatal(1,"Camera pipeline timeout ready%b good%d bad%d presentations%d",ready,good,bad,presentations);end
endmodule
