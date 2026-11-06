`include "src/generated/sunny_tutorial_meta.vh"
// Dedicated JDY UART. Tutorial commands never enter the FM parameter decoder.
// Score v1 is decoded locally and generates only ready/valid MIDI events.
// Controls and calibration use A5 5A CMD D0..D7 XOR, D4..D7 = 'G','U','I','D'.
module sunny_tutorial_system #(
    parameter integer CLK_HZ = 50000000,
    parameter integer UART_CLKS_PER_BIT = 434,
    parameter integer LED_COUNT = `TUTORIAL_LED_COUNT,
    parameter integer BIT_CYCLES = 63,
    parameter integer T0H_CYCLES = 15,
    parameter integer T1H_CYCLES = 33,
    parameter integer RESET_CYCLES = 16000,
    parameter integer BUTTON_CYCLES = CLK_HZ/100,
    parameter integer DEFAULT_SPEED = `TUTORIAL_DEFAULT_SPEED,
    parameter integer DEFAULT_COUNT_IN = `TUTORIAL_DEFAULT_COUNT_IN,
    parameter integer DEFAULT_TRANSPOSE = `TUTORIAL_DEFAULT_TRANSPOSE,
    parameter integer SCORE_MAX_EVENTS = 8192,
    parameter integer SYNTH_VOICE_COUNT = 16,
    parameter integer EXTERNAL_GUARD=0,
    parameter integer PHONE_ENABLED = 0,
    parameter integer KEY_PLAN_ENABLED = 0,
    parameter MAP_FILE = "src/generated/tutorial_led_map.mem"
)(
    input wire clk, reset_n,
    input wire external_mode_busy,input wire external_busy,
    input wire bt_rx,
    output wire bt_tx,
    input wire start_button_n, stop_button_n,
    input wire [31:0] live_midi_event,
    input wire live_midi_valid,
    input wire [31:0] key_midi_event,
    input wire key_midi_valid,
    input wire [1:0] key_source,
    input wire key_plan_ready,input wire keyboard_disconnected,
    output wire key_plan_active,output wire [6:0] key_plan_first,
    output wire [24:0] key_plan_valid,output wire [174:0] key_plan_notes,
    output wire [31:0] auto_midi_event,
    output wire auto_midi_valid,
    input wire auto_midi_ready,
    output wire auto_playing, auto_flushing,
    output wire led_data,
    output wire running, count_in, beat_active,
    output wire initialized, mapping_missing, frame_done, reply_overflow,
    output wire mode_lock,
    output wire calibration_success,
    output reg phone_request_valid,output reg [63:0] phone_request_payload,
    input wire phone_request_ready,
    input wire phone_response_valid,input wire [15:0] phone_response_token,
    input wire [7:0] phone_response_status,phone_response_value,
    input wire phone_response_was_write,
    output wire tone_success
);
    wire mode_busy=(external_mode_busy===1'b1)||(EXTERNAL_GUARD && external_busy);
    reg mode_busy_q;
    always @(posedge clk or negedge reset_n)if(!reset_n)mode_busy_q<=0;else mode_busy_q<=mode_busy;
    localparam [31:0] MAGIC = 32'h44495547;
    wire packet_valid, packet_error, reliable_valid;
    wire [7:0] command, checksum;
    wire [63:0] payload;
    wire [2:0] error_code;
    // Consume recognized old reliable envelopes atomically rather than letting
    // embedded payload bytes masquerade as tutorial control frames.
    uart_packet_rx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .TIMEOUT_CLKS(CLK_HZ/5),.ENABLE_RELIABLE(1)) rx (
        .clk(clk),.reset_n(reset_n),.rx(bt_rx),
        .packet_valid(packet_valid),.packet_error(packet_error),
        .command(command),.payload(payload),.checksum(checksum),.error_code(error_code),
        .reliable_valid(reliable_valid),.reliable_ready(1'b1),
        .reliable_body(),.reliable_digest()
    );
    reg reply_valid;
    reg [7:0] reply_command, reply_status;
    reg capability_valid;
    reg [31:0] capability_nonce;
    // F4 response: A5 5A F4 78 status token_lo token_hi actual XOR.
    wire [7:0] phone_check=8'hf4 ^ 8'h78 ^ phone_response_status ^
        phone_response_token[7:0] ^ phone_response_token[15:8] ^ phone_response_value;
    wire [71:0] phone_frame={phone_check,phone_response_value,phone_response_token,
                             phone_response_status,8'h78,8'hf4,8'h5a,8'ha5};
    uart_status_reply #(.CLKS_PER_BIT(UART_CLKS_PER_BIT),.CLK_HZ(CLK_HZ),
        .SCORE_MAX_EVENTS(SCORE_MAX_EVENTS),.SYNTH_VOICE_COUNT(SYNTH_VOICE_COUNT),.ENABLE_RELIABLE(0),.ENABLE_PHONE(PHONE_ENABLED),.ENABLE_KEY_PLAN(KEY_PLAN_ENABLED)) reply (
        .clk(clk),.reset_n(reset_n),.valid(reply_valid),
        .command(reply_command),.status(reply_status),
        .capability_valid(capability_valid),.capability_nonce(capability_nonce),
        .reliable_valid(1'b0),.reliable_frame(256'd0),.reliable_ready(),
        .phone_valid(phone_response_valid),.phone_frame(phone_frame),
        .tx(bt_tx),.overflow(reply_overflow)
    );
    wire local_start, local_stop;
    debounced_press #(.STABLE_CYCLES(BUTTON_CYCLES)) start_button (
        .clk(clk),.reset_n(reset_n),.button_n(start_button_n),.pressed(local_start));
    debounced_press #(.STABLE_CYCLES(BUTTON_CYCLES)) stop_button (
        .clk(clk),.reset_n(reset_n),.button_n(stop_button_n),.pressed(local_stop));
    reg player_start, player_stop;
    reg [7:0] speed_percent;
    reg [3:0] count_in_beats;
    reg signed [7:0] transpose;
    reg wait_for_key;
    wire [127:0] expected_notes, preview_notes;
    wire sunny_count_in,sunny_beat_active,uploaded_count_in,uploaded_beat_active;
    wire fresh_key_valid,keys_all_released;wire [6:0] fresh_key_note;
    assign count_in = sunny_count_in | uploaded_count_in;
    assign beat_active = sunny_beat_active | uploaded_beat_active;
    wire finished;
    wire [31:0] elapsed_ms;
    sunny_tutorial_player #(.CLK_HZ(CLK_HZ),.NOTE_COUNT(`SUNNY_NOTE_COUNT),
        .END_MS(`SUNNY_END_MS),.BEAT_MS(`SUNNY_BEAT_MS)) player (
        .clk(clk),.reset_n(reset_n),.start(player_start),.stop(player_stop),
        .speed_percent(speed_percent),.count_in_beats(count_in_beats),.transpose(transpose),
        .wait_for_key(wait_for_key),.live_midi_event(key_midi_event),.live_midi_valid(key_midi_valid),.key_source(key_source),
        .clear_usb_held(KEY_PLAN_ENABLED && keyboard_disconnected),
        .running(running),.count_in(sunny_count_in),.beat_active(sunny_beat_active),.finished(finished),
        .elapsed_ms(elapsed_ms),.current_notes(expected_notes),.preview_notes(preview_notes),
        .fresh_key_valid(fresh_key_valid),.fresh_key_note(fresh_key_note),.keys_all_released(keys_all_released)
    );
    reg score_cmd_valid;
    reg [7:0] score_command;
    reg [63:0] score_payload;
    reg score_pending, score_ack_wait, score_local, local_auto_stop;
    reg [7:0] score_wait_count, score_status;
    wire score_done, score_error, score_loaded;
    wire [127:0] auto_notes;
    // A guide run consumes the player's entire stream locally, including its
    // stop/finish CCs, so it never plays or silences the performer's notes.
    // Latch the mode only for an admissible start and keep it through flushing.
    reg score_guide_only;
    wire [31:0] score_midi_event;
    wire score_midi_valid;
    wire score_midi_ready = score_guide_only ? 1'b1 : auto_midi_ready;
    assign auto_midi_event = score_midi_event;
    assign auto_midi_valid = score_midi_valid && !score_guide_only;
    wire score_busy = score_pending || score_ack_wait || score_cmd_valid || local_auto_stop;
    assign mode_lock = running || player_start || local_start || auto_playing || auto_flushing ||
        (packet_valid && ((command == 8'h53 || command == 8'h59 || command == 8'h5A) ||
            (command == 8'h70 && payload[63:32] == MAGIC && payload[7:0] == 1))) ||
        ((score_pending || score_cmd_valid) && (score_command == 8'h53 || score_command == 8'h59 || score_command == 8'h5A));
    score_player #(.CLK_HZ(CLK_HZ),.RAM_DEPTH(SCORE_MAX_EVENTS),.MAX_EVENTS(SCORE_MAX_EVENTS),.ENABLE_KEY_PLAN(KEY_PLAN_ENABLED)) auto_player (
        .clk(clk),.reset_n(reset_n),.cmd_valid(score_cmd_valid),.cmd_command(score_command),.cmd_payload(score_payload),
        .score_done(score_done),.score_error(score_error),
        .midi_event_data(score_midi_event),.midi_event_valid(score_midi_valid),.midi_event_ready(score_midi_ready),
        .volume_event_data(),.volume_event_valid(),.volume_event_ready(1'b0),
        .fresh_key_valid(fresh_key_valid && (!key_plan_active || key_source == 0)),.fresh_key_note(fresh_key_note),
        .key_plan_allowed(KEY_PLAN_ENABLED && key_plan_ready && keys_all_released),
        .key_plan_active(key_plan_active),.key_plan_first(key_plan_first),.key_plan_valid(key_plan_valid),.key_plan_notes(key_plan_notes),
        .guide_count_in(uploaded_count_in),.guide_beat_active(uploaded_beat_active),
        .guide_mask(auto_notes),.loaded(score_loaded),.playing(auto_playing),.flush_active(auto_flushing),.upload_crc32()
    );
    reg [127:0] live_notes;
    wire [3:0] live_status = live_midi_event[23:20];
    wire [6:0] live_note = live_midi_event[14:8];
    wire [6:0] live_velocity = live_midi_event[6:0];
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) live_notes <= 0;
        else if (live_midi_valid) begin
            if (live_status == 4'h9) live_notes[live_note] <= live_velocity != 0;
            else if (live_status == 4'h8) live_notes[live_note] <= 0;
            else if (live_status == 4'hB && (live_note == 120 || live_note == 123)) live_notes <= 0;
        end
    end

    reg [8:0] map_rom [0:LED_COUNT-1];
    integer init_index, clear_index;
    reg init_done, clear_active, map_pending, map_ack_wait;
    reg [7:0] map_ack_command;
    reg [15:0] map_index;
    reg [1:0] map_kind;
    reg [6:0] map_note;
    reg scan_enable;
    reg [15:0] scan_index;
    wire cfg_ready, cfg_error, frame_ready, strip_busy;
    wire cfg_valid = !init_done || clear_active || map_pending;
    wire [15:0] cfg_index = !init_done ? 16'(init_index) :
                              clear_active ? 16'(clear_index) : map_index;
    wire [8:0] cfg_entry = !init_done ? map_rom[init_index] :
                            clear_active ? 9'd0 : {map_kind,map_note};
    wire [127:0] unmapped_notes;
    assign initialized = init_done;
    assign mapping_missing = running && (|unmapped_notes);
    initial $readmemh(MAP_FILE,map_rom);
    score_strip_guide #(.LED_COUNT(LED_COUNT),.BIT_CYCLES(BIT_CYCLES),
        .T0H_CYCLES(T0H_CYCLES),.T1H_CYCLES(T1H_CYCLES),.RESET_CYCLES(RESET_CYCLES)) strip (
        .clk(clk),.reset_n(reset_n),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),
        .cfg_index(cfg_index),.cfg_kind(cfg_entry[8:7]),.cfg_note(cfg_entry[6:0]),.cfg_error(cfg_error),
        .frame_valid(init_done),.frame_ready(frame_ready),
        .current_notes(running ? expected_notes : (auto_playing || auto_flushing) ? auto_notes : live_notes),
        .preview_notes(running ? preview_notes : 128'd0),.beat_active(beat_active),
        .scan_enable(scan_enable),.scan_index(scan_index),.busy(strip_busy),
        .frame_done(frame_done),.unmapped_notes(unmapped_notes),.led_data(led_data)
    );
    // A completed map is reported only after one clear and 25 distinct
    // successful note writes. The optional beat lamp must also be unique.
    localparam integer CAL_TIMEOUT_CYCLES = CLK_HZ * 15;
    localparam integer CAL_TIMEOUT_W = $clog2(CAL_TIMEOUT_CYCLES + 1);
    localparam integer CAL_BANNER_CYCLES = CLK_HZ * 4;
    localparam integer CAL_BANNER_W = $clog2(CAL_BANNER_CYCLES + 1);
    localparam integer TONE_BANNER_CYCLES = CLK_HZ * 4;
    localparam integer TONE_BANNER_W = $clog2(TONE_BANNER_CYCLES + 1);
    reg cal_active, cal_invalid, cal_beat;
    reg [5:0] cal_count;
    reg [127:0] cal_notes;
    reg [LED_COUNT-1:0] cal_leds;
    reg [CAL_TIMEOUT_W-1:0] cal_timeout;
    reg [CAL_BANNER_W-1:0] cal_banner;
    reg cal_banner_start,cal_banner_clear;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) cal_banner<=0;
        else if(cal_banner_clear) cal_banner<=0;
        else if(cal_banner_start) cal_banner<=CAL_BANNER_CYCLES;
        else if(cal_banner!=0) cal_banner<=cal_banner-1'b1;
    end
    reg [TONE_BANNER_W-1:0] tone_banner;
    assign calibration_success = cal_banner != 0;
    assign tone_success = tone_banner != 0;
    wire config_busy = map_pending || map_ack_wait || clear_active;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            init_index <= 0; init_done <= 0; clear_index <= 0; clear_active <= 0;
            map_pending <= 0; map_ack_wait <= 0; map_ack_command <= 0;
            map_index <= 0; map_kind <= 0; map_note <= 0;
            scan_enable <= 0; scan_index <= 0;
            speed_percent <= 8'(DEFAULT_SPEED); count_in_beats <= 4'(DEFAULT_COUNT_IN);
            transpose <= 8'(DEFAULT_TRANSPOSE);
            wait_for_key <= 0;
            player_start <= 0; player_stop <= 0;
            reply_valid <= 0; reply_command <= 0; reply_status <= 0;
            capability_valid <= 0; capability_nonce <= 0;
            score_cmd_valid <= 0; score_command <= 0; score_payload <= 0;
            score_pending <= 0; score_ack_wait <= 0; score_local <= 0;
            score_wait_count <= 0; score_status <= 0; local_auto_stop <= 0;
            score_guide_only <= 0;
            cal_active<=0;cal_invalid<=0;cal_beat<=0;cal_count<=0;
            cal_notes<=0;cal_leds<=0;cal_timeout<=0;cal_banner_start<=0;cal_banner_clear<=0;
            phone_request_valid<=0;phone_request_payload<=0;tone_banner<=0;
        end else begin
            player_start <= 0; player_stop <= 0; reply_valid <= 0;
            capability_valid <= 0; score_cmd_valid <= 0;
            phone_request_valid<=0;
            cal_banner_start<=0;cal_banner_clear<=0;
            if (tone_banner != 0) tone_banner <= tone_banner - 1'b1;
            if (PHONE_ENABLED && phone_response_valid && phone_response_status==0 && phone_response_was_write)
                tone_banner <= TONE_BANNER_CYCLES;
            if (cal_active && !clear_active && !map_pending && !map_ack_wait) begin
                if (cal_timeout == CAL_TIMEOUT_CYCLES-1) begin
                    cal_active<=0;cal_invalid<=1;cal_timeout<=0;
                end else cal_timeout<=cal_timeout+1'b1;
            end
            if (score_pending) begin
                score_wait_count <= score_wait_count + 1'b1;
                if (score_done || score_error || &score_wait_count) begin
                    score_pending <= 0;
                    score_status <= score_error ? 8'd1 : score_done ? 8'd0 : 8'd4;
                    if (!score_local) score_ack_wait <= 1;
                end
            end
            if (score_ack_wait && !packet_valid && !packet_error && !reliable_valid && !map_ack_wait) begin
                reply_valid <= 1; reply_command <= score_command; reply_status <= score_status;
                score_ack_wait <= 0;
            end
            // S1 can stop offline playback too. Wait for the current command's
            // completion before issuing an internal STOP; it must not steal ACKs.
            if (local_auto_stop && !score_pending && !score_ack_wait && !score_cmd_valid &&
                !packet_valid && !packet_error && !reliable_valid && !map_ack_wait) begin
                score_command <= 8'h54; score_payload <= 0; score_cmd_valid <= 1;
                score_pending <= 1; score_local <= 1; score_wait_count <= 0; local_auto_stop <= 0;
            end
            if (!init_done && cfg_ready) begin
                if (init_index == LED_COUNT-1) begin init_done <= 1; init_index <= 0; end
                else init_index <= init_index+1;
            end else if (clear_active && cfg_ready) begin
                if (clear_index == LED_COUNT-1) begin
                    clear_active <= 0; map_ack_wait <= 1; map_ack_command <= 8'h73;
                    cal_active<=1;cal_invalid<=0;cal_beat<=0;cal_count<=0;
                    cal_notes<=0;cal_leds<=0;cal_timeout<=0;
                end else clear_index <= clear_index+1;
            end else if (map_pending && cfg_ready) begin
                map_pending <= 0; map_ack_wait <= 1; map_ack_command <= 8'h72;
            end
            // A simultaneous incoming request is rejected first; preserve the
            // older configuration completion until the next free reply cycle.
            if (map_ack_wait && !packet_valid && !packet_error && !reliable_valid) begin
                reply_valid <= 1; reply_command <= map_ack_command;
                reply_status <= cfg_error ? 8'd1 : 8'd0; map_ack_wait <= 0;
                if (map_ack_command == 8'h72 && cal_active) begin
                    cal_timeout<=0;
                    if (cfg_error || cal_leds[map_index] || map_kind == 0 ||
                        (map_kind == 1 && (cal_notes[map_note] || cal_count >= 25)) ||
                        (map_kind == 2 && cal_beat)) cal_invalid<=1;
                    else begin
                        cal_leds[map_index]<=1;
                        if (map_kind == 1) begin cal_notes[map_note]<=1;cal_count<=cal_count+1'b1;end
                        else cal_beat<=1;
                    end
                end
            end
            if (packet_error) begin
                if (cal_active) cal_invalid<=1;
                reply_valid <= 1; reply_command <= command;
                reply_status <= error_code == 1 ? 8'd2 : 8'd3;
            end else if (reliable_valid) begin
                reply_valid <= 1; reply_command <= 8'h60; reply_status <= 1;
            end else if (packet_valid) begin
                reply_valid <= 1; reply_command <= command; reply_status <= 1;
                // A rejected/interrupted mapping invalidates this transaction.
                if (command == 8'h72 && cal_active &&
                    !(payload[63:32] == MAGIC && init_done && !config_busy && !running &&
                      !auto_playing && !auto_flushing && !score_busy &&
                      {16'd0,payload[15:0]} < LED_COUNT && payload[23:16] <= 2 && payload[31:24] < 128))
                    cal_invalid<=1;
                if (PHONE_ENABLED && command == 8'h78 && payload[63:56]==8'hd9 && payload[55:48]<=3 &&
                    payload[47:32]!=0 && init_done && phone_request_ready) begin
                    // The UI firmware owns parameter conversion, range checks,
                    // touch serialization and final readback/response.
                    phone_request_valid<=1;phone_request_payload<=payload;reply_valid<=0;
                end else if (command == 8'h57 && payload[63:32] == 0 && payload[31:0] != 0) begin
                    capability_valid <= 1; capability_nonce <= payload[31:0]; reply_valid <= 0;
                end else if (command == 8'h54 && payload == 0 && !score_busy &&
                             !auto_playing && !auto_flushing) begin
                    // An idle STOP must not emit the player's All Notes Off:
                    // those CCs would silence unrelated manual performance.
                    reply_status <= 0;
                end else if (((command >= 8'h50 && command <= 8'h55) || command == 8'h59 || command == 8'h5A) && !score_busy &&
                    (command == 8'h55 || command == 8'h54 ||
                        (!running && !player_start && !local_start && !local_stop && !config_busy &&
                         ((command != 8'h53 && command != 8'h59 && command != 8'h5A) || !mode_busy)))) begin
                    if (((command == 8'h53 || command == 8'h59) && payload == 0 || command == 8'h5A) &&
                        score_loaded && !auto_playing && !auto_flushing)
                        begin
                            score_guide_only <= command == 8'h59 || command == 8'h5A;
                            scan_enable <= 0;
                            cal_active<=0;cal_invalid<=1;
                        end
                    score_command <= command; score_payload <= payload; score_cmd_valid <= 1;
                    score_pending <= 1; score_local <= 0; score_wait_count <= 0; reply_valid <= 0;
                end else if (payload[63:32] == MAGIC && init_done && !config_busy) begin
                    case (command)
                        8'h70: if (payload[31:8] == 0 && payload[7:0] <= 1 &&
                            (payload[7:0] == 0 || (!auto_playing && !auto_flushing && !score_busy && !local_stop && !mode_busy))) begin
                            scan_enable <= 0;
                            if (payload[7:0] == 0) player_stop <= 1;
                            else if (!running) begin player_start <= 1;cal_active<=0;cal_invalid<=1;end
                            reply_status <= 0;
                        end
                        8'h71: if (!running && !auto_playing && !auto_flushing && !score_busy && payload[31:24] == 0 && payload[7:0] <= 1 &&
                                      {16'd0,payload[23:8]} < LED_COUNT) begin
                            scan_enable <= payload[0]; scan_index <= payload[23:8]; reply_status <= 0;
                        end
                        8'h72: if (!running && !auto_playing && !auto_flushing && !score_busy && {16'd0,payload[15:0]} < LED_COUNT &&
                                      payload[23:16] <= 2 && payload[31:24] < 128) begin
                            map_index <= payload[15:0]; map_kind <= payload[17:16];
                            map_note <= payload[30:24]; map_pending <= 1; reply_valid <= 0; cal_banner_clear<=1;
                        end
                        8'h73: if (!running && !auto_playing && !auto_flushing && !score_busy && payload[31:0] == 0) begin
                            clear_active <= 1; clear_index <= 0; scan_enable <= 0; reply_valid <= 0;
                            cal_active<=0;cal_invalid<=1;cal_banner_clear<=1;
                        end
                        8'h74: if (!running && !auto_playing && !auto_flushing && !score_busy && payload[31:24] == 0 &&
                                      payload[7:0] >= 50 && payload[7:0] <= 150 && payload[15:8] <= 8 &&
                                      $signed(payload[23:16]) >= -24 && $signed(payload[23:16]) <= 24) begin
                            speed_percent <= payload[7:0]; count_in_beats <= payload[11:8];
                            transpose <= payload[23:16]; reply_status <= 0;
                        end
                        8'h75: if (payload[31:0] == 0) reply_status <= 0;
                        8'h77: if (payload[31:0] == 0 && cal_active && !cal_invalid && cal_count == 25 &&
                                    !running && !auto_playing && !auto_flushing && !score_busy) begin
                            reply_status<=0;cal_active<=0;cal_banner_start<=1;
                        end
                        8'h76: if (!running && !player_start && !auto_playing && !auto_flushing &&
                            !score_busy && payload[31:8] == 0 && payload[7:0] <= 1) begin
                            wait_for_key <= payload[0]; reply_status <= 0;
                        end
                        default: begin end
                    endcase
                end
            end
            if (local_start && !packet_valid && init_done && !config_busy && !running &&
                !auto_playing && !auto_flushing && !score_busy && !local_stop && !mode_busy) begin
                player_start <= 1; scan_enable <= 0;cal_active<=0;cal_invalid<=1;
            end
            if(EXTERNAL_GUARD && mode_busy && !mode_busy_q)begin
                player_stop<=1;player_start<=0;scan_enable<=0;
                if(auto_playing || (score_pending && (score_command==8'h53 || score_command==8'h59 || score_command==8'h5a)))local_auto_stop<=1;
            end
            if (local_stop) begin player_stop <= 1; player_start <= 0; scan_enable <= 0; end
            if (local_stop && (auto_playing || auto_flushing ||
                (score_pending && (score_command == 8'h53 || score_command == 8'h59 || score_command == 8'h5A)))) local_auto_stop <= 1;
            if (KEY_PLAN_ENABLED && keyboard_disconnected && key_plan_active) local_auto_stop <= 1;
        end
    end
endmodule
