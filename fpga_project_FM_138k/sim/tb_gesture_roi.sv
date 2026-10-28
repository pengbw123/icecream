`timescale 1ns/1ps
module tb_gesture_roi;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,enable=1,fs=0,fg=0,fb=0,pw=0,busy=0;
    reg [14:0] addr=0;reg [7:0] data=0;
    wire wr,start;wire [7:0] idx;wire [6:0] val;wire [14:0] energy;
    gesture_roi dut(clk,reset_n,enable,fs,fg,fb,pw,addr,data,busy,wr,idx,val,start,energy);
    integer received=0,starts=0,i,r,g,b,v,sum=0;
    reg check=0;
    always @(negedge clk)begin
        if(wr&&check)begin
            // Stimulus RGB332 equals sample's linear address low byte.
            i=(15+(received/16)*6)*160+35+(received%16)*6;
            r=((i&255)>>5)*18;g=(((i&255)>>2)&7)*18;b=(i&3)*42;
            v=127-((r+2*g+b)>>2);
            v=v>=12?127:0;
            if(idx!==received||val!==v)$fatal(1,"ROI sample %0d idx %0d val %0d expected %0d",received,idx,val,v);
            sum=sum+v;received=received+1;
        end
        if(start)begin starts=starts+1;if(energy!==sum)$fatal(1,"energy");end
    end
    task boundary(input good,input bad);
        begin @(posedge clk);#1;fs=1;fg=good;fb=bad;
            @(posedge clk);#1;fs=0;fg=0;fb=0;end
    endtask
    task pixels(input skip);
        integer p;
        begin
            for(p=0;p<19200;p=p+1)begin
                @(posedge clk);#1;pw=!(skip&&p==2435);addr=p;data=p;
            end
            @(posedge clk);#1;pw=0;repeat(3)@(posedge clk);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);reset_n=1;
        boundary(0,0);check=1;pixels(0);check=0;
        if(received!=256)$fatal(1,"missing samples %0d",received);
        boundary(1,0);repeat(3)@(negedge clk);if(starts!=1)$fatal(1,"good frame not published");
        // A busy frame, a missing ROI pixel and frame_bad must each be discarded.
        busy=1;boundary(0,0);pixels(0);busy=0;boundary(1,0);
        pixels(1);boundary(1,0);
        pixels(0);boundary(1,1);
        repeat(3)@(negedge clk);if(starts!=1)$fatal(1,"invalid frame published");
        enable=0;boundary(1,0);repeat(3)@(negedge clk);
        if(wr||start)$fatal(1,"disabled output");
        $display("PASS gesture_roi: RGB332/coordinates/energy, valid/bad/missing/busy frames");$finish;
    end
    initial begin #5000000;$fatal(1,"timeout");end
endmodule
