// Passive, isolated touch NoteOn -> transmitted I2S left-word onset probe.
// This module never stalls, changes, or feeds back into the instrument.
// Start excludes touch-IC scanning and the C firmware's polling/coordinate work.
// Done excludes the DAC/analog path. Both pins are scope markers, not audio.
module scope_touch_latency #(
    parameter integer QUIET_FRAMES = 32,
    parameter integer THRESHOLD = 32,
    parameter integer PULSE_CLOCKS = 50000,     // 1 ms at 50 MHz
    parameter integer TIMEOUT_CLOCKS = 12500000 // 250 ms at 50 MHz
) (
    input wire clk,reset_n,enable,
    input wire event_valid,event_ready,
    input wire [31:0] event_data,
    input wire [7:0] active_voices,
    input wire bclk,lrclk,serial_data,
    output reg start_marker,done_marker
);
    localparam integer PULSE_BITS = (PULSE_CLOCKS < 2) ? 1 : $clog2(PULSE_CLOCKS+1);
    localparam integer AGE_BITS = (TIMEOUT_CLOCKS < 2) ? 1 : $clog2(TIMEOUT_CLOCKS+1);
    localparam integer QUIET_BITS = (QUIET_FRAMES < 2) ? 1 : $clog2(QUIET_FRAMES+1);
    localparam [PULSE_BITS-1:0] PULSE_LIMIT = PULSE_CLOCKS[PULSE_BITS-1:0];
    localparam [AGE_BITS-1:0] AGE_LIMIT = TIMEOUT_CLOCKS[AGE_BITS-1:0]-1'b1;
    localparam [QUIET_BITS-1:0] QUIET_LIMIT = QUIET_FRAMES[QUIET_BITS-1:0];
    localparam [15:0] SAMPLE_THRESHOLD = THRESHOLD[15:0];
    reg [PULSE_BITS-1:0] start_hold,done_hold;
    reg [AGE_BITS-1:0] age;
    reg [QUIET_BITS-1:0] quiet_frames;
    reg pending;

    // All observed I2S pins are generated in clk's domain. Observe their
    // registered values without adding any logic to the existing serial path.
    // Wait for a real right->left LRCLK transition to discard the boot fragment.
    reg previous_bclk,previous_lrclk,frame_aligned;
    reg [4:0] left_index;
    reg [15:0] left_shift;
    wire bclk_rise = bclk && !previous_bclk;
    wire left_start = previous_lrclk && !lrclk;
    wire word_complete = bclk_rise && frame_aligned && !lrclk && left_index==16;
    wire [15:0] word_now = {left_shift[14:0],serial_data};
    wire [15:0] magnitude = word_now[15] ? (~word_now+16'd1) : word_now;
    reg [15:0] last_magnitude;
    wire live_note_on = event_valid && event_ready && !event_data[31] &&
                        event_data[23:20]==4'h9 && event_data[6:0]!=0;
    wire qualified = enable && quiet_frames==QUIET_LIMIT &&
                     active_voices==0 && last_magnitude<=SAMPLE_THRESHOLD;

    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            previous_bclk<=0;previous_lrclk<=0;frame_aligned<=0;
            left_index<=0;left_shift<=0;
        end else begin
            previous_bclk<=bclk;previous_lrclk<=lrclk;
            if(left_start) begin
                frame_aligned<=1;left_index<=0;left_shift<=0;
            end else if(bclk_rise && frame_aligned && !lrclk) begin
                // Index zero is the mandatory one-BCLK I2S delay bit.
                if(left_index==0) left_index<=1;
                else if(left_index<=16) begin
                    left_shift<=word_now;left_index<=left_index+1'b1;
                end
            end
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            start_hold<=0;done_hold<=0;age<=0;quiet_frames<=0;
            pending<=0;last_magnitude<=16'hffff;start_marker<=0;done_marker<=0;
        end else begin
            if(start_hold>1) begin start_hold<=start_hold-1'b1;start_marker<=1;end
            else begin start_hold<=0;start_marker<=0;end
            if(done_hold>1) begin done_hold<=done_hold-1'b1;done_marker<=1;end
            else begin done_hold<=0;done_marker<=0;end
            if(!enable || active_voices!=0) quiet_frames<=0;
            if(word_complete) begin
                last_magnitude<=magnitude;
                if(enable && active_voices==0 && magnitude<=SAMPLE_THRESHOLD) begin
                    if(quiet_frames<QUIET_LIMIT) quiet_frames<=quiet_frames+1'b1;
                end else quiet_frames<=0;
            end
            if(live_note_on) begin
                if(!pending && qualified) begin
                    start_hold<=PULSE_LIMIT;start_marker<=1;pending<=1;age<=0;quiet_frames<=0;
                end else if(pending) begin
                    // An overlapping NoteOn cannot be attributed to one onset.
                    // Do not emit a completion marker that could look valid.
                    pending<=0;age<=0;
                end
            end
            if(pending && !live_note_on) begin
                if(!enable || active_voices>1 || age>=AGE_LIMIT) begin
                    pending<=0;age<=0;
                end else if(word_complete && magnitude>SAMPLE_THRESHOLD) begin
                    // Observed completion is one clk (20 ns at 50 MHz) after
                    // the physical BCLK rising edge sampling the 16th data bit.
                    done_hold<=PULSE_LIMIT;done_marker<=1;pending<=0;age<=0;
                end else age<=age+1'b1;
            end
        end
    end
endmodule
