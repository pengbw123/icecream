`timescale 1ns/1ps
// Behavioral PLL/ODDR for raster verification only, not electrical modelling.
module video_pll #(parameter PIXEL_DIV=30,ENABLE_SERIAL=0)
    (input clkin,output reg pixel_clk=0,output serial_clk,output reg lock=0);
    always #15 pixel_clk=~pixel_clk;
    assign serial_clk=0;
    initial #200 lock=1;
endmodule
module ODDR(output reg Q0,output Q1,input D0,D1,TX,CLK);
    always @(posedge CLK)Q0<=D0;
    always @(negedge CLK)Q0<=D1;
    assign Q1=TX;
endmodule
module tb_rgb_visualizer;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0;
    reg [9:0] sample_div=0;
    reg tick=0;
    reg signed [15:0] pcm=0;
    real phase=0;
    always @(negedge clk)begin
        sample_div=sample_div+1;
        tick=sample_div==0;
        if(tick)begin phase=phase+0.033;pcm=$rtoi(18000*$sin(phase)+5000*$sin(3*phase));end
    end
    reg [31:0] event_word=0;
    reg event_valid=0;
    wire pclk,de,hs,vs,bl,lock;
    wire [4:0] r,b;
    wire [5:0] g;
    rgb_visualizer dut(.clk(clk),.reset_n(reset_n),.sample_tick(tick),.audio_sample(pcm),
        .midi_event_data(event_word),.midi_event_valid(event_valid),.active_voice_count(5'd3),
        .preset_index(5'd10),.algorithm(5'd4),.operator_envelopes(48'hB090603080D0),
        .touch_present(1'b1),.keyboard_octave(4'sd0),.master_volume(7'd96),
        .lcd_pclk(pclk),.lcd_de(de),.lcd_hsync(hs),.lcd_vsync(vs),.lcd_bl(bl),
        .lcd_r(r),.lcd_g(g),.lcd_b(b),.pll_locked(lock));
    task note_on(input [6:0] note);
        begin @(negedge clk);event_word={8'd0,8'h90,1'b0,note,8'd100};event_valid=1;
            @(negedge clk);event_valid=0;end
    endtask
    integer file_handle,pixels,row_pixels=0,rows=0;
    reg de_prev=0;
    initial begin
        repeat(20)@(negedge clk);reset_n=1;
        note_on(48);note_on(52);note_on(55);
        repeat(2)begin wait(dut.frame_latch);@(posedge dut.pclk);wait(!dut.frame_latch);end
        wait(!de);@(posedge de);
        file_handle=$fopen("tmp/rgb_preview.ppm","wb");
        $fwrite(file_handle,"P6\n800 480\n255\n");
        pixels=0;
        while(pixels<800*480)begin
            @(posedge pclk);
            if(de)begin
                if(^{r,g,b}===1'bx)$fatal(1,"Unknown RGB output");
                $fwrite(file_handle,"%c%c%c",{r,r[4:2]},{g,g[5:4]},{b,b[4:2]});
                pixels=pixels+1;row_pixels=row_pixels+1;
            end
            if(de_prev&&!de)begin
                if(row_pixels!=800)$fatal(1,"Active row width %0d",row_pixels);
                rows=rows+1;row_pixels=0;
            end
            de_prev=de;
        end
        if(rows!=479||row_pixels!=800)$fatal(1,"Frame row count %0d",rows);
        $fclose(file_handle);$display("PASS 800x480 RGB raster, stable pixels and screenshot");$finish;
    end
    // Bank ownership is checked at every audio write, not just by image shape.
    always @(posedge clk)if(reset_n&&tick&&!dut.capture_pending)
        if(dut.write_bank==dut.display_bank)$fatal(1,"Audio overwrote displayed waveform bank");
    initial begin #100000000;$fatal(1,"Raster timeout");end
endmodule
