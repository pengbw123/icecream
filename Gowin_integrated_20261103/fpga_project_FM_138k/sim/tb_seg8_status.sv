`timescale 1ns/1ps
module tb_seg8_status;
    reg clk=0,reset_n=0,tick=0;
    always #10 clk=~clk;
    reg signed [15:0] sample=0;
    reg [7:0] voices=0;
    wire dio,sclk,rclk;
    seg8_audio_status #(.WINDOW_CYCLES(64),.SCAN_DIV(1)) dut(
        .clk(clk),.reset_n(reset_n),.sample_tick(tick),.audio_sample(sample),
        .active_voices(voices),.data(dio),.shift_clk(sclk),.latch_clk(rclk));
    reg [31:0] scan_input=32'h12345678;
    wire sd,sc,sl;
    seg8_status #(.SCAN_DIV(1)) scan(.clk(clk),.reset_n(reset_n),.bcd(scan_input),
        .data(sd),.shift_clk(sc),.latch_clk(sl));
    reg [15:0] serial=0;
    integer bits=0,latches=0;
    reg [31:0] expected_frame;
    integer expected_digit=0;
    function [7:0] glyph(input [3:0] n);
        case(n)
            0:glyph=8'hc0;1:glyph=8'hf9;2:glyph=8'ha4;3:glyph=8'hb0;
            4:glyph=8'h99;5:glyph=8'h92;6:glyph=8'h82;7:glyph=8'hf8;
            8:glyph=8'h80;9:glyph=8'h90;10:glyph=8'hc7;11:glyph=8'h8c;
            default:glyph=8'hff;
        endcase
    endfunction
    // Decode actual pins, not internal serial_word. Check the full chain and
    // a changed input between digits: all eight digits must share a snapshot.
    always @(posedge clk) if(reset_n && scan.divider==0 && scan.bit_cycle==0 && scan.digit==0)
        expected_frame=scan_input;
    always @(posedge sc) begin serial={serial[14:0],sd};bits=bits+1;end
    always @(posedge sl) begin
        if(bits!=16) $fatal(1,"HC595 needs exactly 16 rising edges, got %0d",bits);
        if(serial[7:0] !== (8'b1<<expected_digit)) $fatal(1,"digit selection/order");
        if(serial[15:8] !== glyph(expected_frame>>(expected_digit*4)))
            $fatal(1,"glyph/snapshot digit %0d got %h",expected_digit,serial);
        if(!serial[15]) $fatal(1,"decimal point must be off");
        expected_digit=(expected_digit+1)%8;latches=latches+1;bits=0;
    end
    task check_level(input integer amp,input integer wanted);
        begin
            @(negedge clk);tick=1;sample=amp;
            repeat(132) @(negedge clk);
            if(dut.level!==wanted) $fatal(1,"amplitude %0d expected %0d got %0d",amp,wanted,dut.level);
        end
    endtask
    integer amp,ref_level;
    initial begin
        repeat(4) @(negedge clk);reset_n=1;
        check_level(0,0);check_level(32767,99);check_level(-32768,99);
        check_level(16384,50);check_level(-8192,25);check_level(1,0);
        // Numerical sweep exercises sign, scaling and decimal conversion.
        for(amp=-32768;amp<32768;amp=amp+997) begin
            ref_level=((amp<0 ? -amp : amp)*99+16384)>>15;
            check_level(amp,ref_level);
            if(dut.digits[23:16] !== (((ref_level/10)<<4)|(ref_level%10)))
                $fatal(1,"level decimal formatting");
        end
        @(negedge clk);voices=32;scan_input=32'hbf09af32;
        repeat(5) @(negedge clk);
        if(dut.digits[15:0]!==16'hbf32) $fatal(1,"32 voices must not wrap");
        voices=8'd255;repeat(5) @(negedge clk);
        if(dut.digits[7:0]!==8'h99) $fatal(1,"overflow should saturate");
        // Sample on the exact final window clock must not be lost.
        tick=0;repeat(132) @(negedge clk);
        wait(dut.window_count==63);@(negedge clk);sample=-32768;tick=1;
        @(negedge clk);tick=0;repeat(3) @(negedge clk);
        if(dut.level!==99) $fatal(1,"sample on window boundary lost");
        // Nonzero sample wire without strobe must not keep a stale peak alive.
        repeat(132) @(negedge clk);
        if(dut.level!==0) $fatal(1,"missing strobes must return to silence");
        voices=0;scan_input=32'haf00bf00;repeat(600) @(negedge clk);
        if(dut.digits!==32'haf00bf00) $fatal(1,"silence/zero voices format");
        if(latches<32) $fatal(1,"insufficient complete scans");
        $display("PASS seg8: PCM sweep, signed full scale, boundary sample, silence timeout, decimal voices, serial ordering, coherent frames and DP off (%0d latches)",latches);
        $finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
