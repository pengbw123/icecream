`timescale 1ns/1ps
// Production top: real command decoder, AI, merge, owners, 32-voice FM and I2S.
// Only tempo's clocks/us parameter is accelerated; I2S stays 1024 clocks/sample.
module tb_polyphony_audio;
    reg clk=0;always #10 clk=~clk;
    reg key_s2=1,ui_command_valid=0,external_midi_event_valid=0;
    reg [7:0] ui_command=0;reg [63:0] ui_payload=0;
    reg [31:0] external_midi_event_data=0;
    wire ui_command_ready,external_midi_event_ready;
    wire [31:0] ai_status;wire [15:0] readback_data;wire readback_valid;
    wire signed [15:0] pcm;wire tick;
    wire score_active=test_active;wire test_active,test_valid,test_ready;wire [31:0] test_data,mask;wire [7:0] voices;reg press=0;
    polyphony_test32 generator(clk,!key_s2,press,1'b1,test_active,test_valid,test_data,test_ready);
    top #(.FM_VOICE_COUNT(32),.EXTERNAL_SCORE_ENABLED(1),.POLY_TEST_ENABLED(1),.FX2_ENABLED(1),.OUTPUT_SELECT_ENABLED(1)) dut(.poly_test_active(test_active),.poly_test_valid(test_valid),.poly_test_data(test_data),.poly_test_ready(test_ready),.clk(clk),.key_s2(key_s2),
        .arp_config(160'd0),.arp_suspend(1'b0),.sequence_active(1'b0),.arp_status(),.arp_notes(),.ai_status(ai_status),
        .headphone_select(1'b0),.headphone_din(),.uart_rx_pin(1'b1),
        .ui_command_valid(ui_command_valid),.ui_command(ui_command),.ui_payload(ui_payload),.ui_command_ready(ui_command_ready),
        .fx_write(1'b0),.fx_index(4'd0),.fx_value(32'd0),.fx_read_index(4'd0),.fx_read_value(),
        .uart_tx_pin(),.usb_host_dp(),.usb_host_dn(),.i2s_bclk(),.i2s_lrclk(),.i2s_din(),
        .lcd_resetn(),.lcd_clk(),.lcd_cs(),.lcd_dc(),.lcd_data(),
        .external_midi_event_data(external_midi_event_data),.external_midi_event_valid(external_midi_event_valid),
        .external_midi_event_ready(external_midi_event_ready),
        .monitor_sample(pcm),.monitor_sample_tick(tick),.monitor_midi_event_data(),.monitor_midi_event_valid(),
        .monitor_voice_count(voices),.monitor_voice_mask(mask),.monitor_preset(),.monitor_algorithm(),.monitor_operator_envelopes(),
        .readback_data(readback_data),.readback_valid(readback_valid),
        .perf_snapshot(1'b0),.perf_clear(1'b0),.perf_index(5'd0),.perf_bridge_drop(1'b0),.perf_data(),.external_score_active(score_active));

 integer fd,n,peak=0;
 initial begin
  repeat(8)@(negedge clk);key_s2=0;wait(dut.audio_reset_n);wait(dut.u_fm_uart_control.preset_load_state==0);repeat(30)@(negedge clk);
  // Configure the production core as one sine carrier, rapid release, no scaling.
  for(integer op=0;op<6;op=op+1)begin
   dut.u_fm_poly_synth.patch_op_enable[op]=(op==0);
   dut.u_fm_poly_synth.patch_op_frequency[op]=32'h10000;
   dut.u_fm_poly_synth.patch_op_fixed[op]=0;
   dut.u_fm_poly_synth.patch_op_detune[op]=7;
   dut.u_fm_poly_synth.patch_op_gain[op]=70;
   dut.u_fm_poly_synth.patch_algorithm_flags[op]=4;
   dut.u_fm_poly_synth.patch_rate_scaling[op]=0;
   dut.u_fm_poly_synth.patch_velocity_sensitivity[op]=0;
   dut.u_fm_poly_synth.patch_left_depth[op]=0;dut.u_fm_poly_synth.patch_right_depth[op]=0;
  end
  for(integer eg=0;eg<24;eg=eg+1)begin dut.u_fm_poly_synth.patch_eg_qrate[eg]=63;dut.u_fm_poly_synth.patch_eg_level[eg]=(eg%4==3)?0:4032;end
  repeat(30)@(negedge clk);press=1;@(negedge clk);press=0;
  wait(generator.state==2);repeat(10000)@(negedge clk);
  if(voices!=32||mask!==32'hffffffff)$fatal(1,"not 32 real voices: %d %h",voices,mask);
  repeat(512)begin @(posedge tick);@(negedge tick);end
  fd=$fopen("tmp/polyphony_pcm.txt","w");
  for(n=0;n<4096;n=n+1)begin @(posedge tick);#1;$fdisplay(fd,"%d",$signed(pcm));if($signed(pcm)>peak)peak=$signed(pcm);@(negedge tick);end
  $fclose(fd);if(peak<2)$fatal(1,"test voices have no audible output peak=%d",peak);
  @(negedge clk);press=1;@(negedge clk);press=0;wait(!test_active);wait(voices==0);
  if(dut.u_performance.deadlines!=0||dut.u_performance.lost_ticks!=0||dut.u_performance.steals!=0)$fatal(1,"audio deadline, sample loss or stealing in test32");
  if(mask!==0)$fatal(1,"mask did not clear after release");
  $display("PASS production test32: real 32-slot mask, 32 voices, 4096 PCM samples, matched stop releases to zero");$finish;
 end
 initial begin #1000000000;$fatal(1,"poly audio timeout voices=%d",voices);end
endmodule
