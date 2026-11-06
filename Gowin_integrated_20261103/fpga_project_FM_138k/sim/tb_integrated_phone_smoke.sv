`timescale 1ns/1ps
// Regression for the 0x69 patch readback path, the 0x60 algorithm->routing
// install, the deprecated 0x68 command and the UART byte that used to be lost
// during a local-command injection cycle.
module tb_integrated_phone_smoke #(parameter integer TEST_VOICES=2);
    reg clk=0;
    always #10 clk=~clk;
    reg reset_n=0;

    // ---- fm_uart_control interface -----------------------------------
    reg uart_rx=1;
    wire local_valid;
    wire [7:0] local_cmd;
    wire [63:0] local_payload;
    wire local_ready;
    wire preset_select_valid;
    wire [6:0] preset_select;
    wire [31:0] midi_event_data;
    wire midi_event_valid;
    wire [6:0] midi_event_brightness;
    wire strum_mode;
    wire [15:0] strum_interval_ms, strum_gate_ms;
    wire [6:0] strum_velocity_speed_depth, strum_velocity_brightness_depth;
    wire fm_global_write_valid;
    wire [4:0] fm_algorithm;
    wire [2:0] fm_feedback;
    wire fm_osc_sync;
    wire [6:0] fm_transpose;
    wire [2:0] fm_lfo_waveform;
    wire [6:0] fm_lfo_speed, fm_lfo_delay;
    wire fm_lfo_sync;
    wire [6:0] fm_lfo_pitch_depth, fm_lfo_amp_depth;
    wire [2:0] fm_pitch_mod_sensitivity;
    wire fm_operator_write_valid;
    wire [2:0] fm_operator_index;
    wire fm_operator_enable, fm_operator_fixed;
    wire [3:0] fm_operator_detune;
    wire [31:0] fm_operator_frequency;
    wire [15:0] fm_operator_output_gain;
    wire fm_envelope_write_valid;
    wire [2:0] fm_envelope_operator;
    wire [1:0] fm_envelope_stage;
    wire [15:0] fm_envelope_coefficient, fm_envelope_level;
    wire [2:0] fm_rate_scaling, fm_velocity_sensitivity;
    wire [1:0] fm_amp_mod_sensitivity;
    wire fm_scaling_write_valid;
    wire [2:0] fm_scaling_operator;
    wire [6:0] fm_scaling_breakpoint, fm_scaling_left_depth, fm_scaling_right_depth;
    wire [1:0] fm_scaling_left_curve, fm_scaling_right_curve;
    wire fm_pitch_envelope_write_valid;
    wire [1:0] fm_pitch_envelope_stage;
    wire [15:0] fm_pitch_envelope_coefficient;
    wire [22:0] fm_pitch_envelope_ratio;
    wire fm_algorithm_flags_write_valid;
    wire [47:0] fm_algorithm_flags;
    wire fm_note_gain_write_valid;
    wire [9:0] fm_note_gain_address;
    wire [15:0] fm_note_gain_value;
    wire aux_write_valid;wire [9:0] aux_write_address;wire [15:0] aux_write_value;
    wire fm_patch_commit;
    wire [9:0] patch_read_address;
    wire [15:0] patch_read_data;
    wire [15:0] readback_data;
    wire readback_valid;
    wire [5:0]  fx_cfg_addr;
    wire [15:0] fx_cfg_value;
    wire        fx_cfg_write;
    wire [5:0]  fx_read_index;
    wire [15:0] fx_read_value;
    wire packet_received, packet_error;
    wire [6:0] current_preset;

    fm_uart_control u_ctl (
        .clk(clk), .reset_n(reset_n), .uart_rx_pin(uart_rx),
        .local_command_valid(local_valid), .local_command(local_cmd),
        .local_payload(local_payload), .local_command_ready(local_ready),
        .preset_select_valid(preset_select_valid), .preset_select(preset_select),
        .midi_event_data(midi_event_data), .midi_event_valid(midi_event_valid),
        .midi_event_brightness(midi_event_brightness), .midi_event_ready(1'b1),
        .strum_mode(strum_mode), .strum_interval_ms(strum_interval_ms),
        .strum_gate_ms(strum_gate_ms),
        .strum_velocity_speed_depth(strum_velocity_speed_depth),
        .strum_velocity_brightness_depth(strum_velocity_brightness_depth),
        .fm_global_write_valid(fm_global_write_valid), .fm_algorithm(fm_algorithm),
        .fm_feedback(fm_feedback), .fm_osc_sync(fm_osc_sync),
        .fm_transpose(fm_transpose), .fm_lfo_waveform(fm_lfo_waveform),
        .fm_lfo_speed(fm_lfo_speed), .fm_lfo_delay(fm_lfo_delay),
        .fm_lfo_sync(fm_lfo_sync), .fm_lfo_pitch_depth(fm_lfo_pitch_depth),
        .fm_lfo_amp_depth(fm_lfo_amp_depth),
        .fm_pitch_mod_sensitivity(fm_pitch_mod_sensitivity),
        .fm_operator_write_valid(fm_operator_write_valid),
        .fm_operator_index(fm_operator_index), .fm_operator_enable(fm_operator_enable),
        .fm_operator_fixed(fm_operator_fixed), .fm_operator_detune(fm_operator_detune),
        .fm_operator_frequency(fm_operator_frequency),
        .fm_operator_output_gain(fm_operator_output_gain),
        .fm_envelope_write_valid(fm_envelope_write_valid),
        .fm_envelope_operator(fm_envelope_operator),
        .fm_envelope_stage(fm_envelope_stage),
        .fm_envelope_coefficient(fm_envelope_coefficient),
        .fm_envelope_level(fm_envelope_level), .fm_rate_scaling(fm_rate_scaling),
        .fm_velocity_sensitivity(fm_velocity_sensitivity),
        .fm_amp_mod_sensitivity(fm_amp_mod_sensitivity),
        .fm_scaling_write_valid(fm_scaling_write_valid),
        .fm_scaling_operator(fm_scaling_operator),
        .fm_scaling_breakpoint(fm_scaling_breakpoint),
        .fm_scaling_left_depth(fm_scaling_left_depth),
        .fm_scaling_right_depth(fm_scaling_right_depth),
        .fm_scaling_left_curve(fm_scaling_left_curve),
        .fm_scaling_right_curve(fm_scaling_right_curve),
        .fm_pitch_envelope_write_valid(fm_pitch_envelope_write_valid),
        .fm_pitch_envelope_stage(fm_pitch_envelope_stage),
        .fm_pitch_envelope_coefficient(fm_pitch_envelope_coefficient),
        .fm_pitch_envelope_ratio(fm_pitch_envelope_ratio),
        .fm_algorithm_flags_write_valid(fm_algorithm_flags_write_valid),
        .fm_algorithm_flags(fm_algorithm_flags),
        .fm_note_gain_write_valid(fm_note_gain_write_valid),
        .fm_note_gain_address(fm_note_gain_address),
        .fm_note_gain_value(fm_note_gain_value), .fm_patch_commit(fm_patch_commit),
        .aux_write_valid(aux_write_valid),.aux_write_address(aux_write_address),.aux_write_value(aux_write_value),
        .patch_read_address(patch_read_address), .patch_read_data(patch_read_data),
        .readback_data(readback_data), .readback_valid(readback_valid),
        .fx_cfg_addr(fx_cfg_addr), .fx_cfg_value(fx_cfg_value),
        .fx_cfg_write(fx_cfg_write), .fx_read_index(fx_read_index),
        .fx_read_value(fx_read_value),
        .packet_received(packet_received), .packet_error(packet_error),
        .current_preset(current_preset)
    );

    reg reference_frozen=0;reg [31:0] test_tag=0;reg [13:0] test_bend=0;
    reg test_tick=0,test_valid=0;reg [31:0] test_event=0;reg [6:0] test_porta=0;
    // Real synth readback source (idle engine, sample_tick held low).
    wire signed [15:0] sample_out;
    wire [7:0] active_voice_count;
    wire [47:0] operator_envelope_levels;
    wire synth_midi_ready;
    wire perf_busy,perf_pending,perf_start,perf_done,perf_steal;
    reg perf_snapshot=0;reg [4:0] perf_index=0;wire [31:0] perf_data;
    audio_performance_monitor #(.VOICE_CAPACITY(TEST_VOICES)) u_perf(.clk(clk),.reset_n(reset_n),
        .sample_tick(test_tick),.engine_busy(perf_busy),.sample_pending(perf_pending),
        .render_start(perf_start),.render_done(perf_done),.voice_steal(perf_steal),
        .midi_accept(test_valid&&synth_midi_ready),.midi_stall(test_valid&&!synth_midi_ready),
        .bridge_drop(1'b0),.active_voices(active_voice_count),.audio_sample(sample_out),
        .snapshot(perf_snapshot),.clear_stats(1'b0),.read_index(perf_index),.read_data(perf_data));
    integer perf_clock=0,perf_begin=0,perf_tick_clock=0,perf_render_expected=0,perf_response_expected=0;
    always @(posedge clk)begin
        perf_clock=perf_clock+1;
        if(test_tick)perf_tick_clock=perf_clock;
        if(perf_start)perf_begin=perf_clock;
        if(perf_done)begin
            perf_render_expected=perf_clock-perf_begin;
            perf_response_expected=perf_clock-perf_tick_clock;
        end
    end
    fm_poly_synth #(.VOICE_COUNT(TEST_VOICES)) u_synth (
        .perf_busy(perf_busy),.perf_pending(perf_pending),.perf_render_start(perf_start),
        .perf_render_done(perf_done),.perf_voice_steal(perf_steal),
        .clk(clk), .reset_n(reset_n), .sample_tick(test_tick),
        .midi_event_data(test_event), .midi_event_valid(test_valid),
        .midi_event_brightness(7'd0), .midi_event_ready(synth_midi_ready),
        .fm_algorithm(fm_algorithm), .fm_feedback(fm_feedback),
        .fm_osc_sync(fm_osc_sync), .fm_transpose(fm_transpose),
        .fm_lfo_waveform(fm_lfo_waveform), .fm_lfo_speed(fm_lfo_speed),
        .fm_lfo_delay(fm_lfo_delay), .fm_lfo_sync(fm_lfo_sync),
        .fm_lfo_pitch_depth(fm_lfo_pitch_depth),
        .fm_lfo_amp_depth(fm_lfo_amp_depth),
        .fm_pitch_mod_sensitivity(fm_pitch_mod_sensitivity),
        .fm_operator_write_valid(fm_operator_write_valid),
        .fm_operator_index(fm_operator_index), .fm_operator_enable(fm_operator_enable),
        .fm_operator_fixed(fm_operator_fixed), .fm_operator_detune(fm_operator_detune),
        .fm_operator_frequency(fm_operator_frequency),
        .fm_operator_output_gain(fm_operator_output_gain),
        .fm_envelope_write_valid(fm_envelope_write_valid),
        .fm_envelope_operator(fm_envelope_operator),
        .fm_envelope_stage(fm_envelope_stage),
        .fm_envelope_coefficient(fm_envelope_coefficient),
        .fm_envelope_level(fm_envelope_level), .fm_rate_scaling(fm_rate_scaling),
        .fm_velocity_sensitivity(fm_velocity_sensitivity),
        .fm_amp_mod_sensitivity(fm_amp_mod_sensitivity),
        .fm_scaling_write_valid(fm_scaling_write_valid),
        .fm_scaling_operator(fm_scaling_operator),
        .fm_scaling_breakpoint(fm_scaling_breakpoint),
        .fm_scaling_left_depth(fm_scaling_left_depth),
        .fm_scaling_right_depth(fm_scaling_right_depth),
        .fm_scaling_left_curve(fm_scaling_left_curve),
        .fm_scaling_right_curve(fm_scaling_right_curve),
        .fm_pitch_envelope_write_valid(fm_pitch_envelope_write_valid),
        .fm_pitch_envelope_stage(fm_pitch_envelope_stage),
        .fm_pitch_envelope_coefficient(fm_pitch_envelope_coefficient),
        .fm_pitch_envelope_ratio(fm_pitch_envelope_ratio),
        .fm_algorithm_flags_write_valid(fm_algorithm_flags_write_valid),
        .fm_algorithm_flags(fm_algorithm_flags),
        .fm_note_gain_write_valid(fm_note_gain_write_valid),
        .fm_note_gain_address(fm_note_gain_address),
        .fm_note_gain_value(fm_note_gain_value),
        .aux_write_valid(aux_write_valid),.aux_write_address(aux_write_address),.aux_write_value(aux_write_value),
        .fm_patch_commit(fm_patch_commit),
        .patch_read_address(patch_read_address), .patch_read_data(patch_read_data),
        .pitch_bend(test_bend), .vibrato_depth(7'd0), .vibrato_rate(7'd64),
        .portamento_time(test_porta), .sample_out(sample_out),
        .active_voice_count(active_voice_count),
        .operator_envelope_levels(operator_envelope_levels)
    );

    audio_fx u_fx(.clk(clk),.reset_n(reset_n),.sample_tick(1'b0),.dry_sample(16'sd0),
        .cfg_write(fx_cfg_write),.cfg_addr(fx_cfg_addr),.cfg_value(fx_cfg_value),
        .read_addr(fx_read_index),.read_value(fx_read_value),.sample_out());
    wire [31:0] ui_event;wire ui_valid;wire [6:0] ui_volume;wire ui_present;
    wire phone_valid,phone_ready,phone_rsp,phone_write,tone_success,overflow,initialized;
    wire [63:0] phone_payload;wire [15:0] phone_token;wire [7:0] phone_status,phone_value;
    tri1 scl,sda,int_pin;wire rst_pin;
    touch_ui_controller #(.PHONE_ENABLED(1),.VOICE_CAPACITY(TEST_VOICES)) u_ui(
        .clk(clk),.reset_n(reset_n),.tp_scl(scl),.tp_sda(sda),.tp_int(int_pin),.tp_rst(rst_pin),
        .sd_miso(1'b1),.midi_event_data(ui_event),.midi_event_valid(ui_valid),.midi_event_ready(1'b1),
        .monitor_event(ui_event),.monitor_event_valid(ui_valid),.preset_index(current_preset),
        .algorithm(fm_algorithm),.active_voices(active_voice_count),.touch_present(ui_present),.master_volume(ui_volume),
        .command_valid(local_valid),.command(local_cmd),.command_payload(local_payload),.command_ready(local_ready),
        .patch_read_data(readback_data),.patch_read_valid(readback_valid),.fx_read_value(32'd0),
        .external_guide_active(1'b0),.external_guide_suspend(1'b0),.ai_status(32'd0),.composer_status(32'd0),.composer_detail(32'd0),
        .arp_status(32'd0),.arp_notes(128'd0),.perf_data(32'd0),.gesture_status(32'd0),.gesture_detail(32'd0),
        .phone_request_valid(phone_valid),.phone_request_payload(phone_payload),.phone_request_ready(phone_ready),
        .phone_response_valid(phone_rsp),.phone_response_token(phone_token),.phone_response_status(phone_status),
        .phone_response_value(phone_value),.phone_response_was_write(phone_write));
    midi_performance_control u_mpc(.clk(clk),.reset_n(reset_n),.midi_event_data(ui_event),.midi_event_valid(ui_valid),
        .preset_select_valid(preset_select_valid),.preset_select(preset_select));
    reg bt_rx=1;wire bt_tx;
    sunny_tutorial_system #(.UART_CLKS_PER_BIT(8),.LED_COUNT(32),.SCORE_MAX_EVENTS(32),.PHONE_ENABLED(1),
        .MAP_FILE("sim/calibration_test_map.mem")) u_link(
        .clk(clk),.reset_n(reset_n),.bt_rx(bt_rx),.bt_tx(bt_tx),.start_button_n(1'b1),.stop_button_n(1'b1),
        .external_mode_busy(1'b0),.live_midi_event(ui_event),.live_midi_valid(ui_valid),.key_midi_event(ui_event),
        .key_midi_valid(ui_valid),.key_source(2'd0),.auto_midi_ready(1'b1),.initialized(initialized),.reply_overflow(overflow),
        .phone_request_valid(phone_valid),.phone_request_payload(phone_payload),.phone_request_ready(phone_ready),
        .phone_response_valid(phone_rsp),.phone_response_token(phone_token),.phone_response_status(phone_status),
        .phone_response_value(phone_value),.phone_response_was_write(phone_write),.tone_success(tone_success));
    wire [7:0] byte_in;wire byte_valid;
    uart_rx #(.CLKS_PER_BIT(8)) u_monitor(.clk(clk),.reset_n(reset_n),.rx(bt_tx),.data(byte_in),.valid(byte_valid),.busy());
    reg [7:0] bytes[0:4095];integer n=0;reg seen_banner=0;reg [7:0] last_value;
    always @(posedge clk)begin if(byte_valid)begin bytes[n]=byte_in;n=n+1;end if(tone_success)seen_banner=1;end
    task automatic tick;@(posedge clk);#1;endtask
    task automatic txbyte(input [7:0] b);@(negedge clk);bt_rx=0;repeat(8)tick();
        for(integer i=0;i<8;i=i+1)begin @(negedge clk);bt_rx=b[i];repeat(8)tick();end
        @(negedge clk);bt_rx=1;repeat(8)tick();endtask
    task automatic phone(input [7:0] grp,sel,row,value,input [15:0] tok,input [7:0] flags,expect_status,expect_value);
        reg [63:0] data;reg [7:0] x;integer before_n,limit;
        data={8'hd9,flags,tok,value,row,sel,grp};x=8'h78;before_n=n;
        txbyte('ha5);txbyte('h5a);txbyte('h78);
        for(integer j=0;j<8;j=j+1)begin txbyte(data[j*8+:8]);x=x^data[j*8+:8];end txbyte(x);
        limit=0;while(n<before_n+9)begin tick();limit=limit+1;
            if(limit>5000000)$fatal(1,"phone timeout group=%0d row=%0d PC=%h pending=%b",grp,row,u_ui.address,u_ui.phone_pending);
        end
        if(expect_status==8'hff)begin
            expect_status=bytes[before_n+4];expect_value=bytes[before_n+7];
            if((expect_status!=0 && expect_status!=4) || (expect_status==0 && expect_value!=value) ||
               (expect_status==4 && expect_value==value))$fatal(1,"unexpected write result grp=%0d sel=%0d row=%0d requested=%0d status=%0d actual=%0d",grp,sel,row,value,expect_status,expect_value);
        end
        last_value=expect_value;
        x=8'hf4^8'h78^expect_status^tok[7:0]^tok[15:8]^expect_value;
        if(bytes[before_n]!='ha5||bytes[before_n+1]!='h5a||bytes[before_n+2]!='hf4||bytes[before_n+3]!='h78||
           bytes[before_n+4]!=expect_status||bytes[before_n+5]!=tok[7:0]||bytes[before_n+6]!=tok[15:8]||
           bytes[before_n+7]!=expect_value||bytes[before_n+8]!=x)
           $fatal(1,"phone reply group=%0d row=%0d got %h %h %h %h %h %h %h %h %h",grp,row,bytes[before_n],bytes[before_n+1],bytes[before_n+2],bytes[before_n+3],bytes[before_n+4],bytes[before_n+5],bytes[before_n+6],bytes[before_n+7],bytes[before_n+8]);
        $display("PHONE_FM grp=%0d sel=%0d row=%0d status=%0d value=%0d wait_clocks=%0d",grp,sel,row,expect_status,expect_value,limit);$fflush();
    endtask
    reg [15:0] next_tok=16'h1000;reg [7:0] read_value,goal;
    task automatic write_then_read(input [7:0] grp,sel,row,value);
        phone(grp,sel,row,value,next_tok,0,8'hff,0);next_tok=next_tok+1;read_value=last_value;
        phone(grp,sel,row,0,next_tok,1,0,read_value);next_tok=next_tok+1;
    endtask
    initial begin
        repeat(10)tick();@(negedge clk);reset_n=1;force u_ui.reset_ready=1'b1;
        wait(initialized);phone(7,0,0,30,16'h01a5,0,0,30);
        if(ui_volume!=30||!seen_banner)$fatal(1,"volume or success banner not updated");
        phone(7,0,0,0,16'h025a,1,0,30);
        phone(1,0,0,12,16'h0301,0,0,12);
        if(fm_algorithm!=12)$fatal(1,"real synth algorithm not changed");
        phone(1,0,0,0,16'h0401,1,0,12);
        phone(2,0,4,75,16'h0501,0,0,75);
        phone(2,0,4,0,16'h0601,1,0,75);
        phone(5,0,3,70,16'h0701,0,0,70);
        phone(5,0,3,0,16'h0801,1,0,70);
        phone(6,0,0,10,16'h0901,0,2,0);
        phone(6,0,0,10,16'h0a01,2,0,10);
        if(current_preset!=10)$fatal(1,"factory preset not loaded");
        if(overflow)$fatal(1,"UART reply overflow");
        $display("INTEGRATED_PHONE_SMOKE_OK actual RV32: volume, algorithm, operator gain, FX and dirty-preset/forced-load readback");$finish;
    end
    initial begin #10000000000;$fatal(1,"test watchdog");end
endmodule
