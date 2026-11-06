// 25 WS2812 LEDs represent MIDI notes 48..72 (C3 through C5).
// GRB at 800 kbit/s from a 50 MHz clock. A complete frame is resent after
// at least 300 us of low level, so note changes are visible without a latch.
module ws2812_keys (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [31:0] midi_event_data,
    input  wire        midi_event_valid,
    output wire        led_data
);
    localparam integer LED_COUNT = 25;
    localparam [1:0] RESET_GAP = 2'd0, LOAD_LED = 2'd1,
                     SEND_BIT = 2'd2;
    reg [6:0] key_velocity [0:LED_COUNT-1];
    reg [1:0] state;
    reg [13:0] reset_timer;
    reg [5:0] bit_timer;
    reg [4:0] led_index;
    reg [4:0] bit_index;
    reg [23:0] shift_data;
    wire [7:0] status = midi_event_data[23:16];
    wire [6:0] note = midi_event_data[14:8];
    wire [6:0] velocity = midi_event_data[6:0];
    wire in_range = (note >= 7'd48) && (note <= 7'd72);
    wire note_on = (status[7:4] == 4'h9) && (velocity != 7'd0);
    wire note_off = (status[7:4] == 4'h8) ||
                    ((status[7:4] == 4'h9) && (velocity == 7'd0));

    function [23:0] color_from_velocity;
        input [6:0] value;
        reg [7:0] green, red, blue;
        begin
            if (value == 0) begin
                green = 0; red = 0; blue = 0;
            end else begin
                // Low velocity: teal; high velocity: orange/red.
                green = {1'b0, 7'd127 - value};
                red = {1'b0, value};
                blue = {2'b00, 6'd63 - value[6:1]};
            end
            color_from_velocity = {green, red, blue};
        end
    endfunction

    // WS2812: 1.26 us/bit, T0H=0.40 us, T1H=0.80 us.
    assign led_data = (state == SEND_BIT) &&
                      (bit_timer < (shift_data[23] ? 6'd40 : 6'd20));

    integer i;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < LED_COUNT; i = i + 1)
                key_velocity[i] <= 7'd0;
            state <= RESET_GAP;
            reset_timer <= 14'd0;
            bit_timer <= 6'd0;
            led_index <= 5'd0;
            bit_index <= 5'd0;
            shift_data <= 24'd0;
        end else begin
            if (midi_event_valid && in_range && (note_on || note_off))
                key_velocity[note - 7'd48] <= note_on ? velocity : 7'd0;
            if (midi_event_valid && status[7:4] == 4'hB &&
                (note == 7'd120 || note == 7'd123)) begin
                for (i = 0; i < LED_COUNT; i = i + 1)
                    key_velocity[i] <= 7'd0;
            end

            case (state)
                RESET_GAP: begin
                    if (reset_timer == 14'd15000) begin
                        reset_timer <= 14'd0;
                        led_index <= 5'd0;
                        state <= LOAD_LED;
                    end else reset_timer <= reset_timer + 1'b1;
                end
                LOAD_LED: begin
                    shift_data <= color_from_velocity(key_velocity[led_index]);
                    bit_index <= 5'd0;
                    bit_timer <= 6'd0;
                    state <= SEND_BIT;
                end
                SEND_BIT: begin
                    if (bit_timer == 6'd62) begin
                        bit_timer <= 6'd0;
                        shift_data <= {shift_data[22:0], 1'b0};
                        if (bit_index == 5'd23) begin
                            if (led_index == 5'd24) begin
                                state <= RESET_GAP;
                                reset_timer <= 14'd0;
                            end else begin
                                led_index <= led_index + 1'b1;
                                state <= LOAD_LED;
                            end
                        end else bit_index <= bit_index + 1'b1;
                    end else bit_timer <= bit_timer + 1'b1;
                end
                default: state <= RESET_GAP;
            endcase
        end
    end
endmodule
