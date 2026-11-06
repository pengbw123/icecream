// -----------------------------------------------------------------------------
// tb_score_arbiter.sv
//
// Self-checking testbench for score_event_arbiter.
//
// Both sources are driven the way the real hardware drives them: level valid
// with stable data that advances only on the acknowledge.  A synthesizer
// stand-in applies back pressure for a programmable number of clocks.
//
// Coverage:
//   1. USB alone: every event delivered, in order, exactly once
//   2. player alone under back pressure: same, and valid/data stay stable while
//      the arbiter is waiting (the old top-level mailbox bug)
//   3. both sources continuously valid at the same time: strict round-robin,
//      no starvation of either source, no duplicated or lost event
//   4. an urgent player event (score note-off flush) overtakes a saturated USB
//      stream instead of waiting behind it
//
// Only assert / $fatal / $display are used.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_score_arbiter;

    localparam [15:0] TAG_USB    = 16'hA000;
    localparam [15:0] TAG_PLAYER = 16'hB000;

    reg clk = 1'b0;
    always #10 clk = ~clk;

    reg reset_n = 1'b0;

    // ---- USB mailbox source -------------------------------------------
    reg        usb_enable = 1'b0;
    reg        usb_valid  = 1'b0;
    reg [31:0] usb_data   = {TAG_USB, 16'd0};
    wire       usb_ack;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            usb_valid <= 1'b0;
            usb_data  <= {TAG_USB, 16'd0};
        end else begin
            // Level valid: it only drops on the acknowledge, and only when the
            // source has been switched off (otherwise the next event follows
            // immediately).  Data advances strictly after the acknowledge,
            // which is exactly the contract the real USB mailbox honours.
            if (usb_ack)            usb_valid <= usb_enable;
            else if (usb_enable)    usb_valid <= 1'b1;
            else                    usb_valid <= usb_valid;
            if (usb_ack) usb_data <= usb_data + 32'd1;
        end
    end

    // ---- player source -------------------------------------------------
    reg        player_enable = 1'b0;
    reg        player_urgent = 1'b0;
    reg        player_valid  = 1'b0;
    reg [31:0] player_data   = {TAG_PLAYER, 16'd0};
    wire       player_ack;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            player_valid <= 1'b0;
            player_data  <= {TAG_PLAYER, 16'd0};
        end else begin
            if (player_ack)          player_valid <= player_enable;
            else if (player_enable)  player_valid <= 1'b1;
            else                     player_valid <= player_valid;
            if (player_ack) player_data <= player_data + 32'd1;
        end
    end

    // ---- arbiter -------------------------------------------------------
    wire [31:0] midi_data;
    wire        midi_valid;
    reg         midi_ready = 1'b1;

    score_event_arbiter dut (
        .clk(clk), .reset_n(reset_n),
        .usb_event_valid(usb_valid),
        .usb_event_data(usb_data),
        .usb_event_ack(usb_ack),
        .player_event_valid(player_valid),
        .player_event_data(player_data),
        .player_event_urgent(player_urgent),
        .player_event_ack(player_ack),
        .midi_event_data(midi_data),
        .midi_event_valid(midi_valid),
        .midi_event_ready(midi_ready)
    );

    // ---- synthesizer stand-in with back pressure ------------------------
    integer stall    = 1;         // extra clocks the sink stays busy
    integer busy_cnt = 0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            midi_ready <= 1'b1;
            busy_cnt   <= 0;
        end else if (midi_valid && midi_ready) begin
            midi_ready <= 1'b0;
            busy_cnt   <= stall + 1;
        end else if (busy_cnt != 0) begin
            busy_cnt   <= busy_cnt - 1;
            if (busy_cnt == 1) midi_ready <= 1'b1;
        end
    end

    // ---- monitors ------------------------------------------------------
    integer usb_seen    = 0;
    integer player_seen = 0;
    integer alt_errors  = 0;
    reg [1:0] last_src  = 2'd0;   // 1 = USB delivered last, 2 = player
    reg       check_alt = 1'b0;   // written by the stimulus only

    reg        pending_active = 1'b0;
    reg [31:0] pending_data   = 32'd0;

    always @(posedge clk) begin
        if (reset_n) begin
            // The arbiter must never swap the event it is presenting.
            if (pending_active) begin
                if (!midi_valid)
                    $fatal(1, "midi_event_valid dropped before the handshake");
                if (midi_data !== pending_data)
                    $fatal(1, "midi_event_data changed before the handshake");
            end
            pending_active <= midi_valid && !midi_ready;
            if (midi_valid && !midi_ready) pending_data <= midi_data;

            if (midi_valid && midi_ready) begin
                if (midi_data[31:16] == TAG_USB) begin
                    if (midi_data[15:0] !== usb_seen[15:0])
                        $fatal(1, "USB event out of order or duplicated: %0d, expected %0d",
                               midi_data[15:0], usb_seen);
                    usb_seen <= usb_seen + 1;
                    if (check_alt) begin
                        if (last_src == 2'd1) alt_errors <= alt_errors + 1;
                        last_src <= 2'd1;
                    end
                end else if (midi_data[31:16] == TAG_PLAYER) begin
                    if (midi_data[15:0] !== player_seen[15:0])
                        $fatal(1, "player event out of order or duplicated: %0d, expected %0d",
                               midi_data[15:0], player_seen);
                    player_seen <= player_seen + 1;
                    if (check_alt) begin
                        if (last_src == 2'd2) alt_errors <= alt_errors + 1;
                        last_src <= 2'd2;
                    end
                end else begin
                    $fatal(1, "unknown event tag %h", midi_data);
                end
            end
        end
    end

    // ---- stimulus ------------------------------------------------------
    task automatic wait_usb_idle(input integer timeout);
        integer guard;
        begin
            guard = 0;
            while (usb_valid && (guard < timeout)) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (usb_valid) $fatal(1, "USB source never went idle");
            repeat (4) @(negedge clk);
        end
    endtask

    task automatic wait_player_idle(input integer timeout);
        integer guard;
        begin
            guard = 0;
            while (player_valid && (guard < timeout)) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (player_valid) $fatal(1, "player source never went idle");
            repeat (4) @(negedge clk);
        end
    endtask

    integer guard;
    integer base_usb;
    integer base_player;

    initial begin
        repeat (8) @(negedge clk);
        reset_n = 1'b1;
        repeat (4) @(negedge clk);

        // ---- 1. USB only, no back pressure -------------------------------
        stall       = 0;
        usb_enable  = 1'b1;
        guard       = 0;
        while ((usb_seen < 16) && (guard < 2000)) begin
            @(negedge clk);
            guard = guard + 1;
        end
        if (usb_seen < 16) $fatal(1, "USB events were not delivered (got %0d)", usb_seen);
        usb_enable = 1'b0;
        wait_usb_idle(200);
        if (player_seen != 0) $fatal(1, "player events appeared with the player idle");

        // ---- 2. player only, with back pressure --------------------------
        stall         = 5;
        player_enable = 1'b1;
        guard         = 0;
        while ((player_seen < 16) && (guard < 4000)) begin
            @(negedge clk);
            guard = guard + 1;
        end
        if (player_seen < 16)
            $fatal(1, "player events were not delivered under back pressure (got %0d)",
                   player_seen);
        player_enable = 1'b0;
        wait_player_idle(400);

        // ---- 3. both sources saturated: strict round robin ---------------
        base_usb    = usb_seen;
        base_player = player_seen;
        stall       = 1;
        check_alt   = 1'b1;
        last_src    = 2'd0;
        usb_enable    = 1'b1;
        player_enable = 1'b1;
        guard = 0;
        while (((usb_seen < base_usb + 32) || (player_seen < base_player + 32)) &&
               (guard < 8000)) begin
            @(negedge clk);
            guard = guard + 1;
        end
        if ((usb_seen < base_usb + 32) || (player_seen < base_player + 32))
            $fatal(1, "starvation: usb=%0d player=%0d", usb_seen - base_usb,
                   player_seen - base_player);
        usb_enable    = 1'b0;
        player_enable = 1'b0;
        check_alt     = 1'b0;
        wait_usb_idle(400);
        wait_player_idle(400);
        if (alt_errors != 0)
            $fatal(1, "round robin failed: %0d consecutive same-source deliveries",
                   alt_errors);
        // Strict alternation implies an even split; allow for one event that
        // was already in flight when the sources were switched off.
        if ((usb_seen - base_usb) > (player_seen - base_player) + 2 ||
            (player_seen - base_player) > (usb_seen - base_usb) + 2)
            $fatal(1, "unfair split: usb=%0d player=%0d",
                   usb_seen - base_usb, player_seen - base_player);

        // ---- 4. urgent player event overtakes a saturated USB stream ------
        stall         = 1;
        usb_enable    = 1'b1;
        repeat (20) @(negedge clk);          // USB is continuously valid now
        if (!usb_valid) $fatal(1, "USB source not saturated");
        base_usb    = usb_seen;
        base_player = player_seen;
        player_urgent = 1'b1;
        player_enable = 1'b1;
        guard = 0;
        while ((player_seen == base_player) && (guard < 400)) begin
            @(negedge clk);
            guard = guard + 1;
        end
        if (player_seen == base_player)
            $fatal(1, "urgent player event was never delivered");
        if ((usb_seen - base_usb) > 1)
            $fatal(1, "urgent player event waited behind %0d USB events",
                   usb_seen - base_usb);
        player_enable = 1'b0;
        player_urgent = 1'b0;
        wait_player_idle(200);
        usb_enable = 1'b0;
        wait_usb_idle(400);

        $display("SCORE_ARBITER_TEST_OK usb=%0d player=%0d alt_errors=%0d",
                 usb_seen, player_seen, alt_errors);
        $finish;
    end

    initial begin
        #(1000000 * 2);
        $fatal(1, "simulation watchdog");
    end

endmodule
