`timescale 1ns/1ps
module tb_midi_input_trace;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,usb_accept=0,audio_accept=0,snapshot=0,clear_stats=0;
 reg [31:0] usb_data=0,midi_data=0;reg [4:0] index=0;wire [31:0] data;
 audio_performance_monitor #(.MIDI_TRACE_ENABLED(1)) dut(
 .clk(clk),.reset_n(reset_n),.sample_tick(1'b0),.engine_busy(1'b0),.sample_pending(1'b0),
 .render_start(1'b0),.render_done(1'b0),.voice_steal(1'b0),.midi_accept(audio_accept),.midi_stall(1'b0),.bridge_drop(1'b0),
 .usb_accept(usb_accept),.usb_data(usb_data),.midi_data(midi_data),.active_voices(8'd0),.audio_sample(16'sd0),
 .snapshot(snapshot),.clear_stats(clear_stats),.read_index(index),.read_data(data));
 task step;begin @(posedge clk);#1;@(negedge clk);end endtask
 task snap;begin snapshot=1;step();snapshot=0;end endtask
 task check(input [4:0] a,input [31:0] v);begin index=a;#1;if(data!==v)$fatal(1,"trace[%d]=%h expected %h",a,data,v);end endtask
 initial begin
  repeat(4)step();reset_n=1;step();
  usb_data=32'h09903c7f;usb_accept=1;step();usb_accept=0;
  midi_data=32'h00903c7f;audio_accept=1;step();step();audio_accept=0;snap();
  check(24,1);check(12,2);check(25,32'h09903c7f);check(26,0);check(27,32'h00903c7f);check(28,32'h00903c7f);
  usb_data=32'h19913d50;usb_accept=1;step();usb_accept=0;
  check(24,1);check(25,32'h09903c7f); // Held snapshot is immutable.
  snap();check(24,2);check(25,32'h19913d50);check(26,32'h09903c7f);
  clear_stats=1;step();clear_stats=0;snap();check(24,0);check(12,0);check(25,0);check(26,0);check(27,0);check(28,0);
  $display("PASS MIDI trace: USB vs audio counts, complete cable/channel payloads, last/previous, coherent snapshots and clear");$finish;
 end
endmodule
