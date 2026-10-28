`timescale 1ns/1ps
module tb_gesture_score_gate;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,enable=1,iv=0;reg signed [31:0] a=0,b=0,c=0;
    reg [1:0] cls=0;reg [14:0] energy=4000;
    wire valid,accepted;wire [15:0] margin;wire [1:0] rc;wire [14:0] re;
    gesture_score_gate dut(clk,reset_n,enable,iv,a,b,c,cls,energy,valid,accepted,margin,rc,re);
    integer checked=0;reg [15:0] margins[0:255];reg decisions[0:255];
    reg [1:0] classes[0:255];reg [14:0] energies[0:255];integer sent=0;
    longint signed top,second,delta;
    task send(input signed [31:0] x,y,z,input [1:0] cl,input [14:0] en);
        begin
            @(negedge clk);iv=1;a=x;b=y;c=z;cls=cl;energy=en;
            top=x;second=y;if(y>x)begin top=y;second=x;end
            if(z>top)begin second=top;top=z;end else if(z>second)second=z;
            delta=top-second;margins[sent]=delta>65535?65535:delta;
            decisions[sent]=delta>=2048&&en>=768&&en<=30000&&cl<3;
            classes[sent]=cl;energies[sent]=en;sent=sent+1;
        end
    endtask
    always @(posedge clk)if(valid)begin
        if(margin!==margins[checked]||accepted!==decisions[checked]||rc!==classes[checked]||re!==energies[checked])
            $fatal(1,"ranking pipeline mismatch %0d margin %0d expected %0d",checked,margin,margins[checked]);
        checked=checked+1;
    end
    initial begin
        repeat(3)@(negedge clk);reset_n=1;
        send(32'sh7fffffff,32'sh80000000,32'sh80000000,0,4000);
        send(32'sh80000000,32'sh7fffffff,32'sh7fffffff,1,4000);
        send(-100,-3000,-4000,0,768);send(-100,-2147,-4000,0,30000);
        send(0,2048,0,1,767);send(0,2048,0,1,30001);send(0,2048,0,3,4000);
        for(integer i=0;i<120;i=i+1)send($random,$random,$random,i%3,4000);
        @(negedge clk);iv=0;repeat(7)@(negedge clk);
        if(checked!=sent)$fatal(1,"dropped pipeline vectors");
        iv=1;@(negedge clk);enable=0;iv=0;repeat(6)@(negedge clk);
        if(valid)$fatal(1,"disable leaked old result");
        $display("PASS gesture_score_gate: %0d back-to-back vectors, signed extremes/ties, threshold/area/class bounds, disable",checked);$finish;
    end
endmodule
