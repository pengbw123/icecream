`timescale 1ns/1ps
module tb_gesture_gray_adapt;
reg clk=0;always #10 clk=~clk;
reg reset_n=0,wr=0,start_in=0;reg [9:0] idx;reg [7:0] val;
wire fw,done;wire [9:0] fi;wire [7:0] fv;
gesture_gray_adapt dut(clk,reset_n,wr,idx,val,start_in,fw,fi,fv,done);
reg [7:0] raw[0:565247],expected[0:565247];integer n,k,received=0;
always @(negedge clk)if(fw)begin
 if(fi!==received||fv!==expected[n*1024+received])$fatal(1,"adapt frame%0d pixel%0d got%0d expected%0d",n,received,fv,expected[n*1024+received]);
 received=received+1;
end
initial begin
 $readmemh("src/generated/gesture_gray/raw_test_features.mem",raw);
 $readmemh("src/generated/gesture_gray/test_features.mem",expected);
 repeat(4)@(negedge clk);reset_n=1;
 for(n=0;n<552;n=n+1)begin
  received=0;
  for(k=0;k<1024;k=k+1)begin @(negedge clk);wr=1;idx=k;val=raw[n*1024+k];end
  @(negedge clk);wr=0;start_in=1;@(negedge clk);start_in=0;
  wait(done);@(negedge clk);if(received!=1024)$fatal(1,"Missing normalized samples");
 end
 $display("PASS gray adapt: 552 frames / 565248 values exact Python parity; corners, global black, gain floor, clamp, ordered replay");$finish;
end
initial begin #200000000;$fatal(1,"adapt timeout");end
endmodule
