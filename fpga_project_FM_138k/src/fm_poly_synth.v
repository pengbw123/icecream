// Six-operator, sixteen-voice phase-modulation synthesizer.
//
// The render scheduler is genuinely pipelined: operator N for voices 0..15 is
// issued on consecutive clocks, then operator N+1 is issued.  A voice is not
// revisited until the four-stage sine/gain pipeline has written its buses, so
// dependent operators see the completed result without stalling.  One shared
// sine ROM and three shared multiplier stages replace 96 parallel operators.
//
// Operator order follows the DX7 SysEx order: index 0 is OP6 and index 5 is
// OP1.  The 32 routing rows are the public DX7 algorithm description used by
// the Apache-2.0 msfa engine.  This implementation is musically compatible,
// not bit-exact. Operator envelopes use the measured DX7 logarithmic level
// domain and a shared ROM converts that level to linear gain.
module fm_poly_synth #(
    parameter integer VOICE_COUNT = 16
) (
    input  wire               clk,
    input  wire               reset_n,
    input  wire               sample_tick,
    input  wire [31:0]        midi_event_data,
    input  wire               midi_event_valid,
    input  wire [6:0]         midi_event_brightness,
    output wire               midi_event_ready,

    input  wire [4:0]         fm_algorithm,
    input  wire [2:0]         fm_feedback,
    input  wire               fm_osc_sync,
    input  wire [6:0]         fm_transpose,
    input  wire [2:0]         fm_lfo_waveform,
    input  wire [6:0]         fm_lfo_speed,
    input  wire [6:0]         fm_lfo_delay,
    input  wire               fm_lfo_sync,
    input  wire [6:0]         fm_lfo_pitch_depth,
    input  wire [6:0]         fm_lfo_amp_depth,
    input  wire [2:0]         fm_pitch_mod_sensitivity,

    input  wire               fm_operator_write_valid,
    input  wire [2:0]         fm_operator_index,
    input  wire               fm_operator_enable,
    input  wire               fm_operator_fixed,
    input  wire [3:0]         fm_operator_detune,
    input  wire [31:0]        fm_operator_frequency,
    input  wire [15:0]        fm_operator_output_gain,
    input  wire               fm_envelope_write_valid,
    input  wire [2:0]         fm_envelope_operator,
    input  wire [1:0]         fm_envelope_stage,
    input  wire [15:0]        fm_envelope_coefficient,
    input  wire [15:0]        fm_envelope_level,
    input  wire [2:0]         fm_rate_scaling,
    input  wire [2:0]         fm_velocity_sensitivity,
    input  wire [1:0]         fm_amp_mod_sensitivity,
    input  wire               fm_scaling_write_valid,
    input  wire [2:0]         fm_scaling_operator,
    input  wire [6:0]         fm_scaling_breakpoint,
    input  wire [6:0]         fm_scaling_left_depth,
    input  wire [6:0]         fm_scaling_right_depth,
    input  wire [1:0]         fm_scaling_left_curve,
    input  wire [1:0]         fm_scaling_right_curve,
    input  wire               fm_pitch_envelope_write_valid,
    input  wire [1:0]         fm_pitch_envelope_stage,
    input  wire [15:0]        fm_pitch_envelope_coefficient,
    // Signed Q8.15 Yamaha pitch units, packed in the historical "ratio" port
    // so the UART command number remains backward-compatible.
    input  wire [22:0]        fm_pitch_envelope_ratio,
    input  wire               fm_algorithm_flags_write_valid,
    input  wire [47:0]        fm_algorithm_flags,
    input  wire               fm_note_gain_write_valid,
    input  wire [9:0]         fm_note_gain_address,
    input  wire [15:0]        fm_note_gain_value,
    input  wire               fm_patch_commit,
    // 0x69 parameter readback: live patch values for the on-device editor.
    input  wire [9:0]         patch_read_address,
    output reg  [15:0]        patch_read_data,

    input  wire [13:0]        pitch_bend,
    input  wire [6:0]         vibrato_depth,
    input  wire [6:0]         vibrato_rate,
    input  wire [6:0]         portamento_time,
    output reg  signed [15:0] sample_out,
    output reg  [4:0]         active_voice_count,
    output reg  [47:0]        operator_envelope_levels
);

    localparam integer OPERATOR_COUNT = 6;
    localparam integer SLOT_COUNT = VOICE_COUNT * OPERATOR_COUNT;
    localparam integer VOICE_BITS = (VOICE_COUNT <= 16) ? 4 : 5;

    localparam [3:0] ENGINE_IDLE       = 4'd0;
    localparam [3:0] ENGINE_CLEAR      = 4'd1;
    localparam [3:0] ENGINE_PREP       = 4'd2;
    localparam [3:0] ENGINE_ISSUE      = 4'd3;
    localparam [3:0] ENGINE_DRAIN      = 4'd4;
    localparam [3:0] ENGINE_MIX        = 4'd5;
    localparam [3:0] ENGINE_EVENT_SCAN = 4'd6;
    localparam [3:0] ENGINE_EVENT_INIT = 4'd7;
    localparam [3:0] ENGINE_EVENT_GAIN_CAPTURE = 4'd8;
    localparam [3:0] ENGINE_PREP_RESOLVE = 4'd9;
    localparam [3:0] ENGINE_PREP_COMBINE = 4'd10;
    localparam [3:0] ENGINE_OUTPUT = 4'd11;
    localparam [3:0] ENGINE_RETIRE = 4'd12;
    localparam [3:0] ENGINE_EVENT_GAIN_WAIT = 4'd13;
    localparam [3:0] ENGINE_EVENT_SCALE_MUL = 4'd14;
    localparam [3:0] ENGINE_EVENT_SCALE_FINISH = 4'd15;

    reg [31:0] midi_phase_increment [0:127];
    // Each word stores one Q15 quarter-wave sample plus its forward delta.
    // This keeps interpolation in the same single compact ROM block.
    reg [23:0] sine_quarter_delta [0:511];
    reg [16:0] pitch_ratio_table [0:511];
    reg [16:0] dx7_level_gain [0:4095];
    reg [23:0] dx7_eg_block_step [0:63];
    reg [15:0] dx7_ams_attenuation_q15 [0:511];
    reg [16:0] dx7_note_detune [0:1919];
    reg [17:0] dx7_pitch_eg_fraction [0:255];
    reg [7:0]  dx7_velocity_curve [0:63];
    reg [31:0] dx7_lfo_phase_increment [0:127];
    reg [31:0] dx7_lfo_delay_inc [0:99];
    reg [31:0] dx7_lfo_delay_inc2 [0:99];
    reg signed [8:0] dx7_lfo_sine [0:255];
    initial begin
        $readmemh("src/generated/midi_phase_inc.mem", midi_phase_increment);
        $readmemh("src/generated/dx7_sine_quarter_delta_512.mem",
                  sine_quarter_delta);
        $readmemb("src/generated/pitch_ratio_q16.mem", pitch_ratio_table);
        $readmemb("src/generated/dx7_level_gain_q16.mem", dx7_level_gain);
        $readmemh("src/generated/dx7_eg_block_step_q14.mem", dx7_eg_block_step);
        $readmemh("src/generated/dx7_ams_attenuation_q15.mem",
                  dx7_ams_attenuation_q15);
        $readmemb("src/generated/dx7_note_detune_q16.mem", dx7_note_detune);
        $readmemb("src/generated/dx7_pitch_eg_fraction_q16.mem",
                  dx7_pitch_eg_fraction);
        $readmemh("src/generated/dx7_velocity_curve.mem", dx7_velocity_curve);
        $readmemh("src/generated/dx7_lfo_phase_inc.mem", dx7_lfo_phase_increment);
        $readmemh("src/generated/dx7_lfo_delay_inc.mem", dx7_lfo_delay_inc);
        $readmemh("src/generated/dx7_lfo_delay_inc2.mem", dx7_lfo_delay_inc2);
        $readmemb("src/generated/dx7_lfo_sine_q8.mem", dx7_lfo_sine);
    end

    // Patch storage. Frequency is Q16.16 ratio in ratio mode and a direct
    // Q0.32 phase increment in fixed mode. Output gain is unsigned Q2.14.
    reg        patch_op_enable [0:5];
    reg        patch_op_fixed [0:5];
    reg [31:0] patch_op_frequency [0:5];
    reg [3:0]  patch_op_detune [0:5];
    reg [15:0] patch_op_gain [0:5];
    // Compiled DX7 rate-clock value.  This replaces the old one-pole
    // coefficient whose asymptotic tail caused ten-second notes.
    reg [5:0]  patch_eg_qrate [0:23];
    reg [15:0] patch_eg_level [0:23];
    reg [2:0]  patch_rate_scaling [0:5];
    reg [2:0]  patch_velocity_sensitivity [0:5];
    reg [1:0]  patch_amp_mod_sensitivity [0:5];
    reg [6:0]  patch_breakpoint [0:5];
    reg [6:0]  patch_left_depth [0:5];
    reg [6:0]  patch_right_depth [0:5];
    reg [1:0]  patch_left_curve [0:5];
    reg [1:0]  patch_right_curve [0:5];
    reg [7:0] patch_pitch_step [0:3];
    reg signed [22:0] patch_pitch_target [0:3];
    reg [7:0]  patch_algorithm_flags [0:5];

    // Patch readback for the on-device editor (UART command 0x69).
    //   0x000..0x00B global fields + 48-bit routing flags
    //   0x040 + op*0x20 + off  per-operator fields (op 0..5)
    //   0x140 + stage*8 + off  pitch envelope (stage 0..3)
    // The answer is registered, so the control plane waits two clocks.
    wire [2:0] patch_read_op = patch_read_address[9:5] - 3'd2;
    wire [4:0] patch_read_offset = patch_read_address[4:0];
    wire [1:0] patch_read_pitch_stage = patch_read_address[4:3];
    always @(posedge clk) begin
        patch_read_data <= 16'd0;
        if (patch_read_address < 10'h040) begin
            case (patch_read_address[3:0])
                4'h0: patch_read_data <= {11'd0, fm_algorithm};
                4'h1: patch_read_data <= {13'd0, fm_feedback};
                4'h2: patch_read_data <= {13'd0, fm_lfo_waveform,
                                          fm_lfo_sync, fm_osc_sync};
                4'h3: patch_read_data <= {9'd0, fm_transpose};
                4'h4: patch_read_data <= {9'd0, fm_lfo_speed};
                4'h5: patch_read_data <= {9'd0, fm_lfo_delay};
                4'h6: patch_read_data <= {9'd0, fm_lfo_pitch_depth};
                4'h7: patch_read_data <= {9'd0, fm_lfo_amp_depth};
                4'h8: patch_read_data <= {13'd0, fm_pitch_mod_sensitivity};
                4'h9: patch_read_data <= fm_algorithm_flags[15:0];
                4'hA: patch_read_data <= fm_algorithm_flags[31:16];
                4'hB: patch_read_data <= fm_algorithm_flags[47:32];
                default: patch_read_data <= 16'd0;
            endcase
        end else if (patch_read_address < 10'h100) begin
            case (patch_read_offset)
                5'd0: patch_read_data <= {10'd0, patch_op_detune[patch_read_op],
                                          patch_op_fixed[patch_read_op],
                                          patch_op_enable[patch_read_op]};
                5'd1: patch_read_data <= patch_op_frequency[patch_read_op][15:0];
                5'd2: patch_read_data <= patch_op_frequency[patch_read_op][31:16];
                5'd3: patch_read_data <= patch_op_gain[patch_read_op];
                5'd4: patch_read_data <= {9'd0, patch_breakpoint[patch_read_op]};
                5'd5: patch_read_data <= {9'd0, patch_left_depth[patch_read_op]};
                5'd6: patch_read_data <= {9'd0, patch_right_depth[patch_read_op]};
                5'd7: patch_read_data <= {14'd0, patch_right_curve[patch_read_op],
                                          patch_left_curve[patch_read_op]};
                5'd8: patch_read_data <= {8'd0,
                                          patch_amp_mod_sensitivity[patch_read_op],
                                          patch_velocity_sensitivity[patch_read_op],
                                          patch_rate_scaling[patch_read_op]};
                5'd9:  patch_read_data <= {10'd0,
                                          patch_eg_qrate[patch_read_op*4 + 2'd0]};
                5'd10: patch_read_data <= {10'd0,
                                          patch_eg_qrate[patch_read_op*4 + 2'd1]};
                5'd11: patch_read_data <= {10'd0,
                                          patch_eg_qrate[patch_read_op*4 + 2'd2]};
                5'd12: patch_read_data <= {10'd0,
                                          patch_eg_qrate[patch_read_op*4 + 2'd3]};
                5'd13: patch_read_data <=
                                          patch_eg_level[patch_read_op*4 + 2'd0];
                5'd14: patch_read_data <=
                                          patch_eg_level[patch_read_op*4 + 2'd1];
                5'd15: patch_read_data <=
                                          patch_eg_level[patch_read_op*4 + 2'd2];
                5'd16: patch_read_data <=
                                          patch_eg_level[patch_read_op*4 + 2'd3];
                default: patch_read_data <= 16'd0;
            endcase
        end else if (patch_read_address >= 10'h140 &&
                     patch_read_address < 10'h160) begin
            case (patch_read_address[2:0])
                3'd0: patch_read_data <= {8'd0,
                                          patch_pitch_step[patch_read_pitch_stage]};
                3'd1: patch_read_data <=
                                          patch_pitch_target[patch_read_pitch_stage][15:0];
                3'd2: patch_read_data <= {9'd0,
                                          patch_pitch_target[patch_read_pitch_stage][22:16]};
                default: patch_read_data <= 16'd0;
            endcase
        end
    end

    // Per-voice and per-operator real-time state.
    reg        voice_active [0:VOICE_COUNT-1];
    reg        voice_gate [0:VOICE_COUNT-1];
    reg        voice_key_down [0:VOICE_COUNT-1];
    reg [6:0]  voice_note [0:VOICE_COUNT-1];
    reg [6:0]  voice_velocity [0:VOICE_COUNT-1];
    reg [23:0] voice_age [0:VOICE_COUNT-1];
    reg [5:0] voice_eg_block_position [0:VOICE_COUNT-1];
    reg [VOICE_COUNT-1:0] voice_carrier_alive;
    reg signed [22:0] voice_pitch_level [0:VOICE_COUNT-1];
    reg [20:0] voice_combined_pitch_ratio [0:VOICE_COUNT-1];
    reg [1:0]  voice_pitch_stage [0:VOICE_COUNT-1];
    // DX7 feedback averages the two preceding operator samples.  Keeping only
    // one sample changed the feedback spectrum most strongly at settings 5..7.
    // Retain the operator product at the scale of Dexed's Q24 feedback
    // samples. The former >>>16 history discarded ten more fractional bits
    // before the two-sample average and introduced avoidable feedback error.
    reg signed [27:0] voice_feedback_old [0:VOICE_COUNT-1];
    reg signed [27:0] voice_feedback_new [0:VOICE_COUNT-1];
    reg signed [31:0] voice_bus_one [0:VOICE_COUNT-1];
    reg signed [31:0] voice_bus_two [0:VOICE_COUNT-1];
    reg signed [31:0] voice_output [0:VOICE_COUNT-1];
    // 108 bits/slot: phase, increment, Q14 logarithmic envelope, signed
    // output/key/velocity level offset and EG stage.
    // A single dual-port state RAM removes more than nine thousand flip-flops
    // from the 16-voice build. One voice is revisited only after 16 clocks,
    // leaving ample distance between a slot read and its writeback.
    reg [107:0] operator_state_memory [0:SLOT_COUNT-1];
    // Dexed's FM kernel retains the previous gain endpoint and adds a signed
    // rounded increment on each of 64 samples. Each slot keeps that exact
    // interpolation state separately from its phase/EG RAM word.
    // {target[16:0], signed step[12:0], signed current[17:0]}.
    reg [47:0] operator_gain_state_memory [0:SLOT_COUNT-1];
    reg [47:0] operator_gain_read_data;
    wire [6:0] operator_state_read_address;
    reg [107:0] operator_state_read_data;
    reg operator_state_write_valid;
    reg [6:0] operator_state_write_address;
    reg [107:0] operator_state_write_data;
    // Centralise the RAM layout so a future envelope-width change cannot
    // silently shift the neighbouring phase and frequency fields again.
    function [107:0] pack_operator_state;
        input [31:0] phase;
        input [31:0] increment;
        input [25:0] envelope;
        input signed [15:0] level_offset;
        input [1:0] stage;
        begin
            pack_operator_state = {
                phase, increment, envelope, level_offset, stage
            };
        end
    endfunction
    always @(posedge clk) begin
        operator_state_read_data <= operator_state_memory[operator_state_read_address];
        operator_gain_read_data <= operator_gain_state_memory[operator_state_read_address];
        if (operator_state_write_valid)
            operator_state_memory[operator_state_write_address]
                <= operator_state_write_data;
    end

    reg operator_read_pending;
    reg [VOICE_BITS-1:0] operator_read_voice;
    reg [2:0] operator_read_operator;
    reg [7:0] operator_read_flags;
    reg signed [32:0] operator_read_modulation;

    reg [31:0] lfo_phase;
    // EG increments are generated with Dexed's Q24 sample-rate multiplier
    // for one 64-sample block at 48,828.125 Hz. Voice-local block positions
    // make Note On start its first gain ramp immediately.
    reg [31:0] lfo_delay_state;
    reg [5:0] lfo_delay_block_sample;
    reg signed [7:0] lfo_sample_hold;
    reg [15:0] lfsr;
    reg [15:0] lfo_amp_base;
    reg [6:0] master_volume_target;
    reg [6:0] master_volume_current;
    reg sustain_active;
    reg [VOICE_BITS-1:0] allocation_cursor;
    reg [VOICE_BITS-1:0] display_voice;

    reg event_pending;
    reg [31:0] pending_event;
    reg [6:0] pending_brightness;
    assign midi_event_ready = ~event_pending;

    reg sample_pending;
    reg [3:0] engine_state;
    reg [VOICE_BITS-1:0] scheduler_voice;
    reg [2:0] scheduler_operator;
    reg [VOICE_BITS-1:0] mix_voice;
    reg signed [39:0] mix_accumulator;
    reg [VOICE_BITS-1:0] event_scan_voice;
    reg [VOICE_BITS-1:0] event_target_voice;
    reg [2:0] event_init_operator;
    reg event_free_found;
    reg [VOICE_BITS-1:0] event_free_voice;
    reg [23:0] event_oldest_age;
    reg [VOICE_BITS-1:0] event_oldest_voice;
    reg [6:0] event_note;
    reg [6:0] event_velocity;
    reg [5:0] event_scale_group;
    reg [6:0] event_scale_depth;
    reg [1:0] event_scale_curve;
    reg [7:0] event_scale_base_level;
    reg [14:0] event_scale_product;
    reg [7:0] event_scale_magnitude;
    reg signed [15:0] event_level_offset_latched;
    reg [10:0] event_detune_address;
    reg [16:0] event_detune_read_data;
    reg [31:0] event_note_increment_latched;
    reg [31:0] event_patch_frequency_latched;
    reg event_patch_fixed_latched;
    reg [31:0] event_base_increment;
    reg [31:0] event_corrected_increment;
    wire [48:0] event_detuned_product =
        event_base_increment * event_detune_read_data;
    always @(posedge clk)
        event_detune_read_data <= dx7_note_detune[event_detune_address];

    integer i;
    integer init_index;
    integer count_index;

    function [6:0] transpose_note;
        input [6:0] note;
        input [6:0] transpose_value;
        reg signed [9:0] shifted;
        begin
            shifted = $signed({1'b0, note}) +
                      $signed({1'b0, transpose_value}) - 10'sd24;
            if (shifted < 0) transpose_note = 7'd0;
            else if (shifted > 127) transpose_note = 7'd127;
            else transpose_note = shifted[6:0];
        end
    endfunction

    function [15:0] velocity_gain;
        input [6:0] velocity;
        input [2:0] sensitivity;
        reg [14:0] missing;
        reg [15:0] reduction;
        begin
            // Sensitivity zero ignores velocity. At seven, the softest key is
            // attenuated strongly but never becomes exactly silent.
            missing = (7'd127 - velocity) * sensitivity;
            reduction = {1'b0, missing, 1'b0};
            if (reduction > 16'd14336) velocity_gain = 16'd2048;
            else velocity_gain = 16'd16384 - reduction;
        end
    endfunction

    function [7:0] dx7_scale_level;
        input [6:0] level;
        begin
            if (level >= 7'd20)
                dx7_scale_level = 8'd28 + level;
            else begin
                case (level)
                    0: dx7_scale_level=0;   1: dx7_scale_level=5;
                    2: dx7_scale_level=9;   3: dx7_scale_level=13;
                    4: dx7_scale_level=17;  5: dx7_scale_level=20;
                    6: dx7_scale_level=23;  7: dx7_scale_level=25;
                    8: dx7_scale_level=27;  9: dx7_scale_level=29;
                    10: dx7_scale_level=31; 11: dx7_scale_level=33;
                    12: dx7_scale_level=35; 13: dx7_scale_level=37;
                    14: dx7_scale_level=39; 15: dx7_scale_level=41;
                    16: dx7_scale_level=42; 17: dx7_scale_level=43;
                    18: dx7_scale_level=45; default: dx7_scale_level=46;
                endcase
            end
        end
    endfunction

    function [7:0] dx7_exp_scale;
        input [5:0] group;
        begin
            case (group)
                0:dx7_exp_scale=0; 1:dx7_exp_scale=1; 2:dx7_exp_scale=2;
                3:dx7_exp_scale=3; 4:dx7_exp_scale=4; 5:dx7_exp_scale=5;
                6:dx7_exp_scale=6; 7:dx7_exp_scale=7; 8:dx7_exp_scale=8;
                9:dx7_exp_scale=9; 10:dx7_exp_scale=11; 11:dx7_exp_scale=14;
                12:dx7_exp_scale=16; 13:dx7_exp_scale=19; 14:dx7_exp_scale=23;
                15:dx7_exp_scale=27; 16:dx7_exp_scale=33; 17:dx7_exp_scale=39;
                18:dx7_exp_scale=47; 19:dx7_exp_scale=56; 20:dx7_exp_scale=66;
                21:dx7_exp_scale=80; 22:dx7_exp_scale=94; 23:dx7_exp_scale=110;
                24:dx7_exp_scale=126; 25:dx7_exp_scale=142;
                26:dx7_exp_scale=158; 27:dx7_exp_scale=174;
                28:dx7_exp_scale=190; 29:dx7_exp_scale=206;
                30:dx7_exp_scale=222; 31:dx7_exp_scale=238;
                default: dx7_exp_scale=250;
            endcase
        end
    endfunction

    function signed [15:0] saturate16;
        input signed [39:0] value;
        begin
            if (value > 40'sd32767) saturate16 = 16'sd32767;
            else if (value < -40'sd32768) saturate16 = -16'sd32768;
            else saturate16 = value[15:0];
        end
    endfunction

    // Piecewise soft knee: the lower 75% of full scale is transparent, then
    // the remaining headroom is compressed 4:1 before the final hard ceiling.
    // This keeps dense chords from turning into flat-topped square edges.
    function signed [15:0] soft_limit16;
        input signed [39:0] value;
        reg negative;
        reg [39:0] magnitude;
        reg [39:0] limited;
        begin
            negative = value[39];
            magnitude = negative ? -value : value;
            if (magnitude <= 40'd24576)
                limited = magnitude;
            else if (magnitude <= 40'd57340)
                limited = 40'd24576 + ((magnitude - 40'd24576) >> 2);
            else
                limited = 40'd32767;
            soft_limit16 = negative ? -$signed(limited[15:0])
                                    :  $signed(limited[15:0]);
        end
    endfunction

    function [4:0] glide_shift;
        input [6:0] value;
        begin
            case (value[6:4])
                3'd0: glide_shift = 5'd4;
                3'd1: glide_shift = 5'd6;
                3'd2: glide_shift = 5'd8;
                3'd3: glide_shift = 5'd10;
                3'd4: glide_shift = 5'd11;
                3'd5: glide_shift = 5'd12;
                3'd6: glide_shift = 5'd13;
                default: glide_shift = 5'd14;
            endcase
        end
    endfunction

    // Global LFO. The patch LFO and physical modulation strip share the same
    // oscillator; the strip adds depth and its RATE knob can override speed.
    wire [7:0] lfo_ramp = lfo_phase[31:24];
    wire signed [8:0] lfo_triangle = lfo_phase[31]
        ? (9'sd255 - $signed({1'b0, lfo_phase[30:23]}) * 2)
        : ($signed({1'b0, lfo_phase[30:23]}) * 2 - 9'sd255);
    reg signed [8:0] lfo_value;
    always @* begin
        case (fm_lfo_waveform)
            3'd0: lfo_value = lfo_triangle;
            3'd1: lfo_value = 9'sd255 - $signed({1'b0, lfo_ramp}) * 2;
            3'd2: lfo_value = $signed({1'b0, lfo_ramp}) * 2 - 9'sd255;
            3'd3: lfo_value = lfo_phase[31] ? -9'sd255 : 9'sd255;
            3'd4: lfo_value = dx7_lfo_sine[lfo_phase[31:24]];
            default: lfo_value = $signed(lfo_sample_hold) <<< 1;
        endcase
    end
    // DX7 amplitude modulation is one-sided: a maximum LFO sample gives no
    // attenuation and a minimum sample gives the deepest attenuation.  The
    // former absolute value made two AM pulses per LFO cycle and removed the
    // intended slow brightness/level sweep from AMS-heavy patches.
    wire [8:0] lfo_amp_unipolar =
        (10'sd255 - $signed({lfo_value[8], lfo_value})) >>> 1;
    wire [6:0] selected_lfo_speed = (vibrato_rate != 7'd64)
        ? vibrato_rate : fm_lfo_speed;
    wire [31:0] lfo_phase_increment =
        dx7_lfo_phase_increment[selected_lfo_speed];
    function [7:0] pitch_mod_sensitivity_scale;
        input [2:0] sensitivity;
        begin
            case (sensitivity)
                3'd0: pitch_mod_sensitivity_scale = 8'd0;
                3'd1: pitch_mod_sensitivity_scale = 8'd10;
                3'd2: pitch_mod_sensitivity_scale = 8'd20;
                3'd3: pitch_mod_sensitivity_scale = 8'd33;
                3'd4: pitch_mod_sensitivity_scale = 8'd55;
                3'd5: pitch_mod_sensitivity_scale = 8'd92;
                3'd6: pitch_mod_sensitivity_scale = 8'd153;
                default: pitch_mod_sensitivity_scale = 8'd255;
            endcase
        end
    endfunction
    wire [6:0] lfo_delay_table_address = (fm_lfo_delay > 7'd99)
        ? 7'd99 : fm_lfo_delay;
    wire [31:0] lfo_delay_increment = lfo_delay_state[31]
        ? dx7_lfo_delay_inc2[lfo_delay_table_address]
        : dx7_lfo_delay_inc[lfo_delay_table_address];
    wire [32:0] lfo_delay_advance = {1'b0, lfo_delay_state} +
        {1'b0, lfo_delay_increment};
    wire [7:0] lfo_delay_advance_fade = lfo_delay_advance[32]
        ? 8'hff
        : lfo_delay_advance[31] ? lfo_delay_advance[30:23] : 8'd0;
    reg [7:0] lfo_fade;
    wire signed [17:0] lfo_value_delayed_product = lfo_value *
        $signed({1'b0, lfo_fade});
    reg signed [8:0] lfo_value_delayed;
    wire [7:0] patch_pitch_sensitivity =
        pitch_mod_sensitivity_scale(fm_pitch_mod_sensitivity);
    wire signed [26:0] lfo_patch_pitch_product = lfo_value_delayed *
        $signed({1'b0, fm_lfo_pitch_depth}) *
        $signed({1'b0, patch_pitch_sensitivity});
    // The physical MOD strip remains useful even when the loaded DX7 voice
    // has PMS=0.  Its fixed scale is close to DX7 sensitivity setting 5.
    wire signed [25:0] lfo_manual_pitch_product = lfo_value_delayed *
        $signed({1'b0, vibrato_depth}) * 8'sd92;
    wire signed [27:0] lfo_pitch_product =
        $signed({lfo_patch_pitch_product[26], lfo_patch_pitch_product}) +
        $signed({{2{lfo_manual_pitch_product[25]}}, lfo_manual_pitch_product});
    wire signed [11:0] lfo_pitch_index_wide = lfo_pitch_product >>> 16;
    wire signed [9:0] lfo_pitch_index = lfo_pitch_index_wide[9:0];
    wire signed [10:0] pitch_index_combined =
        $signed({2'b00, pitch_bend[13:5]}) + lfo_pitch_index;
    wire [8:0] pitch_table_address = (pitch_index_combined < 0) ? 9'd0 :
        (pitch_index_combined > 11'sd511) ? 9'd511 : pitch_index_combined[8:0];
    reg [16:0] global_pitch_ratio;

    // Operator issue combinational path.
    wire [9:0] issue_slot_wide = scheduler_voice * 6 + scheduler_operator;
    assign operator_state_read_address = issue_slot_wide[6:0];
    wire [7:0] issue_flags = patch_algorithm_flags[scheduler_operator];
    wire [1:0] issue_input_bus = issue_flags[5:4];
    wire signed [31:0] issue_bus_value =
        (issue_input_bus == 2'd1) ? voice_bus_one[scheduler_voice] :
        (issue_input_bus == 2'd2) ? voice_bus_two[scheduler_voice] : 32'sd0;
    wire signed [28:0] issue_feedback_sum =
        $signed({voice_feedback_old[scheduler_voice][27],
                 voice_feedback_old[scheduler_voice]}) +
        $signed({voice_feedback_new[scheduler_voice][27],
                 voice_feedback_new[scheduler_voice]});
    wire signed [28:0] issue_feedback_shifted =
        issue_feedback_sum >>> (4'd9 - fm_feedback);
    wire signed [31:0] issue_feedback_value = (fm_feedback == 0)
        ? 32'sd0
        : $signed({{3{issue_feedback_shifted[28]}}, issue_feedback_shifted}) <<< 8;
    wire signed [32:0] issue_modulation_sum =
        $signed({issue_bus_value[31], issue_bus_value}) +
        ((issue_flags[7:6] == 2'b11)
         ? $signed({issue_feedback_value[31], issue_feedback_value}) : 33'sd0);

    wire [31:0] render_phase = operator_state_read_data[107:76];
    wire [31:0] render_increment = operator_state_read_data[75:44];
    wire [25:0] render_env_current = operator_state_read_data[43:18];
    wire signed [15:0] render_level_offset =
        $signed(operator_state_read_data[17:2]);
    wire [1:0] render_env_stage_stored = operator_state_read_data[1:0];
    wire [1:0] render_env_stage = voice_gate[operator_read_voice]
        ? render_env_stage_stored : 2'd3;
    // DX7 fixed-frequency operators ignore the voice pitch EG and patch LFO.
    // Applying those ratios made percussion/noise/effect voices wander in
    // pitch and was one of the main reasons a few cartridges sounded nothing
    // like their Dexed counterpart.  Ratio-mode operators retain the complete
    // pitch path. (Pitch bend for fixed operators is a documented remaining
    // approximation; keeping their programmed frequency is much closer than
    // applying the whole modulation path.)
    wire [52:0] issue_global_pitch_product = render_increment *
        voice_combined_pitch_ratio[operator_read_voice];
    // Put the fixed/ratio selection after the multiplier.  Besides matching
    // the intended behavior, this keeps a mux out of the DSP input path and
    // preserves the small but important margin over the 50 MHz constraint.
    wire [36:0] issue_frequency_wide =
        patch_op_fixed[operator_read_operator]
        ? {5'd0, render_increment} : issue_global_pitch_product[52:16];
    wire [31:0] issue_frequency = |issue_frequency_wide[36:32]
        ? 32'hffffffff : issue_frequency_wide[31:0];
    wire [31:0] issue_phase_modulated = render_phase +
        operator_read_modulation[31:0];
    wire [1:0] issue_quadrant = issue_phase_modulated[31:30];
    wire [8:0] issue_quarter_index = issue_phase_modulated[29:21];
    wire [8:0] issue_sine_address = issue_quadrant[0]
        ? (9'd511 - issue_quarter_index) : issue_quarter_index;
    wire [10:0] issue_sine_fraction = issue_phase_modulated[20:10];

    wire [4:0] issue_eg_patch_index = operator_read_operator * 4 + render_env_stage;
    wire signed [17:0] issue_env_target_integer_wide =
        $signed({1'b0, patch_eg_level[issue_eg_patch_index]}) +
        $signed(render_level_offset);
    wire [11:0] issue_env_target_integer =
        (issue_env_target_integer_wide < 18'sd16) ? 12'd16 :
        (issue_env_target_integer_wide > 18'sd4095) ? 12'd4095 :
        issue_env_target_integer_wide[11:0];
    wire [25:0] issue_env_target = {issue_env_target_integer, 14'd0};

    // DX7 rate scaling raises qrate by up to 27 counts at high notes.  Four
    // qrate counts double the logarithmic envelope speed.
    wire [6:0] issue_note_third = voice_note[operator_read_voice] / 3;
    wire [4:0] issue_rate_group = (issue_note_third > 7'd7)
        ? ((issue_note_third - 7'd7 > 7'd31)
           ? 5'd31 : issue_note_third - 7'd7) : 5'd0;
    wire [7:0] issue_rate_scale_product = issue_rate_group *
        patch_rate_scaling[operator_read_operator];
    wire [5:0] issue_rate_scale_delta = issue_rate_scale_product >> 3;
    wire [6:0] issue_qrate_sum = patch_eg_qrate[issue_eg_patch_index] +
        issue_rate_scale_delta;
    wire [5:0] issue_qrate = issue_qrate_sum > 7'd63
        ? 6'd63 : issue_qrate_sum[5:0];
    wire [23:0] issue_env_step = dx7_eg_block_step[issue_qrate];
    wire [23:0] issue_amp_lfo_fade_product = lfo_amp_base * lfo_fade;
    wire [7:0] issue_amp_lfo_depth = issue_amp_lfo_fade_product[23:16];
    wire [6:0] issue_amp_lfo_depth_clamped =
        (issue_amp_lfo_depth > 8'd99) ? 7'd99 : issue_amp_lfo_depth[6:0];
    wire [8:0] issue_ams_address =
        {patch_amp_mod_sensitivity[operator_read_operator],
         issue_amp_lfo_depth_clamped};
    wire [15:0] issue_ams_attenuation =
        dx7_ams_attenuation_q15[issue_ams_address];
    // The LFO/AMS depth is sampled when the next 64-sample gain endpoint is
    // calculated. Dexed interpolates that endpoint through the whole block.

    // Envelope/frequency pre-pipeline.  The first implementation performed
    // coefficient selection, multiplication, add, saturation and state-RAM
    // write selection in one cycle.  Registering the multiplier outputs here
    // cuts that critical path while still accepting one operator every clock.
    reg        e0_valid;
    reg [VOICE_BITS-1:0] e0_voice;
    reg [2:0] e0_operator;
    reg [7:0] e0_flags;
    reg [8:0] e0_sine_address;
    reg [10:0] e0_sine_fraction;
    reg       e0_sine_reverse;
    reg       e0_sine_negative;
    reg       e0_block_start;
    reg [15:0] e0_ams_attenuation;
    reg [47:0] e0_gain_state;
    reg       e0_enabled;
    reg [31:0] e0_phase;
    reg [31:0] e0_increment;
    reg [31:0] e0_frequency;
    reg [25:0] e0_env_current;
    reg [25:0] e0_env_target;
    reg [1:0] e0_env_stage;
    reg [23:0] e0_env_step;
    reg signed [15:0] e0_level_offset;

    wire e0_env_rising = e0_env_target > e0_env_current;
    wire [25:0] e0_attack_origin = (e0_env_current < (26'd1716 << 14))
        ? (26'd1716 << 14) : e0_env_current;
    // Dexed computes ((17 << 24) - level_q16) >> 24, i.e. floor of
    // 17 - level/256. For a fractional level this is 16-floor(level/256),
    // not 17-floor(level/256). The old expression made every attack block
    // about one rate unit too fast except at exact multiples of 256.
    wire [4:0] e0_attack_factor_raw =
        5'd16 - e0_attack_origin[25:22] +
        (e0_attack_origin[21:0] == 22'd0);
    wire [4:0] e0_attack_factor = (e0_attack_factor_raw == 0)
        ? 5'd1 : e0_attack_factor_raw;
    wire [28:0] e0_attack_step = e0_env_step * e0_attack_factor;
    wire [29:0] e0_env_rise_wide = {4'b0, e0_attack_origin} +
        {1'b0, e0_attack_step};
    wire [26:0] e0_env_fall_wide = {1'b0, e0_env_current} - e0_env_step;
    wire e0_rise_reached =
        (e0_env_rise_wide >= {4'b0, e0_env_target});
    wire e0_fall_reached =
        ({1'b0, e0_env_current} <= {1'b0, e0_env_target} +
                                     {3'b0, e0_env_step});
    wire [25:0] e0_env_next = !e0_block_start
        ? e0_env_current
        : e0_env_rising
        ? (e0_rise_reached
           ? e0_env_target : e0_env_rise_wide[25:0])
        : (e0_fall_reached
           ? e0_env_target : e0_env_fall_wide[25:0]);
    // Decide stage completion from the same pre-saturation comparisons. A
    // second compare after the envelope mux was the 50 MHz critical path.
    wire e0_env_reached = e0_env_rising
        ? e0_rise_reached : e0_fall_reached;
    wire [1:0] e0_env_stage_next = (e0_block_start && e0_env_reached)
        ? ((e0_env_stage < 2) ? e0_env_stage + 1'b1 :
           (!voice_gate[e0_voice] ? 2'd3 : e0_env_stage))
        : e0_env_stage;
    // Register the advanced EG level before multiplying by the nonlinear AMS
    // attenuation. This extra pipeline stage keeps the 25K's 50 MHz path from
    // spanning both EG arithmetic and the multiplier in the same clock.
    reg        a0_valid;
    reg [VOICE_BITS-1:0] a0_voice;
    reg [2:0] a0_operator;
    reg [7:0] a0_flags;
    reg [8:0] a0_sine_address;
    reg [10:0] a0_sine_fraction;
    reg       a0_sine_reverse;
    reg       a0_sine_negative;
    reg [31:0] a0_phase_next;
    reg [31:0] a0_increment;
    reg [25:0] a0_env_next;
    reg signed [15:0] a0_level_offset;
    reg [1:0] a0_env_stage_next;
    reg [15:0] a0_ams_attenuation;
    reg [47:0] a0_gain_state;
    reg       a0_block_start;
    reg       a0_enabled;
    // Keep this second register boundary even if the fitter uses the next
    // stage's DSP input registers: a0_env_next also feeds state writeback.
    reg        b0_valid;
    reg [VOICE_BITS-1:0] b0_voice;
    reg [2:0] b0_operator;
    reg [7:0] b0_flags;
    reg [8:0] b0_sine_address;
    reg [10:0] b0_sine_fraction;
    reg       b0_sine_reverse;
    reg       b0_sine_negative;
    reg [11:0] b0_env_integer;
    reg [15:0] b0_ams_attenuation;
    reg [47:0] b0_gain_state;
    reg       b0_block_start;
    reg       b0_enabled;
    wire [15:0] b0_ams_retained_q15 = 16'd32768 - b0_ams_attenuation;
    wire [27:0] b0_ams_level_product =
        b0_env_integer * b0_ams_retained_q15;
    wire [11:0] b0_gain_level_index = b0_ams_level_product[26:15];

    // Six-stage operator pipeline. The shared AMS multiplier is not copied
    // per voice; a voice's next operator is issued after this pipeline drains.
    reg        p0_valid;
    reg [VOICE_BITS-1:0] p0_voice;
    reg [2:0] p0_operator;
    reg [7:0] p0_flags;
    reg [8:0] p0_sine_address;
    reg [10:0] p0_sine_fraction;
    reg       p0_sine_reverse;
    reg       p0_sine_negative;
    reg [11:0] p0_gain_index;
    reg [47:0] p0_gain_state;
    reg        p0_block_start;
    reg        p0_enabled;

    reg        p1_valid;
    reg [VOICE_BITS-1:0] p1_voice;
    reg [2:0] p1_operator;
    reg [7:0] p1_flags;
    reg [15:0] p1_sine_base;
    reg [7:0] p1_sine_delta;
    reg [10:0] p1_sine_fraction;
    reg       p1_sine_reverse;
    reg       p1_sine_negative;
    reg [16:0] p1_envelope;
    reg [47:0] p1_gain_state;
    reg        p1_block_start;
    reg        p1_enabled;

    wire [16:0] p1_old_gain_target = p1_gain_state[47:31];
    wire signed [12:0] p1_old_gain_step = $signed(p1_gain_state[30:18]);
    wire signed [17:0] p1_old_gain_current = $signed(p1_gain_state[17:0]);
    wire signed [18:0] p1_gain_difference =
        $signed({2'b00, p1_envelope}) -
        $signed({2'b00, p1_old_gain_target});
    wire signed [18:0] p1_rounded_gain_step =
        (p1_gain_difference + 19'sd32) >>> 6;
    wire signed [12:0] p1_gain_step = p1_block_start
        ? p1_rounded_gain_step[12:0] : p1_old_gain_step;
    wire signed [17:0] p1_gain_start = p1_block_start
        ? $signed({1'b0, p1_old_gain_target}) : p1_old_gain_current;
    wire signed [18:0] p1_gain_sum =
        $signed({p1_gain_start[17], p1_gain_start}) +
        $signed({{6{p1_gain_step[12]}}, p1_gain_step});
    wire signed [17:0] p1_gain_next = p1_gain_sum[17:0];
    wire [16:0] p1_gain_target_next = p1_block_start
        ? p1_envelope : p1_old_gain_target;
    always @(posedge clk) begin
        if (engine_state == ENGINE_EVENT_GAIN_CAPTURE)
            operator_gain_state_memory[event_target_voice * 6 +
                                       event_init_operator] <= 48'd0;
        else if (p1_valid)
            operator_gain_state_memory[p1_voice * 6 + p1_operator] <= {
                p1_gain_target_next, p1_gain_step, p1_gain_next
            };
    end

    reg        p2_valid;
    reg [VOICE_BITS-1:0] p2_voice;
    reg [2:0] p2_operator;
    reg [7:0] p2_flags;
    reg signed [16:0] p2_sine;
    reg signed [17:0] p2_gain;
    reg        p2_enabled;

    wire [18:0] p1_sine_delta_product =
        p1_sine_delta * p1_sine_fraction;
    wire [7:0] p1_sine_delta_step = p1_sine_delta_product[18:11];
    wire [16:0] p1_sine_rising_value =
        {1'b0, p1_sine_base} + {9'd0, p1_sine_delta_step};
    wire [16:0] p1_sine_falling_value =
        {1'b0, p1_sine_base} + {9'd0, p1_sine_delta} -
        {9'd0, p1_sine_delta_step};
    wire [16:0] p1_sine_magnitude = p1_sine_reverse
        ? p1_sine_falling_value : p1_sine_rising_value;
    wire signed [16:0] p1_sine_interpolated = p1_sine_negative
        ? -$signed(p1_sine_magnitude) : $signed(p1_sine_magnitude);

    reg        p3_valid;
    reg [VOICE_BITS-1:0] p3_voice;
    reg [2:0] p3_operator;
    reg [7:0] p3_flags;
    reg signed [34:0] p3_sample_product;
    reg signed [17:0] p3_envelope;
    reg        p3_enabled;

    wire signed [34:0] p3_operator_sample_wide = p3_sample_product >>> 16;
    wire signed [31:0] p3_operator_sample = p3_enabled
        ? p3_operator_sample_wide[31:0] : 32'sd0;
    // In Dexed, internal level 3840 produces gain 2.0 in a phase domain where
    // one cycle is 2^24.  Our sine is Q15 and phase is Q0.32, hence <<18.
    // The previous <<17 mapping halved every modulation index and audibly
    // removed upper sidebands (the characteristic "dark FPGA" error).
    wire signed [31:0] p3_modulation_value = p3_operator_sample <<< 18;

    wire pipeline_busy = e0_valid | a0_valid | b0_valid |
                         p0_valid | p1_valid |
                         p2_valid | p3_valid |
                         operator_read_pending | operator_state_write_valid;

    // Pitch envelope is linear in Yamaha's logarithmic pitch domain, matching
    // PitchEnv::getsample in msfa/Dexed. The former one-pole ratio mover slowed
    // down near every target and gave exaggerated bends on wide intervals.
    wire [2:0] prep_pitch_index = voice_pitch_stage[scheduler_voice];
    wire signed [22:0] prep_pitch_target = patch_pitch_target[prep_pitch_index];
    wire signed [23:0] prep_pitch_delta_input =
        $signed(prep_pitch_target) -
        $signed(voice_pitch_level[scheduler_voice]);
    reg [VOICE_BITS-1:0] prep_voice_latched;
    reg prep_active_latched;
    reg prep_gate_latched;
    reg [1:0] prep_stage_latched;
    reg signed [22:0] prep_current_latched;
    reg signed [22:0] prep_target_latched;
    reg signed [23:0] prep_delta_latched;
    reg [7:0] prep_step_latched;
    reg signed [22:0] prep_level_resolved;
    reg [17:0] prep_fraction_ratio_latched;
    wire signed [23:0] prep_signed_step = prep_delta_latched[23]
        ? -$signed({1'b0, prep_step_latched})
        :  $signed({1'b0, prep_step_latched});
    wire signed [23:0] prep_next_wide =
        $signed(prep_current_latched) + prep_signed_step;
    wire signed [22:0] prep_next =
        (prep_delta_latched >= 0 &&
         prep_next_wide >= $signed(prep_target_latched))
        ? prep_target_latched :
        (prep_delta_latched < 0 &&
         prep_next_wide <= $signed(prep_target_latched))
        ? prep_target_latched : prep_next_wide[22:0];
    wire signed [10:0] prep_pitch_eighth = prep_level_resolved >>> 12;
    wire signed [3:0] prep_pitch_octave = prep_pitch_eighth >>> 8;
    reg [20:0] prep_pitch_ratio_resolved;
    always @* begin
        case (prep_pitch_octave)
            -4: prep_pitch_ratio_resolved = prep_fraction_ratio_latched >> 4;
            -3: prep_pitch_ratio_resolved = prep_fraction_ratio_latched >> 3;
            -2: prep_pitch_ratio_resolved = prep_fraction_ratio_latched >> 2;
            -1: prep_pitch_ratio_resolved = prep_fraction_ratio_latched >> 1;
             0: prep_pitch_ratio_resolved = prep_fraction_ratio_latched;
             1: prep_pitch_ratio_resolved = prep_fraction_ratio_latched << 1;
             2: prep_pitch_ratio_resolved = prep_fraction_ratio_latched << 2;
            default: prep_pitch_ratio_resolved = prep_fraction_ratio_latched << 3;
        endcase
    end
    wire [37:0] prep_combined_product = prep_pitch_ratio_resolved * global_pitch_ratio;
    wire [20:0] prep_combined_ratio = |prep_combined_product[37]
        ? 21'h1fffff : prep_combined_product[36:16];

    wire [6:0] event_transposed_note = transpose_note(event_note, fm_transpose);
    wire [63:0] event_frequency_product =
        event_note_increment_latched * event_patch_frequency_latched;
    wire [31:0] event_operator_increment = event_patch_fixed_latched
        ? event_patch_frequency_latched : event_frequency_product[47:16];
    wire signed [8:0] event_velocity_curve_signed =
        $signed({1'b0, dx7_velocity_curve[event_velocity[6:1]]}) - 9'sd239;
    wire signed [12:0] event_velocity_product = event_velocity_curve_signed *
        $signed({1'b0, patch_velocity_sensitivity[event_init_operator]});
    wire signed [15:0] event_velocity_delta =
        (($signed(event_velocity_product) + 13'sd7) >>> 3) <<< 4;
    wire signed [8:0] event_scale_note_offset =
        $signed({2'b00, event_note}) -
        $signed({2'b00, patch_breakpoint[event_init_operator]}) - 9'sd17;
    wire event_scale_right = !event_scale_note_offset[8];
    wire [8:0] event_scale_distance = event_scale_right
        ? event_scale_note_offset : -event_scale_note_offset;
    wire [8:0] event_scale_group_raw = (event_scale_distance + 1'b1) / 3;
    wire [5:0] event_scale_group_wire = (event_scale_group_raw > 32)
        ? 6'd32 : event_scale_group_raw[5:0];
    wire [6:0] event_scale_depth_wire = event_scale_right
        ? patch_right_depth[event_init_operator]
        : patch_left_depth[event_init_operator];
    wire [1:0] event_scale_curve_wire = event_scale_right
        ? patch_right_curve[event_init_operator]
        : patch_left_curve[event_init_operator];
    wire [7:0] event_scale_source =
        ((event_scale_curve == 0) || (event_scale_curve == 3))
        ? {2'd0, event_scale_group} : dx7_exp_scale(event_scale_group);
    wire [23:0] event_scale_times_329 =
        ({9'd0, event_scale_product} << 8) +
        ({9'd0, event_scale_product} << 6) +
        ({9'd0, event_scale_product} << 3) +
        event_scale_product;
    wire [8:0] event_scaled_amount =
        ((event_scale_curve == 0) || (event_scale_curve == 3))
        ? event_scale_times_329[20:12] : event_scale_times_329[23:15];
    wire signed [9:0] event_scaled_signed = (event_scale_curve < 2)
        ? -$signed({1'b0, event_scale_magnitude})
        :  $signed({1'b0, event_scale_magnitude});
    wire signed [10:0] event_output_level_wide =
        $signed({1'b0, event_scale_base_level}) + event_scaled_signed;
    wire [7:0] event_output_level_clamped = event_output_level_wide < 0
        ? 8'd0 : (event_output_level_wide > 127 ? 8'd127
                                               : event_output_level_wide[7:0]);
    wire signed [16:0] event_level_offset_final =
        ($signed({1'b0, event_output_level_clamped}) <<< 5) - 17'sd4256 +
        event_velocity_delta;

    always @* begin
        active_voice_count = 5'd0;
        for (count_index = 0; count_index < VOICE_COUNT;
             count_index = count_index + 1)
            if (voice_active[count_index])
                active_voice_count = active_voice_count + 1'b1;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            engine_state <= ENGINE_IDLE;
            event_pending <= 1'b0;
            pending_event <= 32'd0;
            pending_brightness <= 7'd0;
            sample_pending <= 1'b0;
            scheduler_voice <= {VOICE_BITS{1'b0}};
            scheduler_operator <= 3'd0;
            mix_voice <= {VOICE_BITS{1'b0}};
            mix_accumulator <= 40'sd0;
            event_scan_voice <= {VOICE_BITS{1'b0}};
            event_target_voice <= {VOICE_BITS{1'b0}};
            event_init_operator <= 3'd0;
            event_free_found <= 1'b0;
            event_free_voice <= {VOICE_BITS{1'b0}};
            event_oldest_age <= 24'd0;
            event_oldest_voice <= {VOICE_BITS{1'b0}};
            event_note <= 7'd60;
            event_velocity <= 7'd100;
            event_scale_group <= 0;
            event_scale_depth <= 0;
            event_scale_curve <= 0;
            event_scale_base_level <= 0;
            event_scale_product <= 0;
            event_scale_magnitude <= 0;
            event_level_offset_latched <= -16'sd192;
            event_detune_address <= 11'd0;
            event_note_increment_latched <= 32'd0;
            event_patch_frequency_latched <= 32'd0;
            event_patch_fixed_latched <= 1'b0;
            event_base_increment <= 32'd0;
            event_corrected_increment <= 32'd0;
            prep_voice_latched <= 0;
            prep_active_latched <= 1'b0;
            prep_gate_latched <= 1'b0;
            prep_stage_latched <= 2'd0;
            prep_current_latched <= 23'sd0;
            prep_target_latched <= 23'sd0;
            prep_delta_latched <= 24'sd0;
            prep_step_latched <= 8'd1;
            prep_level_resolved <= 23'sd0;
            prep_fraction_ratio_latched <= 18'h10000;
            sample_out <= 16'sd0;
            lfo_phase <= 32'd0;
            lfo_delay_state <= 32'hffffffff;
            lfo_delay_block_sample <= 6'd0;
            lfo_fade <= 8'hff;
            lfo_value_delayed <= 9'sd0;
            lfo_sample_hold <= 8'sd0;
            lfsr <= 16'h1ace;
            lfo_amp_base <= 16'd0;
            global_pitch_ratio <= 17'h10000;
            master_volume_target <= 7'd96;
            master_volume_current <= 7'd96;
            sustain_active <= 1'b0;
            allocation_cursor <= {VOICE_BITS{1'b0}};
            display_voice <= {VOICE_BITS{1'b0}};
            operator_envelope_levels <= 48'd0;
            voice_carrier_alive <= {VOICE_COUNT{1'b0}};
            a0_valid <= 1'b0;
            b0_valid <= 1'b0;
            p0_valid <= 1'b0;
            p1_valid <= 1'b0;
            p2_valid <= 1'b0;
            p3_valid <= 1'b0;
            a0_voice <= 0; a0_operator <= 0; a0_flags <= 0;
            a0_sine_address <= 0; a0_sine_fraction <= 0;
            a0_sine_reverse <= 0; a0_sine_negative <= 0;
            a0_ams_attenuation <= 0;
            a0_phase_next <= 0; a0_increment <= 0;
            a0_env_next <= 0; a0_level_offset <= 0;
            a0_env_stage_next <= 0;
            a0_gain_state <= 0; a0_block_start <= 1'b0;
            a0_enabled <= 0;
            b0_voice <= 0; b0_operator <= 0; b0_flags <= 0;
            b0_sine_address <= 0; b0_sine_fraction <= 0;
            b0_sine_reverse <= 0; b0_sine_negative <= 0;
            b0_env_integer <= 0; b0_ams_attenuation <= 0;
            b0_gain_state <= 0; b0_block_start <= 1'b0;
            b0_enabled <= 0;
            p0_voice <= 0; p0_operator <= 0; p0_flags <= 0;
            p0_sine_address <= 0; p0_sine_fraction <= 0;
            p0_sine_reverse <= 0; p0_sine_negative <= 0;
            p0_gain_index <= 0; p0_gain_state <= 0;
            p0_block_start <= 1'b0; p0_enabled <= 0;
            p1_voice <= 0; p1_operator <= 0; p1_flags <= 0;
            p1_sine_base <= 0; p1_sine_delta <= 0;
            p1_sine_fraction <= 0; p1_sine_reverse <= 0;
            p1_sine_negative <= 0;
            p1_envelope <= 0; p1_gain_state <= 0;
            p1_block_start <= 1'b0; p1_enabled <= 0;
            p2_voice <= 0; p2_operator <= 0; p2_flags <= 0; p2_sine <= 0;
            p2_gain <= 0; p2_enabled <= 0;
            p3_voice <= 0; p3_operator <= 0; p3_flags <= 0;
            p3_sample_product <= 0; p3_envelope <= 0; p3_enabled <= 0;
            e0_valid <= 1'b0;
            e0_voice <= 0; e0_operator <= 0; e0_flags <= 0;
            e0_sine_address <= 0; e0_sine_fraction <= 0;
            e0_sine_reverse <= 0; e0_sine_negative <= 0;
            e0_block_start <= 1'b0; e0_ams_attenuation <= 0;
            e0_gain_state <= 0; e0_enabled <= 0;
            e0_phase <= 0; e0_increment <= 0; e0_frequency <= 0;
            e0_env_current <= 0; e0_env_target <= 0; e0_env_stage <= 0;
            e0_env_step <= 0; e0_level_offset <= 0;
            operator_state_write_valid <= 1'b0;
            operator_state_write_address <= 7'd0;
            operator_state_write_data <= 108'd0;
            operator_read_pending <= 1'b0;
            operator_read_voice <= 0;
            operator_read_operator <= 0;
            operator_read_flags <= 0;
            operator_read_modulation <= 0;

            // Default electric-piano patch. Operators are OP6..OP1.
            for (init_index = 0; init_index < 6; init_index = init_index + 1) begin
                patch_op_enable[init_index] <= 1'b1;
                patch_op_fixed[init_index] <= 1'b0;
                patch_op_frequency[init_index] <= 32'h00010000;
                patch_op_detune[init_index] <= 4'd7;
                patch_op_gain[init_index] <= (init_index[0]) ? 16'd72 : 16'd95;
                patch_rate_scaling[init_index] <= 3'd2;
                patch_velocity_sensitivity[init_index] <= 3'd3;
                patch_amp_mod_sensitivity[init_index] <= 2'd0;
                patch_breakpoint[init_index] <= 7'd60;
                patch_left_depth[init_index] <= 7'd0;
                patch_right_depth[init_index] <= 7'd20;
                patch_left_curve[init_index] <= 2'd0;
                patch_right_curve[init_index] <= 2'd0;
            end
            patch_op_frequency[0] <= 32'h000e0000;
            patch_op_frequency[1] <= 32'h00010000;
            patch_op_frequency[2] <= 32'h00030000;
            patch_op_frequency[3] <= 32'h00010000;
            patch_op_frequency[4] <= 32'h00020000;
            patch_op_frequency[5] <= 32'h00010000;
            patch_algorithm_flags[0] <= 8'hc1;
            patch_algorithm_flags[1] <= 8'h14;
            patch_algorithm_flags[2] <= 8'h01;
            patch_algorithm_flags[3] <= 8'h14;
            patch_algorithm_flags[4] <= 8'h01;
            patch_algorithm_flags[5] <= 8'h14;
            for (init_index = 0; init_index < 24; init_index = init_index + 1) begin
                case (init_index[1:0])
                    2'd0: begin patch_eg_qrate[init_index] <= 6'd63; patch_eg_level[init_index] <= 16'd4032; end
                    2'd1: begin patch_eg_qrate[init_index] <= 6'd36; patch_eg_level[init_index] <= 16'd3008; end
                    2'd2: begin patch_eg_qrate[init_index] <= 6'd20; patch_eg_level[init_index] <= 16'd2496; end
                    default: begin patch_eg_qrate[init_index] <= 6'd36; patch_eg_level[init_index] <= 16'd0; end
                endcase
            end
            for (init_index = 0; init_index < 4; init_index = init_index + 1) begin
                patch_pitch_step[init_index] <= 8'd1;
                patch_pitch_target[init_index] <= 23'sd0;
            end
            for (init_index = 0; init_index < VOICE_COUNT; init_index = init_index + 1) begin
                voice_active[init_index] <= 1'b0;
                voice_gate[init_index] <= 1'b0;
                voice_key_down[init_index] <= 1'b0;
                voice_note[init_index] <= 7'd0;
                voice_velocity[init_index] <= 7'd0;
                voice_age[init_index] <= 24'd0;
                voice_eg_block_position[init_index] <= 6'd0;
                voice_pitch_level[init_index] <= 23'sd0;
                voice_combined_pitch_ratio[init_index] <= 21'h10000;
                voice_pitch_stage[init_index] <= 2'd0;
                voice_feedback_old[init_index] <= 28'sd0;
                voice_feedback_new[init_index] <= 28'sd0;
                voice_bus_one[init_index] <= 32'sd0;
                voice_bus_two[init_index] <= 32'sd0;
                voice_output[init_index] <= 32'sd0;
            end
        end else begin
            operator_state_write_valid <= 1'b0;
            operator_read_pending <= 1'b0;
            // Runtime patch writes are intentionally narrow and deterministic.
            if (fm_operator_write_valid && fm_operator_index < 6) begin
                patch_op_enable[fm_operator_index] <= fm_operator_enable;
                patch_op_fixed[fm_operator_index] <= fm_operator_fixed;
                patch_op_frequency[fm_operator_index] <= fm_operator_frequency;
                patch_op_detune[fm_operator_index] <=
                    (fm_operator_detune > 4'd14) ? 4'd14 : fm_operator_detune;
                patch_op_gain[fm_operator_index] <= fm_operator_output_gain;
            end
            if (fm_envelope_write_valid && fm_envelope_operator < 6) begin
                patch_eg_qrate[fm_envelope_operator * 4 + fm_envelope_stage]
                    <= fm_envelope_coefficient[5:0];
                patch_eg_level[fm_envelope_operator * 4 + fm_envelope_stage]
                    <= fm_envelope_level;
                // Rate scaling / velocity sensitivity / AMS belong to the
                // envelope command.  They used to be re-latched by the scaling
                // command, which silently copied the previous operator's
                // values whenever only 0x64 was sent.
                patch_rate_scaling[fm_envelope_operator] <= fm_rate_scaling;
                patch_velocity_sensitivity[fm_envelope_operator]
                    <= fm_velocity_sensitivity;
                patch_amp_mod_sensitivity[fm_envelope_operator]
                    <= fm_amp_mod_sensitivity;
            end
            if (fm_scaling_write_valid && fm_scaling_operator < 6) begin
                patch_breakpoint[fm_scaling_operator] <= fm_scaling_breakpoint;
                patch_left_depth[fm_scaling_operator] <= fm_scaling_left_depth;
                patch_right_depth[fm_scaling_operator] <= fm_scaling_right_depth;
                patch_left_curve[fm_scaling_operator] <= fm_scaling_left_curve;
                patch_right_curve[fm_scaling_operator] <= fm_scaling_right_curve;
            end
            if (fm_pitch_envelope_write_valid) begin
                patch_pitch_step[fm_pitch_envelope_stage]
                    <= fm_pitch_envelope_coefficient[7:0];
                patch_pitch_target[fm_pitch_envelope_stage]
                    <= $signed(fm_pitch_envelope_ratio);
            end
            if (fm_algorithm_flags_write_valid) begin
                patch_algorithm_flags[0] <= fm_algorithm_flags[7:0];
                patch_algorithm_flags[1] <= fm_algorithm_flags[15:8];
                patch_algorithm_flags[2] <= fm_algorithm_flags[23:16];
                patch_algorithm_flags[3] <= fm_algorithm_flags[31:24];
                patch_algorithm_flags[4] <= fm_algorithm_flags[39:32];
                patch_algorithm_flags[5] <= fm_algorithm_flags[47:40];
            end
            if (fm_patch_commit) begin
                // Avoid a half-old/half-new timbre. The editor also sends All
                // Notes Off, but this local guard covers interrupted transfers.
                for (i = 0; i < VOICE_COUNT; i = i + 1) begin
                    voice_active[i] <= 1'b0;
                    voice_gate[i] <= 1'b0;
                    voice_key_down[i] <= 1'b0;
                end
            end

            if (sample_tick) begin
                sample_pending <= 1'b1;
                lfo_phase <= lfo_phase + lfo_phase_increment;
                lfo_value_delayed <= lfo_value_delayed_product >>> 8;
                if (lfo_delay_block_sample == 6'd63) begin
                    lfo_delay_block_sample <= 6'd0;
                    lfo_delay_state <= lfo_delay_advance[32]
                        ? 32'hffffffff : lfo_delay_advance[31:0];
                    lfo_fade <= lfo_delay_advance_fade;
                end else begin
                    lfo_delay_block_sample <= lfo_delay_block_sample + 1'b1;
                end
                lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
                if (&lfo_phase[31:24]) lfo_sample_hold <= lfsr[7:0];
                lfo_amp_base <= lfo_amp_unipolar * fm_lfo_amp_depth;
                global_pitch_ratio <= pitch_ratio_table[pitch_table_address];
                if (master_volume_current < master_volume_target)
                    master_volume_current <= master_volume_current + 1'b1;
                else if (master_volume_current > master_volume_target)
                    master_volume_current <= master_volume_current - 1'b1;
            end

            if (midi_event_valid && midi_event_ready) begin
                pending_event <= midi_event_data;
                pending_brightness <= midi_event_brightness;
                event_pending <= 1'b1;
            end

            // Pipeline stage movement and final algorithm-bus routing.
            p1_valid <= p0_valid;
            p1_voice <= p0_voice;
            p1_operator <= p0_operator;
            p1_flags <= p0_flags;
            p1_sine_base <= sine_quarter_delta[p0_sine_address][23:8];
            p1_sine_delta <= sine_quarter_delta[p0_sine_address][7:0];
            p1_sine_fraction <= p0_sine_fraction;
            p1_sine_reverse <= p0_sine_reverse;
            p1_sine_negative <= p0_sine_negative;
            p1_envelope <= dx7_level_gain[p0_gain_index];
            p1_gain_state <= p0_gain_state;
            p1_block_start <= p0_block_start;
            p1_enabled <= p0_enabled;
            p2_valid <= p1_valid;
            p2_voice <= p1_voice;
            p2_operator <= p1_operator;
            p2_flags <= p1_flags;
            p2_sine <= p1_sine_interpolated;
            p2_gain <= p1_gain_next;
            p2_enabled <= p1_enabled;
            p3_valid <= p2_valid;
            p3_voice <= p2_voice;
            p3_operator <= p2_operator;
            p3_flags <= p2_flags;
            p3_sample_product <= p2_sine * p2_gain;
            p3_envelope <= p2_gain;
            p3_enabled <= p2_enabled;
            if (p3_valid) begin
                case (p3_flags[1:0])
                    2'd1: begin
                        if (p3_flags[2])
                            voice_bus_one[p3_voice] <= voice_bus_one[p3_voice] +
                                                       p3_modulation_value;
                        else voice_bus_one[p3_voice] <= p3_modulation_value;
                    end
                    2'd2: begin
                        if (p3_flags[2])
                            voice_bus_two[p3_voice] <= voice_bus_two[p3_voice] +
                                                       p3_modulation_value;
                        else voice_bus_two[p3_voice] <= p3_modulation_value;
                    end
                    default: voice_output[p3_voice] <= voice_output[p3_voice] +
                                                              p3_operator_sample;
                endcase
                if (p3_flags[7:6] == 2'b11) begin
                    voice_feedback_old[p3_voice] <= voice_feedback_new[p3_voice];
                    // Dexed stores two signed post-gain samples before
                    // shifting their sum by 9-feedback. The shared product
                    // is already at the matching Q24 scale after >>>6.
                    voice_feedback_new[p3_voice] <=
                        p3_sample_product >>> 6;
                end
            end
            p0_valid <= b0_valid;
            if (b0_valid) begin
                p0_voice <= b0_voice;
                p0_operator <= b0_operator;
                p0_flags <= b0_flags;
                p0_sine_address <= b0_sine_address;
                p0_sine_fraction <= b0_sine_fraction;
                p0_sine_reverse <= b0_sine_reverse;
                p0_sine_negative <= b0_sine_negative;
                p0_gain_index <= b0_gain_level_index;
                p0_gain_state <= b0_gain_state;
                p0_block_start <= b0_block_start;
                p0_enabled <= b0_enabled;
            end
            b0_valid <= a0_valid;
            if (a0_valid) begin
                b0_voice <= a0_voice;
                b0_operator <= a0_operator;
                b0_flags <= a0_flags;
                b0_sine_address <= a0_sine_address;
                b0_sine_fraction <= a0_sine_fraction;
                b0_sine_reverse <= a0_sine_reverse;
                b0_sine_negative <= a0_sine_negative;
                b0_env_integer <= a0_env_next[25:14];
                b0_ams_attenuation <= a0_ams_attenuation;
                b0_gain_state <= a0_gain_state;
                b0_block_start <= a0_block_start;
                b0_enabled <= a0_enabled;
                operator_state_write_valid <= 1'b1;
                operator_state_write_address <= a0_voice * 6 + a0_operator;
                operator_state_write_data <= pack_operator_state(
                    a0_phase_next,
                    a0_increment,
                    a0_env_next,
                    a0_level_offset,
                    a0_env_stage_next
                );
            end
            a0_valid <= e0_valid;
            if (e0_valid) begin
                a0_voice <= e0_voice;
                a0_operator <= e0_operator;
                a0_flags <= e0_flags;
                a0_sine_address <= e0_sine_address;
                a0_sine_fraction <= e0_sine_fraction;
                a0_sine_reverse <= e0_sine_reverse;
                a0_sine_negative <= e0_sine_negative;
                a0_ams_attenuation <= e0_ams_attenuation;
                a0_gain_state <= e0_gain_state;
                a0_block_start <= e0_block_start;
                a0_enabled <= e0_enabled;
                a0_phase_next <= e0_phase + e0_frequency;
                a0_increment <= e0_increment;
                a0_env_next <= e0_env_next;
                a0_level_offset <= e0_level_offset;
                a0_env_stage_next <= e0_env_stage_next;
                if (e0_voice == display_voice)
                    operator_envelope_levels[e0_operator * 8 +: 8]
                        <= e0_env_next[25:18];
                if ((e0_flags[1:0] == 2'd0) && e0_enabled &&
                    // Retirement only needs the prior sample's carrier
                    // level.  Avoid the 26-bit EG update/comparator on this
                    // clock-enable path; one audio-frame tail is inaudible.
                    (e0_env_current > (26'd32 << 14)))
                    voice_carrier_alive[e0_voice] <= 1'b1;
            end
            e0_valid <= operator_read_pending;
            if (operator_read_pending) begin
                e0_voice <= operator_read_voice;
                e0_operator <= operator_read_operator;
                e0_flags <= operator_read_flags;
                e0_sine_address <= issue_sine_address;
                e0_sine_fraction <= issue_sine_fraction;
                e0_sine_reverse <= issue_quadrant[0];
                e0_sine_negative <= issue_quadrant[1];
                e0_block_start <=
                    (voice_eg_block_position[operator_read_voice] == 6'd1);
                e0_ams_attenuation <= issue_ams_attenuation;
                e0_gain_state <= operator_gain_read_data;
                e0_enabled <= patch_op_enable[operator_read_operator];
                e0_phase <= render_phase;
                e0_increment <= render_increment;
                e0_frequency <= issue_frequency;
                e0_env_current <= render_env_current;
                e0_env_target <= issue_env_target;
                e0_env_stage <= render_env_stage;
                e0_env_step <= issue_env_step;
                e0_level_offset <= render_level_offset;
            end

            case (engine_state)
                ENGINE_IDLE: begin
                    if (event_pending) begin
                        if (((pending_event[23:20] == 4'h9) &&
                             pending_event[6:0] != 0)) begin
                            event_note <= pending_event[14:8];
                            event_velocity <= pending_event[6:0];
                            event_scan_voice <= 0;
                            event_free_found <= 1'b0;
                            event_oldest_age <= 24'd0;
                            event_oldest_voice <= allocation_cursor;
                            engine_state <= ENGINE_EVENT_SCAN;
                            event_pending <= 1'b0;
                        end else begin
                            // Note Off, CC volume/sustain/all-notes-off are
                            // short enough to apply atomically between frames.
                            if ((pending_event[23:20] == 4'h8) ||
                                ((pending_event[23:20] == 4'h9) &&
                                 pending_event[6:0] == 0)) begin
                                for (i = 0; i < VOICE_COUNT; i = i + 1)
                                    if (voice_active[i] &&
                                        voice_note[i] == pending_event[14:8]) begin
                                        voice_key_down[i] <= 1'b0;
                                        if (!sustain_active) begin
                                            voice_gate[i] <= 1'b0;
                                            voice_pitch_stage[i] <= 2'd3;
                                        end
                                    end
                            end else if (pending_event[23:20] == 4'hb) begin
                                if (pending_event[14:8] == 7'd20)
                                    master_volume_target <= pending_event[6:0];
                                if (pending_event[14:8] == 7'd64) begin
                                    sustain_active <= pending_event[6:0] >= 7'd64;
                                    if (pending_event[6:0] < 7'd64)
                                        for (i = 0; i < VOICE_COUNT; i = i + 1)
                                            if (voice_active[i] && !voice_key_down[i]) begin
                                                voice_gate[i] <= 1'b0;
                                                voice_pitch_stage[i] <= 2'd3;
                                            end
                                end
                                if (pending_event[14:8] == 7'd123)
                                    for (i = 0; i < VOICE_COUNT; i = i + 1) begin
                                        voice_gate[i] <= 1'b0;
                                        voice_key_down[i] <= 1'b0;
                                    end
                            end
                            event_pending <= 1'b0;
                        end
                    end else if (sample_pending) begin
                        sample_pending <= 1'b0;
                        scheduler_voice <= 0;
                        engine_state <= ENGINE_CLEAR;
                    end
                end

                ENGINE_EVENT_SCAN: begin
                    if (!voice_active[event_scan_voice] && !event_free_found) begin
                        event_free_found <= 1'b1;
                        event_free_voice <= event_scan_voice;
                    end
                    if (voice_age[event_scan_voice] >= event_oldest_age) begin
                        event_oldest_age <= voice_age[event_scan_voice];
                        event_oldest_voice <= event_scan_voice;
                    end
                    if (event_scan_voice == VOICE_COUNT-1) begin
                        event_target_voice <= event_free_found
                            ? event_free_voice : event_oldest_voice;
                        event_init_operator <= 3'd0;
                        engine_state <= ENGINE_EVENT_INIT;
                    end else event_scan_voice <= event_scan_voice + 1'b1;
                end

                ENGINE_EVENT_INIT: begin
                    // The preset ROM output previously drove a 32x32 multiply
                    // and the base-frequency register in one clock. Capture
                    // its operands first, then use the existing WAIT cycle
                    // for the multiply; event initialization gains no cycles.
                    event_note_increment_latched <=
                        midi_phase_increment[event_transposed_note];
                    event_patch_frequency_latched <=
                        patch_op_frequency[event_init_operator];
                    event_patch_fixed_latched <=
                        patch_op_fixed[event_init_operator];
                    event_detune_address <=
                        (event_transposed_note * 11'd15) +
                        patch_op_detune[event_init_operator];
                    if (event_init_operator == 0) begin
                        // Dexed/msfa keydown() starts the synced LFO half a
                        // cycle before our former zero-phase reset.  The
                        // starting polarity is audible on voices with a
                        // strong pitch or amplitude modulation attack.
                        if (fm_lfo_sync)
                            lfo_phase <= 32'h7fffffff;
                        // Dexed's Lfo::keydown() clears the delay phase, then
                        // getdelay() advances it once for the first 64-sample
                        // block. Apply that first increment here and continue
                        // at the original block cadence below.
                        lfo_delay_state <= dx7_lfo_delay_inc[lfo_delay_table_address];
                        lfo_fade <= dx7_lfo_delay_inc[lfo_delay_table_address][31]
                            ? dx7_lfo_delay_inc[lfo_delay_table_address][30:23]
                            : 8'd0;
                        lfo_delay_block_sample <= 6'd0;
                        voice_active[event_target_voice] <= 1'b1;
                        voice_gate[event_target_voice] <= 1'b1;
                        voice_key_down[event_target_voice] <= 1'b1;
                        voice_note[event_target_voice] <= event_note;
                        voice_velocity[event_target_voice] <= event_velocity;
                        voice_age[event_target_voice] <= 24'd0;
                        voice_eg_block_position[event_target_voice] <= 6'd0;
                        voice_pitch_level[event_target_voice] <= patch_pitch_target[3];
                        voice_combined_pitch_ratio[event_target_voice] <= 21'h10000;
                        voice_pitch_stage[event_target_voice] <= 2'd0;
                        voice_feedback_old[event_target_voice] <= 28'sd0;
                        voice_feedback_new[event_target_voice] <= 28'sd0;
                        display_voice <= event_target_voice;
                    end
                    event_scale_group <= event_scale_group_wire;
                    event_scale_depth <= event_scale_depth_wire;
                    event_scale_curve <= event_scale_curve_wire;
                    event_scale_base_level <=
                        dx7_scale_level(patch_op_gain[event_init_operator][6:0]);
                    engine_state <= ENGINE_EVENT_GAIN_WAIT;
                end

                ENGINE_EVENT_GAIN_WAIT: begin
                    event_base_increment <= event_operator_increment;
                    event_scale_product <= event_scale_source * event_scale_depth;
                    engine_state <= ENGINE_EVENT_SCALE_MUL;
                end

                ENGINE_EVENT_SCALE_MUL: begin
                    // The two preceding FSM cycles give the synchronous ROM
                    // time to return the selected note/detune correction.
                    event_corrected_increment <= event_patch_fixed_latched
                        ? event_base_increment
                        : (event_detuned_product[48]
                           ? 32'hffffffff : event_detuned_product[47:16]);
                    event_scale_magnitude <= (|event_scaled_amount[8])
                        ? 8'hff : event_scaled_amount[7:0];
                    engine_state <= ENGINE_EVENT_SCALE_FINISH;
                end

                ENGINE_EVENT_SCALE_FINISH: begin
                    event_level_offset_latched <=
                        (event_level_offset_final > 17'sd8191) ? 16'sd8191 :
                        (event_level_offset_final < -17'sd8192) ? -16'sd8192 :
                        event_level_offset_final[15:0];
                    engine_state <= ENGINE_EVENT_GAIN_CAPTURE;
                end

                ENGINE_EVENT_GAIN_CAPTURE: begin
                    operator_state_write_valid <= 1'b1;
                    operator_state_write_address <=
                        event_target_voice * 6 + event_init_operator;
                    operator_state_write_data <= pack_operator_state(
                        (fm_osc_sync ? 32'd0 : lfo_phase),
                        event_corrected_increment,
                        // Q14 envelope state is 26 bits. The former 24-bit
                        // field made the old concatenation only 106 bits wide.
                        26'd0,
                        event_level_offset_latched,
                        2'd0
                    );
                    if (event_init_operator == 5) begin
                        allocation_cursor <= (event_target_voice == VOICE_COUNT-1)
                            ? 0 : event_target_voice + 1'b1;
                        engine_state <= ENGINE_IDLE;
                    end else begin
                        event_init_operator <= event_init_operator + 1'b1;
                        engine_state <= ENGINE_EVENT_INIT;
                    end
                end

                ENGINE_CLEAR: begin
                    if (scheduler_voice == 0)
                        voice_carrier_alive <= {VOICE_COUNT{1'b0}};
                    voice_bus_one[scheduler_voice] <= 32'sd0;
                    voice_bus_two[scheduler_voice] <= 32'sd0;
                    voice_output[scheduler_voice] <= 32'sd0;
                    if (scheduler_voice == VOICE_COUNT-1) begin
                        scheduler_voice <= 0;
                        engine_state <= ENGINE_PREP;
                    end else scheduler_voice <= scheduler_voice + 1'b1;
                end

                ENGINE_PREP: begin
                    prep_voice_latched <= scheduler_voice;
                    prep_active_latched <= voice_active[scheduler_voice];
                    prep_gate_latched <= voice_gate[scheduler_voice];
                    prep_stage_latched <= voice_pitch_stage[scheduler_voice];
                    prep_current_latched <= voice_pitch_level[scheduler_voice];
                    prep_target_latched <= prep_pitch_target;
                    prep_delta_latched <= prep_pitch_delta_input;
                    prep_step_latched <= patch_pitch_step[prep_pitch_index];
                    if (voice_active[scheduler_voice]) begin
                        if (voice_age[scheduler_voice] != 24'hffffff)
                            voice_age[scheduler_voice] <= voice_age[scheduler_voice] + 1'b1;
                        voice_eg_block_position[scheduler_voice] <=
                            voice_eg_block_position[scheduler_voice] + 1'b1;
                    end
                    engine_state <= ENGINE_PREP_RESOLVE;
                end

                ENGINE_PREP_RESOLVE: begin
                    prep_level_resolved <= prep_next;
                    prep_fraction_ratio_latched <=
                        dx7_pitch_eg_fraction[prep_next[19:12]];
                    if (prep_active_latched) begin
                        voice_pitch_level[prep_voice_latched] <= prep_next;
                        if (prep_next == prep_target_latched) begin
                            if (prep_stage_latched < 2)
                                voice_pitch_stage[prep_voice_latched]
                                    <= prep_stage_latched + 1'b1;
                            else if (!prep_gate_latched)
                                voice_pitch_stage[prep_voice_latched] <= 2'd3;
                        end
                    end
                    engine_state <= ENGINE_PREP_COMBINE;
                end

                ENGINE_PREP_COMBINE: begin
                    if (prep_active_latched)
                        voice_combined_pitch_ratio[prep_voice_latched]
                            <= prep_combined_ratio;
                    if (scheduler_voice == VOICE_COUNT-1) begin
                        scheduler_voice <= 0;
                        scheduler_operator <= 0;
                        engine_state <= ENGINE_ISSUE;
                    end else begin
                        scheduler_voice <= scheduler_voice + 1'b1;
                        engine_state <= ENGINE_PREP;
                    end
                end

                ENGINE_ISSUE: begin
                    if (voice_active[scheduler_voice]) begin
                        operator_read_pending <= 1'b1;
                        operator_read_voice <= scheduler_voice;
                        operator_read_operator <= scheduler_operator;
                        operator_read_flags <= issue_flags;
                        operator_read_modulation <= issue_modulation_sum;
                    end
                    if (scheduler_voice == VOICE_COUNT-1) begin
                        scheduler_voice <= 0;
                        if (scheduler_operator == 5)
                            engine_state <= ENGINE_DRAIN;
                        else scheduler_operator <= scheduler_operator + 1'b1;
                    end else scheduler_voice <= scheduler_voice + 1'b1;
                end

                ENGINE_DRAIN: begin
                    if (!pipeline_busy) begin
                        scheduler_voice <= 0;
                        engine_state <= ENGINE_RETIRE;
                    end
                end

                ENGINE_RETIRE: begin
                    // A released voice is reclaimed only after every carrier
                    // has crossed the inaudible DX7 threshold.  This replaces
                    // the audible fixed ten-second guillotine.
                    if (voice_active[scheduler_voice] &&
                        !voice_gate[scheduler_voice] &&
                        !voice_carrier_alive[scheduler_voice])
                        voice_active[scheduler_voice] <= 1'b0;
                    if (scheduler_voice == VOICE_COUNT-1) begin
                        mix_voice <= 0;
                        mix_accumulator <= 40'sd0;
                        engine_state <= ENGINE_MIX;
                    end else scheduler_voice <= scheduler_voice + 1'b1;
                end

                ENGINE_MIX: begin
                    if (voice_active[mix_voice])
                        mix_accumulator <= mix_accumulator +
                            {{8{voice_output[mix_voice][31]}}, voice_output[mix_voice]};
                    if (mix_voice == VOICE_COUNT-1) begin
                        // Commit the last voice into the accumulator first;
                        // ENGINE_OUTPUT consumes it on the following clock.
                        engine_state <= ENGINE_OUTPUT;
                    end else mix_voice <= mix_voice + 1'b1;
                end

                ENGINE_OUTPUT: begin
                    if (master_volume_current == 0)
                        sample_out <= 16'sd0;
                    else begin
                        // MODE/CC20: keep its 0..127 range, but reduce every
                        // nonzero output level by 6 dB to leave headroom.
                        case (master_volume_current[6:4])
                            3'd0: sample_out <= soft_limit16(mix_accumulator >>> 8);
                            3'd1: sample_out <= soft_limit16(mix_accumulator >>> 7);
                            3'd2: sample_out <= soft_limit16(mix_accumulator >>> 6);
                            3'd3: sample_out <= soft_limit16(mix_accumulator >>> 5);
                            3'd4: sample_out <= soft_limit16(mix_accumulator >>> 4);
                            3'd5: sample_out <= soft_limit16(mix_accumulator >>> 3);
                            3'd6: sample_out <= soft_limit16(mix_accumulator >>> 2);
                            default: sample_out <= soft_limit16(mix_accumulator >>> 1);
                        endcase
                    end
                    engine_state <= ENGINE_IDLE;
                end
                default: engine_state <= ENGINE_IDLE;
            endcase
        end
    end

    wire [6:0] unused_brightness = midi_event_brightness;
    wire [4:0] unused_glide_shift = glide_shift(portamento_time);
endmodule
