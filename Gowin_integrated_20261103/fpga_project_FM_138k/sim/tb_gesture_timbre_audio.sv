`timescale 1ns/1ps
// Real ROM loader, shared FM32 pipeline, expression, FX and I2S. Camera
// inference is exercised separately; this bench injects accepted coordinates.
module tb_gesture_timbre_audio;
 reg clk=0;always #10 clk=~clk;
 reg key=1,control=0,mv=0,cv=0;reg [31:0] packet=0,md=0;
 reg [7:0] command=0;reg [63:0] payload=0;wire cr,mr,tick;
 wire [31:0] status;wire [6:0] preset;wire [7:0] voices;wire signed [15:0] pcm;
 top #(.GESTURE_ENABLED(1),.FX2_ENABLED(1),.FM_VOICE_COUNT(32)) dut(
  .clk(clk),.key_s2(key),.gesture_control(control),.gesture_timbre_mode(1'b1),
  .gesture_position_packet(packet),.gesture_surface_status(status),.gesture_valid(1'b0),.gesture_action(4'd0),
  .arp_config(160'd0),.arp_suspend(1'b0),.sequence_active(1'b0),
  .headphone_select(1'b0),.uart_rx_pin(1'b1),.external_score_active(1'b0),
  .ui_command_valid(cv),.ui_command(command),.ui_payload(payload),.ui_command_ready(cr),
  .fx_write(1'b0),.fx_index(4'd0),.fx_value(32'd0),.fx_read_index(4'd0),
  .external_midi_event_data(md),.external_midi_event_valid(mv),.external_midi_event_ready(mr),
  .monitor_sample(pcm),.monitor_sample_tick(tick),.monitor_voice_count(voices),.monitor_preset(preset),
  .perf_snapshot(1'b0),.perf_clear(1'b0),.perf_index(5'd0),.perf_bridge_drop(1'b0),
  .poly_test_active(1'b0),.poly_test_valid(1'b0),.poly_test_data(32'd0),.trace_usb_accept(1'b0),.trace_usb_data(32'd0));
 task coords(input integer c,x,y);
  begin @(negedge clk);packet={~packet[31],13'd0,c[1:0],1'b1,y[6:0],1'b0,x[6:0]};end
 endtask
 task midi(input [31:0] data);
  begin @(negedge clk);md=data;mv=1;do @(posedge clk);while(!mr);@(negedge clk);mv=0;end
 endtask
 task frames(input integer n);begin repeat(n)begin @(posedge tick);@(negedge tick);end end endtask
 task capture(input integer profile,bright);
  integer fd,peak,absval;string path;
  begin coords(profile,bright,0);frames(2200);
   path=$sformatf("tmp/timbre_pcm_%0d_%0d.txt",profile,bright);fd=$fopen(path,"w");peak=0;
   repeat(2048)begin @(posedge tick);#1;absval=$signed(pcm)<0?-$signed(pcm):$signed(pcm);
    if(absval>peak)peak=absval;$fdisplay(fd,"%d",$signed(pcm));@(negedge tick);end
   $fclose(fd);if(peak<5||peak>=32767)$fatal(1,"silent/clipped profile=%d bright=%d peak=%d",profile,bright,peak);
   $display("Captured profile=%d bright=%d preset=%d peak=%d",profile,bright,preset,peak);
  end
 endtask
 task choose(input integer c,p);
  begin coords(c,64,0);wait(preset==p&&!dut.preset_busy&&!status[18]);frames(5);
   if(preset!=p)$fatal(1,"loader mismatch");
   // Keep factory sustain, but accelerate only its release for test duration.
   for(integer i=0;i<6;i++)begin dut.u_fm_poly_synth.patch_eg_qrate[i*4+3]=63;dut.u_fm_poly_synth.patch_eg_level[i*4+3]=0;end
  end
 endtask
 integer saved;
 integer idle_debug=0;
 always @(posedge clk)if(control&&dut.g_timbre.control.wanted_valid&&!dut.fm_live_busy&&idle_debug<5)begin
  idle_debug=idle_debug+1;
  $display("IDLE CHECK wanted=%d loadready=%b sel=%b synth=%b perf=%b psv=%b voices=%d",dut.g_timbre.control.desired,dut.g_timbre.control.loader_ready,dut.selected_midi_valid,dut.synth_midi_event_valid,dut.perform_valid,dut.preset_select_valid,voices);$fflush();
 end
 initial begin
  repeat(8)@(negedge clk);key=0;wait(dut.audio_reset_n);wait(!dut.preset_busy);control=1;
  $display("Timbre audio: boot ready");$fflush();
  // Raise master volume through the real MIDI controller, not force sample data.
  midi(32'h00b00740);
  $display("Timbre audio: volume event accepted");$fflush();
  choose(1,44);midi(32'h00903c64);wait(voices==1);
  capture(1,0);capture(1,127);
  // Requested new patch must not destroy held LIVE notes.
  coords(0,64,0);frames(20);if(preset!=44||voices!=1||!status[17])$fatal(1,"held note changed patch");
  midi(32'h00803c00);choose(0,0);midi(32'h00903c64);wait(voices==1);
  capture(0,0);capture(0,127);midi(32'h00803c00);
  choose(2,85);midi(32'h00903c64);wait(voices==1);capture(2,0);capture(2,127);
  coords(2,127,127);frames(2200);if(dut.timbre_vibrato!=63)$fatal(1,"vibrato depth not applied");
  if(dut.u_fm_poly_synth.back_lfo_phase_increment===32'd0)$fatal(1,"BACKING control corrupted");
  control=0;frames(2);if(dut.timbre_expression)$fatal(1,"control disable did not restore");
  midi(32'h00803c00);wait(voices==0);
  if(dut.u_performance.deadlines||dut.u_performance.lost_ticks)$fatal(1,"missed audio deadline");
  $display("PASS gesture timbre production: three actual ROM presets, live-note wait, six PCM captures, expression and clean disable, no missed samples");$finish;
 end
 initial begin #2000000000;$fatal(1,"production timbre timeout preset=%d state=%d voices=%d",preset,dut.g_timbre.control.state,voices);end
 initial begin #10000000;$display("Timbre 10ms: preset=%d load=%b ctrlstate=%d livebusy=%b ready=%b selected=%b synth=%b perform=%b status=%h packet=%h engine=%d pending=%b",preset,dut.preset_busy,dut.g_timbre.control.state,dut.fm_live_busy,cr,dut.selected_midi_valid,dut.synth_midi_event_valid,dut.perform_valid,status,packet,dut.u_fm_poly_synth.engine_state,dut.u_fm_poly_synth.event_pending);$fflush();end
endmodule
