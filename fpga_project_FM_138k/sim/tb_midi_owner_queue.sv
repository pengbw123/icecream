`timescale 1ns/1ps
module tb_midi_owner_queue;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,in_valid=0,out_ready=0;
    reg [31:0] in_data=0;reg [6:0] in_brightness=99;
    wire in_ready,out_valid;wire [31:0] out_data;wire [6:0] out_brightness;
    midi_owner_queue dut(.*);
    task send(input [31:0] d);begin
        @(negedge clk);in_data=d;in_valid=1;
        while(!in_ready)@(negedge clk);
        @(negedge clk);in_valid=0;
    end endtask
    initial begin
        #100;reset_n=1;
        send(32'h00903c64);in_data=32'h00903e77;in_brightness=7;repeat(20)@(negedge clk);
        if(!out_valid||out_data!==32'h00903c64||out_brightness!=99||in_ready)$fatal(1,"Queue lost stalled event");
        out_ready=1;@(negedge clk);
        send(32'h80903c60);#1;if(out_valid)$fatal(1,"Demo overlap forwarded");
        send(32'h00803c00);#1;if(out_valid)$fatal(1,"Human release cut demo");
        send(32'h80803c00);#1;if(!out_valid||out_data!==32'h80803c00)$fatal(1,"Final owner release lost");
        @(negedge clk);out_ready=0;
        send(32'h00903e55);repeat(10)@(negedge clk);
        if(!out_valid||out_data!==32'h00903e55)$fatal(1,"Queue repeat stall corrupted word");
        $display("PASS MIDI ownership queue ordering, overlap, brightness and stable backpressure");$finish;
    end
    initial begin #100000;$fatal(1,"Owner queue timeout");end
endmodule
