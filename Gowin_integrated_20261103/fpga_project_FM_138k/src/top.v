// Tang Primer 25K USB-MIDI six-operator FM synthesizer.
// USB-A on the Dock is the host port (D+=L6, D-=K6). USB-C remains the
// BL616 JTAG/UART connection and carries 115200-baud diagnostics/configuration.
module top #(
    parameter integer FM_VOICE_COUNT = 32,
    parameter integer USB_HOST_ENABLED = 0,
    parameter integer OUTPUT_SELECT_ENABLED = 0,
    // 1: keep the DX7 core, MIDI and I2S; bypass the non-DX7 effects/LCD.
    // 0: restore the original chorus/reverb, output meter and SPI display.
    parameter integer FM_AUDIO_ONLY = 1,
    parameter integer PRO_FX_ENABLED = 0,
    // 1: use the new parameterised post-mix FX chain (audio_fx.v).
    parameter integer FX2_ENABLED = 0,
    parameter integer GESTURE_ENABLED = 0,
    parameter integer EXTERNAL_SCORE_ENABLED=0,
    parameter integer MAPPED_KEY_SUPPORT=0,
    parameter integer BOARD_LATENCY_INPUT=0,
    parameter integer POLY_TEST_ENABLED=0,
    parameter integer MIDI_TRACE_ENABLED=0,
    // USB key velocity calibration endpoints: 0x00 -> 0, 80 -> 127.
    // Compile-time knobs; pads (channel 10) and UART are not rescaled.
    parameter [6:0] USB_KEY_VELOCITY_MIN = 7'h00,
    parameter [6:0] USB_KEY_VELOCITY_MAX = 7'd80,
    parameter       USB_KEY_VELOCITY_CALIBRATE = 1'b1
) (
    input wire poly_test_active,poly_test_valid,input wire [31:0] poly_test_data,output wire poly_test_ready,
    input wire trace_usb_accept,input wire [31:0] trace_usb_data,
    input  wire clk,
    input  wire key_s2,
    input wire [159:0] arp_config,input wire arp_suspend,input wire sequence_active,
    input wire external_guide_active,output wire external_auto_request,
    input wire key_plan_active,output wire key_plan_poly_available,
    output wire [31:0] ai_status,composer_status,composer_detail,
    input wire gesture_valid,input wire [3:0] gesture_action,
    input wire gesture_timbre_mode,input wire [31:0] gesture_position_packet,output wire [31:0] gesture_surface_status,
    input wire gesture_control,output wire [1:0] gesture_mode,
    output wire gesture_ready,gesture_allowed,gesture_cancel,
    output wire [31:0] arp_status,output wire [127:0] arp_notes,
    input wire headphone_select,
    output wire headphone_din,
    input  wire uart_rx_pin,
    input wire ui_command_valid,input wire [7:0] ui_command,input wire [63:0] ui_payload,
    output wire ui_command_ready,
    input wire fx_write,input wire [3:0] fx_index,input wire [31:0] fx_value,
    input wire [3:0] fx_read_index,output wire [31:0] fx_read_value,
    output wire uart_tx_pin,
    inout  wire usb_host_dp,
    inout  wire usb_host_dn,
    output wire i2s_bclk,
    output wire i2s_lrclk,
    output wire i2s_din,
    output wire lcd_resetn,
    output wire lcd_clk,
    output wire lcd_cs,
    output wire lcd_dc,
    output wire lcd_data,
    input  wire [31:0] external_midi_event_data,
    input  wire external_midi_event_valid,
    output wire external_midi_event_ready,
    output wire signed [15:0] monitor_sample,
    output wire monitor_sample_tick,
    output reg [31:0] monitor_midi_event_data,
    output reg monitor_midi_event_valid,
    output wire [7:0] monitor_voice_count,
    output wire [31:0] monitor_voice_mask,
    output wire [6:0] monitor_preset,
    output wire [4:0] monitor_algorithm,
    output wire [47:0] monitor_operator_envelopes,
    output wire [15:0] readback_data,
    output wire readback_valid,
    input wire perf_snapshot,perf_clear,input wire [4:0] perf_index,
    input wire perf_bridge_drop,output wire [31:0] perf_data,output wire latency_marker,input wire external_score_active,
    input wire board_latency_valid,input wire [31:0] board_latency_data
);
    wire clk_usb_48m;
    wire clk_usb_bram_96m;
    wire usb_pll_lock;
    wire usb_debug_reset_n;
    wire usb_debug_cpu_fetch;
    wire usb_debug_uart_write;
    wire [31:0] usb_debug_cpu_addr;
    wire [31:0] usb_midi_event_data;
    wire usb_midi_event_toggle;
    reg midi_event_ack_toggle;
    wire usb_midi_connected;
    wire [31:0] synth_midi_event_data;
    wire synth_midi_event_valid;
    wire synth_midi_event_ready;
    reg usb_pll_lock_meta = 1'b0;
    reg usb_pll_lock_sync = 1'b0;
    reg usb_pll_lock_prev = 1'b0;
    reg [31:0] usb_pll_unlock_count = 32'd0;

    // Retain the proven USB soft-core watchdog from the additive build.
    localparam [27:0] USB_ALIVE_TIMEOUT_CYCLES = 28'd150_000_000;
    localparam [22:0] USB_RESET_HOLD_CYCLES = 23'd5_000_000;
    reg [1:0] usb_uart_activity_sync = 2'b00;
    reg [27:0] usb_alive_timeout_count = 28'd0;
    reg [22:0] usb_reset_hold_count = 23'd0;
    reg usb_watchdog_reset = 1'b0;
    wire audio_reset_n = ~(key_s2 | (USB_HOST_ENABLED != 0 && usb_watchdog_reset));
    wire usb_reset = key_s2 | ~usb_pll_lock | usb_watchdog_reset;

    generate if (USB_HOST_ENABLED != 0) begin : gen_usb_host
        usb_pll u_usb_pll (
            .clkin(clk), .clkout0(clk_usb_48m),
            .clkout1(clk_usb_bram_96m), .lock(usb_pll_lock)
        );
        usb_midi_host u_usb_midi_host (
            .clk_48m(clk_usb_48m), .clk_cpu_bram_96m(clk_usb_bram_96m),
            .reset(usb_reset), .usb_dp(usb_host_dp), .usb_dn(usb_host_dn),
            .cpu_uart_tx(uart_tx_pin), .cpu_uart_rx(uart_rx_pin),
            .midi_event_data(usb_midi_event_data),
            .midi_event_toggle(usb_midi_event_toggle),
            .midi_event_ack_toggle(midi_event_ack_toggle),
            .midi_connected(usb_midi_connected),
            .debug_pll_unlock_count(usb_pll_unlock_count),
            .debug_reset_n(usb_debug_reset_n),
            .debug_cpu_fetch(usb_debug_cpu_fetch),
            .debug_uart_write(usb_debug_uart_write),
            .debug_cpu_addr(usb_debug_cpu_addr)
        );
    end else begin : gen_no_usb_host
        assign clk_usb_48m = 1'b0;
        assign clk_usb_bram_96m = 1'b0;
        assign usb_pll_lock = 1'b1;
        assign usb_midi_event_data = 32'd0;
        assign usb_midi_event_toggle = 1'b0;
        assign usb_midi_connected = 1'b0;
        assign usb_debug_reset_n = 1'b1;
        assign usb_debug_cpu_fetch = 1'b0;
        assign usb_debug_uart_write = 1'b0;
        assign usb_debug_cpu_addr = 32'd0;
        assign uart_tx_pin = 1'b1;
        assign usb_host_dp = 1'bz;
        assign usb_host_dn = 1'bz;
    end endgenerate

    always @(posedge clk) begin
        usb_pll_lock_meta <= usb_pll_lock;
        usb_pll_lock_sync <= usb_pll_lock_meta;
        usb_pll_lock_prev <= usb_pll_lock_sync;
        if (key_s2) usb_pll_unlock_count <= 32'd0;
        else if (usb_pll_lock_prev && !usb_pll_lock_sync)
            usb_pll_unlock_count <= usb_pll_unlock_count + 1'b1;
    end

    always @(posedge clk) begin
        usb_uart_activity_sync <= {usb_uart_activity_sync[0], usb_debug_uart_write};
        if (key_s2 || !usb_pll_lock_sync) begin
            usb_alive_timeout_count <= 28'd0;
            usb_reset_hold_count <= 23'd0;
            usb_watchdog_reset <= 1'b0;
        end else if (usb_watchdog_reset) begin
            if (usb_reset_hold_count == USB_RESET_HOLD_CYCLES - 1'b1) begin
                usb_reset_hold_count <= 23'd0;
                usb_alive_timeout_count <= 28'd0;
                usb_watchdog_reset <= 1'b0;
            end else usb_reset_hold_count <= usb_reset_hold_count + 1'b1;
        end else if (usb_uart_activity_sync[1]) begin
            usb_alive_timeout_count <= 28'd0;
        end else if (usb_alive_timeout_count == USB_ALIVE_TIMEOUT_CYCLES - 1'b1) begin
            usb_alive_timeout_count <= 28'd0;
            usb_reset_hold_count <= 23'd0;
            usb_watchdog_reset <= 1'b1;
        end else usb_alive_timeout_count <= usb_alive_timeout_count + 1'b1;
    end

    reg [1:0] midi_request_sync;
    reg [31:0] midi_event_latched;
    reg midi_event_valid;
    wire raw_midi_event_ready;
    // Scale the configured USB key range to MIDI 0..127. Note On with raw
    // velocity 0 remains a Note Off; channel 10 pads and UART stay unscaled.
    localparam [7:0] USB_KEY_VELOCITY_SPAN =
        (USB_KEY_VELOCITY_MAX > USB_KEY_VELOCITY_MIN)
        ? USB_KEY_VELOCITY_MAX - USB_KEY_VELOCITY_MIN : 8'd1;
    // Q8 slope approximates 127/(max-min). Multiplication by this constant
    // becomes shifts/adds in synthesis, while either endpoint may be edited.
    localparam [15:0] USB_KEY_VELOCITY_SLOPE_Q8 =
        (16'd32512 + (USB_KEY_VELOCITY_SPAN >> 1)) /
        USB_KEY_VELOCITY_SPAN;
    wire [6:0] usb_key_velocity = usb_midi_event_data[6:0];
    wire [7:0] usb_velocity_delta =
        {1'b0, usb_key_velocity} - {1'b0, USB_KEY_VELOCITY_MIN};
    wire [23:0] usb_velocity_scaled_q8 =
        usb_velocity_delta * USB_KEY_VELOCITY_SLOPE_Q8 + 24'd128;
    wire [7:0] usb_velocity_expanded = usb_velocity_scaled_q8[15:8];
    wire [6:0] usb_velocity_calibrated =
        (usb_key_velocity <= USB_KEY_VELOCITY_MIN)
        ? 7'd0 : (usb_key_velocity >= USB_KEY_VELOCITY_MAX)
        ? 7'd127 : usb_velocity_expanded[6:0];
    wire usb_key_note_on = (usb_midi_event_data[23:16] == 8'h90) &&
        (usb_key_velocity != 0);
    wire [31:0] usb_midi_event_calibrated =
        (USB_KEY_VELOCITY_CALIBRATE && usb_key_note_on)
        ? {usb_midi_event_data[31:8], 1'b0, usb_velocity_calibrated}
        : usb_midi_event_data;
    always @(posedge clk or negedge audio_reset_n) begin
        if (!audio_reset_n) begin
            midi_request_sync <= 2'b00;
            midi_event_ack_toggle <= 1'b0;
            midi_event_latched <= 32'd0;
            midi_event_valid <= 1'b0;
        end else begin
            midi_request_sync <= {midi_request_sync[0], usb_midi_event_toggle};
            // Acknowledging the asynchronous mailbox transfers ownership to
            // this slot. Keep its payload valid until the arbiter accepts it.
            if (midi_event_valid && raw_midi_event_ready)
                midi_event_valid <= 1'b0;
            if ((!midi_event_valid || raw_midi_event_ready) &&
                (midi_request_sync[1] != midi_event_ack_toggle)) begin
                midi_event_latched <= usb_midi_event_calibrated;
                midi_event_valid <= 1'b1;
                midi_event_ack_toggle <= midi_request_sync[1];
            end
        end
    end

    wire [13:0] pitch_bend;
    wire [6:0] vibrato_depth, vibrato_rate, portamento_time;
    assign key_plan_poly_available=portamento_time==0;
    wire guide_owned=MAPPED_KEY_SUPPORT && external_guide_active;
    wire block_mono_change=MAPPED_KEY_SUPPORT && key_plan_active &&
        synth_midi_event_data[23:20]==4'hb && synth_midi_event_data[14:8]==7'd22;
    wire [6:0] chorus_mix, delay_mix, delay_time, reverb_mix;
    wire preset_select_valid;
    wire [6:0] preset_select;
    midi_performance_control u_midi_performance_control (
        .clk(clk), .reset_n(audio_reset_n),
        .midi_event_data(synth_midi_event_data),
        .midi_event_valid(synth_midi_event_valid && synth_midi_event_ready && !block_mono_change),
        .pitch_bend(pitch_bend), .vibrato_depth(vibrato_depth),
        .vibrato_rate(vibrato_rate), .portamento_time(portamento_time),
        .chorus_mix(chorus_mix), .delay_mix(delay_mix),
        .delay_time(delay_time), .reverb_mix(reverb_mix),
        .preset_select_valid(preset_select_valid),
        .preset_select(preset_select)
    );

    wire strum_mode;
    wire [15:0] strum_interval_ms, strum_gate_ms;
    wire [6:0] strum_velocity_speed_depth, strum_velocity_brightness_depth;
    wire [31:0] uart_midi_event_data;
    wire uart_midi_event_valid, uart_midi_event_ready;
    wire [6:0] uart_midi_event_brightness;
    wire uart_packet_received, uart_packet_error;
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
    wire aux_write_valid;wire [9:0] aux_write_address;wire [15:0] aux_write_value;
    wire [6:0] current_preset;
    wire timbre_mode=GESTURE_ENABLED&&(gesture_timbre_mode===1'b1);
    wire timbre_request,timbre_expression,preset_busy,fm_live_busy;
    wire [6:0] timbre_preset,timbre_brightness,timbre_vibrato;
    wire timbre_loading;
    assign timbre_loading=gesture_surface_status[18];
    wire [9:0] fm_patch_read_address;
    wire [15:0] fm_patch_read_data;

    fm_uart_control u_fm_uart_control (
        .clk(clk), .reset_n(audio_reset_n), .uart_rx_pin(uart_rx_pin),
        .local_command_valid(ui_command_valid),.local_command(ui_command),
        .local_payload(ui_payload),.local_command_ready(ui_command_ready),
        .preset_select_valid(preset_select_valid||timbre_request),
        .preset_select(preset_select_valid?preset_select:timbre_preset),
        .preset_busy(preset_busy),.midi_event_data(uart_midi_event_data),
        .midi_event_valid(uart_midi_event_valid),
        .midi_event_brightness(uart_midi_event_brightness),
        .midi_event_ready(uart_midi_event_ready),
        .strum_mode(strum_mode), .strum_interval_ms(strum_interval_ms),
        .strum_gate_ms(strum_gate_ms),
        .strum_velocity_speed_depth(strum_velocity_speed_depth),
        .strum_velocity_brightness_depth(strum_velocity_brightness_depth),
        .fm_global_write_valid(fm_global_write_valid),
        .fm_algorithm(fm_algorithm), .fm_feedback(fm_feedback),
        .fm_osc_sync(fm_osc_sync), .fm_transpose(fm_transpose),
        .fm_lfo_waveform(fm_lfo_waveform), .fm_lfo_speed(fm_lfo_speed),
        .fm_lfo_delay(fm_lfo_delay),
        .fm_lfo_sync(fm_lfo_sync),
        .fm_lfo_pitch_depth(fm_lfo_pitch_depth),
        .fm_lfo_amp_depth(fm_lfo_amp_depth),
        .fm_pitch_mod_sensitivity(fm_pitch_mod_sensitivity),
        .fm_operator_write_valid(fm_operator_write_valid),
        .fm_operator_index(fm_operator_index),
        .fm_operator_enable(fm_operator_enable),
        .fm_operator_fixed(fm_operator_fixed),
        .fm_operator_detune(fm_operator_detune),
        .fm_operator_frequency(fm_operator_frequency),
        .fm_operator_output_gain(fm_operator_output_gain),
        .fm_envelope_write_valid(fm_envelope_write_valid),
        .fm_envelope_operator(fm_envelope_operator),
        .fm_envelope_stage(fm_envelope_stage),
        .fm_envelope_coefficient(fm_envelope_coefficient),
        .fm_envelope_level(fm_envelope_level),
        .fm_rate_scaling(fm_rate_scaling),
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
        .patch_read_address(fm_patch_read_address),
        .patch_read_data(fm_patch_read_data),
        .readback_data(readback_data), .readback_valid(readback_valid),
        .fx_cfg_addr(fx_cfg_addr),.fx_cfg_value(fx_cfg_value),
        .fx_cfg_write(fx_cfg_write),.fx_read_index(fx2_read_index),
        .fx_read_value(fx2_read_value),
        .packet_received(uart_packet_received), .packet_error(uart_packet_error),
        .current_preset(current_preset)
    );

    wire sample_tick;
    // Registered elastic input: isolate FIFO-pointer/source arbitration from
    // pad classification and the ARP/SEQ observe fanout. Producers hold valid
    // until accepted, with USB mailbox > external queue > UART priority.
    wire [31:0] ingress_mux_data = midi_event_valid
        ? midi_event_latched : external_midi_event_valid
        ? external_midi_event_data : uart_midi_event_data;
    wire ingress_mux_valid=midi_event_valid|external_midi_event_valid|uart_midi_event_valid;
    wire ingress_ready;
    wire [6:0] ingress_mux_brightness = midi_event_valid
        ? midi_event_latched[6:0] : external_midi_event_valid
        ? external_midi_event_data[6:0] : uart_midi_event_brightness;
    reg [31:0] selected_midi_data;
    reg [6:0] selected_brightness;
    reg selected_midi_valid;
    // A one-cycle bubble on replacement removes the downstream ARP/pad
    // classification -> external ACK -> score RAM/write-enable timing path.
    // Capacity remains one held event; upstream must retain valid until ready.
    wire ingress_buffer_ready = !selected_midi_valid;
    always @(posedge clk or negedge audio_reset_n) begin
        if (!audio_reset_n) begin
            selected_midi_data <= 32'd0;
            selected_brightness <= 7'd0;
            selected_midi_valid <= 1'b0;
        end else if (ingress_buffer_ready) begin
            selected_midi_valid <= ingress_mux_valid;
            if (ingress_mux_valid) begin
                selected_midi_data <= ingress_mux_data;
                selected_brightness <= ingress_mux_brightness;
            end
        end else if(ingress_ready)selected_midi_valid<=0;
    end
    wire [6:0] synth_midi_event_brightness;
    wire [31:0] arp_midi_data;
    wire [6:0] arp_brightness;
    wire arp_valid,arp_ready;
    wire arp_ingress_ready,composer_consume;
    wire [31:0] composer_midi_data,auto_midi_data;
    wire composer_midi_valid,composer_midi_ready,auto_midi_valid,auto_midi_ready;
    wire [6:0] auto_brightness;
    wire bass_start_request=aux_write_valid && aux_write_address==10'h3f0 && aux_write_value[0];
    wire composer_start_request=aux_write_valid &&
        ((aux_write_address==10'h3c0 && aux_write_value[0]) ||
         (aux_write_address==10'h3c5 && aux_write_value[3:0]!=0 && aux_write_value[3:0]!=3));
    assign external_auto_request=bass_start_request||composer_start_request;
    ai_melody_composer #(.GESTURE_ENABLED(0)) u_composer(.clk(clk),.reset_n(audio_reset_n),
        .gesture_valid(1'b0),.gesture_action(4'd0),
        .gesture_ready(),.gesture_allowed(),.gesture_cancel(),
        .cfg_write(aux_write_valid && !(guide_owned && composer_start_request)),.cfg_address(aux_write_address),.cfg_value(aux_write_value),
        .suspend(arp_suspend||arp_config[0]||ai_status[0]),
        .observe_data(selected_midi_data),.observe_valid(selected_midi_valid&&ingress_ready),.consume_input(composer_consume),
        .out_data(composer_midi_data),.out_valid(composer_midi_valid),.out_ready(composer_midi_ready),
        .status(composer_status),.detail(composer_detail));
    wire [31:0] perform_data;wire [6:0] perform_brightness;
    wire perform_valid,perform_ready,perform_busy,perform_restart;
    generate if(GESTURE_ENABLED)begin:g_timbre
        wire expression_requested;
        reg expression_active;
        // Keep guide-command decoding out of the FM pitch calculation path.
        always @(posedge clk) begin
            if(!audio_reset_n) expression_active<=1'b0;
            else expression_active<=expression_requested;
        end
        assign timbre_expression=expression_active;
        gesture_timbre_control control(.clk(clk),.reset_n(audio_reset_n),.sample_tick(sample_tick),
            .enable(timbre_mode&&gesture_control&&gesture_allowed),.position_packet(gesture_position_packet),
            .live_busy(fm_live_busy),.loader_ready(ui_command_ready&&!preset_select_valid&&!selected_midi_valid&&!synth_midi_event_valid&&!perform_valid),
            .loader_busy(preset_busy),.current_preset(current_preset),.preset_valid(timbre_request),.preset(timbre_preset),
            .expression_enable(expression_requested),.brightness(timbre_brightness),.vibrato(timbre_vibrato),.status(gesture_surface_status));
    end else begin:g_no_timbre
        assign timbre_request=0;assign timbre_preset=0;assign timbre_expression=0;
        assign timbre_brightness=127;assign timbre_vibrato=0;assign gesture_surface_status=0;
    end endgenerate

    wire [159:0] effective_arp_config=gesture_mode==2 ?
        {32'd187500,32'd187500,32'd250000,32'd250000,32'h00000041}:arp_config;
    assign gesture_allowed=GESTURE_ENABLED&&!guide_owned&&!arp_suspend&&
        (timbre_mode||(!arp_config[0]&&!sequence_active&&!composer_status[0]&&!ai_status[0]))&&
        !(EXTERNAL_SCORE_ENABLED&&external_score_active)&&!test_owns_audio;
    generate if(GESTURE_ENABLED)begin:g_gesture_perform
        gesture_performer u_performer(.clk(clk),.reset_n(audio_reset_n),
            .enable(gesture_control&&gesture_allowed&&!timbre_mode),.track_enable(gesture_allowed),.action_valid(gesture_valid),.action(gesture_action),
            .action_ready(gesture_ready),.arp_enabled(arp_status[1]==(effective_arp_config[0]&&!arp_suspend)),.mode(gesture_mode),.busy(perform_busy),.cancel(gesture_cancel),.restart_arp(perform_restart),
            .in_data(selected_midi_data),.in_brightness(selected_brightness),
            .in_valid(selected_midi_valid&&!composer_consume),.in_ready(perform_ready),
            .out_data(perform_data),.out_brightness(perform_brightness),.out_valid(perform_valid),.out_ready(arp_ingress_ready));
    end else begin:g_no_gesture_perform
        assign perform_data=selected_midi_data;assign perform_brightness=selected_brightness;
        assign perform_valid=selected_midi_valid&&!composer_consume;assign perform_ready=arp_ingress_ready;
        assign gesture_mode=0;assign perform_busy=0;assign gesture_ready=0;assign gesture_cancel=0;assign perform_restart=0;
    end endgenerate
    assign ingress_ready=composer_consume ? 1'b1 : perform_ready;
    reg arp_suspend_q,sequence_active_q;
    always @(posedge clk) begin
        if(!audio_reset_n) begin
            arp_suspend_q<=1'b0;
            sequence_active_q<=1'b0;
        end else begin
            arp_suspend_q<=arp_suspend;
            sequence_active_q<=sequence_active;
        end
    end
    midi_arpeggiator #(.LIVE_PART_SUPPORT(GESTURE_ENABLED)) u_arp(.clk(clk),.reset_n(audio_reset_n),.live_part(gesture_mode==2),
        .config_data(effective_arp_config),.suspend(arp_suspend_q),.sequence_mode(sequence_active_q),
        .sync_step(1'b0),.sync_restart(perform_restart),.external_sync(1'b0),
        .in_data(perform_data),.in_brightness(perform_brightness),.in_valid(perform_valid),.in_ready(arp_ingress_ready),
        .out_data(arp_midi_data),.out_brightness(arp_brightness),.out_valid(arp_valid),.out_ready(arp_ready),
        .status(arp_status),.chord_notes(arp_notes));
    wire [31:0] ai_midi_data,merged_midi_data;
    wire ai_midi_valid,ai_midi_ready,merged_midi_valid,merged_midi_ready;
    wire [6:0] merged_brightness;
    ai_bass_accompaniment u_ai_bass(.clk(clk),.reset_n(audio_reset_n),
        .cfg_write(aux_write_valid && !(guide_owned && bass_start_request)),.cfg_address(aux_write_address),.cfg_value(aux_write_value),
        .suspend(arp_suspend||arp_config[0]),
        .observe_data(arp_midi_data),.observe_valid(arp_valid&&arp_ready),
        .out_data(ai_midi_data),.out_valid(ai_midi_valid),.out_ready(ai_midi_ready),.status(ai_status));
    ai_midi_merge u_auto_merge(.clk(clk),.reset_n(audio_reset_n),
        .live_data(ai_midi_data),.live_brightness(ai_midi_data[6:0]),.live_valid(ai_midi_valid),.live_ready(ai_midi_ready),
        .ai_data(composer_midi_data),.ai_valid(composer_midi_valid),.ai_ready(composer_midi_ready),
        .out_data(auto_midi_data),.out_brightness(auto_brightness),.out_valid(auto_midi_valid),.out_ready(auto_midi_ready));
    ai_midi_merge u_ai_merge(.clk(clk),.reset_n(audio_reset_n),
        .live_data(arp_midi_data),.live_brightness(arp_brightness),.live_valid(arp_valid),.live_ready(arp_ready),
        .ai_data(auto_midi_data),.ai_valid(auto_midi_valid),.ai_ready(auto_midi_ready),
        .out_data(merged_midi_data),.out_brightness(merged_brightness),.out_valid(merged_midi_valid),.out_ready(merged_midi_ready));
    wire [31:0] normal_midi_data;wire [6:0] normal_brightness;wire normal_valid,normal_ready;
    wire test_owns_audio=POLY_TEST_ENABLED&&poly_test_active;
    assign synth_midi_event_data=test_owns_audio?poly_test_data:normal_midi_data;
    assign synth_midi_event_valid=test_owns_audio?poly_test_valid:normal_valid;
    assign synth_midi_event_brightness=test_owns_audio?7'd127:normal_brightness;
    assign normal_ready=test_owns_audio?1'b1:synth_midi_event_ready;
    assign poly_test_ready=test_owns_audio&&synth_midi_event_ready;
    midi_owner_queue #(.INDEPENDENT_PARTS(1)) u_note_queue(.clk(clk),.reset_n(audio_reset_n),
        .in_data(merged_midi_data),.in_brightness(merged_brightness),.in_valid(merged_midi_valid),.in_ready(merged_midi_ready),
        .out_data(normal_midi_data),.out_brightness(normal_brightness),
        .out_valid(normal_valid),.out_ready(normal_ready));
    assign raw_midi_event_ready = ingress_buffer_ready;
    assign external_midi_event_ready = ingress_buffer_ready & ~midi_event_valid;
    assign uart_midi_event_ready = ingress_buffer_ready &
        ~midi_event_valid & ~external_midi_event_valid;

    wire signed [15:0] synth_sample;
    wire [7:0] active_voice_count;
    wire [47:0] operator_envelope_levels;
    wire perf_busy,perf_pending,perf_start,perf_done,perf_steal;
    wire fm_midi_ready;
    assign synth_midi_event_ready=fm_midi_ready&&!timbre_loading;
    fm_poly_synth #(.VOICE_COUNT(FM_VOICE_COUNT),.EXPRESSION_ENABLED(GESTURE_ENABLED)) u_fm_poly_synth (
        .expression_enable(timbre_expression),.expression_brightness(timbre_brightness),.live_busy(fm_live_busy),
        .perf_busy(perf_busy),.perf_pending(perf_pending),.perf_render_start(perf_start),
        .perf_render_done(perf_done),.perf_voice_steal(perf_steal),
        .clk(clk), .reset_n(audio_reset_n), .sample_tick(sample_tick),
        .midi_event_data(synth_midi_event_data),
        .midi_event_valid(synth_midi_event_valid&&!timbre_loading),
        .midi_event_brightness(synth_midi_event_brightness),
        .midi_event_ready(fm_midi_ready),
        .fm_algorithm(fm_algorithm), .fm_feedback(fm_feedback),
        .fm_osc_sync(fm_osc_sync), .fm_transpose(fm_transpose),
        .fm_lfo_waveform(timbre_expression?3'd4:fm_lfo_waveform), .fm_lfo_speed(fm_lfo_speed),
        .fm_lfo_delay(timbre_expression?7'd0:fm_lfo_delay), .fm_lfo_sync(fm_lfo_sync),
        .fm_lfo_pitch_depth(timbre_expression?7'd0:fm_lfo_pitch_depth),
        .fm_lfo_amp_depth(fm_lfo_amp_depth),
        .fm_pitch_mod_sensitivity(fm_pitch_mod_sensitivity),
        .fm_operator_write_valid(fm_operator_write_valid),
        .fm_operator_index(fm_operator_index),
        .fm_operator_enable(fm_operator_enable),
        .fm_operator_fixed(fm_operator_fixed),
        .fm_operator_detune(fm_operator_detune),
        .fm_operator_frequency(fm_operator_frequency),
        .fm_operator_output_gain(fm_operator_output_gain),
        .fm_envelope_write_valid(fm_envelope_write_valid),
        .fm_envelope_operator(fm_envelope_operator),
        .fm_envelope_stage(fm_envelope_stage),
        .fm_envelope_coefficient(fm_envelope_coefficient),
        .fm_envelope_level(fm_envelope_level),
        .fm_rate_scaling(fm_rate_scaling),
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
        .patch_read_address(fm_patch_read_address),
        .patch_read_data(fm_patch_read_data),
        .pitch_bend(pitch_bend),
        .vibrato_depth(timbre_expression?timbre_vibrato:vibrato_depth), .vibrato_rate(timbre_expression?7'd50:vibrato_rate),
        .portamento_time(((EXTERNAL_SCORE_ENABLED&&external_score_active)||gesture_mode==2)?7'd0:portamento_time), .sample_out(synth_sample),
        .active_voice_count(active_voice_count),.active_voice_mask(monitor_voice_mask),
        .operator_envelope_levels(operator_envelope_levels)
    );

    wire signed [15:0] output_sample,pre_gesture_sample;
    wire latency_frame_load,latency_left_done;wire [31:0] engine_perf_data,latency_perf_data;
    assign perf_data=(perf_index>=18&&perf_index<24)?latency_perf_data:engine_perf_data;
    // On ACG720 the start event is captured before the board input FIFO,
    // with USB transport metadata stripped, for both keyboard and touch.
    wire latency_event_valid=BOARD_LATENCY_INPUT ?
        (board_latency_valid||(uart_midi_event_valid&&uart_midi_event_ready)) : ingress_mux_valid;
    wire [31:0] latency_event_data=BOARD_LATENCY_INPUT ?
        (board_latency_valid?board_latency_data:uart_midi_event_data) : ingress_mux_data;
    audio_note_latency u_note_latency(.clk(clk),.reset_n(audio_reset_n),
        .enable(!(EXTERNAL_SCORE_ENABLED&&external_score_active)&&!arp_config[0]&&!sequence_active&&!composer_status[0]&&!ai_status[0]&&!arp_suspend&&gesture_mode==0&&!perform_busy),
        .event_valid(latency_event_valid),.event_ready(BOARD_LATENCY_INPUT?1'b1:ingress_buffer_ready),.event_data(latency_event_data),
        .active_voices(active_voice_count),.frame_load(latency_frame_load),.left_word_done(latency_left_done),
        .sample_value(output_sample),.snapshot(perf_snapshot),.clear_stats(perf_clear),
        .read_index(perf_index),.read_data(latency_perf_data),.marker(latency_marker));
    audio_performance_monitor #(.VOICE_CAPACITY(FM_VOICE_COUNT),.MIDI_TRACE_ENABLED(MIDI_TRACE_ENABLED)) u_performance(.clk(clk),.reset_n(audio_reset_n),
        .usb_accept(trace_usb_accept),.usb_data(trace_usb_data),.midi_data(synth_midi_event_data),
        .sample_tick(sample_tick),.engine_busy(perf_busy),.sample_pending(perf_pending),
        .render_start(perf_start),.render_done(perf_done),.voice_steal(perf_steal),
        .midi_accept(synth_midi_event_valid&&synth_midi_event_ready),
        .midi_stall(synth_midi_event_valid&&!synth_midi_event_ready),.bridge_drop(perf_bridge_drop),
        .active_voices(active_voice_count),.audio_sample(output_sample),
        .snapshot(perf_snapshot),.clear_stats(perf_clear),.read_index(perf_index),.read_data(engine_perf_data));
    wire [5:0]  fx_cfg_addr;
    wire [15:0] fx_cfg_value;
    wire        fx_cfg_write;
    wire [5:0]  fx2_read_index;
    wire [15:0] fx2_read_value;
    generate if(FX2_ENABLED)begin:gen_fx2
        audio_fx u_fx2(.clk(clk),.reset_n(audio_reset_n),.sample_tick(sample_tick),
            .dry_sample(synth_sample),.cfg_write(fx_cfg_write),
            .cfg_addr(fx_cfg_addr),.cfg_value(fx_cfg_value),
            .read_addr(fx2_read_index),.read_value(fx2_read_value),
            .sample_out(pre_gesture_sample));
        assign fx_read_value = 32'd0;
        assign lcd_resetn=0;assign lcd_clk=0;assign lcd_cs=1;assign lcd_dc=0;assign lcd_data=0;
    end else if(PRO_FX_ENABLED)begin:gen_pro_fx
        pro_audio_effects u_fx(.clk(clk),.reset_n(audio_reset_n),.sample_tick(sample_tick),
            .dry_sample(synth_sample),.config_write(fx_write),.config_index(fx_index),.config_value(fx_value),
            .read_index(fx_read_index),.read_value(fx_read_value),
            .midi_event(synth_midi_event_data),.midi_valid(synth_midi_event_valid&&synth_midi_event_ready),
            .sample_out(pre_gesture_sample));
        assign lcd_resetn=0;assign lcd_clk=0;assign lcd_cs=1;assign lcd_dc=0;assign lcd_data=0;
    end else if (FM_AUDIO_ONLY) begin : gen_audio_only
        // Direct digital path for tone-matching against Dexed.  The FM mixer
        // already has a soft knee; bypassing the second limiter avoids
        // changing attack timbre before I2S.
        assign pre_gesture_sample = synth_sample;
        assign fx_read_value=0;
        assign lcd_resetn = 1'b0;
        assign lcd_clk = 1'b0;
        assign lcd_cs = 1'b1;
        assign lcd_dc = 1'b0;
        assign lcd_data = 1'b0;
    end else begin : gen_full_features
        assign fx_read_value=0;
        wire signed [15:0] effected_sample;
        wire [7:0] peak_level;
        wire clip_active;
        audio_effects u_audio_effects (
            .clk(clk), .reset_n(audio_reset_n), .sample_tick(sample_tick),
            .dry_sample(synth_sample), .chorus_mix(chorus_mix),
            .reverb_mix(reverb_mix), .sample_out(effected_sample)
        );
        audio_output_stage u_audio_output_stage (
            .clk(clk), .reset_n(audio_reset_n), .sample_tick(sample_tick),
            .sample_in(effected_sample), .sample_out(pre_gesture_sample),
            .peak_level(peak_level), .clip_active(clip_active)
        );
        fm_status_lcd u_fm_status_lcd (
            .clk(clk), .reset_n(audio_reset_n), .sample_tick(sample_tick),
            .audio_sample(output_sample),
            .active_voice_count(active_voice_count),
            .preset_index(current_preset), .algorithm(fm_algorithm),
            .algorithm_flags(fm_algorithm_flags),
            .operator_envelope_levels(operator_envelope_levels),
            .peak_level(peak_level), .clip_active(clip_active),
            .lcd_resetn(lcd_resetn), .lcd_clk(lcd_clk), .lcd_cs(lcd_cs),
            .lcd_dc(lcd_dc), .lcd_data(lcd_data)
        );
    end endgenerate
    generate if(GESTURE_ENABLED)begin:g_gesture_chop
        gesture_chopper u_chopper(.clk(clk),.reset_n(audio_reset_n),.sample_tick(sample_tick),
            .enable(gesture_mode==1),.bypass(test_owns_audio),
            .sample_in(pre_gesture_sample),.sample_out(output_sample),.gate_open());
    end else begin:g_no_gesture_chop
        assign output_sample=pre_gesture_sample;
    end endgenerate
    i2s_tx #(.BCLK_HALF_DIV(8),.OUTPUT_SELECT_ENABLED(OUTPUT_SELECT_ENABLED)) u_i2s_tx (
        .clk(clk), .reset_n(audio_reset_n),
        .headphone_select(headphone_select),.headphone_din(headphone_din),
        .sample_left(output_sample), .sample_right(output_sample),
        .frame_load(latency_frame_load),.left_word_done(latency_left_done),
        .sample_tick(sample_tick), .i2s_bclk(i2s_bclk),
        .i2s_lrclk(i2s_lrclk), .i2s_din(i2s_din)
    );

    assign monitor_sample = output_sample;
    assign monitor_sample_tick = sample_tick;
    // Telemetry consumers observe a registered acceptance pulse. This does
    // not participate in MIDI acknowledgement or audio scheduling.
    always @(posedge clk or negedge audio_reset_n)begin
        if(!audio_reset_n)begin monitor_midi_event_data<=0;monitor_midi_event_valid<=0;end
        else begin
            monitor_midi_event_valid<=selected_midi_valid&&ingress_ready;
            if(selected_midi_valid&&ingress_ready)monitor_midi_event_data<=selected_midi_data;
        end
    end
    assign monitor_voice_count = active_voice_count;
    assign monitor_preset = current_preset;
    assign monitor_algorithm = fm_algorithm;
    assign monitor_operator_envelopes = operator_envelope_levels;

    wire unused_fm_global_write_valid = fm_global_write_valid;
    wire [6:0] unused_delay = delay_mix ^ delay_time;
    wire [7:0] unused_voice_count = active_voice_count;
    wire unused_strum_config = strum_mode ^ strum_interval_ms[0] ^
        strum_gate_ms[0] ^ strum_velocity_speed_depth[0] ^
        strum_velocity_brightness_depth[0];
    wire unused_status = unused_strum_config ^ uart_packet_received ^ uart_packet_error ^
                         usb_debug_reset_n ^ usb_debug_cpu_fetch;
    wire [31:0] unused_usb_debug_cpu_addr = usb_debug_cpu_addr;
endmodule
