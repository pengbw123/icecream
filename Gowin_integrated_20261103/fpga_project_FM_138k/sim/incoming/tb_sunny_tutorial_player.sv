`timescale 1ns/1ps
`include "src/generated/sunny_tutorial_meta.vh"
module tb_sunny_tutorial_player;
    localparam integer DIV = 10;
    reg clk = 0;
    always #10 clk = ~clk;
    reg reset_n = 0, start = 0, stop = 0;
    reg [7:0] speed_percent = 100;
    reg [3:0] count_in_beats = 4;
    reg signed [7:0] transpose = -2;
    wire wait_for_key=0;
    wire [31:0] live_midi_event=0;
    wire live_midi_valid=0;
    wire [1:0] key_source=0;
    wire running,count_in,beat_active,finished;
    wire [31:0] elapsed_ms;
    wire [127:0] current_notes,preview_notes;
    reg [63:0] reference [0:`SUNNY_NOTE_COUNT];
    integer assertions = 0;
    sunny_tutorial_player #(.CLK_HZ(10000),.NOTE_COUNT(`SUNNY_NOTE_COUNT),
        .END_MS(`SUNNY_END_MS),.BEAT_MS(`SUNNY_BEAT_MS)) dut(.fresh_key_valid(),.fresh_key_note(),.clear_usb_held(1'b0),.keys_all_released(),.*);
    task automatic tick;
        @(posedge clk); #1;
    endtask
    task automatic exercise(input int speed_value, count_value, transpose_value);
        int cursor, cycles, real_ms, music_ms, score_ms, final_real_ms, next_pitch;
        reg [127:0] expected_current,expected_preview;
        @(negedge clk);
        speed_percent = 8'(speed_value); count_in_beats = 4'(count_value);
        transpose = 8'(transpose_value); start = 1;
        tick();
        @(negedge clk); start = 0;
        cursor = -1;
        final_real_ms = ((`SUNNY_END_MS+count_value*400)*100+speed_value-1)/speed_value+2;
        for (cycles = 1; cycles <= final_real_ms*DIV; cycles++) begin
            tick();
            // Settle synchronous lookahead fetches; do not compare an internal
            // state or derive expected output from the DUT's elapsed counter.
            if (cycles % DIV == 5) begin
                real_ms = cycles / DIV;
                music_ms = real_ms*speed_value/100;
                score_ms = music_ms-count_value*400;
                expected_current = 0; expected_preview = 0;
                if (score_ms < `SUNNY_END_MS) begin
                    while (cursor+1 < `SUNNY_NOTE_COUNT && int'(reference[cursor+1][31:0]) <= score_ms)
                        cursor++;
                    if (cursor >= 0 && score_ms < int'(reference[cursor][31:0])+int'(reference[cursor][47:32]))
                        expected_current = 128'd1 << (int'(reference[cursor][55:48])+transpose_value);
                    if (cursor+1 < `SUNNY_NOTE_COUNT &&
                        int'(reference[cursor+1][31:0])-score_ms <= 200) begin
                        next_pitch = int'(reference[cursor+1][55:48])+transpose_value;
                        expected_preview = 128'd1 << next_pitch;
                    end
                end
                assertions++;
                if (current_notes != expected_current || preview_notes != expected_preview)
                    $fatal(1,"Timeline speed=%0d ms=%0d current=%032h expected=%032h preview=%032h expected=%032h",speed_value,score_ms,current_notes,expected_current,preview_notes,expected_preview);
                if (running != (score_ms < `SUNNY_END_MS) ||
                    count_in != (score_ms < 0) ||
                    beat_active != ((score_ms < `SUNNY_END_MS) && music_ms%400 < 50))
                    $fatal(1,"Count-in/beat/end mismatch speed=%0d score_ms=%0d",speed_value,score_ms);
                if (score_ms >= 0 && score_ms < `SUNNY_END_MS && elapsed_ms != 32'(score_ms))
                    $fatal(1,"Elapsed time drift");
            end
        end
        if (running || current_notes || preview_notes) $fatal(1,"Last-note/end did not clear");
    endtask
    initial begin
        $readmemh("src/generated/sunny_tutorial_notes.mem",reference);
        repeat (3) tick(); @(negedge clk); reset_n = 1;
        exercise(100,4,-2);
        exercise(50,4,0);
        exercise(150,0,5);
        @(negedge clk); speed_percent=100; count_in_beats=4; start=1;
        tick(); @(negedge clk); start=0;
        repeat (100) tick();
        if (!count_in) $fatal(1,"Expected count-in");
        @(negedge clk); stop=1; start=1;
        tick();
        if (running || current_notes || preview_notes || beat_active) $fatal(1,"STOP must win");
        @(negedge clk); stop=0; start=0;
        repeat (10) tick();
        if (running) $fatal(1,"Unexpected restart");
        $display("SUNNY_TIMELINE_OK notes=%0d assertions=%0d rates=50/100/150 count-in/preview/gate/beat/end/stop",`SUNNY_NOTE_COUNT,assertions);
        $finish;
    end
    initial begin #200000000; $fatal(1,"Timeline timeout"); end
endmodule
