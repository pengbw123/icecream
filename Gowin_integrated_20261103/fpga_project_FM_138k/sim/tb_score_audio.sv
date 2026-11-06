`timescale 1ns/1ps
// Production top: real command decoder, AI, merge, owners, 32-voice FM and I2S.
// Only tempo's clocks/us parameter is accelerated; I2S stays 1024 clocks/sample.
module tb_score_audio;
    reg clk=0;always #10 clk=~clk;
    reg key_s2=1,ui_command_valid=0,external_midi_event_valid=0;
    reg [7:0] ui_command=0;reg [63:0] ui_payload=0;
    reg [31:0] external_midi_event_data=0;
    wire ui_command_ready,external_midi_event_ready;
    wire [31:0] ai_status;wire [15:0] readback_data;wire readback_valid;
    wire signed [15:0] pcm;wire tick;
    reg score_active=0;
    top #(.FM_VOICE_COUNT(32),.EXTERNAL_SCORE_ENABLED(1)) dut(.clk(clk),.key_s2(key_s2),
        .arp_config(160'd0),.arp_suspend(1'b0),.sequence_active(1'b0),.arp_status(),.arp_notes(),.ai_status(ai_status),
        .headphone_select(1'b0),.headphone_din(),.uart_rx_pin(1'b1),
        .ui_command_valid(ui_command_valid),.ui_command(ui_command),.ui_payload(ui_payload),.ui_command_ready(ui_command_ready),
        .fx_write(1'b0),.fx_index(4'd0),.fx_value(32'd0),.fx_read_index(4'd0),.fx_read_value(),
        .uart_tx_pin(),.usb_host_dp(),.usb_host_dn(),.i2s_bclk(),.i2s_lrclk(),.i2s_din(),
        .lcd_resetn(),.lcd_clk(),.lcd_cs(),.lcd_dc(),.lcd_data(),
        .external_midi_event_data(external_midi_event_data),.external_midi_event_valid(external_midi_event_valid),
        .external_midi_event_ready(external_midi_event_ready),
        .monitor_sample(pcm),.monitor_sample_tick(tick),.monitor_midi_event_data(),.monitor_midi_event_valid(),
        .monitor_voice_count(),.monitor_preset(),.monitor_algorithm(),.monitor_operator_envelopes(),
        .readback_data(readback_data),.readback_valid(readback_valid),
        .perf_snapshot(1'b0),.perf_clear(1'b0),.perf_index(5'd0),.perf_bridge_drop(1'b0),.perf_data(),.external_score_active(score_active));
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
    reg [7:0] tag=0;
    task midi(input [7:0] s,input [6:0] n,v);
        begin @(negedge clk);external_midi_event_data={tag,s,1'b0,n,1'b0,v};external_midi_event_valid=1;
            do @(posedge clk);while(!external_midi_event_ready);
            @(negedge clk);external_midi_event_valid=0;repeat(400)@(negedge clk);end
    endtask
    integer i,live_count,back_count;
    task gates(input integer expected_live,input integer expected_back);
        begin
            repeat(20000)@(negedge clk);live_count=0;back_count=0;
            for(i=0;i<32;i=i+1)if(dut.u_fm_poly_synth.voice_gate[i])begin
                if(dut.u_fm_poly_synth.voice_part[i])back_count++;
                else live_count++;
            end
            if(live_count!=expected_live||back_count!=expected_back)
                $fatal(1,"Gates LIVE=%0d BACKING=%0d expected %0d/%0d",live_count,back_count,expected_live,expected_back);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);key_s2=0;repeat(20000)@(negedge clk);
        // User enables mono glide; score must temporarily become polyphonic.
        midi(8'hb0,22,1);repeat(20000)@(negedge clk);
        if(!dut.u_fm_poly_synth.mono_mode)$fatal(1,"Glide not enabled by real decoder");
        score_active=1;repeat(20000)@(negedge clk);
        if(dut.u_note_latency.enable!==1'b0)$fatal(1,"Score playback contaminated human latency measurement");
        if(dut.u_fm_poly_synth.mono_mode||dut.portamento_time==0)$fatal(1,"Score mask lost stored glide / remained mono");
        tag=8'h88;midi(8'h90,60,90);midi(8'h90,64,90);gates(2,0);
        // Human overlaps score pitch: note owner must not cut the score note.
        tag=0;midi(8'h90,60,80);midi(8'h80,60,0);gates(2,0);
        tag=8'h40;midi(8'h90,48,90);gates(2,1);
        tag=8'h88;midi(8'hb0,64,0);midi(8'hb0,123,0);gates(0,1);
        score_active=0;repeat(20000)@(negedge clk);
        if(dut.u_note_latency.enable!==1'b1)$fatal(1,"Human latency measurement not restored");
        if(!dut.u_fm_poly_synth.mono_mode||dut.portamento_time==0)$fatal(1,"User glide not restored");
        gates(0,1);
        tag=0;midi(8'hb0,123,0);gates(0,0);
        if(dut.u_performance.deadlines||dut.u_performance.lost_ticks)$fatal(1,"Audio render missed deadline");
        $display("PASS production score tags->owners->FM32: polyphonic playback, same-note human ownership, BACKING preserved, glide restored, global panic, no missed samples");$finish;
    end
    initial begin #100000000;$fatal(1,"Score/audio timeout");end
endmodule
