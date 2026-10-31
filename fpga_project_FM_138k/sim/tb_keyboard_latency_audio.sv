`timescale 1ns/1ps
// Production top: real command decoder, AI, merge, owners, 32-voice FM and I2S.
// Only tempo's clocks/us parameter is accelerated; I2S stays 1024 clocks/sample.
module tb_keyboard_latency_audio;
    reg clk=0;always #10 clk=~clk;
    reg key_s2=1,ui_command_valid=0,external_midi_event_valid=0;
    reg [7:0] ui_command=0;reg [63:0] ui_payload=0;
    wire [31:0] external_midi_event_data;wire external_valid;
    reg [31:0] packet=0,touch_data=0;reg usb_valid=0,touch_valid=0;
    wire [31:0] decoded,board_data;wire decoded_valid,ur,tr,bv,br;
    wire marker;
    usb_midi_event_decode decode(.packet(packet),.valid(decoded_valid),.event_data(decoded));
    midi_event_arbiter3 arb(.clk(clk),.reset_n(!key_s2),
      .data0({8'd0,decoded[23:0]}),.valid0(usb_valid&&decoded_valid),.ready0(ur),
      .data1(32'd0),.valid1(1'b0),.ready1(),.data2(touch_data),.valid2(touch_valid),.ready2(tr),
      .event_data(board_data),.event_valid(bv),.event_ready(br));
    midi_input_queue queue(.clk(clk),.reset_n(!key_s2),.in_data(board_data),.in_valid(bv),.in_ready(br),
      .out_data(external_midi_event_data),.out_valid(external_valid),.out_ready(external_midi_event_ready));
    wire ui_command_ready,external_midi_event_ready;
    wire [31:0] ai_status;wire [15:0] readback_data;wire readback_valid;
    wire signed [15:0] pcm;wire tick;
    top #(.FM_VOICE_COUNT(32),.BOARD_LATENCY_INPUT(1)) dut(.clk(clk),.key_s2(key_s2),
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
     begin @(negedge clk);packet={velocity,note,status,cable,status[7:4]};usb_valid=1;
      do @(posedge clk);while(!ur);@(negedge clk);usb_valid=0;repeat(400)@(negedge clk);end
    endtask
    task send_touch;
     begin @(negedge clk);touch_data=32'h00903c64;touch_valid=1;
      do @(posedge clk);while(!tr);@(negedge clk);touch_valid=0;end
    endtask
    integer rises=0,width=0,last_width=0;reg last_marker=0;
    always @(posedge clk)begin
     #1;
     if(marker&&!last_marker)begin rises++;width=0;end
     if(marker)width++;
     if(!marker&&last_marker)last_width=width;
     last_marker=marker;
    end
    task silence;
     begin send_usb(8'hb0,120,0,0);wait(dut.u_note_latency.quiet>=32);@(negedge clk);end
    endtask
    task completed(input integer n);
     begin wait(dut.u_note_latency.completed==n);repeat(4)@(negedge clk);
      if(last_width!==dut.u_note_latency.last_latency)$fatal(1,"Pin pulse %0d differs from counter %0d",last_width,dut.u_note_latency.last_latency);
      $display("Measured digital pulse %0d: %0d clocks",n,last_width);
      if(last_width>=250000)$fatal(1,"Digital fast-patch delay exceeds 5ms");
     end
    endtask
    initial begin
     repeat(5)@(negedge clk);key_s2=0;repeat(20000)@(negedge clk);
     for(integer ch=0;ch<16;ch++)begin
      silence;send_usb(8'h90+ch,60,80,ch);completed(ch+1);
     end
     silence;send_touch;completed(17);
     if(rises!=17||dut.u_note_latency.timeouts||dut.u_performance.deadlines||dut.u_performance.lost_ticks)$fatal(1,"Trigger/deadline failure");
     $display("PASS USB MIDI decode->arbiter->FIFO->production FM32->I2S: all 16 channels/cables and touch, 17 measured pulses exactly equal counters, fast-patch digital delays below 5ms");$finish;
    end
    initial begin #200000000;$fatal(1,"keyboard latency timeout count=%0d skipped=%0d state=%h",dut.u_note_latency.completed,dut.u_note_latency.skipped,dut.u_note_latency.held[5]);end
endmodule
