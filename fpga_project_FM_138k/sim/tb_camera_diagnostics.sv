`timescale 1ns/1ps
module tb_camera_diagnostics;
    wire [31:0] gesture_status=32'd0,gesture_detail=32'd0;
    reg pixel_clk=0,camera_pclk=0,clock_on=1;
    realtime half_period=13;
    always #20 pixel_clk=~pixel_clk;always begin #(half_period);if(clock_on)camera_pclk=~camera_pclk;end
    reg reset_n=0,camera_href=0,camera_vsync=0,config_ready=0,debug_request=0,frame_latch=0;
    reg [2:0] config_fault=0;reg [15:0] chip_id=16'h5640;
    reg [71:0] debug_packet=0;
    reg [9:0] prefetch_x=0,prefetch_y=352,x=0,y=352;
    wire debug_ack,area,ink;
    wire [7:0] frame_count=8'h12,error_count=8'h34,drop_count=8'h56;
    wire [7:0] capture_status=8'hd0;
    camera_diagnostics dut(.*);
    task cycles(input integer n);begin repeat(n)@(negedge pixel_clk);end endtask
    task latch;begin cycles(2);frame_latch=1;cycles(1);frame_latch=0;cycles(1);end endtask
    task char_check(input integer col,row,input [6:0] expected);
        begin prefetch_x=col*16;prefetch_y=352+row*32;#1;
            if(dut.character!==expected)$fatal(1,"Diagnostic glyph at %d/%d got%c expected%c",row,col,dut.character,expected);
        end
    endtask
    reg [71:0] saved;
    initial begin
        cycles(5);reset_n=1;config_ready=1;cycles(10);
        debug_packet={8'h05,16'h0281,16'h027f,16'h00f0,16'h4b00};saved=debug_packet;
        debug_request=1;wait(debug_ack);cycles(3);latch;
        if(dut.display_packet!==saved||dut.display_id!==16'h5640)$fatal(1,"Debug snapshot not coherent");
        char_check(0,0,"I");char_check(3,0,"5");char_check(4,0,"6");char_check(5,0,"4");char_check(6,0,"0");
        char_check(18,0,"1");char_check(2,2,"0");char_check(4,2,"F");char_check(5,2,"0");
        char_check(10,2,"2");char_check(11,2,"7");char_check(12,2,"F");char_check(17,2,"1");
        char_check(2,3,"4");char_check(3,3,"B");char_check(10,3,"5");
        char_check(19,3,"1");char_check(20,3,"2");char_check(24,3,"5");char_check(25,3,"6");char_check(29,3,"3");char_check(30,3,"4");
        camera_href=1;cycles(5);camera_href=0;camera_vsync=1;cycles(5);camera_vsync=0;cycles(5);
        if(dut.href_count!=1||dut.vsync_count!=1)$fatal(1,"Raw sync edges missing");
        cycles(51000);latch;
        if(dut.display_clock<38450||dut.display_clock>38475)$fatal(1,"PCLK measurement %d",dut.display_clock);
        half_period=6.25;cycles(51000);latch;
        if(dut.display_clock<79995||dut.display_clock>80005)$fatal(1,"80MHz PCLK overflowed %d",dut.display_clock);
        char_check(2,1,"1");char_check(3,1,"3");char_check(4,1,"8");char_check(14,3,"D");
        clock_on=0;cycles(51000);latch;if(dut.display_clock!=0)$fatal(1,"Stopped PCLK not detected");
        config_ready=0;debug_request=0;debug_packet=0;config_fault=4;cycles(10);latch;
        if(dut.display_packet!==saved||dut.display_fault!=4||dut.display_ready)$fatal(1,"Recovery erased the last failing frame");
        char_check(10,0,"4");char_check(18,0,"0");
        config_ready=1;clock_on=1;cycles(10);debug_packet={8'h00,16'd640,16'd640,16'd240,16'd19200};debug_request=1;
        wait(debug_ack);cycles(3);latch;
        if(dut.display_packet!==debug_packet)$fatal(1,"Next attempt snapshot missing");
        $display("PASS camera diagnostics: coherent held frame packet, accurate independent PCLK rate/stop detection, raw H/V activity, retained failure evidence and readable ID/fault/geometry hex glyphs");$finish;
    end
    initial begin #10000000;$fatal(1,"Diagnostic timeout");end
endmodule
