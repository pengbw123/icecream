`timescale 1ns/1ps
module tb_gesture_chopper;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,enable=0,bypass=0;
 reg signed [15:0] sample_in=10000;
 wire signed [15:0] sample_out;
 gesture_chopper #(.HALF_PERIOD(256)) dut(.clk(clk),.reset_n(reset_n),.sample_tick(1'b1),
  .enable(enable),.bypass(bypass),.sample_in(sample_in),.sample_out(sample_out),.gate_open());
 integer reference1,reference2;
 always @(posedge clk)begin
  if(!reset_n)begin reference1<=0;reference2<=0;end
  else begin reference1<=($signed(sample_in)*$signed({1'b0,dut.gain}))>>>7;reference2<=reference1;end
 end
 integer i,expected,zeros=0,full=0;integer signed last;
 initial begin
  repeat(4)@(negedge clk);reset_n=1;
  repeat(4)@(negedge clk);if(sample_out!=10000)$fatal(1,"Normal is not unity gain");
  enable=1;last=10000;
  for(i=0;i<1600;i=i+1)begin
   @(negedge clk);expected=reference2;
   if($signed(sample_out)!=expected)$fatal(1,"Gain wrap/sign error");
   if(sample_out==0)zeros=zeros+1;if(sample_out==10000)full=full+1;
   if(sample_out-last>79||last-sample_out>79)$fatal(1,"Unsmoothed gate edge");last=sample_out;
  end
  if(zeros<200||full<200)$fatal(1,"Missing audible gate plateaus");
  sample_in=-32768;repeat(700)begin @(negedge clk);expected=reference2;
   if($signed(sample_out)!=expected)$fatal(1,"Negative sample overflow");end
  enable=0;repeat(140)@(negedge clk);if(sample_out!==sample_in)$fatal(1,"Control-off did not restore unity");
  enable=1;repeat(400)@(negedge clk);bypass=1;#1;
  if(sample_out!==sample_in)$fatal(1,"32-voice test bypass not transparent");
  $display("PASS gesture chopper: unity, smooth edges, open/closed plateaus, signed full scale, disable recovery, test bypass");$finish;
 end
endmodule
