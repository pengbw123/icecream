`timescale 1ns/1ps
// Production top: real command decoder, AI, merge, owners, 32-voice FM and I2S.
// Only tempo's clocks/us parameter is accelerated; I2S stays 1024 clocks/sample.
module tb_usb_single_voice #(parameter integer BOARD_FX=0,USE_BRIDGE=0,GESTURE_CASE=0);
    reg clk=0;always #10 clk=~clk;
    reg key_s2=1,ui_command_valid=0,external_midi_event_valid=0;
    reg [7:0] ui_command=0;reg [63:0] ui_payload=0;
    wire [31:0] external_midi_event_data;wire external_valid;
    reg [31:0] packet=0,touch_data=0;reg usb_valid=0,touch_valid=0;
    wire [31:0] decoded,board_data;wire decoded_valid,ur,tr,bv,br;
    wire marker;reg gesture_control=0,gesture_valid=0;reg [3:0] gesture_action=0;wire [1:0] gesture_mode;
    usb_midi_event_decode decode(.packet(packet),.valid(decoded_valid),.event_data(decoded));
    wire bridge_serial,bridge_tx_ready,bridge_valid,bridge_ready;
    wire [31:0] bridge_data;wire [15:0] bridge_drops;
    // Real 25K frame transmitter and 138K UART receiver at 1 Mbaud.
    midi_frame_tx bridge_tx(.clk(clk),.reset_n(!key_s2),.event_data(decoded),
      .event_valid(USE_BRIDGE&&usb_valid&&decoded_valid),.event_ready(bridge_tx_ready),.tx(bridge_serial));
    midi_bridge_rx bridge_rx(.clk(clk),.reset_n(!key_s2),.rx_pin(bridge_serial),
      .midi_event_data(bridge_data),.midi_event_valid(bridge_valid),.midi_event_ready(bridge_ready),
      .dropped_events(bridge_drops),.dropped_pulse());
    midi_event_arbiter3 arb(.clk(clk),.reset_n(!key_s2),
      .data0({8'd0,decoded[23:0]}),.valid0(!USE_BRIDGE&&usb_valid&&decoded_valid),.ready0(ur),
      .data1(bridge_data),.valid1(USE_BRIDGE&&bridge_valid),.ready1(bridge_ready),.data2(touch_data),.valid2(touch_valid),.ready2(tr),
      .event_data(board_data),.event_valid(bv),.event_ready(br));
    midi_input_queue queue(.clk(clk),.reset_n(!key_s2),.in_data(board_data),.in_valid(bv),.in_ready(br),
      .out_data(queued_data),.out_valid(queued_valid),.out_ready(queued_ready));
    wire [31:0] queued_data;wire queued_valid,queued_ready;
    score_event_arbiter score_merge(.clk(clk),.reset_n(!key_s2),.usb_event_valid(queued_valid),.usb_event_data(queued_data),.usb_event_ack(queued_ready),.player_event_valid(1'b0),.player_event_data(32'd0),.player_event_urgent(1'b0),.player_event_ack(),.midi_event_data(external_midi_event_data),.midi_event_valid(external_valid),.midi_event_ready(external_midi_event_ready));
    wire ui_command_ready,external_midi_event_ready;
    wire [31:0] ai_status;wire [15:0] readback_data;wire readback_valid;
    wire signed [15:0] pcm;wire tick;
    top #(.GESTURE_ENABLED(GESTURE_CASE),.FM_VOICE_COUNT(32),.MIDI_TRACE_ENABLED(1),.BOARD_LATENCY_INPUT(1),.FM_AUDIO_ONLY(!BOARD_FX),.FX2_ENABLED(BOARD_FX),.OUTPUT_SELECT_ENABLED(1)) dut(.trace_usb_accept(!USE_BRIDGE&&usb_valid&&decoded_valid&&ur),.trace_usb_data(decoded),.clk(clk),.key_s2(key_s2),
        .gesture_control(gesture_control),.gesture_valid(gesture_valid),.gesture_action(gesture_action),.gesture_mode(gesture_mode),
        .arp_config(160'd0),.arp_suspend(1'b0),.sequence_active(1'b0),.arp_status(),.arp_notes(),.ai_status(ai_status),
        .headphone_select(1'b0),.headphone_din(),.uart_rx_pin(1'b1),
        .ui_command_valid(ui_command_valid),.ui_command(ui_command),.ui_payload(ui_payload),.ui_command_ready(ui_command_ready),
        .fx_write(1'b0),.fx_index(4'd0),.fx_value(32'd0),.fx_read_index(4'd0),.fx_read_value(),
        .uart_tx_pin(),.usb_host_dp(),.usb_host_dn(),.i2s_bclk(),.i2s_lrclk(),.i2s_din(),
        .lcd_resetn(),.lcd_clk(),.lcd_cs(),.lcd_dc(),.lcd_data(),
        .external_midi_event_data(external_midi_event_data),.external_midi_event_valid(external_valid),
        .external_midi_event_ready(external_midi_event_ready),
        .monitor_sample(pcm),.monitor_sample_tick(tick),.monitor_midi_event_data(),.monitor_midi_event_valid(),
        .monitor_voice_count(),.monitor_preset(),.monitor_algorithm(),.monitor_operator_envelopes(),
        .readback_data(readback_data),.readback_valid(readback_valid),
        .perf_snapshot(1'b0),.perf_clear(1'b0),.perf_index(5'd0),.perf_bridge_drop(1'b0),.perf_data(),.latency_marker(marker),.board_latency_valid(bv&&br),.board_latency_data(board_data));
    defparam dut.u_ai_bass.CLOCKS_PER_US=1;
    reg flag=0;reg [15:0] got;
    always @(posedge clk)if(readback_valid)begin got=readback_data;flag=1;end
    task cmd(input [7:0] c,input [63:0] value);
        begin wait(ui_command_ready);@(negedge clk);ui_command=c;ui_payload=value;ui_command_valid=1;
            @(negedge clk);ui_command_valid=0;repeat(4)@(negedge clk);end
    endtask
    task aux(input [9:0] a,input [15:0] v);
        begin cmd(8'h6a,{32'd0,v,6'd0,a});end
    endtask
    task copy_param(input [9:0] a);
        begin flag=0;cmd(8'h69,{54'd0,a});wait(flag);aux(a,got);end
    endtask
    task send_usb(input [7:0] status,input [7:0] note,input [7:0] velocity,input [3:0] cable);
     begin if(USE_BRIDGE)wait(bridge_tx_ready);@(negedge clk);packet={velocity,note,status,cable,status[7:4]};usb_valid=1;
      do @(posedge clk);while(!(USE_BRIDGE?bridge_tx_ready:ur));@(negedge clk);usb_valid=0;if(USE_BRIDGE)wait(bridge_tx_ready);repeat(400)@(negedge clk);end
    endtask
    task send_touch;
     begin @(negedge clk);touch_data=32'h00903c64;touch_valid=1;
      do @(posedge clk);while(!tr);@(negedge clk);touch_valid=0;end
    endtask

 task restart;
  begin key_s2=1;repeat(8)@(negedge clk);key_s2=0;wait(dut.u_fm_uart_control.preset_load_state==0);repeat(100)@(negedge clk);end
 endtask
 generate if(GESTURE_CASE)begin:g_accelerate
  // Icarus does not apply this nested parameter defparam consistently.
  // Accelerate only the existing microsecond divider in simulation.
  initial force dut.u_arp.us_div=dut.u_arp.CLOCKS_PER_US-1;
  defparam dut.g_gesture_chop.u_chopper.HALF_PERIOD=256;
 end endgenerate
 integer generated=0,zero_windows=0,open_windows=0;reg [6:0] generated_notes[0:7];
 generate if(GESTURE_CASE)begin:g_observe
 always @(posedge clk)begin
  if(dut.synth_midi_event_valid&&dut.synth_midi_event_ready&&dut.synth_midi_event_data[31:24]==8'h88&&dut.synth_midi_event_data[23:20]==9)begin
   if(generated<8)generated_notes[generated]<=dut.synth_midi_event_data[14:8];generated<=generated+1;
  end
  if(tick&&gesture_mode==1)begin
   if(dut.g_gesture_chop.u_chopper.gain==0&&dut.pre_gesture_sample!=0)begin
    if(pcm!=0)$fatal(1,"Production chop closed gate not silent");zero_windows<=zero_windows+1;
   end
   if(dut.g_gesture_chop.u_chopper.gain==128&&pcm!=0)open_windows<=open_windows+1;
  end
 end
 end endgenerate
 task pose(input [3:0] a);begin @(negedge clk);gesture_action=a;gesture_valid=1;@(negedge clk);gesture_valid=0;end endtask
 initial begin
  if(GESTURE_CASE)begin
   restart();gesture_control=1;
   send_usb(8'h90,60,80,0);send_usb(8'h90,64,80,0);send_usb(8'h90,67,80,0);repeat(12000)@(negedge clk);
   if(dut.u_fm_poly_synth.active_voice_count!=3)$fatal(1,"Production normal chord");
   pose(3);wait(gesture_mode==1);repeat(1100000)@(negedge clk);
   if(zero_windows==0||open_windows==0)$fatal(1,"Production chop no audible contrast");
   pose(4);wait(gesture_mode==2);wait(generated>=6);@(negedge clk);
   if(generated_notes[0]!=60||generated_notes[1]!=64||generated_notes[2]!=67||generated_notes[3]!=72||generated_notes[4]!=76||generated_notes[5]!=79)$fatal(1,"Production ARP notes wrong");
   pose(2);wait(gesture_mode==0&&!dut.perform_busy);repeat(12000)@(negedge clk);
   if(dut.composer_status[0]||dut.u_performance.deadlines||dut.u_performance.lost_ticks)$fatal(1,"Composer/deadline affected");
   $display("PASS production FM32+FX gesture: real chord, chopped PCM with silence/full plateaus, six-note current-patch ARP, palm restore, AI inactive, no deadlines/lost samples");$finish;
  end
  restart();send_usb(8'h90,60,80,0);repeat(12000)@(negedge clk);
  if(dut.u_performance.usb_events!==(USE_BRIDGE?0:1)||bridge_drops!==0||dut.u_fm_poly_synth.active_voice_count!==1||dut.u_performance.midi_events!==1)$fatal(1,"USB duplicated voices=%d MIDI=%d",dut.u_fm_poly_synth.active_voice_count,dut.u_performance.midi_events);
  restart();send_touch();repeat(12000)@(negedge clk);
  if(dut.u_fm_poly_synth.active_voice_count!==1||dut.u_performance.midi_events!==1)$fatal(1,"touch duplicated");
  restart();send_usb(8'h90,60,80,0);send_usb(8'h91,60,80,0);repeat(12000)@(negedge clk);
  if(dut.u_fm_poly_synth.active_voice_count!==2||dut.u_performance.midi_events!==2)$fatal(1,"layered channels not preserved");
  $display("Input path USE_BRIDGE=%0d",USE_BRIDGE);$display("PASS production ingress: one NoteOn=one voice; one touch=one voice; two channel NoteOns=two voices");$finish;
 end
 initial begin #(GESTURE_CASE?200000000:20000000);$fatal(1,"single voice timeout");end
endmodule
