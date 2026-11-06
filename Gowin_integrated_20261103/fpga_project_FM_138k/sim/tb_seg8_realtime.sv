`timescale 1ns/1ps
// Exercise the actual 50 MHz / 40 ms / 50 kHz production parameters and decode
// only HC595 pins. The fast unit test separately covers arithmetic edge cases.
module tb_seg8_realtime;
    reg clk=0,reset_n=0;
    always #10 clk=~clk;
    reg [9:0] sample_div=0;
    reg tick=0;
    always @(posedge clk) begin sample_div<=sample_div+1'b1;tick<=sample_div==0;end
    reg signed [15:0] pcm=16384;
    reg [7:0] voices=32;
    wire dio,sclk,rclk;
    seg8_audio_status dut(.clk(clk),.reset_n(reset_n),.sample_tick(tick),
        .audio_sample(pcm),.active_voices(voices),
        .data(dio),.shift_clk(sclk),.latch_clk(rclk));
    reg [15:0] shift=0;
    reg [7:0] seen[0:7];
    integer bits=0,i,frames=0;
    time last_shift=0;
    always @(posedge sclk) begin
        if(bits>0 && $time-last_shift!=20000) $fatal(1,"not a 50 kHz shift clock");
        shift={shift[14:0],dio};bits=bits+1;last_shift=$time;
    end
    always @(posedge rclk) begin
        if(bits!=16 || shift[15]!==1'b1) $fatal(1,"invalid HC595 frame / DP");
        for(i=0;i<8;i=i+1) if(shift[7:0]==(8'b1<<i)) seen[i]=shift[15:8];
        bits=0;frames=frames+1;
    end
    initial begin
        #100;reset_n=1;
        #39000000;
        if(dut.level!==0) $fatal(1,"peak updated before 40 ms");
        // Allow a complete old scan plus a complete new scan (5.6 ms).
        #7000000;
        if({seen[7],seen[6],seen[5],seen[4],seen[3],seen[2],seen[1],seen[0]}
             !==64'hc7ff92c08cFFb0a4) $fatal(1,"expected physical L 50P 32");
        @(negedge clk);pcm=0;voices=0;
        #81000000;
        if({seen[7],seen[6],seen[5],seen[4],seen[3],seen[2],seen[1],seen[0]}
             !==64'hc7ffc0c08cffc0c0) $fatal(1,"expected physical L 00P 00 after silence");
        if(frames<300) $fatal(1,"scan stopped");
        $display("PASS seg8 production parameters: 40 ms peak window, 50 kHz serial pins, L 50P 32, silence L 00P 00 (%0d digit frames)",frames);
        $finish;
    end
    initial begin #130000000;$fatal(1,"timeout");end
endmodule
