`timescale 1ns/1ps
module tb_gesture_expression_scope;
 reg clk=0;always #10 clk=~clk;reg reset_n=0,expression=0;
 reg [6:0] bright=0;reg [25:0] env=0;reg [7:0] flags=1;
 fm_poly_synth #(.VOICE_COUNT(32),.EXPRESSION_ENABLED(1)) dut(
  .clk(clk),.reset_n(reset_n),.sample_tick(1'b0),.midi_event_valid(1'b0),.midi_event_data(32'd0),.midi_event_brightness(7'd0),
  .expression_enable(expression),.expression_brightness(bright),
  .fm_operator_write_valid(1'b0),.fm_envelope_write_valid(1'b0),
  .fm_scaling_write_valid(1'b0),.fm_pitch_envelope_write_valid(1'b0),.fm_algorithm_flags_write_valid(1'b0),
  .fm_note_gain_write_valid(1'b0),.aux_write_valid(1'b0),.fm_patch_commit(1'b0));
 integer expected;
 initial begin
  repeat(4)@(negedge clk);reset_n=1;
  force dut.a0_valid=1;force dut.a0_voice=0;force dut.a0_flags=flags;force dut.a0_env_next=env;
  for(integer mode=0;mode<4;mode++)begin
   expression=(mode!=3);dut.voice_part[0]=(mode==1);flags=(mode==2)?0:1;
   for(integer level=0;level<4096;level++)begin
    env=level<<14;@(posedge clk);#1;
    expected=(mode==0)?(level<508?0:level-508):level;
    if(dut.b0_env_integer!==expected[11:0])$fatal(1,"scope/clamp mode=%d level=%d got=%d expected=%d",mode,level,dut.b0_env_integer,expected);
    @(negedge clk);
   end
  end
  $display("PASS expression scope: every 12-bit level, LIVE modulator only; carrier/BACKING/disabled exact, no underflow");$finish;
 end
endmodule
