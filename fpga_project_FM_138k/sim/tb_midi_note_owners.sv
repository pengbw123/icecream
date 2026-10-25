`timescale 1ns/1ps
module tb_midi_note_owners;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,valid=0,ready=1;
    reg [31:0] data=0;wire forward;
    midi_note_owners dut(.*);
    wire part_forward;
    midi_note_owners #(.INDEPENDENT_PARTS(1)) part_dut(.clk(clk),.reset_n(reset_n),
        .data(data),.valid(valid),.ready(ready),.forward(part_forward));
    task event_check(input [31:0] v,input expected);begin
        @(negedge clk);data=v;valid=1;#1;
        if(forward!==expected)$fatal(1,"Owner filter event %h forward=%b",v,forward);
        @(negedge clk);valid=0;
    end endtask
    initial begin
        #100;reset_n=1;
        event_check(32'h00903c64,1); // human starts C4
        event_check(32'h80903c60,0); // demo joins without retriggering
        event_check(32'h80803c00,0); // demo stops, human keeps sound
        event_check(32'h00803c00,1);
        event_check(32'h80903c60,1);
        event_check(32'h00903c64,0);
        event_check(32'h00903c00,0); // human velocity zero release
        event_check(32'h80803c00,1);
        event_check(32'h00903e64,1);
        event_check(32'h00903e64,1); // normal retrigger retained
        event_check(32'h00b07b00,1);
        if(dut.human!=0||dut.demo!=0)$fatal(1,"All Notes Off did not clear owners");
        event_check(32'h00903c64,1);
        event_check(32'h00b0167f,1);
        if(dut.human!=0)$fatal(1,"Mono switch did not clear synth ownership");
        event_check(32'h00b07b00,1);
        event_check(32'h40903c64,1);
        if(part_dut.demo!=0||part_dut.human!=0)$fatal(1,"BACKING contaminated LIVE/practice ownership");
        @(negedge clk);data=32'h00903c64;valid=1;#1;
        if(!part_forward)$fatal(1,"BACKING suppressed LIVE same-pitch attack");
        @(negedge clk);valid=0;
        event_check(32'h00b07b00,1);
        ready=0;event_check(32'h00903c64,1);
        if(dut.human!=0)$fatal(1,"Backpressured input changed ownership");
        $display("PASS independent human/demo MIDI ownership and backpressure");$finish;
    end
endmodule
