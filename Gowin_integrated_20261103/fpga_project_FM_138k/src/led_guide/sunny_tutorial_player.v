// Pure RTL, autonomous monophonic practice timeline. No PCM, CPU, or MIDI
// injection: the performer supplies the sound through the existing instrument.
module sunny_tutorial_player #(
    parameter integer CLK_HZ = 50000000,
    parameter integer NOTE_COUNT = 343,
    parameter integer END_MS = 156400,
    parameter integer BEAT_MS = 400,
    parameter integer PREVIEW_MS = 200,
    parameter ROM_FILE = "src/generated/sunny_tutorial_notes.mem"
)(
    input wire clk, reset_n,
    input wire start, stop,
    input wire [7:0] speed_percent,
    input wire [3:0] count_in_beats,
    input wire signed [7:0] transpose,
    input wire wait_for_key,
    input wire [31:0] live_midi_event,
    input wire live_midi_valid,
    input wire [1:0] key_source,
    input wire clear_usb_held,
    output reg running,
    output wire count_in,
    output wire beat_active,
    output reg finished,
    output reg [31:0] elapsed_ms,
    output wire [127:0] current_notes,
    output wire [127:0] preview_notes,
    // Reuse the same source-aware fresh-key detector for uploaded scores.
    output wire fresh_key_valid,
    output wire [6:0] fresh_key_note,
    output wire keys_all_released
);
    localparam integer MS_DIV = (CLK_HZ/1000 < 1) ? 1 : CLK_HZ/1000;
    localparam integer INDEX_WIDTH = (NOTE_COUNT > 0) ? $clog2(NOTE_COUNT+1) : 1;
    reg [63:0] notes_rom [0:NOTE_COUNT];
    reg [INDEX_WIDTH-1:0] rom_address;
    reg [63:0] rom_data, next_note;
    reg [1:0] fetch_state;
    reg next_valid, active_valid;
    reg [15:0] next_index;
    reg [6:0] active_note;
    reg wait_mode;
    reg [127:0] held_usb, held_bridge, held_touch;
    wire [127:0] held_notes = held_usb | held_bridge | held_touch;
    reg [31:0] active_end;
    reg [15:0] count_remaining, beat_phase;
    reg [6:0] speed_remainder;
    integer ms_divider;
    wire [8:0] speed_sum = {2'd0,speed_remainder} + {1'd0,speed_percent};
    wire [1:0] step_ms = speed_sum >= 9'd200 ? 2'd2 :
                         speed_sum >= 9'd100 ? 2'd1 : 2'd0;
    wire signed [8:0] next_pitch = $signed({1'b0,next_note[55:48]}) +
                                   $signed({transpose[7],transpose});
    wire pitch_valid = next_pitch >= 0 && next_pitch < 128;
    wire preview_window = count_remaining != 0 ?
        ({16'd0,count_remaining} + next_note[31:0] <= PREVIEW_MS) :
        (next_note[31:0] >= elapsed_ms && next_note[31:0]-elapsed_ms <= PREVIEW_MS);
    assign count_in = running && count_remaining != 0;
    assign beat_active = running && (!wait_mode || count_in) && beat_phase < 16'd50;
    assign current_notes = running && !count_in && active_valid && (wait_mode || elapsed_ms < active_end)
                            ? (128'd1 << active_note) : 128'd0;
    assign preview_notes = running && !wait_mode && next_valid && pitch_valid && preview_window
                            ? (128'd1 << next_pitch[6:0]) : 128'd0;

    wire [6:0] played_note = live_midi_event[14:8];
    wire note_on = live_midi_valid && live_midi_event[23:20] == 4'h9 &&
                   !live_midi_event[15] && !live_midi_event[7] && live_midi_event[6:0] != 0;
    wire fresh_note_on = note_on && key_source < 3 && !held_notes[played_note];
    assign fresh_key_valid = fresh_note_on;
    assign fresh_key_note = played_note;
    assign keys_all_released = !(|held_notes) && !note_on;
    // Track keys even while stopped/counting in. A key held before its prompt
    // cannot pass that prompt, and repeated pitches require release/re-press.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin held_usb <= 0; held_bridge <= 0; held_touch <= 0; end
        else begin
            if (clear_usb_held) held_usb <= 0;
            if (live_midi_valid) begin
            if ((live_midi_event[23:20] == 4'h9 || live_midi_event[23:20] == 4'h8) && !live_midi_event[15]) begin
                case (key_source)
                    0: held_usb[played_note] <= note_on;
                    1: held_bridge[played_note] <= note_on;
                    2: held_touch[played_note] <= note_on;
                    default: ;
                endcase
            end else if (live_midi_event[23:20] == 4'hB && (played_note == 120 || played_note == 123)) begin
                case (key_source)
                    0: held_usb <= 0;
                    1: held_bridge <= 0;
                    2: held_touch <= 0;
                    default: ;
                endcase
            end
            end
        end
    end

    initial $readmemh(ROM_FILE, notes_rom);
    always @(posedge clk) rom_data <= notes_rom[rom_address];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            running <= 0; finished <= 0; elapsed_ms <= 0;
            rom_address <= 0; next_note <= 0; fetch_state <= 0;
            next_valid <= 0; next_index <= 0;
            active_valid <= 0; active_note <= 0; active_end <= 0;
            wait_mode <= 0;
            count_remaining <= 0; beat_phase <= 0;
            speed_remainder <= 0; ms_divider <= 0;
        end else begin
            finished <= 0;
            if (stop) begin
                running <= 0; next_valid <= 0; active_valid <= 0;
                fetch_state <= 0; ms_divider <= 0;
            end else if (start && !running) begin
                running <= 1; elapsed_ms <= 0;
                wait_mode <= wait_for_key;
                count_remaining <= 16'(count_in_beats*BEAT_MS);
                beat_phase <= 0; speed_remainder <= 0; ms_divider <= 0;
                rom_address <= 0; fetch_state <= 1;
                next_valid <= 0; next_index <= 0; active_valid <= 0;
            end else if (running) begin
                if (ms_divider == MS_DIV-1) begin
                    ms_divider <= 0;
                    speed_remainder <= 7'(speed_sum - (step_ms*9'd100));
                    if ({16'd0,beat_phase}+{30'd0,step_ms} >= BEAT_MS)
                        beat_phase <= 16'({16'd0,beat_phase}+{30'd0,step_ms}-BEAT_MS);
                    else beat_phase <= beat_phase + {14'd0,step_ms};
                    if (count_remaining != 0) begin
                        if (count_remaining <= {14'd0,step_ms}) begin
                            count_remaining <= 0;
                            elapsed_ms <= {30'd0,step_ms}-{16'd0,count_remaining};
                        end else count_remaining <= count_remaining-{14'd0,step_ms};
                    end else if (!wait_mode && elapsed_ms+{30'd0,step_ms} >= END_MS) begin
                        elapsed_ms <= END_MS;
                        running <= 0; active_valid <= 0; next_valid <= 0;
                        finished <= 1;
                    end else if (!wait_mode) elapsed_ms <= elapsed_ms+{30'd0,step_ms};
                end else ms_divider <= ms_divider+1;
                case (fetch_state)
                    1: fetch_state <= 2;
                    2: begin next_note <= rom_data; next_valid <= 1; fetch_state <= 0; end
                    default: begin end
                endcase
                if (next_valid && !count_in && (wait_mode ? !active_valid : elapsed_ms >= next_note[31:0]) && {16'd0,next_index} < NOTE_COUNT) begin
                    active_valid <= pitch_valid;
                    active_note <= next_pitch[6:0];
                    active_end <= next_note[31:0]+{16'd0,next_note[47:32]};
                    next_valid <= 0;
                    next_index <= next_index+1'b1;
                    rom_address <= INDEX_WIDTH'(next_index+1'b1);
                    fetch_state <= 1;
                    if (wait_mode && !pitch_valid && {16'd0,next_index}+1 >= NOTE_COUNT) begin
                        running <= 0; finished <= 1;
                    end
                end
                if (wait_mode && !count_in && active_valid && fresh_note_on && played_note == active_note) begin
                    active_valid <= 0;
                    if ({16'd0,next_index} >= NOTE_COUNT) begin
                        running <= 0; next_valid <= 0; finished <= 1;
                    end
                end
            end
        end
    end
endmodule
