`timescale 1ns/1ps
module tb_gesture_gray_cnn;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,wr=0,start=0;reg [9:0] index=0;reg [7:0] value=0;
 wire busy,done;wire [1:0] cls;wire signed [31:0] s0,s1,s2,s3;wire [15:0] cycles;
 gesture_gray_cnn dut(clk,reset_n,wr,index,value,start,busy,done,cls,s0,s1,s2,s3,cycles);
 reg [7:0] features[0:565247],labels[0:551];reg [31:0] scores[0:2207];
 integer i,j,correct=0,expected,latency=0;
 initial begin
  $readmemh("src/generated/gesture_gray/test_features.mem",features);
  $readmemh("src/generated/gesture_gray/test_scores.mem",scores);
  $readmemh("src/generated/gesture_gray/test_labels.mem",labels);
  repeat(4)@(negedge clk);reset_n=1;
  for(i=0;i<552;i=i+1)begin
   for(j=0;j<1024;j=j+1)begin @(negedge clk);wr=1;index=j;value=features[i*1024+j];end
   @(negedge clk);wr=0;start=1;@(negedge clk);start=0;
   repeat(4)@(negedge clk);wr=1;index=0;value=0;start=1;
   @(negedge clk);wr=0;start=0;
   wait(done);@(negedge clk);
   if(s0!==scores[i*4]||s1!==scores[i*4+1]||s2!==scores[i*4+2]||s3!==scores[i*4+3])
    $fatal(1,"CNN scores image%0d got%0d/%0d/%0d/%0d expected%0d/%0d/%0d/%0d",i,s0,s1,s2,s3,$signed(scores[i*4]),$signed(scores[i*4+1]),$signed(scores[i*4+2]),$signed(scores[i*4+3]));
   expected=0;for(j=1;j<4;j=j+1)if($signed(scores[i*4+j])>$signed(scores[i*4+expected]))expected=j;
   if(cls!==expected||busy)$fatal(1,"CNN argmax/busy");
   if(i==0)latency=cycles;else if(cycles!=latency)$fatal(1,"CNN latency changed");
   if(cls==labels[i])correct=correct+1;
  end
  start=1;@(negedge clk);start=0;repeat(50)@(negedge clk);reset_n=0;@(negedge clk);reset_n=1;
  repeat(20000)@(negedge clk);if(done||busy)$fatal(1,"CNN reset");
  $display("PASS gray CNN: 552 images, 2208 scores bit exact, %0d correct, fixed %0d cycles, busy writes ignored and mid-job reset",correct,latency);$finish;
 end
 initial begin #600000000;$fatal(1,"timeout");end
endmodule
