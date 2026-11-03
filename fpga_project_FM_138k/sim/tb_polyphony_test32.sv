`timescale 1ns/1ps
module tb_polyphony_test32;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,press=0,allowed=0,ready=0;
 wire active,valid;wire [31:0] data;
 polyphony_test32 dut(clk,reset_n,press,allowed,active,valid,data,ready);
 integer ons=0,offs=0,clean=0,cycle=0;reg stalled=0;reg [31:0] held;
 always @(posedge clk)if(reset_n)begin
  if(stalled&&(!valid||data!==held))$fatal(1,"stalled event changed");
  stalled<=valid&&!ready;held<=data;
  if(valid&&ready)begin
   if(data[23:16]==8'h90)begin
    if(data[15:8]!==96+ons||data[7:0]!=32)$fatal(1,"note on order");ons=ons+1;
   end else if(data[23:16]==8'h80)begin
    if(data[15:8]!==96+offs)$fatal(1,"note off order");offs=offs+1;
   end else if(data==32'h88b07b00)begin
    if(ons!=offs)$fatal(1,"unmatched release");clean=clean+1;
   end else $fatal(1,"unexpected event");
  end
 end
 always @(negedge clk)begin cycle=cycle+1;ready=(cycle%7)<3;end
 task push;begin @(negedge clk);press=1;@(negedge clk);press=0;end endtask
 initial begin
  repeat(4)@(negedge clk);reset_n=1;push();repeat(8)@(negedge clk);if(active)$fatal(1,"ignored allowed");
  allowed=1;push();wait(dut.state==2);repeat(10)@(negedge clk);
  if(ons!=32||offs!=0)$fatal(1,"hold counts");push();wait(!active);repeat(2)@(negedge clk);
  if(offs!=32||clean!=1)$fatal(1,"full release");
  ons=0;offs=0;push();wait(ons==5);push();wait(!active);repeat(2)@(negedge clk);
  if(ons!=offs||ons>=32||clean!=2)$fatal(1,"early stop");
  $display("PASS test32: enable guard, held events under backpressure, 32 notes, full stop and early stop cleanup");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
