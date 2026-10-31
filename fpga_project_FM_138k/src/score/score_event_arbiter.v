// -----------------------------------------------------------------------------
// score_event_arbiter.v
//
// Merges the two independent MIDI event sources of the board into the single
// event stream consumed by midi_poly_synth and midi_performance_control:
//
//   * USB  - the existing cross-domain mailbox (toggle request / toggle ack).
//            The USB side holds midi_event_data unchanged until the ack toggle
//            returns, so this port behaves exactly like a valid/ready source:
//            usb_event_valid stays high and usb_event_data stays stable until
//            usb_event_ack pulses.
//   * PLAYER - score_player's event output, same contract.
//
// Behaviour:
//   * One event is latched at a time and presented on midi_event_valid with
//     midi_event_data held stable until midi_event_ready.  A newly arriving
//     source is never latched on top of a pending event, which removes the old
//     top-level hazard of re-capturing the mailbox on a clock edge where
//     midi_event_valid was still high and midi_event_ready was a stale 1.
//   * Every accepted event is emitted exactly once and acknowledged to exactly
//     one source, so the same data can never be delivered twice.
//   * Round robin between the two sources: when both are valid the source that
//     was not served last wins, so under simultaneous pressure the two streams
//     alternate instead of one starving the other.
//   * player_event_urgent (score STOP / natural end note-off flush) lets the
//     player overtake USB events so CC64/CC123 are not delayed behind a busy
//     USB stream.  It never preempts an event that is already latched.
//
// No FIFO is added: the sources hold their own data until acknowledged.
// -----------------------------------------------------------------------------
module score_event_arbiter (
    input  wire        clk,
    input  wire        reset_n,

    // USB mailbox source (level valid, stable data, one-clock ack).
    input  wire        usb_event_valid,
    input  wire [31:0] usb_event_data,
    output wire        usb_event_ack,

    // Score player source (level valid, stable data, one-clock ack).
    input  wire        player_event_valid,
    input  wire [31:0] player_event_data,
    input  wire        player_event_urgent,
    output wire        player_event_ack,

    // Merged stream to the synthesizer (and, via the transfer pulse, to
    // midi_performance_control).
    output reg  [31:0] midi_event_data,
    output reg         midi_event_valid,
    input  wire        midi_event_ready
);

    reg holding;      // an event is latched and being presented
    reg hold_is_usb;  // which source the latched event came from
    reg last_usb;     // round-robin state: USB was served most recently

    // Fair selection.  An urgent player event wins outright; otherwise, when
    // both sources are valid, the one that was not served last is chosen.
    wire player_wins = player_event_valid &&
                       (player_event_urgent || ~usb_event_valid || last_usb);
    wire usb_wins    = usb_event_valid && ~player_wins &&
                       (~player_event_valid || ~last_usb);

    wire transfer = holding && midi_event_ready;

    assign usb_event_ack    = transfer &&  hold_is_usb;
    assign player_event_ack = transfer && !hold_is_usb;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            holding          <= 1'b0;
            hold_is_usb      <= 1'b0;
            last_usb         <= 1'b0;
            midi_event_data  <= 32'd0;
            midi_event_valid <= 1'b0;
        end else if (holding) begin
            // Hold data and valid: a source must never overwrite the pending
            // event, even though the synthesizer's ready may still read high.
            if (midi_event_ready) begin
                holding          <= 1'b0;
                midi_event_valid <= 1'b0;
            end
        end else if (usb_wins) begin
            holding          <= 1'b1;
            hold_is_usb      <= 1'b1;
            last_usb         <= 1'b1;
            midi_event_data  <= usb_event_data;
            midi_event_valid <= 1'b1;
        end else if (player_wins) begin
            holding          <= 1'b1;
            hold_is_usb      <= 1'b0;
            last_usb         <= 1'b0;
            midi_event_data  <= player_event_data;
            midi_event_valid <= 1'b1;
        end
    end

endmodule
