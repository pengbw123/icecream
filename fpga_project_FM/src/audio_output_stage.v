// Final audio safety/telemetry stage.
//
// The FM mixer already applies a wide-accumulator soft knee.  This second,
// inexpensive stage catches peaks introduced by chorus/reverb, exports a
// peak-hold meter to the LCD, and stretches a clipping event long enough to
// be visible without affecting the audio scheduler.
module audio_output_stage (
    input  wire               clk,
    input  wire               reset_n,
    input  wire               sample_tick,
    input  wire signed [15:0] sample_in,
    output reg  signed [15:0] sample_out,
    output reg  [7:0]         peak_level,
    output wire               clip_active
);
    reg [15:0] clip_hold_samples;
    reg [5:0] peak_decay_divider;

    wire [15:0] input_magnitude = sample_in[15]
        ? (~sample_in + 1'b1) : sample_in;
    wire [7:0] instantaneous_peak = input_magnitude[15]
        ? 8'hff : input_magnitude[14:7];
    assign clip_active = (clip_hold_samples != 0);

    function signed [15:0] soft_limit;
        input signed [15:0] value;
        reg negative;
        reg [16:0] magnitude;
        reg [16:0] limited;
        begin
            negative = value[15];
            magnitude = negative ? -$signed(value) : value;
            if (magnitude <= 17'd24576)
                limited = magnitude;
            else
                limited = 17'd24576 + ((magnitude - 17'd24576) >> 2);
            if (limited > 17'd32767)
                limited = 17'd32767;
            soft_limit = negative ? -$signed(limited[15:0])
                                  :  $signed(limited[15:0]);
        end
    endfunction

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sample_out <= 16'sd0;
            peak_level <= 8'd0;
            clip_hold_samples <= 16'd0;
            peak_decay_divider <= 6'd0;
        end else if (sample_tick) begin
            sample_out <= soft_limit(sample_in);

            if (input_magnitude >= 16'd32760)
                clip_hold_samples <= 16'd48828; // approximately one second
            else if (clip_hold_samples != 0)
                clip_hold_samples <= clip_hold_samples - 1'b1;

            if (instantaneous_peak >= peak_level) begin
                peak_level <= instantaneous_peak;
                peak_decay_divider <= 6'd0;
            end else if (peak_decay_divider == 6'd63) begin
                peak_decay_divider <= 6'd0;
                if (peak_level != 0)
                    peak_level <= peak_level - 1'b1;
            end else begin
                peak_decay_divider <= peak_decay_divider + 1'b1;
            end
        end
    end
endmodule
