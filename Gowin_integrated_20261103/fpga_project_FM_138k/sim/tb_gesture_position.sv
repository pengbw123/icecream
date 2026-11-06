`timescale 1ns/1ps
module tb_gesture_position;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,enable=1,cancel=0,sample_valid=0,ready=1;reg [255:0] mask=0;
 wire valid;wire [3:0] action;integer n=0;reg [3:0] last;
 gesture_position dut(.*);
 always @(posedge clk)if(valid&&ready)begin n=n+1;last=action;end
 task sample(input integer x,y);
 begin mask=0;mask[y*16+x]=1;@(negedge clk);sample_valid=1;
 @(negedge clk);sample_valid=0;repeat(265)@(negedge clk);end endtask
 initial begin
 repeat(4)@(negedge clk);reset_n=1;
 sample(3,7);if(n!=1||last!=8)$fatal(1,"left");
 sample(6,7);if(n!=1)$fatal(1,"left hysteresis");
 sample(8,7);if(n!=2||last!=9)$fatal(1,"center");
 sample(12,7);if(n!=3||last!=10)$fatal(1,"right");
 sample(9,7);if(n!=3)$fatal(1,"right hysteresis");
 sample(9,3);if(n!=4||last!=11)$fatal(1,"up");
 sample(9,12);if(n!=5||last!=13)$fatal(1,"down");
 ready=0;sample(2,12);if(!valid||action!=8)$fatal(1,"pending");
 cancel=1;@(negedge clk);cancel=0;if(valid)$fatal(1,"cancel");
 enable=0;@(negedge clk);enable=1;ready=1;sample(15,15);
 if(last!=13)$fatal(1,"last pixel centroid");
 $display("PASS gesture_position: centroid axes, hysteresis, pending cancel, reset and last corner");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
