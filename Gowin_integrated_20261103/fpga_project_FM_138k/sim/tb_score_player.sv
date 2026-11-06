// -----------------------------------------------------------------------------
// tb_score_player.sv
//
// Self-checking testbench for score_player (score protocol v1).
//
// simulate.ps1 builds this source twice:
//   * score_fast    : -GRAM_DEPTH=8 -GMAX_EVENTS=8 -GCLK_HZ=50000
//                     small RAM, 50 clocks per millisecond -> quick timing runs
//   * score_default : default parameters (2048 x 48 RAM, 50 MHz)
//                     real resource shape, real 50000 clocks per millisecond
//
// Coverage:
//   1. CRC32 model against the IEEE known vector 0xCBF43926 ("123456789")
//   2. PROBE (zero payload and non-zero payload)
//   3. BEGIN validation: count zero, count above the limit, wrong version,
//      reserved bits set, and the maximum legal count
//   4. EVENT validation: duplicate/out-of-order index, index past count,
//      delay above 600000, note > 127, velocity > 127
//   5. Reply latency budget (must answer well inside the bridge's 100 clocks)
//   6. SEAL: bad CRC, bad count, bad version, reserved bits, correct seal
//   7. PLAY refused before a seal / with a non-zero payload / while playing
//   8. Natural end: every event, then CC64=0 then CC123=0, mask cleared
//   9. Zero-delay chord: simultaneous events are not pushed to the next ms
//  10. Back pressure: valid stays high with stable data, nothing is dropped
//  11. STOP: immediate acknowledge, CC64/CC123 in order, guide_mask cleared,
//      BEGIN/PLAY/EVENT refused while the flush is pending, and unsent events
//      are really dropped
//  12. Re-upload after a seal (BEGIN clears loaded), replay after a stop
//  13. 2048-event boundary on the default build
//
// Only assert / $fatal / $display are used: no force, no vendor IP.
// Every bookkeeping variable has exactly one writing process, so the checks
// never race with the monitors (the initial block only reads them).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_score_player #(
    parameter integer RAM_DEPTH  = 2048,
    parameter integer MAX_EVENTS = 2048,
    parameter integer CLK_HZ     = 50000000
);
    localparam integer MS_DIV  = ((CLK_HZ / 1000) < 2) ? 2 : (CLK_HZ / 1000);
    localparam integer BIG_RAM = (MAX_EVENTS >= 2048) && (RAM_DEPTH >= 2048);
    localparam integer MAX_CAP = 4096;

    localparam [31:0] W_CC64  = {8'h0B, 8'hB0, 8'd64,  8'd0};
    localparam [31:0] W_CC123 = {8'h0B, 8'hB0, 8'd123, 8'd0};

    reg clk = 1'b0;
    always #10 clk = ~clk;               // 50 MHz

    reg reset_n = 1'b0;

    reg         cmd_valid   = 1'b0;
    reg  [7:0]  cmd_command = 8'd0;
    reg  [63:0] cmd_payload = 64'd0;
    wire        score_done;
    wire        score_error;
    wire [31:0] midi_event_data;
    wire        midi_event_valid;
    reg         midi_event_ready = 1'b1;
    wire [127:0] guide_mask;
    wire        loaded;
    wire        playing;
    wire        flush_active;

    score_player #(
        .RAM_DEPTH(RAM_DEPTH),
        .MAX_EVENTS(MAX_EVENTS),
        .CLK_HZ(CLK_HZ)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .cmd_valid(cmd_valid),
        .cmd_command(cmd_command),
        .cmd_payload(cmd_payload),
        .score_done(score_done),
        .score_error(score_error),
        .midi_event_data(midi_event_data),
        .midi_event_valid(midi_event_valid),
        .midi_event_ready(midi_event_ready),
        .volume_event_data(volume_data), .volume_event_valid(volume_valid),
        .volume_event_ready(volume_ready),
        .guide_mask(guide_mask),
        .loaded(loaded),
        .playing(playing),
        .flush_active(flush_active)
    );

    // ------------------------------------------------------------------
    // Event sink with programmable back pressure.
    // ------------------------------------------------------------------
    integer stall_cycles = 0;            // written by the stimulus only
    integer stall_left   = 0;
    reg sink_block = 0;
    wire [31:0] volume_data;
    wire volume_valid;
    reg volume_ready = 1;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            midi_event_ready <= 1'b1;
            stall_left       <= 0;
        end else if (sink_block) begin
            midi_event_ready <= 1'b0;
            stall_left <= 0;
        end else if (midi_event_valid && midi_event_ready) begin
            stall_left       <= stall_cycles;
            midi_event_ready <= (stall_cycles == 0);
        end else if (stall_left > 0) begin
            stall_left       <= stall_left - 1;
            midi_event_ready <= (stall_left == 1);
        end else begin
            midi_event_ready <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Monitors (the only writers of their own bookkeeping).
    // ------------------------------------------------------------------
    reg [31:0]  captured [0:MAX_CAP-1];
    integer     captured_cycle [0:MAX_CAP-1];
    integer     captured_total = 0;
    integer     cycle_counter  = 0;

    integer     status_seq     = 0;
    reg  [7:0]  status_value   = 8'h00;
    integer     status_latency = 0;
    integer     max_latency    = 0;
    integer     cmd_age        = 0;
    integer     reply_count    = 0;

    always @(posedge clk) begin
        if (!reset_n) begin
            cycle_counter <= 0;
        end else begin
            cycle_counter <= cycle_counter + 1;
        end

        if (cmd_valid) cmd_age <= 0;
        else if (cmd_age < 1000000) cmd_age <= cmd_age + 1;

        if (reset_n && (score_done || score_error)) begin
            status_seq     <= status_seq + 1;
            status_value   <= score_done ? 8'h00 : 8'h01;
            status_latency <= cmd_age + 1;
            reply_count    <= reply_count + 1;
            if ((cmd_age + 1) > max_latency) max_latency <= cmd_age + 1;
        end

        if (reset_n && midi_event_valid && midi_event_ready) begin
            captured[captured_total]       = midi_event_data;
            captured_cycle[captured_total] = cycle_counter;
            captured_total                 = captured_total + 1;
        end
    end

    // Valid must stay asserted with stable data while ready is low.
    reg        bp_active = 1'b0;
    reg [31:0] bp_data   = 32'd0;

    always @(posedge clk) begin
        if (!reset_n) begin
            bp_active <= 1'b0;
        end else begin
            if (bp_active) begin
                if (!midi_event_valid)
                    $fatal(1, "midi_event_valid dropped under back pressure");
                if (midi_event_data !== bp_data)
                    $fatal(1, "midi_event_data changed under back pressure");
            end
            if (midi_event_valid && !midi_event_ready) begin
                bp_active <= 1'b1;
                bp_data   <= midi_event_data;
            end else begin
                bp_active <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------
    // CRC32 model (bit serial, reflected) and event bookkeeping.
    // ------------------------------------------------------------------
    reg [31:0] model_crc;
    integer    model_count;
    integer    cap_base = 0;             // written by the stimulus only

    function automatic [31:0] crc_byte(input [31:0] current, input [7:0] value);
        reg [31:0] x;
        begin
            x = current;
            for (integer b = 0; b < 8; b = b + 1)
                x = (x >> 1) ^ ((x[0] ^ value[b]) ? 32'hEDB88320 : 32'h00000000);
            crc_byte = x;
        end
    endfunction

    task automatic crc_reset;
        begin
            model_crc   = 32'hFFFFFFFF;
            model_count = 0;
        end
    endtask

    // ------------------------------------------------------------------
    // Stimulus helpers.
    // ------------------------------------------------------------------
    task automatic send_cmd(input [7:0] cmd, input [63:0] data);
        begin
            @(negedge clk);
            cmd_command = cmd;
            cmd_payload = data;
            cmd_valid   = 1'b1;
            @(negedge clk);
            cmd_valid   = 1'b0;
        end
    endtask

    task automatic expect_status(input [7:0] want, input string what);
        integer base;
        integer guard;
        begin
            base  = status_seq;
            guard = 0;
            while ((status_seq == base) && (guard < 40000)) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (status_seq == base)
                $fatal(1, "%s: no reply at all", what);
            if (status_value !== want)
                $fatal(1, "%s: status %0d, expected %0d", what, status_value, want);
            if (status_latency >= 100)
                $fatal(1, "%s: reply took %0d clocks (budget 100)", what, status_latency);
        end
    endtask

    task automatic send_expect(input [7:0] cmd, input [63:0] data,
                               input [7:0] want, input string what);
        begin
            send_cmd(cmd, data);
            expect_status(want, what);
        end
    endtask

    task automatic send_begin(input [15:0] count, input [7:0] version,
                              input [39:0] reserved, input [7:0] want,
                              input string what);
        begin
            send_cmd(8'h50, {reserved, version, count});
            expect_status(want, what);
            if (want == 8'h00) crc_reset;
        end
    endtask

    // Accepts one event, checks the ACK, and folds D2..D7 into the CRC model.
    task automatic send_event_ok(input integer index, input [31:0] delay_ms,
                                 input [7:0] note, input [7:0] velocity);
        begin
            send_cmd(8'h51, {velocity, note, delay_ms, index[15:0]});
            expect_status(8'h00, "EVENT accepted");
            model_crc   = crc_byte(model_crc, delay_ms[7:0]);
            model_crc   = crc_byte(model_crc, delay_ms[15:8]);
            model_crc   = crc_byte(model_crc, delay_ms[23:16]);
            model_crc   = crc_byte(model_crc, delay_ms[31:24]);
            model_crc   = crc_byte(model_crc, note);
            model_crc   = crc_byte(model_crc, velocity);
            model_count = model_count + 1;
        end
    endtask

    task automatic send_seal(input [31:0] crc_value, input [15:0] count,
                             input [7:0] version, input [7:0] reserved,
                             input [7:0] want, input string what);
        begin
            send_cmd(8'h52, {reserved, version, count, crc_value});
            expect_status(want, what);
        end
    endtask

    task automatic seal_current(input [7:0] want, input string what);
        begin
            send_seal(~model_crc, model_count[15:0], 8'd1, 8'd0, want, what);
        end
    endtask

    task automatic wait_events(input integer want, input integer timeout);
        integer guard;
        begin
            guard = 0;
            while (((captured_total - cap_base) < want) && (guard < timeout)) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if ((captured_total - cap_base) < want)
                $fatal(1, "timed out waiting for %0d events, captured %0d",
                       want, captured_total - cap_base);
        end
    endtask

    task automatic check_event(input integer index, input [31:0] want,
                               input string what);
        begin
            if (captured[cap_base + index] !== want)
                $fatal(1, "%s: event %0d = %h, expected %h",
                       what, index, captured[cap_base + index], want);
        end
    endtask

    task automatic check_gap(input integer from_index, input integer to_index,
                             input integer ms, input string what);
        integer want;
        integer got;
        begin
            want = ms * MS_DIV;
            got  = captured_cycle[cap_base + to_index] -
                   captured_cycle[cap_base + from_index];
            if (got < want || got > (want + 10))
                $fatal(1, "%s: gap %0d cycles, expected %0d..%0d",
                       what, got, want, want + 10);
        end
    endtask

    task automatic check_chord_gap(input integer from_index, input integer to_index,
                                   input string what);
        integer got;
        begin
            got = captured_cycle[cap_base + to_index] -
                  captured_cycle[cap_base + from_index];
            if (got > 10)
                $fatal(1, "%s: zero-delta events %0d cycles apart", what, got);
        end
    endtask

    task automatic wait_settled(input integer timeout);
        integer guard;
        begin
            guard = 0;
            while ((playing || flush_active) && (guard < timeout)) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (playing || flush_active)
                $fatal(1, "player never settled (playing=%b flush=%b)",
                       playing, flush_active);
        end
    endtask

    task automatic clear_captured;
        begin
            @(negedge clk);
            cap_base = captured_total;
        end
    endtask

    // ------------------------------------------------------------------
    // Main sequence.
    // ------------------------------------------------------------------
    integer i;
    integer note_id;

    initial begin
        reg [31:0] vector_crc;

        // ---- 1. CRC32 model known vector ---------------------------------
        // ASCII "123456789" must give the IEEE reflected CRC32 0xCBF43926.
        vector_crc = 32'hFFFFFFFF;
        vector_crc = crc_byte(vector_crc, 8'h31);
        vector_crc = crc_byte(vector_crc, 8'h32);
        vector_crc = crc_byte(vector_crc, 8'h33);
        vector_crc = crc_byte(vector_crc, 8'h34);
        vector_crc = crc_byte(vector_crc, 8'h35);
        vector_crc = crc_byte(vector_crc, 8'h36);
        vector_crc = crc_byte(vector_crc, 8'h37);
        vector_crc = crc_byte(vector_crc, 8'h38);
        vector_crc = crc_byte(vector_crc, 8'h39);
        if (~vector_crc !== 32'hCBF43926)
            $fatal(1, "CRC32 model known vector %h != CBF43926", vector_crc);

        repeat (8) @(negedge clk);
        reset_n = 1'b1;
        repeat (4) @(negedge clk);

        if (loaded || playing || flush_active || (guide_mask != 0))
            $fatal(1, "reset state is not idle");
        clear_captured;

        // ---- 2. PROBE ----------------------------------------------------
        send_expect(8'h55, 64'd0, BIG_RAM ? 8'h00 : 8'h01,
                    "PROBE zero payload");
        send_expect(8'h55, 64'h0000000000000001, 8'h01, "PROBE with payload");
        send_expect(8'h52, 64'd0, 8'h01, "SEAL before any BEGIN");

        // ---- 3. BEGIN validation -----------------------------------------
        send_begin(16'd0, 8'd1, 40'd0, 8'h01, "BEGIN count zero");
        send_begin(16'(MAX_EVENTS + 1), 8'd1, 40'd0, 8'h01, "BEGIN count too large");
        send_begin(16'd4, 8'd2, 40'd0, 8'h01, "BEGIN wrong version");
        send_begin(16'd4, 8'd1, 40'h0000000001, 8'h01, "BEGIN reserved bits set");
        send_begin(16'(MAX_EVENTS), 8'd1, 40'd0, 8'h00, "BEGIN maximum count");

        // ---- 4. EVENT validation (nothing sealed) ------------------------
        send_expect(8'h51, {8'd100, 8'd60, 32'd0, 16'd1},
                    8'h01, "EVENT out-of-order index");
        send_expect(8'h51, {8'd100, 8'd60, 32'd600001, 16'd0},
                    8'h01, "EVENT delay above 600000");
        send_expect(8'h51, {8'd100, 8'd128, 32'd0, 16'd0},
                    8'h01, "EVENT note above 127");
        send_expect(8'h51, {8'd128, 8'd60, 32'd0, 16'd0},
                    8'h01, "EVENT velocity above 127");
        send_expect(8'h53, 64'd0, 8'h01, "PLAY before SEAL");
        send_expect(8'h53, 64'h1, 8'h01, "PLAY with non-zero payload");
        send_expect(8'h52, 64'd0, 8'h01, "SEAL with an incomplete upload");

        // ---- 5/6. Real upload, seal validation, natural end --------------
        send_begin(16'd4, 8'd1, 40'd0, 8'h00, "BEGIN four events");
        send_event_ok(0, 32'd0, 8'd60, 8'd100);
        send_event_ok(1, 32'd1, 8'd64, 8'd100);
        send_event_ok(2, 32'd1, 8'd60, 8'd0);
        send_event_ok(3, 32'd2, 8'd64, 8'd0);
        send_expect(8'h51, {8'd0, 8'd65, 32'd0, 16'd4},
                    8'h01, "EVENT index past count");

        send_seal(~model_crc ^ 32'h1, 16'd4, 8'd1, 8'd0, 8'h01, "SEAL bad CRC");
        send_seal(~model_crc, 16'd3, 8'd1, 8'd0, 8'h01, "SEAL bad count");
        send_seal(~model_crc, 16'd4, 8'd2, 8'd0, 8'h01, "SEAL bad version");
        send_seal(~model_crc, 16'd4, 8'd1, 8'd1, 8'h01, "SEAL reserved bits set");
        if (loaded) $fatal(1, "loaded set by a failed SEAL");
        send_expect(8'h53, 64'd0, 8'h01, "PLAY after failed SEAL");
        seal_current(8'h00, "SEAL correct");
        if (!loaded) $fatal(1, "loaded not set by a correct SEAL");

        clear_captured;
        send_expect(8'h53, 64'd0, 8'h00, "PLAY accepted");
        if (!playing) $fatal(1, "playing not set by PLAY");
        wait_events(6, 400000);
        wait_settled(400000);

        check_event(0, {8'h09, 8'h90, 8'd60, 8'd100}, "natural end");
        check_event(1, {8'h09, 8'h90, 8'd64, 8'd100}, "natural end");
        check_event(2, {8'h08, 8'h80, 8'd60, 8'd0},   "natural end");
        check_event(3, {8'h08, 8'h80, 8'd64, 8'd0},   "natural end");
        check_event(4, W_CC64,  "natural end CC64");
        check_event(5, W_CC123, "natural end CC123");
        check_gap(0, 1, 1, "delta 1 ms");
        check_gap(1, 2, 1, "delta 1 ms");
        check_gap(2, 3, 2, "delta 2 ms");
        if ((captured_total - cap_base) != 6)
            $fatal(1, "unexpected extra events: %0d", captured_total - cap_base);
        if (guide_mask != 0) $fatal(1, "guide_mask not cleared at natural end");

        // ---- 7. Replay, restart refusal, BEGIN/EVENT while playing -------
        send_expect(8'h53, 64'd0, 8'h00, "replay after natural end");
        send_expect(8'h53, 64'd0, 8'h01, "restart without STOP");
        send_expect(8'h50, {40'd0, 8'd1, 16'd4}, 8'h01, "BEGIN while playing");
        send_expect(8'h51, {8'd0, 8'd60, 32'd0, 16'd0}, 8'h01, "EVENT while playing");
        wait_settled(400000);                 // let the replay finish naturally

        // ---- 8. STOP clears, and refuses commands while flushing ---------
        stall_cycles = 60;                    // widen the note-off flush window
        clear_captured;
        send_cmd(8'h54, 64'd0);
        expect_status(8'h00, "STOP accepted");
        if (status_latency > 8)
            $fatal(1, "STOP acknowledge took %0d clocks", status_latency);
        if (playing)          $fatal(1, "playing still set after STOP");
        if (!flush_active)    $fatal(1, "flush_active not raised by STOP");
        send_expect(8'h50, {40'd0, 8'd1, 16'd4}, 8'h01, "BEGIN during note-off flush");
        send_expect(8'h53, 64'd0, 8'h01, "PLAY during note-off flush");
        send_expect(8'h51, {8'd0, 8'd60, 32'd0, 16'd0}, 8'h01,
                    "EVENT during note-off flush");
        wait_settled(400000);
        stall_cycles = 0;
        wait_events(2, 40000);
        @(negedge clk);
        if ((captured_total - cap_base) != 2)
            $fatal(1, "STOP emitted %0d events, expected 2",
                   captured_total - cap_base);
        check_event(0, W_CC64,  "STOP flush order");
        check_event(1, W_CC123, "STOP flush order");
        if (guide_mask != 0) $fatal(1, "guide_mask not cleared by STOP");

        // ---- 9. Zero-delay chord and back pressure -----------------------
        send_begin(16'd3, 8'd1, 40'd0, 8'h00, "BEGIN chord");
        send_event_ok(0, 32'd0, 8'd60, 8'd100);
        send_event_ok(1, 32'd0, 8'd64, 8'd100);
        send_event_ok(2, 32'd0, 8'd67, 8'd100);
        seal_current(8'h00, "SEAL chord");

        stall_cycles = 6;                     // hold valid between the events
        clear_captured;
        send_expect(8'h53, 64'd0, 8'h00, "PLAY chord");
        wait_events(3, 40000);
        check_event(0, {8'h09, 8'h90, 8'd60, 8'd100}, "chord");
        check_event(1, {8'h09, 8'h90, 8'd64, 8'd100}, "chord");
        check_event(2, {8'h09, 8'h90, 8'd67, 8'd100}, "chord");
        check_chord_gap(0, 1, "chord");
        check_chord_gap(1, 2, "chord");
        for (i = 60; i <= 67; i = i + 1) begin
            note_id = i;
            if ((note_id == 60) || (note_id == 64) || (note_id == 67)) begin
                if (!guide_mask[note_id])
                    $fatal(1, "guide_mask bit %0d not set", note_id);
            end else if (guide_mask[note_id]) begin
                $fatal(1, "guide_mask bit %0d set unexpectedly", note_id);
            end
        end
        stall_cycles = 0;
        wait_events(5, 40000);
        wait_settled(40000);
        check_event(3, W_CC64,  "chord end");
        check_event(4, W_CC123, "chord end");
        if (guide_mask != 0) $fatal(1, "guide_mask not cleared after the chord");

        // ---- 10. STOP in the middle of a long wait -----------------------
        send_begin(16'd2, 8'd1, 40'd0, 8'h00, "BEGIN stop test");
        send_event_ok(0, 32'd3, 8'd72, 8'd90);
        send_event_ok(1, 32'd3, 8'd72, 8'd0);
        seal_current(8'h00, "SEAL stop test");
        clear_captured;
        send_expect(8'h53, 64'd0, 8'h00, "PLAY stop test");
        wait_events(1, 400000);
        check_event(0, {8'h09, 8'h90, 8'd72, 8'd90}, "stop test note on");
        if (!guide_mask[72]) $fatal(1, "guide_mask bit 72 not set");
        send_cmd(8'h54, 64'd0);
        expect_status(8'h00, "STOP mid-play");
        wait_settled(40000);
        wait_events(3, 40000);
        repeat (4 * MS_DIV) @(negedge clk);   // the dropped event must never come
        if ((captured_total - cap_base) != 3)
            $fatal(1, "STOP mid-play emitted %0d events, expected 3",
                   captured_total - cap_base);
        check_event(1, W_CC64,  "STOP mid-play flush");
        check_event(2, W_CC123, "STOP mid-play flush");
        if (guide_mask != 0) $fatal(1, "guide_mask not cleared by STOP");

        // ---- 11. Re-upload after a seal ----------------------------------
        // STOP must drain a previously presented event under back pressure,
        // and repeated STOP must not replace/restart an in-flight flush.
        send_begin(16'd2,8'd1,40'd0,8'd0,"BEGIN drain regression");
        send_event_ok(0,32'd0,8'd60,8'd100);
        send_event_ok(1,32'd3,8'd60,8'd0);
        seal_current(8'd0,"SEAL drain regression");
        clear_captured;
        sink_block=1;
        send_expect(8'h53,64'd0,8'd0,"PLAY blocked sink");
        wait(midi_event_valid && !midi_event_ready);
        volume_ready=0;
        send_expect(8'h56,64'd64,8'd0,"VOLUME during blocked playback");
        if(!playing || !loaded || !volume_valid || volume_data!=={8'h0B,8'hB0,8'd20,8'd64})
            $fatal(1,"volume interfered with playback or mailbox");
        send_expect(8'h56,64'd127,8'd1,"VOLUME queue full");
        if(volume_data!=={8'h0B,8'hB0,8'd20,8'd64}) $fatal(1,"volume pending overwritten");
        volume_ready=1;
        send_expect(8'h55,64'd0,(MAX_EVENTS<2048?8'd1:8'd0),"PROBE while event held");
        send_expect(8'h54,64'd0,8'd0,"STOP blocked event");
        send_expect(8'h54,64'd0,8'd0,"repeated STOP during drain");
        if(!midi_event_valid || midi_event_data!=={8'h09,8'h90,8'd60,8'd100})
            $fatal(1,"STOP revoked or changed pending event");
        sink_block=0;
        wait_settled(40000);
        wait_events(3,40000);
        if(captured_total-cap_base!=3) $fatal(1,"STOP drain duplicate/drop");
        check_event(0,{8'h09,8'h90,8'd60,8'd100},"drain note");
        check_event(1,W_CC64,"drain clear pedal");
        check_event(2,W_CC123,"drain all notes off");
        if(guide_mask!=0) $fatal(1,"drain mask remains set");

        if (!loaded) $fatal(1, "loaded lost after STOP");
        send_begin(16'd1, 8'd1, 40'd0, 8'h00, "BEGIN re-upload");
        if (loaded) $fatal(1, "BEGIN did not clear loaded");
        send_event_ok(0, 32'd0, 8'd48, 8'd77);
        seal_current(8'h00, "SEAL re-upload");
        clear_captured;
        send_expect(8'h53, 64'd0, 8'h00, "PLAY re-upload");
        wait_events(3, 40000);
        wait_settled(40000);
        check_event(0, {8'h09, 8'h90, 8'd48, 8'd77}, "re-upload");
        check_event(1, W_CC64,  "re-upload end");
        check_event(2, W_CC123, "re-upload end");

        // ---- 12. Reserved / malformed score commands ---------------------
        send_expect(8'h57, 64'd0, 8'h01, "unknown command routed to the player");
        send_expect(8'h54, 64'h1, 8'h01, "STOP with non-zero payload");

        // ---- 13. 2048-event boundary (default resource shape) ------------
        if (BIG_RAM) begin
            send_begin(16'd2048, 8'd1, 40'd0, 8'h00, "BEGIN 2048 events");
            for (i = 0; i < 2048; i = i + 1) begin
                if (i[0] == 1'b0) send_event_ok(i, 32'd0, 8'd60, 8'd100);
                else              send_event_ok(i, 32'd0, 8'd60, 8'd0);
            end
            seal_current(8'h00, "SEAL 2048 events");
            clear_captured;
            send_expect(8'h53, 64'd0, 8'h00, "PLAY 2048 events");
            wait_events(2050, 2000000);
            wait_settled(2000000);
            if ((captured_total - cap_base) != 2050)
                $fatal(1, "2048-event run captured %0d events",
                       captured_total - cap_base);
            check_event(0, {8'h09, 8'h90, 8'd60, 8'd100}, "2048 first");
            check_event(1, {8'h08, 8'h80, 8'd60, 8'd0},   "2048 second");
            check_event(2047, {8'h08, 8'h80, 8'd60, 8'd0}, "2048 last event");
            check_event(2048, W_CC64,  "2048 end CC64");
            check_event(2049, W_CC123, "2048 end CC123");
            if (guide_mask != 0)
                $fatal(1, "guide_mask not cleared after 2048 events");
        end

        if (reply_count == 0) $fatal(1, "no reply was ever produced");

        $display("SCORE_PLAYER_TEST_OK ram=%0d max_events=%0d clk_hz=%0d replies=%0d max_latency=%0d",
                 RAM_DEPTH, MAX_EVENTS, CLK_HZ, reply_count, max_latency);
        $finish;
    end

    initial begin
        #(1000000 * 400);
        $fatal(1, "simulation watchdog");
    end

endmodule
