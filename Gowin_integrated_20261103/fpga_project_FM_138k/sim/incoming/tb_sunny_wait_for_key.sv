`timescale 1ns/1ps
`include "src/generated/sunny_tutorial_meta.vh"
module tb_sunny_wait_for_key;
    reg clk=0; always #10 clk=~clk;
    reg reset_n=0,start=0,stop=0,wait_for_key=1;
    reg [7:0] speed_percent=50;
    reg [3:0] count_in_beats=1;
    reg signed [7:0] transpose=-2;
    reg [31:0] live_midi_event=0;
    reg live_midi_valid=0;
    reg [1:0] key_source=0;
    wire running,count_in,beat_active,finished;
    wire [31:0] elapsed_ms;
    wire [127:0] current_notes,preview_notes;
    reg [63:0] reference [0:`SUNNY_NOTE_COUNT];
    int completed=0,checks=0;
    sunny_tutorial_player #(.CLK_HZ(10000),.NOTE_COUNT(`SUNNY_NOTE_COUNT),
        .END_MS(`SUNNY_END_MS),.BEAT_MS(`SUNNY_BEAT_MS)) dut(.fresh_key_valid(),.fresh_key_note(),.clear_usb_held(1'b0),.keys_all_released(),.*);
    always @(posedge clk) if(finished) completed++;
    task automatic tick; @(posedge clk); #1; endtask
    task automatic midi(input int source_id,status,note,velocity);
        @(negedge clk);key_source=2'(source_id);live_midi_event={8'h09,8'(status),8'(note),8'(velocity)};live_midi_valid=1;
        tick();@(negedge clk);live_midi_valid=0;repeat(8)tick();
    endtask
    task automatic begin_practice;
        @(negedge clk);start=1;tick();@(negedge clk);start=0;
    endtask
    task automatic target(input int note);
        int limit=0;
        while(current_notes!=(128'd1<<note))begin tick();limit++;if(limit>20)$fatal(1,"Missing target %0d got=%h",note,current_notes);end
        if(!running || preview_notes || beat_active)$fatal(1,"Wait mode leaked preview/beat or stopped");checks++;
    endtask
    task automatic stuck(input int note,index);
        repeat(100)tick();target(note);
        if(int'(dut.next_index)!=index)$fatal(1,"Held/wrong note advanced index %0d expected %0d",dut.next_index,index);checks++;
    endtask
    int first_pitch,pitch,index_before,cycles;
    initial begin
        $readmemh("src/generated/sunny_tutorial_notes.mem",reference);
        first_pitch=int'(reference[0][55:48])-2;
        repeat(3)tick();@(negedge clk);reset_n=1;
        midi(0,'h90,first_pitch,90); // Already down before start.
        begin_practice();cycles=0;
        while(count_in)begin tick();cycles++;if(cycles>8010)$fatal(1,"Count-in stuck");end
        if(cycles<7990)$fatal(1,"50%% one beat must take 800 real ms");
        target(first_pitch);stuck(first_pitch,1);
        repeat(2000000)tick();target(first_pitch); // Exceeds original song duration.
        if(elapsed_ms!=0)$fatal(1,"Waiting advanced the fixed timeline");
        midi(0,'h90,first_pitch+1,90);stuck(first_pitch,1);
        midi(0,'h90,first_pitch,90);stuck(first_pitch,1);
        midi(2,'h90,first_pitch,90); // A second physical source holds the pitch.
        midi(0,'h80,first_pitch,0);
        midi(0,'h90,first_pitch,90);stuck(first_pitch,1);
        midi(0,'h90,first_pitch,0);midi(2,'h80,first_pitch,0);
        midi(3,'h90,first_pitch,90);stuck(first_pitch,1); // Unknown source cannot pass.
        midi(0,'h90,first_pitch,90);
        pitch=int'(reference[1][55:48])-2;target(pitch);
        if(pitch==first_pitch)begin midi(0,'h90,pitch,90);stuck(pitch,2);end
        // STOP wins over a correct hit and clears the target immediately.
        @(negedge clk);stop=1;live_midi_event={8'h09,8'h90,8'(pitch),8'd90};live_midi_valid=1;
        tick();if(running||current_notes||preview_notes||finished)$fatal(1,"STOP lost to correct hit");
        @(negedge clk);stop=0;live_midi_valid=0;
        for(int s=0;s<3;s++)midi(s,'hB0,123,0);
        count_in_beats=0;speed_percent=150;begin_practice();
        // Play every ROM target once; the melody must never auto-advance.
        for(int n=0;n<`SUNNY_NOTE_COUNT;n++)begin
            pitch=int'(reference[n][55:48])-2;target(pitch);
            index_before=int'(dut.next_index);
            if(index_before!=n+1)$fatal(1,"Skipped/repeated note n=%0d idx=%0d",n,index_before);
            repeat(30)tick();stuck(pitch,index_before);
            midi(0,'h80,pitch,0);midi(0,'h90,pitch,80);
        end
        repeat(10)tick();if(running||current_notes||preview_notes||completed!=1)$fatal(1,"Final hit did not finish exactly once");
        // Fixed-follow mode still advances automatically with no key events.
        wait_for_key=0;begin_practice();repeat(200)tick();
        if(!running||elapsed_ms==0)$fatal(1,"Fixed-follow mode regressed");
        @(negedge clk);stop=1;tick();
        $display("SUNNY_WAIT_KEY_OK notes=%0d checks=%0d wrong/held/repeat/multi-source/transpose/count-in/stop/end",`SUNNY_NOTE_COUNT,checks);
        $finish;
    end
    initial begin #100000000; $fatal(1,"Wait-key timeout"); end
endmodule
