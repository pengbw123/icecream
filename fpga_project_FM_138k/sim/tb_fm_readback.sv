`timescale 1ns/1ps
// Regression for the 0x69 patch readback path, the 0x60 algorithm->routing
// install, the deprecated 0x68 command and the UART byte that used to be lost
// during a local-command injection cycle.
module tb_fm_readback;
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
    reg [4:0] preset_select=0;
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
    wire [4:0] current_preset;

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
        .patch_read_address(patch_read_address), .patch_read_data(patch_read_data),
        .readback_data(readback_data), .readback_valid(readback_valid),
        .fx_cfg_addr(fx_cfg_addr), .fx_cfg_value(fx_cfg_value),
        .fx_cfg_write(fx_cfg_write), .fx_read_index(fx_read_index),
        .fx_read_value(fx_read_value),
        .packet_received(packet_received), .packet_error(packet_error),
        .current_preset(current_preset)
    );

    // Real synth readback source (idle engine, sample_tick held low).
    wire signed [15:0] sample_out;
    wire [4:0] active_voice_count;
    wire [47:0] operator_envelope_levels;
    wire synth_midi_ready;
    fm_poly_synth #(.VOICE_COUNT(2)) u_synth (
        .clk(clk), .reset_n(reset_n), .sample_tick(1'b0),
        .midi_event_data(32'd0), .midi_event_valid(1'b0),
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
        .fm_patch_commit(fm_patch_commit),
        .patch_read_address(patch_read_address), .patch_read_data(patch_read_data),
        .pitch_bend(14'd0), .vibrato_depth(7'd0), .vibrato_rate(7'd64),
        .portamento_time(7'd0), .sample_out(sample_out),
        .active_voice_count(active_voice_count),
        .operator_envelope_levels(operator_envelope_levels)
    );

    // New FX register file / readback path (command 0x70, 0x69 0x200+addr).
    audio_fx u_fx(.clk(clk), .reset_n(reset_n), .sample_tick(1'b0),
        .dry_sample(16'sd0), .cfg_write(fx_cfg_write),
        .cfg_addr(fx_cfg_addr), .cfg_value(fx_cfg_value),
        .read_addr(fx_read_index), .read_value(fx_read_value),
        .sample_out());

    localparam CLKS_PER_BIT = 434;
    reg [47:0] expected_flags [0:31];
    reg [47:0] preset_flags [0:31];
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

    reg [63:0] payload;
    integer race_ok;
    initial begin
        repeat (10) @(posedge clk);
        reset_n = 1;
        repeat (5) @(posedge clk);

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
        #40000000; // 40 ms guard: each UART packet is ~0.95 ms at 115200
        $display("FAIL timeout");
        $finish;
    end
endmodule
