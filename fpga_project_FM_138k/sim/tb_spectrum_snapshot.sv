`timescale 1ns/1ps
module tb_spectrum_snapshot;
    reg clk=0,pclk=0;
    always #10 clk=~clk;always #17 pclk=~pclk;
    reg reset_n=0,video_reset_n=0,we=0,latch_frame=0;
    reg [5:0] wa=0,pa=0;
    reg [13:0] wd=0;
    wire [6:0] level,peak;wire valid;
    audio_spectrum_snapshot dut(.clk(clk),.reset_n(reset_n),.bin_write(we),
        .bin_address(wa),.bin_data(wd),.pixel_clk(pclk),.video_reset_n(video_reset_n),
        .frame_latch(latch_frame),.pixel_address(pa),.level(level),.peak(peak),.valid(valid));
    task send_frame(input integer tag,first);
        integer i;reg [6:0] v;
        begin for(i=first;i<64;i=i+1)begin
            @(negedge clk);v=(i+tag)%90;wa=i;wd={v+7'd4,v};we=1;
            @(negedge clk);we=0;
        end end
    endtask
    task flip;
        begin repeat(6)@(negedge pclk);latch_frame=1;@(negedge pclk);latch_frame=0;
            repeat(6)@(negedge clk);end
    endtask
    task check_frame(input integer tag);
        integer i;reg [6:0] v;
        begin
            if(!valid)$fatal(1,"Snapshot not valid");
            for(i=0;i<64;i=i+1)begin
                @(negedge pclk);pa=i;repeat(2)@(negedge pclk);v=(i+tag)%90;
                if(level!==v||peak!==v+7'd4)$fatal(1,"Torn snapshot tag=%d bar=%d level=%d peak=%d",tag,i,level,peak);
            end
        end
    endtask
    always @(posedge clk)if(reset_n&&valid&&we&&(dut.copying||dut.start)&&dut.write_bank==dut.display_bank)
        $fatal(1,"Audio wrote the displayed spectrum bank");
    initial begin
        repeat(5)@(negedge clk);reset_n=1;video_reset_n=1;
        send_frame(1,0);send_frame(2,0);
        if(valid)$fatal(1,"Spectrum published outside frame boundary");
        flip();check_frame(1);
        send_frame(3,0);check_frame(1);flip();check_frame(3);
        // PLL loss resets both owners. A tail without bin 0 is not a frame.
        @(negedge clk);reset_n=0;video_reset_n=0;
        repeat(5)@(negedge clk);reset_n=1;video_reset_n=1;
        send_frame(4,16);flip();if(valid)$fatal(1,"Partial spectrum after PLL loss accepted");
        send_frame(5,0);flip();check_frame(5);
        $display("PASS spectrum CDC: atomic frame flip, slow video/drop, ownership and PLL-loss recovery");$finish;
    end
    initial begin #1000000;$fatal(1,"Spectrum snapshot timeout");end
endmodule
