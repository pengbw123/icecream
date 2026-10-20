`timescale 1ns/1ps
module tb_visual_auto_gain;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,tick=0,enabled=1;
    reg signed [15:0] sample=0;
    wire [3:0] shift;
    visual_auto_gain dut(.clk(clk),.reset_n(reset_n),.sample_tick(tick),
        .enabled(enabled),.sample(sample),.gain_shift(shift));
    task feed(input integer amplitude,input integer count);
        integer n;
        begin for(n=0;n<count;n=n+1)begin
            @(negedge clk);tick=1;sample=(n&1)?amplitude:-amplitude;
            @(posedge clk);#1;
        end end
    endtask
    initial begin
        repeat(4)@(negedge clk);reset_n=1;
        feed(100,20000); // compressed wall time; 0.41 s of audio ticks
        if(shift<6||shift>8)$fatal(1,"Quiet tone not enlarged: shift=%d",shift);
        if((100<<shift)<6400)$fatal(1,"Insufficient quiet-tone display height");
        feed(20000,1);
        if(shift!=0)$fatal(1,"Loud attack did not reduce gain immediately");
        feed(32768,1);
        if(dut.peak!=32768||shift!=0)$fatal(1,"Signed -32768 peak handling failed");
        feed(100,20000);enabled=0;#1;
        if(shift!=0)$fatal(1,"Manual unity display gain not respected");
        enabled=1;feed(0,30000);
        if(dut.peak!=0||shift!=8)$fatal(1,"Silence follower did not converge safely");
        @(negedge clk);tick=0;sample=32767;
        repeat(4)@(posedge clk);#1;
        if(dut.peak!=0)$fatal(1,"Follower advanced without an audio tick");
        $display("PASS visual AGC: quiet/loud/negative FS/silence/bypass/sample tick");$finish;
    end
endmodule
