`timescale 1ns/1ps
module tb_gray_selftest;
 reg clk=0; always #10 clk=~clk;
 reg reset_n=0,wr=0,start=0,control=0; reg [9:0] idx=0; reg [7:0] val=0;
 reg [7:0] features[0:565247]; reg [31:0] scores[0:2207];
 wire rv,accepted,tracking,av,busy,sw;wire [1:0] cls,stable;wire [14:0] energy;wire [15:0] margin;wire [3:0] action,reason;wire [255:0] mask;wire [2047:0] preview;wire [9:0] si;wire [7:0] sv;
 gesture_gray_pipeline #(.SELF_TEST(1)) dut(clk,clk,reset_n,1'b1,control,1'b0,1'b1,1'b0,1'b0,1'b0,1'b0,15'd0,16'd0,rv,accepted,cls,energy,margin,tracking,stable,av,action,busy,mask,preview,reason,sw,si,sv);
 initial begin
  $readmemh("src/generated/gesture_gray/test_features.mem",features);$readmemh("src/generated/gesture_gray/test_scores.mem",scores);
  force dut.nw=wr;force dut.ni=idx;force dut.nv=val;force dut.ns=start;
  repeat(5)@(negedge clk);reset_n=1;
  for(integer i=0;i<1024;i=i+1)begin @(negedge clk);wr=1;idx=i;val=i;end
  @(negedge clk);wr=0;start=1;@(negedge clk);start=0;
  wait(rv);@(negedge clk);
  if(dut.s0!==32'd24944||$signed(dut.s1)!==-32'sd41371||$signed(dut.s2)!==-32'sd14405||dut.s3!==32'd40219) $fatal(1,"wrong self-test scores %d %d %d %d",dut.s0,dut.s1,dut.s2,dut.s3);
  if(cls!==3||margin!==15275||accepted||av||preview!=={256{8'hff}})$fatal(1,"wrong self-test decision");
  control=1;
  for(integer i=0;i<1024;i=i+1)begin @(negedge clk);wr=1;idx=i;val=features[i];end
  @(negedge clk);wr=0;start=1;@(negedge clk);start=0;
  wait(rv);@(negedge clk);
  if(dut.s0!==scores[0]||dut.s1!==scores[1]||dut.s2!==scores[2]||dut.s3!==scores[3]||accepted||av)$fatal(1,"camera mode or action inhibition");
  $display("PASS CNN selftest: white exact scores, OTHER gap 3BAB, white preview, camera-mode exact scores, actions disabled");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
