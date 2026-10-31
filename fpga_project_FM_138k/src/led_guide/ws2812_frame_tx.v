// Standalone 50 MHz WS2812 RGB serializer. No board pins or audio dependencies.
// Pixel 0 occupies frame_grb[23:0]; each pixel is {green, red, blue}, MSB first.
// Defaults target the cited Worldsemi WS2812B-V5 timing windows. Confirm the
// purchased strip revision and change cycle parameters for a different clock.
module ws2812_frame_tx #(
    parameter integer LED_COUNT = 160,
    parameter integer BIT_CYCLES = 63,
    parameter integer T0H_CYCLES = 15,
    parameter integer T1H_CYCLES = 33,
    parameter integer RESET_CYCLES = 16000
)(
    input wire clk,
    input wire reset_n,
    input wire frame_valid,
    output wire frame_ready,
    input wire [LED_COUNT*24-1:0] frame_grb,
    output wire busy,
    output reg frame_done,
    output reg led_data
);
    localparam [1:0] GAP = 2'd0, IDLE = 2'd1, SEND = 2'd2;
    reg [1:0] state;
    reg [LED_COUNT*24-1:0] pixels_hold;
    reg [23:0] shift_word;
    reg [4:0] bit_index;
    integer bit_timer, reset_timer, led_index;
    reg latch_pending;

    assign frame_ready = (state == IDLE);
    assign busy = (state != IDLE);

    // synthesis translate_off
    initial begin
        if (LED_COUNT < 1 || RESET_CYCLES < 1 || T0H_CYCLES < 1 ||
            T1H_CYCLES <= T0H_CYCLES || T1H_CYCLES >= BIT_CYCLES)
            $fatal(1, "Invalid WS2812 serializer parameters");
    end
    // synthesis translate_on

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= GAP;
            pixels_hold <= 0;
            shift_word <= 0;
            bit_index <= 0;
            bit_timer <= 0;
            reset_timer <= 0;
            led_index <= 0;
            latch_pending <= 0;
            frame_done <= 0;
            led_data <= 0;
        end else begin
            frame_done <= 0;
            case (state)
                GAP: begin
                    led_data <= 0;
                    if (reset_timer == RESET_CYCLES-1) begin
                        reset_timer <= 0;
                        state <= IDLE;
                        frame_done <= latch_pending;
                        latch_pending <= 0;
                    end else reset_timer <= reset_timer + 1;
                end
                IDLE: begin
                    if (frame_valid) begin
                        // Capture the complete frame atomically. Changes to the
                        // input bus while busy cannot tear the outgoing frame.
                        pixels_hold <= frame_grb >> 24;
                        shift_word <= frame_grb[23:0];
                        bit_index <= 0;
                        bit_timer <= 0;
                        led_index <= 0;
                        led_data <= 1;
                        state <= SEND;
                    end
                end
                SEND: begin
                    // Register the output; no counter-comparator glitches are
                    // exposed on the GPIO. Each bit starts with a rising edge.
                    if (bit_timer == (shift_word[23] ? T1H_CYCLES : T0H_CYCLES)-1)
                        led_data <= 0;
                    if (bit_timer == BIT_CYCLES-1) begin
                        bit_timer <= 0;
                        if (bit_index == 5'd23) begin
                            bit_index <= 0;
                            if (led_index == LED_COUNT-1) begin
                                led_data <= 0;
                                reset_timer <= 0;
                                latch_pending <= 1;
                                state <= GAP;
                            end else begin
                                led_index <= led_index + 1;
                                shift_word <= pixels_hold[23:0];
                                pixels_hold <= pixels_hold >> 24;
                                led_data <= 1;
                            end
                        end else begin
                            bit_index <= bit_index + 1'b1;
                            shift_word <= {shift_word[22:0], 1'b0};
                            led_data <= 1;
                        end
                    end else bit_timer <= bit_timer + 1;
                end
                default: begin
                    state <= GAP;
                    reset_timer <= 0;
                    latch_pending <= 0;
                    led_data <= 0;
                end
            endcase
        end
    end
endmodule
