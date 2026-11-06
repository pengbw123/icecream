`timescale 1ns/1ps
module tb_audio_wave_scope;
    reg clk=0;always #10 clk=~clk;
    reg pclk=0;always #15 pclk=~pclk;
    reg reset_n=0,tick=0,frame=0,auto_gain=1;
    reg signed [15:0] pcm=0;
    reg [8:0] address=0;
    wire [7:0] lo,hi;wire valid;
    audio_wave_scope dut(.clk(clk),.reset_n(reset_n),.sample_tick(tick),.auto_gain(auto_gain),
        .audio_sample(pcm),.pixel_clk(pclk),.video_reset_n(reset_n),.frame_latch(frame),
        .pixel_address(address),.y_min(lo),.y_max(hi),.valid(valid));
    integer i,previous_lo,previous_hi,span_width;
    task snapshot(input integer mode);
        begin
            wait(dut.state==0);
            for(i=0;i<512;i=i+1)begin
                @(negedge clk);tick=1;
                // Worst slopes, quiet -> attack inside the same snapshot,
                // plus a quiet full snapshot. Both signed extrema included.
                if(mode==2)pcm=(i&1)?100:-100;
                else if(mode==1 && i<400)pcm=(i&1)?50:-50;
                else pcm=(i&1)?32767:-32768;
                @(negedge clk);tick=0;repeat(3)@(negedge clk);
            end
            wait(dut.state==5);repeat(5)@(negedge pclk);frame=1;
            @(negedge pclk);frame=0;repeat(5)@(negedge pclk);
            if(!valid)$fatal(1,"No snapshot published");
            span_width=0;
            for(i=0;i<512;i=i+1)begin
                @(negedge pclk);address=i;@(posedge pclk);#1;
                if(^{lo,hi}===1'bx||lo>hi||lo<16||hi>240)$fatal(1,"Invalid span %d %d",lo,hi);
                if(i>0 && (lo>previous_hi||hi<previous_lo))$fatal(1,"Disconnected columns at %d",i);
                previous_lo=lo;previous_hi=hi;
                if(hi-lo>span_width)span_width=hi-lo;
            end
            if(span_width<150)$fatal(1,"Trace unexpectedly tiny: %d",span_width);
        end
    endtask
    initial begin
        repeat(10)@(negedge clk);reset_n=1;
        snapshot(0);snapshot(1);snapshot(2);
        $display("PASS waveform connected spans, quiet/attack/full-scale and border margin");$finish;
    end
    always @(posedge clk)if(reset_n&&dut.state==4)
        if(dut.write_bank==dut.display_bank)$fatal(1,"Wave bank collision");
    initial begin #10000000;$fatal(1,"Wave timeout");end
endmodule
