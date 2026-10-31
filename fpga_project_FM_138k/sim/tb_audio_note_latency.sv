`timescale 1ns/1ps
module tb_audio_note_latency;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,enable=1,ev=0,ready=0,snap=0,clear=0;
 reg [31:0] data=32'h00903c64;reg [7:0] voices=0;
 reg signed [15:0] sample=0;reg [4:0] index=18;
 wire load,done;wire [31:0] rd;wire bc,lr,sd,tick;
 i2s_tx #(.BCLK_HALF_DIV(1)) tx(.clk(clk),.reset_n(reset_n),.headphone_select(1'b0),.headphone_din(),
 .sample_left(sample),.sample_right(sample),.sample_tick(tick),.i2s_bclk(bc),.i2s_lrclk(lr),.i2s_din(sd),.frame_load(load),.left_word_done(done));
 audio_note_latency #(.QUIET_FRAMES(2),.TIMEOUT_CLOCKS(2000)) dut(clk,reset_n,enable,ev,ready,data,voices,load,done,sample,snap,clear,index,rd,);
 integer clocks=0,start_time,expected,checks=0;reg watch=0,latched=0;
 always @(posedge clk)begin
  clocks=clocks+1;
  if(watch&&load&&sample>32)latched=1;
  if(watch&&done&&latched)begin expected=clocks-start_time;watch=0;end
 end
 task read_check(input [4:0] addr,input [31:0] value);
 begin @(negedge clk);snap=1;@(negedge clk);snap=0;index=addr;#1;if(rd!==value)$fatal(1,"index%0d got%0d expected%0d",addr,rd,value);checks=checks+1;end
 endtask
 task quiet_wait;
 begin sample=0;voices=0;wait(dut.quiet==2);@(negedge clk);end
 endtask
 task trigger;
 begin ev=1;ready=0;@(posedge clk);#1;start_time=clocks;@(negedge clk);end
 endtask
 initial begin
  repeat(5)@(negedge clk);reset_n=1;quiet_wait;
  trigger;watch=1;latched=0;repeat(4)@(negedge clk);ready=1;@(negedge clk);ev=0;
  repeat(12)@(negedge clk);sample=400;voices=1;wait(!watch);@(negedge clk);
  read_check(18,expected);read_check(20,1);read_check(22,0);
  // No quiet interval: do not attribute a new event to the existing sound.
  trigger;ready=1;@(negedge clk);ev=0;read_check(22,1);
  quiet_wait;trigger;ready=1;@(negedge clk);ev=0;
  repeat(2010)@(negedge clk);read_check(21,1);read_check(20,1);
  quiet_wait;trigger;ready=1;@(negedge clk);ev=0;
  repeat(3)@(negedge clk);ev=1;@(negedge clk);ev=0;
  if(dut.pending)$fatal(1,"overlapping note was attributed");read_check(22,2);
  quiet_wait;trigger;ev=0;clear=1;@(negedge clk);clear=0;sample=400;
  repeat(300)@(negedge clk);read_check(18,0);read_check(20,0);read_check(21,0);
  $display("PASS note latency: real I2S last-bit endpoint, exact clocks, stalled event dedup, nonquiet reject, timeout, overlap cancellation, clear and coherent snapshots (%0d checks)",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"latency timeout");end
endmodule
