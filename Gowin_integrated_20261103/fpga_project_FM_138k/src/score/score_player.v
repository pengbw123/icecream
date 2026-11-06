// -----------------------------------------------------------------------------
// score_player.v
//
// Offline score player.  A Bluetooth/PC download writes 48-bit events
// {velocity[7:0], note[7:0], delay_ms[31:0]} into an inferred synchronous
// BSRAM, and PLAY replays them with a pure-RTL 1 ms clock enable.
//
// Score protocol v1 (same 12-byte framing as every other command:
// A5 5A CMD DATA0..DATA7 XOR, reply A5 5A F0 CMD STATUS XOR):
//
//   0x55 PROBE : DATA all zero.  status 0 = score v1 supported (2048 events).
//   0x56 VOLUME: D0=0..127, D1..7=0. Queue MIDI CC20 for the existing synth.
//                ACK means queued; allowed during playback. A full queue rejects.
//                The RAM/MAX_EVENTS parameters must really hold 2048 events,
//                otherwise the honest answer is status 1 so an application
//                never uploads a score this build cannot store.
//   0x50 BEGIN : D0..1 event count 1..2048, D2 = version 1, D3..7 = 0.
//                Usable while not playing.  Clears loaded and the upload
//                index and restarts CRC32 at 0xFFFFFFFF, so a BEGIN during an
//                upload restarts that upload.
//   0x51 EVENT : D0..1 index (must equal upload_index and be < count),
//                D2..5 delay in ms relative to the previous event (0..600000),
//                D6 note 0..127, D7 velocity 0..127 (0 = note off).
//                Accepted only while uploading and not playing.  The running
//                CRC32 (IEEE reflected, poly 0xEDB88320) accumulates the six
//                bytes D2,D3,D4,D5,D6,D7 in order.  The RAM write happens on
//                the accept edge, the ACK only after the CRC actually merged
//                those bytes.
//   0x52 SEAL  : D0..3 ~CRC32, D4..5 count, D6 = 1, D7 = 0.  loaded is set
//                only when every event has arrived (count == upload_index)
//                and the final CRC and count match.
//   0x53 PLAY  : payload all zero.  Requires loaded, and a restart must be
//                preceded by STOP.  Event 0's delta is scheduled from PLAY.
//   0x54 STOP  : payload all zero.  Stops the schedule, drops unsent events,
//                then sends CC64=0 and CC123=0 in order.  guide_mask is
//                cleared after both ready handshakes.  STOP is acknowledged
//                immediately; the note-off flush runs on in the background.
//
// MIDI output per event, stable valid/ready handshake, no event is dropped:
//   velocity != 0 -> {8'h09, 8'h90, note, velocity}
//   velocity == 0 -> {8'h08, 8'h80, note, 8'd0}
// CC64=0 -> {8'h0B, 8'hB0, 8'd64, 8'd0}, CC123=0 -> {8'h0B, 8'hB0, 8'd123, 8'd0}.
// CC123 is "all notes off": release tails may still ring, the player never
// claims the output is instantly silent.
//
// Timing: the delay countdown restarts its divider whenever a delay is loaded,
// so an N ms delta is N whole milliseconds. Synchronous RAM access and
// handshakes add a few clocks per event (plus any synth back pressure).
// Zero deltas do not wait for a millisecond tick, keeping chords close together.
//
// Error handling: unknown score command, illegal state, bad index, count
// overflow, reserved-bit violations and CRC mismatch all answer score_error
// (status 1).  While the note-off flush is pending BEGIN/EVENT/SEAL/PLAY are
// rejected.  Every answer is produced in at most a few dozen clocks, far
// inside the 100-clock window the control bridge waits.  CRC throughput is two
// reflected bits per clock (one byte per four clocks), so the datapath stays
// short instead of a 48-bit wide combinational chain.
// -----------------------------------------------------------------------------
module score_player #(
    parameter integer RAM_DEPTH  = 2048,
    parameter integer MAX_EVENTS = 2048,
    parameter integer CLK_HZ     = 50000000,
    parameter integer ENABLE_KEY_PLAN = 0
) (
    input  wire         clk,
    input  wire         reset_n,

    // Decoded packet forwarded by synth_uart_control (one-clock cmd_valid).
    input  wire         cmd_valid,
    input  wire [7:0]   cmd_command,
    input  wire [63:0]  cmd_payload,

    // Status back to the control bridge: score_done -> status 0, score_error -> 1.
    output reg          score_done,
    output reg          score_error,

    // MIDI event stream into the arbiter.
    output reg  [31:0]  midi_event_data,
    output reg          midi_event_valid,
    input  wire         midi_event_ready,

    // Independent one-slot mailbox so volume cannot replace a pending note.
    output reg  [31:0] volume_event_data,
    output reg          volume_event_valid,
    input  wire         volume_event_ready,

    // Source-aware fresh key press, supplied by the existing tutorial detector.
    input  wire         fresh_key_valid,
    input  wire [6:0]   fresh_key_note,
    // Mapped v2 score: index is the physical key (first..first+24).
    // Gate mapped starts until all real keys are released and synth is poly.
    input  wire         key_plan_allowed,
    output wire         key_plan_active,
    output reg  [6:0]   key_plan_first,
    output reg  [24:0]  key_plan_valid,
    output reg  [174:0] key_plan_notes,
    output wire         guide_count_in,
    output wire         guide_beat_active,

    // 128-bit logical guide mask (no physical LED is assigned this round).
    output reg  [127:0] guide_mask,

    output reg          loaded,
    output reg          playing,
    // Note-off flush in flight: BEGIN/EVENT/SEAL/PLAY are refused meanwhile.
    output reg          flush_active,
    output wire [31:0]  upload_crc32
);

    localparam [3:0] S_IDLE       = 4'd0;
    localparam [3:0] S_EV_CRC     = 4'd1;
    localparam [3:0] S_PLAY_FETCH = 4'd2;
    localparam [3:0] S_PLAY_LATCH = 4'd3;
    localparam [3:0] S_PLAY_WAIT  = 4'd4;
    localparam [3:0] S_PLAY_ISSUE = 4'd5;
    localparam [3:0] S_PLAY_HOLD  = 4'd6;
    localparam [3:0] S_FLUSH_A    = 4'd7;
    localparam [3:0] S_FLUSH_AH   = 4'd8;
    localparam [3:0] S_FLUSH_B    = 4'd9;
    localparam [3:0] S_FLUSH_BH   = 4'd10;
    localparam [3:0] S_STOP_DRAIN = 4'd12;
    // One cycle for the inferred synchronous RAM read: the address is
    // registered in S_PLAY_FETCH, the data is only valid one clock later.
    localparam [3:0] S_PLAY_RDEN  = 4'd11;
    localparam [3:0] S_WAIT_KEYS  = 4'd13;
    localparam [3:0] S_COUNT_IN   = 4'd14;

    localparam [7:0]  CMD_BEGIN = 8'h50;
    localparam [7:0]  CMD_EVENT = 8'h51;
    localparam [7:0]  CMD_SEAL  = 8'h52;
    localparam [7:0]  CMD_PLAY  = 8'h53;
    localparam [7:0]  CMD_GUIDE = 8'h59; // Same timeline; caller isolates MIDI from the synth.
    // Explicit new command; old 0x59 always retains its original behavior.
    // D0 speed percent, D1 wait-for-key, D2 count-in beats (0 or 4),
    // D3..4 milliseconds/beat, D5..7 ASCII "GP1".
    localparam [7:0]  CMD_PRACTICE = 8'h5A;
    localparam [7:0]  CMD_STOP  = 8'h54;
    localparam [7:0]  CMD_PROBE = 8'h55;
    localparam [7:0]  CMD_VOLUME = 8'h56;
    localparam [7:0]  CMD_CLEAR = 8'h58; // Internal reliable-owner abort; not forwarded by the v1 decoder.

    localparam [31:0] CRC_INIT = 32'hFFFFFFFF;
    localparam [31:0] CRC_POLY = 32'hEDB88320;
    localparam [31:0] DELAY_MAX = 32'd600000;
    localparam [15:0] PROBE_EVENTS = 16'd2048;

    // Events really storable: the protocol cap and the RAM depth both apply.
    // v1 count/index fields are 16 bits. Counts include the one-past-end value;
    // RAM addresses do not. In particular 8192 needs 14 count bits, 13 address bits.
    localparam [15:0] EFF_MAX16 = MAX_EVENTS;

    // Invalid profiles must fail rather than advertise a truncated capacity.
    initial begin
        if (MAX_EVENTS < 1 || MAX_EVENTS > RAM_DEPTH || RAM_DEPTH > 65535)
            $error("score_player requires 1 <= MAX_EVENTS <= RAM_DEPTH <= 65535");
    end

    localparam integer IDX_W = (RAM_DEPTH < 2) ? 1 : $clog2(RAM_DEPTH);

    // 1 ms clock enable.  CLK_HZ/1000 is clamped to >= 2 so the divider always
    // has at least one counting state and the tick cannot free-run.
    localparam integer MS_DIV = ((CLK_HZ / 1000) < 2) ? 2 : (CLK_HZ / 1000);
    localparam integer MS_W   = (MS_DIV < 2) ? 1 : $clog2(MS_DIV);
    localparam [MS_W-1:0] MS_LAST = MS_DIV - 1;

    // ------------------------------------------------------------------
    // Reflected CRC32 helpers (bit serial, two bits per clock).
    // ------------------------------------------------------------------
    function [31:0] crc_step;
        input [31:0] current;
        input        bit_in;
        begin
            crc_step = (current >> 1) ^
                       ((current[0] ^ bit_in) ? CRC_POLY : 32'h00000000);
        end
    endfunction

    function [31:0] crc_step2;
        input [31:0] current;
        input        bit_lo;
        input        bit_hi;
        reg   [31:0] intermediate;
        begin
            intermediate = crc_step(current, bit_lo);
            crc_step2    = crc_step(intermediate, bit_hi);
        end
    endfunction

    // Byte n of the six CRC bytes: n = 0 -> D2 ... n = 5 -> D7.
    function [7:0] crc_byte_sel;
        input [2:0]  n;
        input [47:0] data48;
        begin
            case (n)
                3'd0: crc_byte_sel = data48[7:0];
                3'd1: crc_byte_sel = data48[15:8];
                3'd2: crc_byte_sel = data48[23:16];
                3'd3: crc_byte_sel = data48[31:24];
                3'd4: crc_byte_sel = data48[39:32];
                3'd5: crc_byte_sel = data48[47:40];
                default: crc_byte_sel = 8'd0;
            endcase
        end
    endfunction

    function [31:0] event_word;
        input [7:0] note;
        input [7:0] velocity;
        begin
            event_word = (velocity == 8'd0) ? {8'h08, 8'h80, note, 8'd0}
                                            : {8'h09, 8'h90, note, velocity};
        end
    endfunction

    // ------------------------------------------------------------------
    // Event RAM: one synchronous write port, one synchronous read port.
    // Never reset, so it maps to BSRAM instead of 2048 x 48 flops.
    // ------------------------------------------------------------------
    reg [47:0] score_ram [0:RAM_DEPTH-1];
    reg [47:0] ram_rdata;
    reg [IDX_W-1:0] ram_raddr;

    reg  [3:0]  state;
    reg  [15:0] event_count;
    reg  [15:0] upload_index;
    reg  [31:0] crc_reg;
    assign upload_crc32 = ~crc_reg;
    reg  [2:0]  crc_byte_idx;
    reg  [2:0]  crc_bit_idx;
    reg  [7:0]  crc_byte;
    reg  [47:0] crc_data;
    reg  [31:0] ms_count;
    reg  [MS_W-1:0] ms_div_cnt;
    reg  [IDX_W-1:0] cur_index;
    reg  [7:0]  ev_note;
    reg  [7:0]  ev_velocity;
    reg  [6:0]  ev_physical;
    reg  [4:0]  ev_key_index;
    reg         score_mapped;
    assign key_plan_active = ENABLE_KEY_PLAN && score_mapped && playing;
    reg  [7:0]  practice_speed, speed_remainder;
    reg         practice_wait;
    reg  [127:0] required_notes;
    reg  [31:0] count_in_remaining;
    reg  [15:0] beat_period, beat_phase;
    wire [8:0] speed_sum = {1'b0,speed_remainder}+{1'b0,practice_speed};
    wire [1:0] speed_step = speed_sum >= 9'd200 ? 2'd2 : speed_sum >= 9'd100 ? 2'd1 : 2'd0;
    assign guide_count_in = playing && (state == S_COUNT_IN);
    assign guide_beat_active = guide_count_in && (beat_phase < 16'd50);
    reg         pending_valid;
    reg  [7:0]  pending_command;
    reg  [63:0] pending_payload;

    // ------------------------------------------------------------------
    // Command selection: a parked command has priority, otherwise the live one.
    // ------------------------------------------------------------------
    wire        disp_valid   = pending_valid ? 1'b1 : cmd_valid;
    wire [7:0]  disp_command = pending_valid ? pending_command : cmd_command;
    wire [63:0] disp_payload = pending_valid ? pending_payload : cmd_payload;

    // The CRC engine is the only multi-cycle accept path; everything else
    // (including STOP while a score is playing) is answered in one clock.
    wire dispatch_en = disp_valid && (state != S_EV_CRC);

    wire [47:0] ev_bytes = disp_payload[63:16];        // {D7,D6,D5,D4,D3,D2}
    wire [7:0]  ev_note_in  = disp_payload[55:48];
    wire [7:0]  ev_vel_in   = disp_payload[63:56];
    wire [31:0] ev_delay_in = disp_payload[47:16];

    wire ev_index_ok = (disp_payload[15:0] == upload_index) &&
                       (upload_index < event_count);
    wire ev_field_ok = (score_mapped
                       ? (ev_delay_in[31:25] == 0 && ev_delay_in[24:20] < 25 &&
                          {12'd0,ev_delay_in[19:0]} <= DELAY_MAX)
                       : (ev_delay_in <= DELAY_MAX)) &&
                       (ev_note_in < 8'd128) && (ev_vel_in < 8'd128);
    wire ev_accept   = dispatch_en && (disp_command == CMD_EVENT) &&
                       !playing && !flush_active && ev_index_ok && ev_field_ok;

    wire begin_ok = dispatch_en && (disp_command == CMD_BEGIN) &&
                    !playing && !flush_active &&
                    (disp_payload[15:0] >= 16'd1) &&
                    (disp_payload[15:0] <= EFF_MAX16) &&
                    (((disp_payload[23:16] == 8'd1) && (disp_payload[63:24] == 40'd0)) ||
                     (ENABLE_KEY_PLAN && disp_payload[23:16] == 8'd2 &&
                      disp_payload[31:24] <= 8'd103 && disp_payload[63:32] == 0));

    wire seal_ok = dispatch_en && (disp_command == CMD_SEAL) &&
                   !playing && !flush_active &&
                   (event_count != 16'd0) &&
                   (disp_payload[47:32] == event_count) &&
                   (upload_index == event_count) &&
                   (disp_payload[55:48] == (score_mapped ? 8'd2 : 8'd1)) &&
                   (disp_payload[63:56] == 8'd0) &&
                   (disp_payload[31:0] == ~crc_reg);

    wire practice_fields_ok = disp_payload[7:0] >= 8'd50 && disp_payload[7:0] <= 8'd150 &&
                   disp_payload[15:8] <= 8'd1 &&
                   (disp_payload[23:16] == 8'd0 || disp_payload[23:16] == 8'd4) &&
                   disp_payload[39:24] >= 16'd1 && disp_payload[39:24] <= 16'd60000 &&
                   disp_payload[63:40] == 24'h315047;
    wire play_ok = dispatch_en && loaded && !playing && !flush_active &&
                   (!score_mapped || (ENABLE_KEY_PLAN && key_plan_allowed && disp_command == CMD_PRACTICE)) &&
                   (((disp_command == CMD_PLAY || disp_command == CMD_GUIDE) && disp_payload == 64'd0) ||
                    (disp_command == CMD_PRACTICE && practice_fields_ok));

    wire stop_ok = dispatch_en && (disp_command == CMD_STOP) &&
                   (disp_payload == 64'd0);

    wire probe_ok = dispatch_en && (disp_command == CMD_PROBE) &&
                    (disp_payload == 64'd0) && (EFF_MAX16 >= PROBE_EVENTS);

    // Ram write port (combinational enable from the accept condition).
    wire            ram_write_en = ev_accept;
    wire [IDX_W-1:0] ram_write_addr = upload_index[IDX_W-1:0];
    wire [47:0]     ram_write_data =
        {disp_payload[63:56], disp_payload[55:48], disp_payload[47:16]};

    always @(posedge clk) begin
        if (ram_write_en)
            score_ram[ram_write_addr] <= ram_write_data;
        ram_rdata <= score_ram[ram_raddr];
    end

    // ------------------------------------------------------------------
    // 1 ms clock enable and playback index arithmetic.
    // ------------------------------------------------------------------
    wire ms_tick = (ms_div_cnt == MS_LAST);
    wire [15:0] cur_index_ext = {{(16-IDX_W){1'b0}}, cur_index};
    wire [15:0] cur_index_p1  = cur_index_ext + 16'd1;
    wire        cur_is_last   = (cur_index_p1 >= event_count);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state          <= S_IDLE;
            event_count    <= 16'd0;
            upload_index   <= 16'd0;
            crc_reg        <= CRC_INIT;
            crc_byte_idx   <= 3'd0;
            crc_bit_idx    <= 3'd0;
            crc_byte       <= 8'd0;
            crc_data       <= 48'd0;
            ms_count       <= 32'd0;
            ms_div_cnt     <= {MS_W{1'b0}};
            cur_index      <= {IDX_W{1'b0}};
            ev_note        <= 8'd0;
            ev_velocity    <= 8'd0;
            ev_physical    <= 0;ev_key_index <= 0;score_mapped <= 0;
            key_plan_first <= 0;key_plan_valid <= 0;key_plan_notes <= 0;
            practice_speed <= 8'd100; speed_remainder <= 0; practice_wait <= 0;
            required_notes <= 0; count_in_remaining <= 0;beat_period <= 16'd500;beat_phase <= 0;
            ram_raddr      <= {IDX_W{1'b0}};
            pending_valid  <= 1'b0;
            pending_command <= 8'd0;
            pending_payload <= 64'd0;

            score_done     <= 1'b0;
            score_error    <= 1'b0;
            midi_event_data <= 32'd0;
            midi_event_valid <= 1'b0;
            volume_event_data <= 32'd0;
            volume_event_valid <= 1'b0;
            guide_mask     <= 128'd0;
            loaded         <= 1'b0;
            playing        <= 1'b0;
            flush_active   <= 1'b0;
        end else begin
            // One-clock status pulses; the dispatch below may still raise one.
            score_done  <= 1'b0;
            score_error <= 1'b0;
            if (volume_event_valid && volume_event_ready)
                volume_event_valid <= 1'b0;

            // Free running 1 ms divider; states that load a fresh delay
            // restart it so a delta of N ms is exactly N milliseconds.
            if (ms_tick) ms_div_cnt <= {MS_W{1'b0}};
            else         ms_div_cnt <= ms_div_cnt + 1'b1;

            // The countdown lives outside the command dispatch so that an
            // incoming command can never swallow a millisecond tick.
            if (playing && ms_tick && (state == S_PLAY_WAIT || state == S_COUNT_IN)) begin
                speed_remainder <= speed_sum - speed_step*9'd100;
                if (state == S_PLAY_WAIT && ms_count != 0) begin
                    if (ms_count <= {30'd0,speed_step}) ms_count <= 0;
                    else ms_count <= ms_count - {30'd0,speed_step};
                end
                if (state == S_COUNT_IN) begin
                    if (count_in_remaining <= {30'd0,speed_step}) count_in_remaining <= 0;
                    else count_in_remaining <= count_in_remaining-{30'd0,speed_step};
                    if ({1'b0,beat_phase}+{15'd0,speed_step} >= {1'b0,beat_period})
                        beat_phase <= {1'b0,beat_phase}+{15'd0,speed_step}-{1'b0,beat_period};
                    else beat_phase <= beat_phase+{14'd0,speed_step};
                end
            end
            if (playing && practice_wait && fresh_key_valid && required_notes[fresh_key_note]) begin
                required_notes[fresh_key_note] <= 1'b0;
                guide_mask[fresh_key_note] <= 1'b0;
            end

            begin
                // ------------------------------------------------------
                // Playback, CRC and note-off flush engine.
                // ------------------------------------------------------
                case (state)
                    S_EV_CRC: begin
                        crc_reg <= crc_step2(crc_reg, crc_byte[crc_bit_idx],
                                             crc_byte[crc_bit_idx + 1'b1]);
                        if (crc_bit_idx == 3'd6) begin
                            if (crc_byte_idx == 3'd5) begin
                                state      <= S_IDLE;
                                score_done <= 1'b1;
                            end else begin
                                crc_byte_idx <= crc_byte_idx + 1'b1;
                                crc_byte     <= crc_byte_sel(crc_byte_idx + 1'b1,
                                                             crc_data);
                                crc_bit_idx  <= 3'd0;
                            end
                        end else begin
                            crc_bit_idx <= crc_bit_idx + 2'd2;
                        end
                    end

                    S_PLAY_FETCH: begin
                        // Address out; data arrives after the next clock.
                        ram_raddr <= cur_index;
                        state     <= S_PLAY_RDEN;
                    end

                    S_PLAY_RDEN: begin
                        state <= S_PLAY_LATCH;
                    end


                    S_PLAY_LATCH: begin
                        ms_count    <= practice_wait ? 32'd0 : (score_mapped ? {12'd0,ram_rdata[19:0]} : ram_rdata[31:0]);
                        ev_note     <= ram_rdata[39:32];
                        ev_velocity <= ram_rdata[47:40];
                        ev_key_index <= ram_rdata[24:20];
                        ev_physical <= score_mapped ? key_plan_first + {2'd0,ram_rdata[24:20]} : ram_rdata[38:32];
                        ms_div_cnt  <= {MS_W{1'b0}};
                        // Consume all events at a timestamp as one chord; wait
                        // for every newly required key before the next group.
                        state <= practice_wait && (score_mapped ? (ram_rdata[19:0] != 0) : (ram_rdata[31:0] != 0)) && |required_notes
                                 ? S_WAIT_KEYS : S_PLAY_WAIT;
                    end

                    S_WAIT_KEYS: if (required_notes == 0) state <= S_PLAY_WAIT;

                    S_COUNT_IN: begin
                        if (count_in_remaining == 0 ||
                            (ms_tick && speed_step != 0 && count_in_remaining <= {30'd0,speed_step})) begin
                            ms_div_cnt <= 0;
                            state <= S_PLAY_FETCH;
                        end
                    end

                    S_PLAY_WAIT: begin
                        // A zero delta is issued straight away, so a chord is
                        // never pushed into the next millisecond.  The actual
                        // decrement happens above, outside the dispatch path.
                        if (ms_count == 32'd0) begin
                            state <= S_PLAY_ISSUE;
                        end else if (ms_tick && speed_step != 0 && ms_count <= {30'd0,speed_step}) begin
                            state <= S_PLAY_ISSUE;
                        end
                    end

                    S_PLAY_ISSUE: begin
                        midi_event_data  <= event_word(score_mapped ? {1'b0,ev_physical} : ev_note, ev_velocity);
                        midi_event_valid <= 1'b1;
                        state            <= S_PLAY_HOLD;
                    end

                    S_PLAY_HOLD: begin
                        // Data and valid stay stable until ready arrives.
                        if (midi_event_ready) begin
                            midi_event_valid <= 1'b0;
                            if (midi_event_data[23:16] == 8'h90)
                                guide_mask[midi_event_data[15:8]] <= 1'b1;
                            else
                                guide_mask[midi_event_data[15:8]] <= 1'b0;
                            if (practice_wait)
                                required_notes[midi_event_data[14:8]] <= (midi_event_data[23:16] == 8'h90);
                            if (score_mapped) begin
                                key_plan_valid[ev_key_index] <= ev_velocity != 0;
                                if (ev_velocity != 0) key_plan_notes[ev_key_index*7 +: 7] <= ev_note[6:0];
                            end

                            if (cur_is_last) begin
                                // Score finished: release the pedal and stop
                                // all notes before clearing the mask.
                                playing       <= 1'b0;
                                key_plan_valid <= 0;
                                flush_active  <= 1'b1;
                                state         <= S_FLUSH_A;
                            end else begin
                                cur_index <= cur_index + 1'b1;
                                state     <= S_PLAY_FETCH;
                            end
                        end
                    end

                    S_STOP_DRAIN: begin
                        // The arbiter may already hold this event. Do not revoke
                        // valid/data; drain exactly once, then release all notes.
                        if (midi_event_ready) begin
                            midi_event_valid <= 1'b0;
                            guide_mask[midi_event_data[15:8]] <=
                                (midi_event_data[23:16] == 8'h90);
                            state <= S_FLUSH_A;
                        end
                    end

                    S_FLUSH_A: begin
                        midi_event_data  <= {8'h0B, 8'hB0, 8'd64, 8'd0};
                        midi_event_valid <= 1'b1;
                        state            <= S_FLUSH_AH;
                    end

                    S_FLUSH_AH: begin
                        if (midi_event_ready) begin
                            midi_event_valid <= 1'b0;
                            state            <= S_FLUSH_B;
                        end
                    end

                    S_FLUSH_B: begin
                        midi_event_data  <= {8'h0B, 8'hB0, 8'd123, 8'd0};
                        midi_event_valid <= 1'b1;
                        state            <= S_FLUSH_BH;
                    end

                    S_FLUSH_BH: begin
                        if (midi_event_ready) begin
                            midi_event_valid <= 1'b0;
                            guide_mask       <= 128'd0;
                            required_notes   <= 128'd0;
                            flush_active     <= 1'b0;
                            state            <= S_IDLE;
                        end
                    end

                    default: state <= S_IDLE;
                endcase
            end

            if (dispatch_en) begin
                // ------------------------------------------------------
                // Command dispatch.  Runs in every state except the CRC
                // window, so STOP is answered without waiting for anything.
                // ------------------------------------------------------
                case (disp_command)
                    CMD_CLEAR: begin
                        if(!playing && !flush_active && disp_payload==64'd0) begin
                            event_count <= 0;upload_index <= 0;crc_reg <= CRC_INIT;
                            loaded <= 0;guide_mask <= 0;key_plan_valid <= 0;score_done <= 1'b1;
                        end else score_error <= 1'b1;
                    end
                    CMD_VOLUME: begin
                        if ((disp_payload[63:8] == 56'd0) &&
                            (disp_payload[7:0] < 8'd128) &&
                            (!volume_event_valid || volume_event_ready)) begin
                            volume_event_data <= {8'h0B,8'hB0,8'd20,disp_payload[7:0]};
                            volume_event_valid <= 1'b1;
                            score_done <= 1'b1;
                        end else score_error <= 1'b1;
                    end
                    CMD_PROBE: begin
                        if (probe_ok) score_done  <= 1'b1;
                        else          score_error <= 1'b1;
                    end

                    CMD_BEGIN: begin
                        if (begin_ok) begin
                            event_count  <= disp_payload[15:0];
                            upload_index <= 16'd0;
                            crc_reg      <= CRC_INIT;
                            loaded       <= 1'b0;
                            guide_mask   <= 128'd0;
                            score_mapped <= ENABLE_KEY_PLAN && disp_payload[23:16] == 8'd2;
                            key_plan_first <= disp_payload[30:24];key_plan_valid <= 0;
                            score_done   <= 1'b1;
                        end else begin
                            score_error <= 1'b1;
                        end
                    end

                    CMD_EVENT: begin
                        if (ev_accept) begin
                            // RAM write happens on this edge via ram_write_en;
                            // the ACK waits until the CRC has merged D2..D7.
                            upload_index <= upload_index + 16'd1;
                            crc_data     <= ev_bytes;
                            crc_byte     <= crc_byte_sel(3'd0, ev_bytes);
                            crc_byte_idx <= 3'd0;
                            crc_bit_idx  <= 3'd0;
                            state        <= S_EV_CRC;
                        end else begin
                            score_error <= 1'b1;
                        end
                    end

                    CMD_SEAL: begin
                        if (seal_ok) begin
                            loaded     <= 1'b1;
                            score_done <= 1'b1;
                        end else begin
                            score_error <= 1'b1;
                        end
                    end

                    CMD_PLAY, CMD_GUIDE, CMD_PRACTICE: begin
                        if (play_ok) begin
                            playing      <= 1'b1;
                            cur_index    <= {IDX_W{1'b0}};
                            ms_div_cnt   <= {MS_W{1'b0}};
                            practice_speed <= (disp_command == CMD_PRACTICE) ? disp_payload[7:0] : 8'd100;
                            practice_wait <= (disp_command == CMD_PRACTICE) && disp_payload[8];
                            key_plan_valid <= 0;
                            speed_remainder <= 0;required_notes <= 0;beat_phase <= 0;
                            beat_period <= (disp_command == CMD_PRACTICE) ? disp_payload[39:24] : 16'd500;
                            count_in_remaining <= (disp_command == CMD_PRACTICE && disp_payload[23:16] == 8'd4)
                                ? ({16'd0,disp_payload[39:24]} << 2) : 32'd0;
                            state <= (disp_command == CMD_PRACTICE && disp_payload[23:16] == 8'd4) ? S_COUNT_IN : S_PLAY_FETCH;
                            score_done   <= 1'b1;
                        end else begin
                            score_error <= 1'b1;
                        end
                    end

                    CMD_STOP: begin
                        if (stop_ok) begin
                            // Immediate ACK; the flush continues on its own.
                            // Drain an already presented event without changing
                            // its handshake, then prioritize the CC flush pair.
                            score_done <= 1'b1;
                            if (!flush_active) begin
                                playing <= 1'b0;
                                key_plan_valid <= 0;
                                flush_active <= 1'b1;
                                if (midi_event_valid && !midi_event_ready)
                                    state <= S_STOP_DRAIN;
                                else begin
                                    midi_event_valid <= 1'b0;
                                    state <= S_FLUSH_A;
                                end
                            end
                        end else begin
                            score_error <= 1'b1;
                        end
                    end

                    default: begin
                        // synth_uart_control only forwards 0x50..0x55; anything
                        // else is an unknown score command.
                        score_error <= 1'b1;
                    end
                endcase

                if (pending_valid) pending_valid <= 1'b0;
            end

            // A command that lands inside the CRC window is parked so that no
            // packet is dropped; it is dispatched as soon as the CRC frees up.
            if (cmd_valid && (state == S_EV_CRC) && !pending_valid) begin
                pending_valid   <= 1'b1;
                pending_command <= cmd_command;
                pending_payload <= cmd_payload;
            end
        end
    end

endmodule
