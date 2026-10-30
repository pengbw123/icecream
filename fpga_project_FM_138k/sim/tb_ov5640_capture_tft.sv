`timescale 1ns/1ps
module tb_ov5640_capture_tft;
 wire [15:0] pixel_rgb565;
    reg pclk=0;always #5.9 pclk=~pclk;
    reg reset_n=0,href=0,vsync=0;reg [7:0] data=0;
    wire pixel_write,frame_start,frame_good,frame_bad,frame_toggle,bad_toggle;
    wire [14:0] pixel_address;wire [7:0] pixel_data,capture_status;
    wire debug_request;wire debug_ack=debug_request;wire [71:0] debug_packet;
    ov5640_capture #(.WIDTH(800),.HEIGHT(480),.WARMUP_FRAMES(10),
        .CROP_X(80),.CROP_WIDTH(640),.SAMPLE_X(4),.SAMPLE_Y(4)) dut(.*);
    integer n=0,good=0,bad=0,total=0,current_tag=0,ex,ey;
    reg [15:0] expected;
    function [15:0] source_pixel(input integer tag,x,y);
        source_pixel=x*17+y*31+tag*123;
    endfunction
    always @(posedge pclk)begin
        if(frame_good)good=good+1;
        if(frame_bad)bad=bad+1;
        if(pixel_write)begin
            // Independent geometric oracle: exactly x80,84,..716 and y0,4,..476.
            ex=80+(n%160)*4;ey=(n/160)*4;
            expected=source_pixel(current_tag,ex,ey);
            if(pixel_rgb565!==expected)$fatal(1,"Full precision RGB565 tap mismatch");
            if(n>=19200||pixel_address!==n||pixel_data!=={expected[15:13],expected[10:8],expected[4:3]})
                $fatal(1,"TFT crop/order/byte mismatch index%0d address%0d got%h source(%0d,%0d)",n,pixel_address,pixel_data,ex,ey);
            n=n+1;total=total+1;
        end
    end
    task boundary;
        begin @(negedge pclk);href=0;vsync=1;repeat(6)@(negedge pclk);
            vsync=0;repeat(6)@(negedge pclk);end
    endtask
    task image(input integer tag,malformed);
        integer x,y;reg [15:0] rgb;
        begin
            current_tag=tag;n=0;
            for(y=0;y<480;y=y+1)begin
                @(negedge pclk);href=1;
                for(x=0;x<800;x=x+1)begin
                    rgb=source_pixel(tag,x,y);data=rgb[15:8];@(negedge pclk);
                    if(!(malformed&&y==100&&x==799))begin data=rgb[7:0];@(negedge pclk);end
                end
                href=0;repeat(12)@(negedge pclk);
            end
            boundary;
            if(n!=19200)$fatal(1,"TFT output dimensions %0d",n);
        end
    endtask
    initial begin
        repeat(5)@(negedge pclk);reset_n=1;boundary;
        for(integer i=0;i<10;i=i+1)begin image(i,0);if(good||bad)$fatal(1,"Ten-frame warmup bypassed");end
        image(10,0);
        if(good!=1||bad)$fatal(1,"TFT valid frame not released");
        if(debug_packet!=={8'd0,16'd1600,16'd1600,16'd480,16'd19200})$fatal(1,"TFT full-source geometry packet %h",debug_packet);
        image(11,1);image(12,0);
        if(good!=1||bad!=1)$fatal(1,"TFT malformed row accepted or warmup not restarted");
        $display("PASS TFT capture: 800x480 at 84.75MHz, central 640x480 crop, 4x4 decimation, %0d exact samples, ten-frame warmup, full-source geometry, odd-row rejection and warmup restart",total);$finish;
    end
    initial begin #150000000;$fatal(1,"TFT capture timeout");end
endmodule
