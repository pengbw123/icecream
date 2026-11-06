// Dense continuous-strip mapping, independent of MIDI parsing and board pins.
// Configure each physical LED as off (kind 0), MIDI note (1), or beat lamp (2).
// Several LEDs may represent the same note; black-key positions need not be
// evenly spaced. Reset leaves every map entry OFF until explicitly configured.
module score_strip_guide #(
    parameter integer LED_COUNT = 160,
    parameter integer BIT_CYCLES = 63,
    parameter integer T0H_CYCLES = 15,
    parameter integer T1H_CYCLES = 33,
    parameter integer RESET_CYCLES = 16000,
    parameter [23:0] CURRENT_GRB = 24'h200000,
    parameter [23:0] PREVIEW_GRB = 24'h101800,
    parameter [23:0] BEAT_GRB = 24'h000020,
    parameter [23:0] SCAN_GRB = 24'h080808
)(
    input wire clk,
    input wire reset_n,
    input wire cfg_valid,
    output wire cfg_ready,
    input wire [15:0] cfg_index,
    input wire [1:0] cfg_kind,
    input wire [6:0] cfg_note,
    output reg cfg_error,
    input wire frame_valid,
    output wire frame_ready,
    input wire [127:0] current_notes,
    input wire [127:0] preview_notes,
    input wire beat_active,
    input wire scan_enable,
    input wire [15:0] scan_index,
    output wire busy,
    output reg frame_done,
    output reg [127:0] unmapped_notes,
    output wire led_data
);
    localparam [1:0] IDLE = 2'd0, FILL = 2'd1,
                     SUBMIT = 2'd2, WAIT_TX = 2'd3;
    localparam integer MAP_INDEX_WIDTH = (LED_COUNT > 1) ? $clog2(LED_COUNT) : 1;
    reg [1:0] state;
    reg [8:0] led_map [0:LED_COUNT-1];
    reg [LED_COUNT*24-1:0] pixels;
    reg [127:0] current_hold, preview_hold, represented, pending_unmapped;
    reg beat_hold, scan_hold, user_frame_pending;
    reg [15:0] scan_index_hold;
    // A bounded unsigned address avoids a 32-bit counter/variable-part-select
    // decoder feeding every LED register. Range is 0..LED_COUNT-1.
    reg [MAP_INDEX_WIDTH-1:0] fill_index;
    wire [MAP_INDEX_WIDTH-1:0] cfg_map_index = cfg_index[MAP_INDEX_WIDTH-1:0];
    wire [8:0] entry = led_map[fill_index];
    wire [127:0] entry_note = (entry[8:7] == 2'd1) ?
                              (128'd1 << entry[6:0]) : 128'd0;
    wire tx_ready, tx_busy, tx_done;

    assign cfg_ready = (state == IDLE) && tx_ready;
    // A configuration handshake wins over a frame handshake on the same cycle.
    assign frame_ready = cfg_ready && !cfg_valid;
    assign busy = (state != IDLE) || tx_busy;

    ws2812_frame_tx #(
        .LED_COUNT(LED_COUNT), .BIT_CYCLES(BIT_CYCLES),
        .T0H_CYCLES(T0H_CYCLES), .T1H_CYCLES(T1H_CYCLES),
        .RESET_CYCLES(RESET_CYCLES)
    ) tx (
        .clk(clk), .reset_n(reset_n),
        .frame_valid(state == SUBMIT), .frame_ready(tx_ready),
        .frame_grb(pixels), .busy(tx_busy), .frame_done(tx_done),
        .led_data(led_data)
    );

    // synthesis translate_off
    initial if (LED_COUNT < 1 || LED_COUNT > 65535)
        $fatal(1, "LED_COUNT must fit the 16-bit configuration index");
    // synthesis translate_on

    integer i;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < LED_COUNT; i = i + 1) led_map[i] <= 0;
            // Clear a previously latched pattern after FPGA reset, even before
            // the board owner submits the first user frame.
            state <= SUBMIT;
            fill_index <= 0;
            pixels <= 0;
            current_hold <= 0;
            preview_hold <= 0;
            represented <= 0;
            pending_unmapped <= 0;
            beat_hold <= 0;
            scan_hold <= 0;
            user_frame_pending <= 0;
            scan_index_hold <= 0;
            cfg_error <= 0;
            frame_done <= 0;
            unmapped_notes <= 0;
        end else begin
            cfg_error <= 0;
            frame_done <= 0;
            case (state)
                IDLE: begin
                    if (cfg_valid && cfg_ready) begin
                        if ({16'd0, cfg_index} >= LED_COUNT || cfg_kind == 2'd3)
                            cfg_error <= 1;
                        // Validate the complete index before narrowing the RAM
                        // address; an out-of-range request must never wrap.
                        else led_map[cfg_map_index] <= {cfg_kind, cfg_note};
                    end else if (frame_valid && frame_ready) begin
                        current_hold <= current_notes;
                        preview_hold <= preview_notes;
                        beat_hold <= beat_active;
                        scan_hold <= scan_enable;
                        scan_index_hold <= scan_index;
                        user_frame_pending <= 1;
                        fill_index <= 0;
                        represented <= 0;
                        state <= FILL;
                    end
                end
                FILL: begin
                    represented <= represented | entry_note;
                    pixels[fill_index*24 +: 24] <= 24'd0;
                    if (scan_hold) begin
                        if (fill_index == {16'd0, scan_index_hold})
                            pixels[fill_index*24 +: 24] <= SCAN_GRB;
                    end else if (entry[8:7] == 2'd2) begin
                        if (beat_hold) pixels[fill_index*24 +: 24] <= BEAT_GRB;
                    end else if (entry[8:7] == 2'd1) begin
                        if (current_hold[entry[6:0]])
                            pixels[fill_index*24 +: 24] <= CURRENT_GRB;
                        else if (preview_hold[entry[6:0]])
                            pixels[fill_index*24 +: 24] <= PREVIEW_GRB;
                    end
                    if (fill_index == LED_COUNT-1) begin
                        pending_unmapped <= (current_hold | preview_hold) &
                                            ~(represented | entry_note);
                        state <= SUBMIT;
                    end else fill_index <= fill_index + 1;
                end
                SUBMIT: if (tx_ready) state <= WAIT_TX;
                WAIT_TX: if (tx_done) begin
                    unmapped_notes <= pending_unmapped;
                    frame_done <= user_frame_pending;
                    user_frame_pending <= 0;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
