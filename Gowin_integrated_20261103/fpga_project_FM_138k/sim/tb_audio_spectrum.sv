`timescale 1ns/1ps
module tb_audio_spectrum;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,tick=0;
    reg signed [15:0] sample=0;
    wire we;wire [5:0] addr;wire [13:0] data;
    audio_spectrum_analyzer dut(.clk(clk),.reset_n(reset_n),.sample_tick(tick),
        .audio_sample(sample),.bin_write(we),.bin_address(addr),.bin_data(data));
    integer sample_n=0,divider=0,tone_bin=9,amplitude=16000,mode=0;
    integer count=0,max_level=0,max_band=0,frames=0;
    reg [6:0] levels[0:63],peaks[0:63];
    always @(negedge clk)begin
        tick=0;
        if(reset_n)begin
            divider=divider+1;
            if(divider==64)begin
                divider=0;tick=1;
                if(mode==0)sample=$rtoi(amplitude*$sin(6.283185307179586*tone_bin*sample_n/1024.0));
                else if(mode==1)sample=0;
                else if(mode==2)sample=(sample_n%2)?-32768:32767;
                else sample=$rtoi(6000*$sin(6.283185307179586*9*sample_n/1024.0)+
                                  3000*$sin(6.283185307179586*84*sample_n/1024.0));
                // Advance only during capture, keeping a coherent known block.
                if(dut.state==0)sample_n=sample_n+1;
            end
        end
    end
    always @(posedge clk)if(we)begin
        if(addr!==count[5:0])$fatal(1,"Non-contiguous spectrum frame %d/%d",addr,count);
        if(^data===1'bx || data[6:0]>96 || data[13:7]>96)$fatal(1,"Invalid spectrum level %h",data);
        if(data[13:7]<data[6:0])$fatal(1,"Peak below bar");
        levels[addr]=data[6:0];
        peaks[addr]=data[13:7];
        if(data[6:0]>max_level)begin max_level=data[6:0];max_band=addr;end
        count=count+1;
        if(addr==63)begin count=0;frames=frames+1;end
    end
    task restart(input integer bin_value,amp_value,mode_value);
        begin
            @(negedge clk);reset_n=0;tick=0;
            repeat(4)@(negedge clk);
            tone_bin=bin_value;amplitude=amp_value;mode=mode_value;
            sample_n=0;divider=0;count=0;frames=0;max_level=0;max_band=0;reset_n=1;
        end
    endtask
    integer i,lo,hi,saved;
    initial begin
        restart(9,16000,0);wait(frames==1);#1;
        if(max_level<86||max_level>89)$fatal(1,"Hann/dBFS calibration level=%d expected ~88",max_level);
        lo=dut.bands[max_band]>>10;hi=dut.bands[max_band]&1023;
        if(lo>9||hi<9)$fatal(1,"Wrong frequency band %d range=%d..%d",max_band,lo,hi);
        if($signed(dut.imag_mem[9])< -16080 || $signed(dut.imag_mem[9])> -15920 ||
           $signed(dut.real_mem[9])< -80 || $signed(dut.real_mem[9])>80)
            $fatal(1,"FFT sign/scaling/order R=%d I=%d",$signed(dut.real_mem[9]),$signed(dut.imag_mem[9]));
        // A -12 dB amplitude change must move ~16 log units, with no AGC.
        saved=max_level;restart(84,4000,0);wait(frames==1);#1;
        if(saved-max_level<15||saved-max_level>17)$fatal(1,"Level ratio/FFT scaling %d %d",saved,max_level);
        lo=dut.bands[max_band]>>10;hi=dut.bands[max_band]&1023;
        if(lo>84||hi<84)$fatal(1,"High-frequency peak mapped incorrectly");
        restart(9,0,3);wait(frames==1);#1;
        if($signed(dut.imag_mem[9])< -6080 || $signed(dut.imag_mem[9])> -5920 ||
           $signed(dut.imag_mem[84])< -3080 || $signed(dut.imag_mem[84])> -2920)
            $fatal(1,"Two simultaneous tones lost/cross-modulated");
        // Fresh/reset silence must be all-zero, not uninitialized RAM or a DC bar.
        restart(9,0,1);wait(frames==1);#1;
        for(i=0;i<64;i=i+1)if(levels[i]!=0)$fatal(1,"Silence band %d = %d",i,levels[i]);
        // Full-scale negative input exercises abs(-131072), all butterflies,
        // saturation and log conversion without signed wraparound.
        restart(9,0,2);wait(frames==1);#1;
        if(max_level<85)$fatal(1,"Full-scale/Nyquist energy disappeared");
        // Check real temporal release and peak hold on transition to silence.
        saved=levels[63];mode=1;max_level=0;wait(frames==2);#1;
        if(levels[63]<saved-1)$fatal(1,"Bar release bypassed smoothing");
        if(peaks[63]!=saved)$fatal(1,"Peak hold did not retain the preceding peak");
        $display("PASS spectrum FFT order/sign/scaling, Hann calibration, log bands, silence, negative FS and release");$finish;
    end
    initial begin #30000000;$fatal(1,"Spectrum analyzer timeout");end
endmodule
