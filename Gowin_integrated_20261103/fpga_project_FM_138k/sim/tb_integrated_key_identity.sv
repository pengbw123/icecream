`timescale 1ns/1ps
module tb_integrated_key_identity;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,event_valid=0;reg [31:0] event_data=0;wire event_ready;
 fm_poly_synth #(.VOICE_COUNT(32)) dut(
        .clk(clk),
        .reset_n(reset_n),
        .expression_enable('0),
        .expression_brightness('0),
        .sample_tick('0),
        .midi_event_data(event_data),
        .midi_event_valid(event_valid),
        .midi_event_brightness('0),
        .fm_algorithm('0),
        .fm_feedback('0),
        .fm_osc_sync('0),
        .fm_transpose(7'd64),
        .fm_lfo_waveform('0),
        .fm_lfo_speed('0),
        .fm_lfo_delay('0),
        .fm_lfo_sync('0),
        .fm_lfo_pitch_depth('0),
        .fm_lfo_amp_depth('0),
        .fm_pitch_mod_sensitivity('0),
        .fm_operator_write_valid('0),
        .fm_operator_index('0),
        .fm_operator_enable('0),
        .fm_operator_fixed('0),
        .fm_operator_detune('0),
        .fm_operator_frequency('0),
        .fm_operator_output_gain('0),
        .fm_envelope_write_valid('0),
        .fm_envelope_operator('0),
        .fm_envelope_stage('0),
        .fm_envelope_coefficient('0),
        .fm_envelope_level('0),
        .fm_rate_scaling('0),
        .fm_velocity_sensitivity('0),
        .fm_amp_mod_sensitivity('0),
        .fm_scaling_write_valid('0),
        .fm_scaling_operator('0),
        .fm_scaling_breakpoint('0),
        .fm_scaling_left_depth('0),
        .fm_scaling_right_depth('0),
        .fm_scaling_left_curve('0),
        .fm_scaling_right_curve('0),
        .fm_pitch_envelope_write_valid('0),
        .fm_pitch_envelope_stage('0),
        .fm_pitch_envelope_coefficient('0),
        .fm_pitch_envelope_ratio('0),
        .fm_algorithm_flags_write_valid('0),
        .fm_algorithm_flags('0),
        .fm_note_gain_write_valid('0),
        .fm_note_gain_address('0),
        .fm_note_gain_value('0),
        .fm_patch_commit('0),
        .aux_write_valid('0),
        .aux_write_address('0),
        .aux_write_value('0),
        .patch_read_address('0),
        .pitch_bend('0),
        .vibrato_depth('0),
        .vibrato_rate('0),
        .portamento_time('0),
        .midi_event_ready(event_ready)
 );
 task tick;@(posedge clk);#1;endtask
 task send(input [31:0] packet);
  begin @(negedge clk);event_data=packet;event_valid=1;
   while(!event_ready)tick();tick();@(negedge clk);event_valid=0;
   repeat(800)tick();
  end
 endtask
 function automatic integer held(input integer id,input integer pitch,input integer part);
  held=0;for(integer i=0;i<32;i=i+1)
   if(dut.voice_active[i]&&dut.voice_gate[i]&&dut.voice_key_id[i]==id&&dut.voice_note[i]==pitch&&dut.voice_part[i]==part)held++;
 endfunction
 function automatic [31:0] mapped(input integer id,input integer pitch,input bit on);
  mapped={{2'b0,1'b1,1'b0,4'(id)},7'(on?7'h48:7'h40),1'(id>>4),8'(pitch),8'(on?100:0)};
 endfunction
 initial begin
  repeat(4)tick();reset_n=1;repeat(5000)tick();
  send(mapped(0,67,1));send(mapped(20,67,1));send(32'h00904364);
  if(held(32,67,0)!=1||held(52,67,0)!=1||held(0,67,0)!=1)$fatal(1,"three equal pitches did not allocate independently");
  send(32'h00804300);
  if(held(0,67,0)||held(32,67,0)!=1||held(52,67,0)!=1)$fatal(1,"untagged release killed mapped key");
  send(mapped(0,67,0));if(held(32,67,0)||held(52,67,0)!=1)$fatal(1,"mapped unison release leaked");
  send(mapped(20,67,0));if(held(52,67,0))$fatal(1,"second unison did not release");
  send(32'h10b07800);send(32'h00b07800);
  // Full production capacity, followed by a released tail and a new mapped press.
  for(integer i=0;i<25;i=i+1)send(mapped(i,48+i,1));
  for(integer i=0;i<7;i=i+1)send(32'h00900064|((80+i)<<8));
  begin integer count;count=0;for(integer i=0;i<32;i=i+1)count+=dut.voice_active[i];
   if(count!=32)$fatal(1,"32-voice allocation lost capacity: %0d",count);
  end
  send(mapped(3,51,0));send(mapped(3,100,1));
  for(integer i=0;i<25;i=i+1)if(held(32+i,i==3?100:48+i,0)!=1)$fatal(1,"released-tail reuse stole held mapped key %0d",i);
  send(32'h40903064);send(32'h88b07800);
  if(held(0,48,1)!=1)$fatal(1,"LIVE panic affected BACKING");
  $display("INTEGRATED_KEY_IDENTITY_OK production32 FM: same pitch/three owners, independent releases, full32 slots, released-tail reuse, scoped panic");$finish;
 end
 initial begin #10000000;$fatal(1,"identity timeout");end
endmodule
