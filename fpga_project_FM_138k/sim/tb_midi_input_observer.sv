`timescale 1ns/1ps
module tb_midi_input_observer;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0;reg [2:0] accepted=0;
 reg [31:0] a=32'h09903c7f,b=32'h00904050,c=32'h80904364;
 wire [31:0] data;wire valid;wire [1:0] source;
 midi_input_observer dut(clk,reset_n,a,b,c,accepted[0],accepted[1],accepted[2],data,valid,source);
 integer n;
 initial begin
  repeat(3)@(negedge clk);reset_n=1;
  for(n=0;n<30;n=n+1)begin
   accepted=1<<(n%3);#1;if(valid)$fatal(1,"Observed before acceptance edge");
   @(posedge clk);#1;
   if(!valid||source!=n%3||data!==(n%3==0?a:n%3==1?b:c))$fatal(1,"Wrong accepted event/source");
   @(negedge clk);accepted=0;
   @(posedge clk);#1;if(valid)$fatal(1,"Duplicated observer event");
   @(negedge clk);
  end
  accepted=1;@(posedge clk);#1;reset_n=0;#1;
  if(valid||data!=0)$fatal(1,"Reset did not clear observation");
  $display("PASS MIDI observer: all sources, acceptance edge, idle suppression, reset");$finish;
 end
endmodule
