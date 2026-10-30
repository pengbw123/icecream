`timescale 1ns/1ps
module tb_gesture_gray_preview;
 reg clk=0,pixel_clk=0;always #10 clk=~clk;always #20 pixel_clk=~pixel_clk;
 reg reset_n=0,sw=0,rv=0,fl=0;reg [9:0] si=0;reg [7:0] sv=0,ra=0;
 wire [7:0] rd;wire valid;
 gesture_gray_preview dut(clk,pixel_clk,reset_n,sw,si,sv,rv,fl,ra,rd,valid);
 task frame(input integer offset,input integer count);
  begin
   for(integer k=0;k<count;k=k+1)begin @(negedge clk);sw=1;si=k;sv=(k*37+offset)&255;end
   @(negedge clk);sw=0;rv=1;@(negedge clk);rv=0;
  end
 endtask
 task latch;
  begin repeat(5)@(negedge pixel_clk);fl=1;@(negedge pixel_clk);fl=0;repeat(5)@(negedge clk);end
 endtask
 task check(input integer offset);
  integer k;
  begin
   if(!valid)$fatal(1,"preview not valid");
   for(integer p=0;p<256;p=p+1)begin
    @(negedge pixel_clk);ra=p;@(negedge pixel_clk);
    k=((p/16)*2+1)*32+(p%16)*2+1;
    if(rd!==((k*37+offset)&255))$fatal(1,"RAM preview bank/order p=%0d got=%0d",p,rd);
   end
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);reset_n=1;
  frame(7,1024);if(valid)$fatal(1,"switched outside blank");
  frame(29,1024); // awaiting display: skip, do not corrupt published bank
  latch;check(7);
  frame(41,1024);check(7); // active display remains previous complete bank
  latch;check(41);
  frame(88,100);latch;check(41); // partial input must not publish
  frame(99,1024);latch;check(99);
  @(negedge clk);reset_n=0;repeat(5)@(negedge clk);reset_n=1;
  if(valid)$fatal(1,"reset retained valid");
  frame(129,1024);latch;check(129);
  $display("PASS RAM gray preview: 1280 exact pixels, double-bank CDC, no tearing, skipped/partial frames and reset recovery");$finish;
 end
 initial begin #1000000;$fatal(1,"preview timeout");end
endmodule
