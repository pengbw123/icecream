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
    parameter integer SYNTH_VOICE_COUNT=16,EXTERNAL_GUARD=0,
    parameter MAP_FILE = "src/generated/tutorial_led_map.mem"
)(
    input wire clk, reset_n,
    input wire bt_rx,
    output wire bt_tx,
    input wire start_button_n, stop_button_n,
    input wire [31:0] live_midi_event,
    input wire live_midi_valid,
    input wire [31:0] key_midi_event,
    input wire key_midi_valid,
    input wire [1:0] key_source,
    output wire [31:0] auto_midi_event,
    output wire auto_midi_valid,
    input wire auto_midi_ready,
    output wire auto_playing, auto_flushing,
    output wire led_data,
    output wire running, count_in, beat_active,
    output wire initialized, mapping_missing, frame_done, reply_overflow,
    input wire external_busy
);
    wire blocked=EXTERNAL_GUARD&&external_busy;reg blocked_q;
    always @(posedge clk or negedge reset_n)if(!reset_n)blocked_q<=0;else blocked_q<=blocked;
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
    uart_status_reply #(.CLKS_PER_BIT(UART_CLKS_PER_BIT),.CLK_HZ(CLK_HZ),
        .SCORE_MAX_EVENTS(SCORE_MAX_EVENTS),.SYNTH_VOICE_COUNT(SYNTH_VOICE_COUNT),.ENABLE_RELIABLE(0)) reply (
        .clk(clk),.reset_n(reset_n),.valid(reply_valid),
        .command(reply_command),.status(reply_status),
        .capability_valid(capability_valid),.capability_nonce(capability_nonce),
        .reliable_valid(1'b0),.reliable_frame(256'd0),.reliable_ready(),
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
    wire finished;
    wire [31:0] elapsed_ms;
    sunny_tutorial_player #(.CLK_HZ(CLK_HZ),.NOTE_COUNT(`SUNNY_NOTE_COUNT),
        .END_MS(`SUNNY_END_MS),.BEAT_MS(`SUNNY_BEAT_MS)) player (
        .clk(clk),.reset_n(reset_n),.start(player_start),.stop(player_stop),
        .speed_percent(speed_percent),.count_in_beats(count_in_beats),.transpose(transpose),
        .wait_for_key(wait_for_key),.live_midi_event(key_midi_event),.live_midi_valid(key_midi_valid),.key_source(key_source),
        .running(running),.count_in(count_in),.beat_active(beat_active),.finished(finished),
        .elapsed_ms(elapsed_ms),.current_notes(expected_notes),.preview_notes(preview_notes)
    );
    reg score_cmd_valid;
    reg [7:0] score_command;
    reg [63:0] score_payload;
    reg score_pending, score_ack_wait, score_local, local_auto_stop;
    reg [7:0] score_wait_count, score_status;
    wire score_done, score_error, score_loaded;
    wire [127:0] auto_notes;
    wire score_busy = score_pending || score_ack_wait || score_cmd_valid || local_auto_stop;
    score_player #(.CLK_HZ(CLK_HZ),.RAM_DEPTH(SCORE_MAX_EVENTS),.MAX_EVENTS(SCORE_MAX_EVENTS)) auto_player (
        .clk(clk),.reset_n(reset_n),.cmd_valid(score_cmd_valid),.cmd_command(score_command),.cmd_payload(score_payload),
        .score_done(score_done),.score_error(score_error),
        .midi_event_data(auto_midi_event),.midi_event_valid(auto_midi_valid),.midi_event_ready(auto_midi_ready),
        .volume_event_data(),.volume_event_valid(),.volume_event_ready(1'b0),
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
        end else begin
            player_start <= 0; player_stop <= 0; reply_valid <= 0;
            capability_valid <= 0; score_cmd_valid <= 0;
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
                end else clear_index <= clear_index+1;
            end else if (map_pending && cfg_ready) begin
                map_pending <= 0; map_ack_wait <= 1; map_ack_command <= 8'h72;
            end
            // A simultaneous incoming request is rejected first; preserve the
            // older configuration completion until the next free reply cycle.
            if (map_ack_wait && !packet_valid && !packet_error && !reliable_valid) begin
                reply_valid <= 1; reply_command <= map_ack_command;
                reply_status <= cfg_error ? 8'd1 : 8'd0; map_ack_wait <= 0;
            end
            if (packet_error) begin
                reply_valid <= 1; reply_command <= command;
                reply_status <= error_code == 1 ? 8'd2 : 8'd3;
            end else if (reliable_valid) begin
                reply_valid <= 1; reply_command <= 8'h60; reply_status <= 1;
            end else if (packet_valid) begin
                reply_valid <= 1; reply_command <= command; reply_status <= 1;
                if (command == 8'h57 && payload[63:32] == 0 && payload[31:0] != 0) begin
                    capability_valid <= 1; capability_nonce <= payload[31:0]; reply_valid <= 0;
                end else if (command >= 8'h50 && command <= 8'h55 && !score_busy &&
                    (command == 8'h55 || command == 8'h54 ||
                        (!running && !player_start && !local_start && !local_stop && !config_busy && (!blocked||command!=8'h53)))) begin
                    score_command <= command; score_payload <= payload; score_cmd_valid <= 1;
                    score_pending <= 1; score_local <= 0; score_wait_count <= 0; reply_valid <= 0;
                end else if (payload[63:32] == MAGIC && init_done && !config_busy) begin
                    case (command)
                        8'h70: if (payload[31:8] == 0 && payload[7:0] <= 1 &&
                            (payload[7:0] == 0 || (!blocked && !auto_playing && !auto_flushing && !score_busy && !local_stop))) begin
                            scan_enable <= 0;
                            if (payload[7:0] == 0) player_stop <= 1;
                            else if (!running) player_start <= 1;
                            reply_status <= 0;
                        end
                        8'h71: if (!running && !auto_playing && !auto_flushing && !score_busy && payload[31:24] == 0 && payload[7:0] <= 1 &&
                                      {16'd0,payload[23:8]} < LED_COUNT) begin
                            scan_enable <= payload[0]; scan_index <= payload[23:8]; reply_status <= 0;
                        end
                        8'h72: if (!running && !auto_playing && !auto_flushing && !score_busy && {16'd0,payload[15:0]} < LED_COUNT &&
                                      payload[23:16] <= 2 && payload[31:24] < 128) begin
                            map_index <= payload[15:0]; map_kind <= payload[17:16];
                            map_note <= payload[30:24]; map_pending <= 1; reply_valid <= 0;
                        end
                        8'h73: if (!running && !auto_playing && !auto_flushing && !score_busy && payload[31:0] == 0) begin
                            clear_active <= 1; clear_index <= 0; scan_enable <= 0; reply_valid <= 0;
                        end
                        8'h74: if (!running && !auto_playing && !auto_flushing && !score_busy && payload[31:24] == 0 &&
                                      payload[7:0] >= 50 && payload[7:0] <= 150 && payload[15:8] <= 8 &&
                                      $signed(payload[23:16]) >= -24 && $signed(payload[23:16]) <= 24) begin
                            speed_percent <= payload[7:0]; count_in_beats <= payload[11:8];
                            transpose <= payload[23:16]; reply_status <= 0;
                        end
                        8'h75: if (payload[31:0] == 0) reply_status <= 0;
                        8'h76: if (!running && !player_start && !auto_playing && !auto_flushing &&
                            !score_busy && payload[31:8] == 0 && payload[7:0] <= 1) begin
                            wait_for_key <= payload[0]; reply_status <= 0;
                        end
                        default: begin end
                    endcase
                end
            end
            if (local_start && !blocked && !packet_valid && init_done && !config_busy && !running &&
                !auto_playing && !auto_flushing && !score_busy && !local_stop) begin
                player_start <= 1; scan_enable <= 0;
            end
            if(blocked&&!blocked_q)begin player_stop<=1;player_start<=0;scan_enable<=0;
                if(auto_playing||(score_pending&&score_command==8'h53))local_auto_stop<=1;end
            if (local_stop) begin player_stop <= 1; player_start <= 0; scan_enable <= 0; end
            if (local_stop && (auto_playing || auto_flushing ||
                (score_pending && score_command == 8'h53))) local_auto_stop <= 1;
        end
    end
endmodule
