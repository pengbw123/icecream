`timescale 1ns/1ps
module tb_strip_index_range #(parameter integer LEDS=160);
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,frame_valid=0;wire ready,done;
 score_strip_guide #(.LED_COUNT(LEDS),.BIT_CYCLES(4),.T0H_CYCLES(1),.T1H_CYCLES(2),.RESET_CYCLES(4)) dut(
  .clk(clk),.reset_n(reset_n),.cfg_valid(1'b0),.cfg_ready(),.cfg_index(16'd0),.cfg_kind(2'd0),.cfg_note(7'd0),.cfg_error(),
  .frame_valid(frame_valid),.frame_ready(ready),.current_notes(128'd0),.preview_notes(128'd0),.beat_active(1'b0),
  .scan_enable(1'b1),.scan_index(16'(LEDS-1)),.busy(),.frame_done(done),.unmapped_notes(),.led_data());
 integer n;
 initial begin
  repeat(5)@(negedge clk);reset_n=1;wait(ready);
  @(negedge clk);frame_valid=1;@(negedge clk);frame_valid=0;
  wait(dut.state==2);#1;
  for(n=0;n<LEDS;n=n+1)if(dut.pixels[n*24+:24]!==((n==LEDS-1)?24'h080808:24'd0))$fatal(1,"Strip index range/color error LED=%d",n);
  wait(done);
  $display("PASS bounded strip index: %0d LEDs, final scan pixel, complete serialized frame",LEDS);$finish;
 end
 initial begin #1000000;$fatal(1,"Strip timeout");end
endmodule
