`timescale 1ns/1ps
module tb_gesture_gray_gate;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,enable=1,trigger=0;reg signed [31:0] a,b,c,d;reg [1:0] cl;
 wire rv,accepted,tr,av,busy;wire [1:0] cls,stable;wire [14:0] en;wire [15:0] margin;
 wire [3:0] act,reason;wire [255:0] mask;wire [2047:0] preview;
 gesture_gray_pipeline dut(clk,clk,reset_n,enable,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0,1'b0,15'd0,16'd0,
  rv,accepted,cls,en,margin,tr,stable,av,act,busy,mask,preview,reason);
 reg signed [31:0] vals[0:3];reg signed [63:0] gap;integer best,second;
 task check(input integer n0,n1,n2,n3);
  begin
   vals[0]=n0;vals[1]=n1;vals[2]=n2;vals[3]=n3;best=0;
   for(integer k=1;k<4;k=k+1)if(vals[k]>vals[best])best=k;
   second=best==0?1:0;for(integer k=0;k<4;k=k+1)if(k!=best&&vals[k]>vals[second])second=k;
   gap=$signed(vals[best]);gap=gap-$signed(vals[second]);
   @(negedge clk);a=n0;b=n1;c=n2;d=n3;cl=best;trigger=1;
   @(negedge clk);trigger=0;wait(rv);@(negedge clk);
   if(cls!==best||accepted!==(best<3&&gap>=2048)||margin!==(gap>65535?16'hffff:gap[15:0]))$fatal(1,"4-class signed gate");
   if(reason!==(best==3?4'd5:4'd0))$fatal(1,"OTHER gate reason");
   @(negedge clk);
  end
 endtask
 initial begin
  force dut.cnn.score0=a;force dut.cnn.score1=b;force dut.cnn.score2=c;force dut.cnn.score3=d;
  force dut.cnn.class_id=cl;force dut.cnn.done=trigger;
  repeat(4)@(negedge clk);reset_n=1;
  check(2047,0,-1,-2);check(2048,0,-1,-2);check(-1,-1,-1,-1);
  check(-2147483648,2147483647,0,-1);check(1,0,-1,2147483647);
  check(-2147483648,-2147483647,-2147483646,-2147483645);
  for(integer k=0;k<100;k=k+1)check($random,$random,$random,$random);
  enable=0;repeat(5)@(negedge clk);if(rv||accepted)$fatal(1,"disabled gate");
  $display("PASS gray gate: 106 four-class signed vectors, margin boundary/ties/extremes, saturation, OTHER rejection and disable");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
