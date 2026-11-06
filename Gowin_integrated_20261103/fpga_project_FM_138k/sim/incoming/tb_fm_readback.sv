`timescale 1ns/1ps
// Regression for the 0x69 patch readback path, the 0x60 algorithm->routing
// install, the deprecated 0x68 command and the UART byte that used to be lost
// during a local-command injection cycle.
module tb_fm_readback #(parameter integer TEST_VOICES=2,parameter integer TEST_COMPARE=0);
    reg clk=0;
    always #10 clk=~clk;
    reg reset_n=0;

    // ---- fm_uart_control interface -----------------------------------
    reg uart_rx=1;
    reg local_valid=0;
    reg [7:0] local_cmd=0;
    reg [63:0] local_payload=0;
    wire local_ready;
    reg preset_select_valid=0;
    reg [6:0] preset_select=0;
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
    wire signed [15:0] reference_sample;wire [7:0] reference_count;wire reference_ready;
    wire signed [31:0] reference_voice_output;
    wire [107:0] reference_operator_state[0:5];
    generate if(TEST_COMPARE)begin:g_reference
    fm_poly_synth #(.VOICE_COUNT(16)) u_reference (
        .perf_busy(),.perf_pending(),.perf_render_start(),
        .perf_render_done(),.perf_voice_steal(),
        .clk(clk), .reset_n(reset_n), .sample_tick(test_tick),
        .midi_event_data(TEST_COMPARE==2 ? (test_event&32'hafffffff) : test_event), .midi_event_valid(test_valid && (TEST_COMPARE!=2 || !reference_frozen || test_tag!=0)),
        .midi_event_brightness(7'd0), .midi_event_ready(reference_ready),
        .fm_algorithm(fm_algorithm), .fm_feedback(reference_frozen ? u_synth.back_fm_feedback : fm_feedback),
        .fm_osc_sync(reference_frozen ? u_synth.back_fm_osc_sync : fm_osc_sync), .fm_transpose(reference_frozen ? u_synth.back_fm_transpose : fm_transpose),
        .fm_lfo_waveform(reference_frozen ? u_synth.back_fm_lfo_waveform : fm_lfo_waveform), .fm_lfo_speed(reference_frozen ? u_synth.back_fm_lfo_speed : fm_lfo_speed),
        .fm_lfo_delay(reference_frozen ? u_synth.back_fm_lfo_delay : fm_lfo_delay), .fm_lfo_sync(reference_frozen ? u_synth.back_fm_lfo_sync : fm_lfo_sync),
        .fm_lfo_pitch_depth(reference_frozen ? u_synth.back_fm_lfo_pitch_depth : fm_lfo_pitch_depth),
        .fm_lfo_amp_depth(reference_frozen ? u_synth.back_fm_lfo_amp_depth : fm_lfo_amp_depth),
        .fm_pitch_mod_sensitivity(reference_frozen ? u_synth.back_fm_pitch_mod_sensitivity : fm_pitch_mod_sensitivity),
        .fm_operator_write_valid(fm_operator_write_valid && !reference_frozen),
        .fm_operator_index(fm_operator_index), .fm_operator_enable(fm_operator_enable),
        .fm_operator_fixed(fm_operator_fixed), .fm_operator_detune(fm_operator_detune),
        .fm_operator_frequency(fm_operator_frequency),
        .fm_operator_output_gain(fm_operator_output_gain),
        .fm_envelope_write_valid(fm_envelope_write_valid && !reference_frozen),
        .fm_envelope_operator(fm_envelope_operator),
        .fm_envelope_stage(fm_envelope_stage),
        .fm_envelope_coefficient(fm_envelope_coefficient),
        .fm_envelope_level(fm_envelope_level), .fm_rate_scaling(fm_rate_scaling),
        .fm_velocity_sensitivity(fm_velocity_sensitivity),
        .fm_amp_mod_sensitivity(fm_amp_mod_sensitivity),
        .fm_scaling_write_valid(fm_scaling_write_valid && !reference_frozen),
        .fm_scaling_operator(fm_scaling_operator),
        .fm_scaling_breakpoint(fm_scaling_breakpoint),
        .fm_scaling_left_depth(fm_scaling_left_depth),
        .fm_scaling_right_depth(fm_scaling_right_depth),
        .fm_scaling_left_curve(fm_scaling_left_curve),
        .fm_scaling_right_curve(fm_scaling_right_curve),
        .fm_pitch_envelope_write_valid(fm_pitch_envelope_write_valid && !reference_frozen),
        .fm_pitch_envelope_stage(fm_pitch_envelope_stage),
        .fm_pitch_envelope_coefficient(fm_pitch_envelope_coefficient),
        .fm_pitch_envelope_ratio(fm_pitch_envelope_ratio),
        .fm_algorithm_flags_write_valid(fm_algorithm_flags_write_valid && !reference_frozen),
        .fm_algorithm_flags(fm_algorithm_flags),
        .fm_note_gain_write_valid(fm_note_gain_write_valid && !reference_frozen),
        .fm_note_gain_address(fm_note_gain_address),
        .fm_note_gain_value(fm_note_gain_value),
        .aux_write_valid(aux_write_valid),.aux_write_address(aux_write_address),.aux_write_value(aux_write_value),
        .fm_patch_commit(fm_patch_commit && !reference_frozen),
        .patch_read_address(patch_read_address), .patch_read_data(),
        .pitch_bend(test_bend), .vibrato_depth(7'd0), .vibrato_rate(7'd64),
        .portamento_time(test_porta), .sample_out(reference_sample),
        .active_voice_count(reference_count),
        .operator_envelope_levels()
    );
    assign reference_voice_output=u_reference.voice_output[0];
    for(genvar rs=0;rs<6;rs=rs+1)begin:g_states
        assign reference_operator_state[rs]=u_reference.operator_state_memory[rs];
    end
    end else begin
        assign reference_sample=0;assign reference_count=0;assign reference_ready=1;assign reference_voice_output=0;
        for(genvar rs=0;rs<6;rs=rs+1)begin:g_states_zero assign reference_operator_state[rs]=0;end
    end endgenerate


    // New FX register file / readback path (command 0x70, 0x69 0x200+addr).
    audio_fx u_fx(.clk(clk), .reset_n(reset_n), .sample_tick(1'b0),
        .dry_sample(16'sd0), .cfg_write(fx_cfg_write),
        .cfg_addr(fx_cfg_addr), .cfg_value(fx_cfg_value),
        .read_addr(fx_read_index), .read_value(fx_read_value),
        .sample_out());

    localparam CLKS_PER_BIT = 434;
    reg [47:0] expected_flags [0:31];
    reg [47:0] preset_flags [0:127];
    initial begin
        $readmemh("src/generated/fm_algorithm_flags.mem", expected_flags);
        $readmemh("src/generated/fm_rom1a_algorithm.mem", preset_flags);
    end

    task send_byte(input [7:0] b);
        integer i;
        begin
            uart_rx = 0;
            for (i = 0; i < CLKS_PER_BIT; i = i + 1) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = b[i];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            uart_rx = 1;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    task send_packet(input [7:0] cmd, input [63:0] data);
        integer i;
        reg [7:0] sum;
        begin
            send_byte(8'hA5);
            send_byte(8'h5A);
            send_byte(cmd);
            sum = cmd;
            for (i = 0; i < 8; i = i + 1) begin
                send_byte(data[i*8 +: 8]);
                sum = sum ^ data[i*8 +: 8];
            end
            send_byte(sum);
        end
    endtask

    reg [15:0] got;
    // readback_valid is a one-clock pulse that appears while a packet's final
    // byte is still being clocked out, so latch it instead of waiting on the
    // level after send_packet returns.
    reg rb_flag = 0;
    reg [15:0] rb_value = 0;
    always @(posedge clk) begin
        if (readback_valid) begin
            rb_value <= readback_data;
            rb_flag <= 1'b1;
        end
    end
    task read_param(input [9:0] addr);
        begin
            rb_flag = 1'b0;
            send_packet(8'h69, {54'd0, addr});
            while (!rb_flag) @(posedge clk);
            got = rb_value;
            rb_flag = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    integer errors = 0;
    task check(input [15:0] expected, input [127:0] name);
        begin
            if (got !== expected) begin
                $display("FAIL %0s: got %04h expected %04h", name, got, expected);
                errors = errors + 1;
            end else
                $display("ok   %0s = %04h", name, got);
        end
    endtask

    task key_event(input [7:0] status,input [6:0] note,value);
        begin
            wait(synth_midi_ready);@(negedge clk);test_event=test_tag|{8'd0,status,1'b0,note,1'b0,value};test_valid=1;
            @(negedge clk);test_valid=0;
            repeat(400)@(negedge clk);
        end
    endtask
    task audio_frame;
        begin
            @(negedge clk);test_tick=1;@(negedge clk);test_tick=0;
            wait(u_synth.engine_state!=0);wait(u_synth.engine_state==0);
            repeat(2)@(negedge clk);
        end
    endtask
    task check_mono;
        integer n;reg [31:0] previous,target,phase_before;reg [25:0] env_before;
        begin
            test_porta=127;repeat(5)@(negedge clk);
            key_event(8'h90,60,100);
            repeat(64)audio_frame();
            if(active_voice_count!=1)$fatal(1,"Mono first voice count=%d held=%h active=%b gate=%b",active_voice_count,u_synth.mono_held,u_synth.voice_active[0],u_synth.voice_gate[0]);
            previous=u_synth.operator_state_memory[0][75:44];
            phase_before=u_synth.operator_state_memory[0][107:76];env_before=u_synth.operator_state_memory[0][43:18];
            key_event(8'h90,72,90);
            if(active_voice_count!=1||u_synth.voice_note[0]!=72)$fatal(1,"Mono overlap allocation");
            if(u_synth.operator_state_memory[0][75:44]!=previous ||
               u_synth.operator_state_memory[0][107:76]!=phase_before ||
               u_synth.operator_state_memory[0][43:18]!=env_before)$fatal(1,"Legato jumped pitch/reset phase/envelope");
            target=u_synth.glide_memory[0][31:0];
            if(target<=previous)$fatal(1,"Upward glide target");
            for(n=0;n<8200;n=n+1)begin
                audio_frame();
                if(u_synth.operator_state_memory[0][75:44]<previous || u_synth.operator_state_memory[0][75:44]>target)
                    $fatal(1,"Glide upward wrap/overshoot");
                previous=u_synth.operator_state_memory[0][75:44];
            end
            if(previous!=target)$fatal(1,"Glide failed to settle exactly");
            key_event(8'h90,67,80);repeat(80)audio_frame();
            previous=u_synth.operator_state_memory[0][75:44];
            if(previous>=target)$fatal(1,"Downward glide did not move");
            key_event(8'h80,67,0);
            if(u_synth.voice_note[0]!=72 || !u_synth.voice_gate[0])$fatal(1,"Last-held note return");
            if(u_synth.operator_state_memory[0][75:44]!=previous)$fatal(1,"Return jumped current glide pitch");
            key_event(8'h80,60,0);if(!u_synth.voice_gate[0])$fatal(1,"Old note-off killed current note");
            key_event(8'h80,72,0);if(u_synth.voice_gate[0] || u_synth.mono_held!=0)$fatal(1,"Final release stuck");
            key_event(8'hb0,64,127);key_event(8'h90,60,100);key_event(8'h80,60,0);
            if(!u_synth.voice_gate[0] || u_synth.mono_held!=0)$fatal(1,"Sustain physical key separation");
            key_event(8'h90,48,100);
            if(u_synth.glide_memory[0][64:32]!=0)$fatal(1,"Sustain/release tail incorrectly triggered glide");
            key_event(8'hb0,120,0);
            if(active_voice_count!=0 || u_synth.mono_held!=0)$fatal(1,"All sound off left mono keys");
            test_porta=0;repeat(5)@(negedge clk);
            key_event(8'h90,60,100);key_event(8'h90,64,100);
            if(active_voice_count!=2)$fatal(1,"Glide OFF did not restore polyphony");
            $display("PASS mono legato: overlap, preserved phase/EG, signed glide, exact endpoint, last priority, sustain, panic and poly bypass");
        end
    endtask
    task fast_command(input [7:0] c,input [63:0] d);
        begin wait(local_ready);@(negedge clk);local_cmd=c;local_payload=d;local_valid=1;
            @(negedge clk);local_valid=0;repeat(12)@(negedge clk);end
    endtask
    task aux(input [9:0] a,input [15:0] v);
        begin fast_command(8'h6a,{32'd0,v,6'd0,a});end
    endtask
    task fast_read(input [9:0] a);
        begin rb_flag=0;fast_command(8'h69,{54'd0,a});wait(rb_flag);got=rb_value;rb_flag=0;end
    endtask
    task copy_backing;
        integer op,w,st;
        begin
            aux(10'h3ff,0);
            for(w=0;w<12;w=w+1)begin fast_read(w);aux(w,got);end
            for(op=0;op<6;op=op+1)for(w=0;w<17;w=w+1)begin
                fast_read(10'h40+op*32+w);aux(10'h40+op*32+w,got);
            end
            for(st=0;st<4;st=st+1)for(w=0;w<3;w=w+1)begin
                fast_read(10'h140+st*8+w);aux(10'h140+st*8+w,got);
            end
            aux(10'h3ff,1);
        end
    endtask
    task check_parts;
        integer n,z,live_v,back_v;reg [31:0] inc_before,recip;
        reg [31:0] back_phase;reg [25:0] env_before;
        begin
            test_bend=8192;
            // Make patch LFO pitch modulation audible in the comparison.
            fast_command(8'h60,{8'd60,8'd40,8'd0,8'd45,5'd0,fm_lfo_waveform,1'b0,fm_transpose,3'd0,1'b1,fm_osc_sync,fm_feedback,3'd0,fm_algorithm});
            fast_command(8'h61,3);
            copy_backing();reference_frozen=1;
            test_tag=32'h40000000;key_event(8'h90,60,100);
            back_v=u_synth.display_voice;
            if(!u_synth.voice_part[back_v])$fatal(1,"BACKING note owner missing");
            for(n=0;n<256;n=n+1)begin audio_frame();
                if(sample_out!==reference_sample)$fatal(1,"BACKING PCM mismatch at %d: %d / %d",n,sample_out,reference_sample);
            end
            inc_before=u_synth.operator_state_memory[back_v*6][75:44];
            back_phase=u_synth.back_lfo_phase;
            // Changing LIVE preset must neither kill BACKING nor reset its LFO.
            @(negedge clk);preset_select=11;preset_select_valid=1;
            @(negedge clk);preset_select_valid=0;repeat(500)@(negedge clk);
            if(!u_synth.voice_gate[back_v]||u_synth.back_lfo_phase!=back_phase)$fatal(1,"LIVE load disturbed BACKING");
            for(n=0;n<256;n=n+1)begin audio_frame();
                if(sample_out!==reference_sample)$fatal(1,"LIVE load changed BACKING PCM %d: %d / %d",n,sample_out,reference_sample);
            end
            test_tag=0;key_event(8'h90,60,100);live_v=u_synth.display_voice;
            if(live_v==back_v||u_synth.voice_part[live_v]||active_voice_count!=2)$fatal(1,"Same pitch not independent");
            if(u_synth.operator_state_memory[live_v*6][75:44]==inc_before)$fatal(1,"Two timbres used same operator frequency");
            for(n=0;n<128;n=n+1)begin
                audio_frame();
                if(u_synth.voice_output[back_v]!==reference_voice_output)$fatal(1,"Mixed timbres changed BACKING bus output");
                for(z=0;z<6;z=z+1)
                    if(u_synth.operator_state_memory[back_v*6+z]!==reference_operator_state[z])
                        $fatal(1,"Mixed timbres corrupted independent operator state");
            end
            key_event(8'hb0,64,127);key_event(8'h80,60,0);
            if(!u_synth.voice_gate[live_v]||!u_synth.voice_gate[back_v])$fatal(1,"LIVE sustain isolation");
            test_tag=32'h40000000;key_event(8'h80,60,0);
            if(u_synth.voice_gate[back_v]||!u_synth.voice_gate[live_v])$fatal(1,"BACKING release / LIVE sustain overlap");
            test_tag=0;key_event(8'hb0,64,0);
            if(u_synth.voice_gate[live_v])$fatal(1,"LIVE sustain release");
            test_tag=32'h10000000;key_event(8'h90,64,90);
            back_v=u_synth.display_voice;
            test_tag=0;key_event(8'h90,67,90);live_v=u_synth.display_voice;
            test_tag=32'h40000000;key_event(8'hb0,123,0);
            if(u_synth.voice_gate[back_v]||!u_synth.voice_gate[live_v])$fatal(1,"ARP stop killed LIVE / failed to release sequence part");
            test_tag=0;key_event(8'hb0,120,0);
            if(active_voice_count!=0)$fatal(1,"Global panic");
            $display("PASS dual part: exact BACKING PCM, LIVE preset isolation, same pitch independent voices, sustain, ARP/SEQ tags and scoped stop");
        end
    endtask
    task check_glide_time;
        integer n;reg [31:0] samples,recip,start,target,fast_step,slow_step,previous;
        begin
            test_porta=127;repeat(5)@(negedge clk);
            key_event(8'h90,60,100);key_event(8'h90,72,100);
            samples=(10*3125+32)/64;recip=32'hffffffff/samples+1;
            aux(10'h3fd,recip[15:0]);aux(10'h3fe,{8'd0,recip[23:16]});
            if(u_synth.glide_reciprocal!=524288)$fatal(1,"Glide half-written reciprocal visible");
            aux(10'h3fc,10);fast_read(10'h00d);if(got!=10)$fatal(1,"Glide time readback");
            key_event(8'h90,84,100);start=u_synth.operator_state_memory[0][75:44];
            target=u_synth.glide_memory[0][31:0];fast_step=u_synth.glide_memory[0][64:32];previous=start;
            for(n=0;n<samples+2;n=n+1)begin audio_frame();
                if(u_synth.operator_state_memory[0][75:44]<previous||u_synth.operator_state_memory[0][75:44]>target)$fatal(1,"10 ms glide discontinuity");
                previous=u_synth.operator_state_memory[0][75:44];
            end
            if(previous!=target)$fatal(1,"10 ms glide duration");
            samples=(1000*3125+32)/64;recip=32'hffffffff/samples+1;
            aux(10'h3fd,recip[15:0]);aux(10'h3fe,{8'd0,recip[23:16]});aux(10'h3fc,1000);
            key_event(8'h90,96,100);slow_step=u_synth.glide_memory[0][64:32];
            if(slow_step>=fast_step/40||slow_step==0)$fatal(1,"1000 ms glide rate not slower");
            $display("PASS adjustable glide: atomic reciprocal, 10/1000 ms endpoints, readback, monotonic samples and exact fast endpoint");
        end
    endtask
    integer bank_n;
    reg [63:0] payload;
    integer race_ok;
    integer metrics_note;
    reg [23:0] age_case [0:9];
    integer age_i;
    reg poly_clock=0;reg [9:0] poly_div=0;
    always @(negedge clk)if(poly_clock)begin poly_div<=poly_div+1'b1;test_tick<=poly_div==0;end
    task burst_event(input [7:0] status,input [6:0] note,value);
        begin
            wait(synth_midi_ready);@(negedge clk);test_event=test_tag|{8'd0,status,1'b0,note,1'b0,value};test_valid=1;
            @(negedge clk);test_valid=0;
        end
    endtask
    integer poly_v,poly_op;
    integer compare_alg,compare_frame,compare_note,nonzero_samples;
    task check_reference;
        begin
            if(TEST_VOICES!=32||!TEST_COMPARE)$fatal(1,"Compare needs 32 voices and TEST_COMPARE=1");
            repeat(500)@(negedge clk);nonzero_samples=0;
            for(compare_alg=0;compare_alg<32;compare_alg=compare_alg+1)begin
                key_event(8'hb0,120,0);
                wait(local_ready);@(negedge clk);local_cmd=8'h60;
                local_payload=compare_alg|(64'd7<<8)|(64'd1<<11)|(64'd24<<16);local_valid=1;
                @(negedge clk);local_valid=0;repeat(100)@(negedge clk);
                for(compare_note=0;compare_note<16;compare_note=compare_note+1)key_event(8'h90,48+compare_note,32+compare_note*5);
                for(compare_frame=0;compare_frame<128;compare_frame=compare_frame+1)begin
                    audio_frame();
                    if(sample_out!==reference_sample)$fatal(1,"16/32 PCM mismatch alg=%d frame=%d new=%d ref=%d",compare_alg,compare_frame,sample_out,reference_sample);
                    if(active_voice_count!==16||reference_count!==16)$fatal(1,"Reference chord lost voices");
                    if(sample_out!=0)nonzero_samples=nonzero_samples+1;
                end
            end
            if(nonzero_samples<100)$fatal(1,"Reference comparison was mostly silent: %d",nonzero_samples);
            $display("PASS bit-exact 16/32 PCM comparison: 32 algorithms, max feedback, 16-note chords, 4096 frames (%d nonzero)",nonzero_samples);$finish;
        end
    endtask
    reg [107:0] first_operator[0:5];reg [31:0] phase_before[0:191];
    task check_poly32;
        begin
            if(TEST_VOICES!=32)$fatal(1,"poly32 needs TEST_VOICES=32");
            repeat(500)@(negedge clk);
            // No render between notes: later initialization must not alias
            // voice 0 or leave slots 128..191 uninitialized.
            for(poly_v=0;poly_v<32;poly_v=poly_v+1)begin
                key_event(8'h90,36+poly_v,100);
                if(active_voice_count!=poly_v+1)$fatal(1,"Count wrapped at voice %d",poly_v);
                if(u_synth.voice_note[poly_v]!==36+poly_v)$fatal(1,"Allocator skipped voice %d",poly_v);
                for(poly_op=0;poly_op<6;poly_op=poly_op+1)begin
                    if(poly_v==0)first_operator[poly_op]=u_synth.operator_state_memory[poly_op];
                    else if(u_synth.operator_state_memory[poly_op]!==first_operator[poly_op])$fatal(1,"High voice initialization aliased voice 0");
                    if((^u_synth.operator_state_memory[poly_v*6+poly_op])===1'bx)$fatal(1,"Slot %d uninitialized",poly_v*6+poly_op);
                    phase_before[poly_v*6+poly_op]=u_synth.operator_state_memory[poly_v*6+poly_op][107:76];
                end
            end
            audio_frame();
            for(poly_v=0;poly_v<32;poly_v=poly_v+1)for(poly_op=0;poly_op<6;poly_op=poly_op+1)
                if(u_synth.operator_state_memory[poly_v*6+poly_op][107:76]===phase_before[poly_v*6+poly_op])
                    $fatal(1,"Operator did not advance: slot %d",poly_v*6+poly_op);
            if(active_voice_count!==32)$fatal(1,"Full 32 count after render");
            // Pedal applies to all 32 slots; release tails remain allocated.
            key_event(8'hb0,64,127);
            for(poly_v=0;poly_v<32;poly_v=poly_v+1)key_event(8'h80,36+poly_v,0);
            for(poly_v=0;poly_v<32;poly_v=poly_v+1)
                if(!u_synth.voice_gate[poly_v]||u_synth.voice_key_down[poly_v])$fatal(1,"Sustain ownership at voice %d",poly_v);
            key_event(8'hb0,64,0);
            for(poly_v=0;poly_v<32;poly_v=poly_v+1)if(u_synth.voice_gate[poly_v])$fatal(1,"Pedal release missed a high voice");
            key_event(8'hb0,120,0);
            if(active_voice_count!==0)$fatal(1,"All sound off missed a high voice");
            // Saturated ready/valid producer, including repeated pitches.
            // Old event-before-sample priority misses deadlines in this case.
            poly_clock=1;
            for(poly_v=0;poly_v<256;poly_v=poly_v+1)burst_event(8'h90,36+(poly_v%64),100);
            repeat(120000)@(negedge clk);
            perf_snapshot=1;@(negedge clk);perf_snapshot=0;
            perf_index=8;#1;if(perf_data!==0)$fatal(1,"Burst caused %d deadline misses",perf_data);
            perf_index=9;#1;if(perf_data!==0)$fatal(1,"Burst caused lost ticks");
            perf_index=13;#1;if(perf_data!=={16'd32,8'd32,8'd32})$fatal(1,"Snapshot full polyphony %h",perf_data);
            perf_index=10;#1;if(perf_data==0)$fatal(1,"Full allocator did not count voice steals");
            perf_index=6;#1;if(perf_data[31:16]>=1024)$fatal(1,"Worst response exceeded frame budget");
            $display("POLY32 max response=%0d clocks",perf_data[31:16]);
            key_event(8'hb0,120,0);repeat(5000)@(negedge clk);
            if(active_voice_count!==0||sample_out!==0)$fatal(1,"All sound off left output");
            $display("PASS 32 voices: 192 independent slots, full count, pedal, high-slot render, dense burst, deadlines, steals and silence");$finish;
        end
    endtask
    initial begin
        repeat (10) @(posedge clk);
        reset_n = 1;
        repeat (5) @(posedge clk);

        if($test$plusargs("keyplan_identity"))begin : keyplan_identity_test
            integer a,b,v;
            repeat(500)@(negedge clk);
            // Physical key indices 19 and 7 play MIDI 67 simultaneously.
            test_tag=32'h23010000;key_event(8'h90,67,100);
            test_tag=32'h27000000;key_event(8'h90,67,90);
            a=-1;b=-1;for(v=0;v<TEST_VOICES;v=v+1)begin
                if(u_synth.voice_key_id[v]==51&&u_synth.voice_gate[v])a=v;
                if(u_synth.voice_key_id[v]==39&&u_synth.voice_gate[v])b=v;
            end
            if(a<0||b<0||a==b)$fatal(1,"tagged unison voices not independent");
            test_tag=0;key_event(8'h80,67,0);
            if(!u_synth.voice_gate[a]||!u_synth.voice_gate[b])$fatal(1,"untagged off released a mapped voice");
            test_tag=32'h23010000;key_event(8'h80,67,0);
            if(u_synth.voice_gate[a]||!u_synth.voice_gate[b])$fatal(1,"first mapped off killed another voice");
            // Both slots are still active because sample ticks are stopped.
            // A new mapped press must reuse A's release tail, not steal B.
            test_tag=32'h28010000;key_event(8'h90,67,75);
            if(!u_synth.voice_gate[b]||!u_synth.voice_gate[a]||u_synth.voice_key_id[a]!=56)
                $fatal(1,"mapped allocation stole held voice instead of release tail");
            test_tag=32'h27000000;key_event(8'h80,67,0);
            if(u_synth.voice_gate[b]||!u_synth.voice_gate[a])$fatal(1,"second mapped voice did not release independently");
            test_tag=32'h28010000;key_event(8'h80,67,0);if(u_synth.voice_gate[a])$fatal(1,"third mapped voice stuck");
            test_tag=0;key_event(8'hb0,120,0);
            key_event(8'h90,60,100);key_event(8'h90,60,90);key_event(8'h80,60,0);
            for(v=0;v<TEST_VOICES;v=v+1)if(u_synth.voice_active[v]&&u_synth.voice_gate[v]&&u_synth.voice_note[v]==60)
                $fatal(1,"legacy untagged note-off did not release all same-pitch voices");
            $display("KEY_PLAN_FM_OK independent same-pitch releases, released-tail priority and legacy semantics");$finish;
        end

        if($test$plusargs("age_boundaries")) begin
            repeat(500) @(negedge clk);
            key_event(8'h90,60,100);
            if(!u_synth.voice_active[0]) $fatal(1,"age test needs active voice 0");
            age_case[0]=0;age_case[1]=1;age_case[2]=24'h0000fe;age_case[3]=24'h0000ff;
            age_case[4]=24'h00fffe;age_case[5]=24'h00ffff;age_case[6]=24'hfeffff;
            age_case[7]=24'hfffffe;age_case[8]=24'hffffff;age_case[9]=24'h9a4d8f;
            for(age_i=0;age_i<10;age_i=age_i+1) begin
                @(negedge clk);u_synth.voice_age[0]=age_case[age_i];
                audio_frame();
                if(u_synth.voice_age[0] !== (age_case[age_i]==24'hffffff ? 24'hffffff : age_case[age_i]+24'd1))
                    $fatal(1,"age increment mismatch at %h: got %h",age_case[age_i],u_synth.voice_age[0]);
            end
            $display("PASS 24-bit voice age carry and saturation boundaries");$finish;
        end

        if($test$plusargs("poly32"))check_poly32();
        if($test$plusargs("compare"))check_reference();

        if($test$plusargs("metrics"))begin
            repeat(500)@(negedge clk);
            for(metrics_note=0;metrics_note<=TEST_VOICES;metrics_note=metrics_note+1)begin
                key_event(8'h90,60+metrics_note,100);audio_frame();
            end
            perf_snapshot=1;@(negedge clk);perf_snapshot=0;
            perf_index=4;#1;if(perf_data!==TEST_VOICES+1)$fatal(1,"Real synth completed frames %d",perf_data);
            perf_index=5;#1;if(perf_data[15:0]!==perf_render_expected)$fatal(1,"Render cycle mismatch %d / %d",perf_data[15:0],perf_render_expected);
            perf_index=6;#1;if(perf_data[15:0]!==perf_response_expected)$fatal(1,"Response cycle mismatch");
            perf_index=10;#1;if(perf_data!==1)$fatal(1,"Real synth voice steal count %d",perf_data);
            perf_index=12;#1;if(perf_data!==TEST_VOICES+1)$fatal(1,"Real synth MIDI count");
            perf_index=8;#1;if(perf_data!==0)$fatal(1,"Unexpected real synth deadline miss");
            perf_index=13;#1;if(perf_data[15:8]!==TEST_VOICES)$fatal(1,"Peak count truncated");
            $display("PASS real FM telemetry: voices=%0d render=%0d response=%0d frames=%0d steals=1",TEST_VOICES,perf_render_expected,perf_response_expected,TEST_VOICES+1);$finish;
        end

        if($test$plusargs("parts_dense"))begin
            copy_backing();poly_clock=1;
            for(poly_v=0;poly_v<32;poly_v=poly_v+1)begin
                test_tag=poly_v[0]?32'h40000000:0;
                burst_event(8'h90,48+poly_v/2,100);
            end
            repeat(1024)@(negedge clk);
            if(active_voice_count!=32)$fatal(1,"Dual part full voice allocation: %d",active_voice_count);
            for(poly_v=0;poly_v<400;poly_v=poly_v+1)begin
                test_tag=poly_v[0]?32'h40000000:0;
                burst_event(8'h90,48+(poly_v%16),80+poly_v%40);
            end
            repeat(512*1024)@(negedge clk);
            poly_clock=0;test_tick=0;wait(!perf_busy&&!perf_pending);
            @(negedge clk);perf_snapshot=1;@(negedge clk);perf_snapshot=0;
            perf_index=8;#1;if(perf_data!=0)$fatal(1,"Dual part missed deadline %d",perf_data);
            perf_index=9;#1;if(perf_data!=0)$fatal(1,"Dual part dropped samples %d",perf_data);
            $display("PASS dual part 32 voices / 432 dense events / fixed 1024-clock sample cadence: no deadline misses or dropped samples");$finish;
        end
        if($test$plusargs("parts"))begin check_parts();$finish;end
        if($test$plusargs("glide_time"))begin check_glide_time();$finish;end
        if($test$plusargs("legato"))begin repeat(500)@(negedge clk);check_mono();$finish;end

        // 1. operator field write then read back through the synth.
        payload = 64'd0;
        payload[7:0] = 8'd0;            // operator 0
        payload[8] = 1'b1;              // enable
        payload[9] = 1'b0;              // ratio
        payload[13:10] = 4'd5;          // detune
        payload[14] = 1'b1;             // detune valid
        payload[47:16] = 32'h0001_8000; // frequency word
        payload[63:48] = 16'd80;        // output level
        send_packet(8'h62, payload);
        read_param(10'h040); check(16'h0015, "op0 enable/fixed/detune");
        read_param(10'h041); check(16'h8000, "op0 freq low");
        read_param(10'h042); check(16'h0001, "op0 freq high");
        read_param(10'h043); check(16'd80,  "op0 level");

        // 2. envelope command (qrate/level + rs/vel/ams).
        payload = 64'd0;
        payload[7:0] = 8'd0;      // operator
        payload[15:8] = 8'd0;     // stage 0
        payload[31:16] = 16'd33;  // qrate
        payload[47:32] = 16'd1000;// level
        payload[50:48] = 3'd2;    // rate scaling
        payload[58:56] = 3'd3;    // velocity sensitivity
        payload[61:60] = 2'd1;    // AMS
        send_packet(8'h63, payload);
        read_param(10'h048); check(16'h005a, "op0 rs/vel/ams");
        read_param(10'h049); check(16'd33, "op0 eg0 qrate");
        read_param(10'h04D); check(16'd1000, "op0 eg0 level");

        // 3. algorithm select installs the routing flags from ROM.
        payload = 64'd0;
        payload[4:0] = 5'd10;
        send_packet(8'h60, payload);
        read_param(10'h000); check(16'd10, "algorithm");
        read_param(10'h009); check(expected_flags[10][15:0], "flags low");
        read_param(10'h00A); check(expected_flags[10][31:16], "flags mid");
        read_param(10'h00B); check(expected_flags[10][47:32], "flags high");

        // 4. 0x68 is deprecated and must be reported as an error.
        payload = 64'd0;
        send_packet(8'h68, payload);
        repeat (4) @(posedge clk);
        if (!saw_68_error) begin
            $display("FAIL 0x68 did not raise packet_error");
            errors = errors + 1;
        end else
            $display("ok   0x68 reported as unsupported");

        // 5. local command injection while a UART byte arrives: the byte must
        //    survive in the holding register (old code dropped it).
        while (!local_ready) @(posedge clk);
        local_cmd = 8'h61;
        local_payload = 64'd7;
        local_valid = 1'b1;
        @(posedge clk);            // injection edge
        local_valid = 1'b0;
        // We are now in the fake-checksum cycle: force a physical byte here.
        force u_ctl.uart_valid = 1'b1;
        force u_ctl.uart_byte = 8'hA5;
        @(posedge clk);
        release u_ctl.uart_valid;
        release u_ctl.uart_byte;
        repeat (4) @(posedge clk);
        race_ok = (u_ctl.parser_state == 4'd1); // WAIT_5A: A5 was preserved
        if (!race_ok) begin
            $display("FAIL injection race: parser_state=%0d", u_ctl.parser_state);
            errors = errors + 1;
        end else
            $display("ok   injection race kept the UART byte");
        if (fm_pitch_mod_sensitivity !== 3'd7) begin
            $display("FAIL local 0x61 not applied: pms=%0d", fm_pitch_mod_sensitivity);
            errors = errors + 1;
        end else
            $display("ok   local command applied");

        // 6. preset load still restores the ROM algorithm flags.
        preset_select = 5'd3;
        preset_select_valid = 1'b1;
        @(posedge clk);
        preset_select_valid = 1'b0;
        repeat (300) @(posedge clk);
        read_param(10'h009); check(preset_flags[3][15:0], "preset flags low");
        read_param(10'h00A); check(preset_flags[3][31:16], "preset flags mid");
        read_param(10'h00B); check(preset_flags[3][47:32], "preset flags high");

        // 7. FX configuration write (0x70) and readback (0x69 0x200+addr).
        send_packet(8'h70, 64'd3 | (64'h1234 << 8));
        repeat (6) @(posedge clk);
        read_param(10'h203); check(16'h1234, "fx reg 3");
        send_packet(8'h70, 64'd0 | (64'h0002 << 8));
        repeat (6) @(posedge clk);
        read_param(10'h200); check(16'h0002, "fx global");
        send_packet(8'h70, 64'd99 | (64'h0001 << 8));
        repeat (6) @(posedge clk);
        if (!saw_fx_error) begin
            $display("FAIL out-of-range FX address did not raise packet_error");
            errors = errors + 1;
        end else
            $display("ok   out-of-range FX address rejected");

        for(bank_n=0;bank_n<128;bank_n=bank_n+1)begin
            @(negedge clk);preset_select=bank_n;preset_select_valid=1;
            @(negedge clk);preset_select_valid=0;
            wait(u_ctl.preset_load_state!=0);wait(u_ctl.preset_load_state==0);
            repeat(10)@(negedge clk);
            if(current_preset!=bank_n || fm_algorithm!==u_ctl.preset_global_memory[bank_n][4:0] ||
               u_synth.patch_op_gain[0]!=={9'd0,u_ctl.preset_operator_memory[bank_n*6][40:34]} ||
               u_synth.patch_eg_qrate[23]!==u_ctl.preset_envelope_memory[bank_n*24+23][5:0] ||
               fm_algorithm_flags!==preset_flags[bank_n])$fatal(1,"128 preset load/address failure bank=%d",bank_n);
        end
        $display("PASS all 128 factory presets, operator/envelope boundaries and algorithm flags");
        if (errors == 0) $display("PASS 0x69 readback, algorithm install, race and preset load");
        else $display("FAIL %0d checks", errors);
        $finish;
    end

    // 0x68 must pulse packet_error.
    reg saw_68_error = 0;
    always @(posedge clk) begin
        if (packet_error) saw_68_error <= 1;
    end
    reg saw_fx_error = 0;
    always @(posedge clk) begin
        if (packet_error && u_ctl.command == 8'h70) saw_fx_error <= 1;
    end
    initial begin
        if($test$plusargs("legato"))#500000000;else #40000000; // 40 ms guard: each UART packet is ~0.95 ms at 115200
        $fatal(1,"FM regression timeout");
    end
endmodule
