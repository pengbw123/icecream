`timescale 1ns/1ps
module tb_polyphony_spectrum;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,tick=0;reg signed [15:0] sample=0;
 wire we;wire [8:0] addr;wire [13:0] data;
 audio_spectrum_analyzer dut(.clk(clk),.reset_n(reset_n),.sample_tick(tick),.audio_sample(sample),.bin_write(),.bin_address(),.bin_data(),.linear_write(we),.linear_address(addr),.linear_data(data));
 reg [15:0] input_samples[0:1023];reg [9:0] expected[0:31];integer levels[0:511];integer n=0,divider=0,count=0,fd,k,p,max_bin;
 always @(negedge clk)begin tick=0;if(reset_n)begin divider=divider+1;
  if(divider==64)begin divider=0;tick=1;sample=input_samples[n];if(dut.state==0)n=(n+1)%1024;end end end
 always @(posedge clk)if(we)begin
  if(addr!==count)$fatal(1,"linear address %d expected %d",addr,count);
  if(^data===1'bx)$fatal(1,"unknown raw FFT");levels[count]=data[6:0];count=count+1;
 end
 initial begin
  $readmemh("tmp/polyphony_fft_input.mem",input_samples);$readmemh("tmp/polyphony_expected_bins.mem",expected);
  repeat(5)@(negedge clk);reset_n=1;wait(count==512);@(negedge clk);
  fd=$fopen("tmp/polyphony_linear_levels.txt","w");for(k=0;k<512;k=k+1)$fdisplay(fd,"%d",levels[k]);$fclose(fd);
  for(k=0;k<32;k=k+1)begin
   p=expected[k];max_bin=p;
   if(levels[p-1]>levels[max_bin])max_bin=p-1;if(levels[p+1]>levels[max_bin])max_bin=p+1;
   if(levels[max_bin]<40||levels[max_bin]<levels[max_bin-1]||levels[max_bin]<levels[max_bin+1])$fatal(1,"missing local peak note %d bin %d",96+k,p);
  end
  $display("PASS linear FFT: ordered 512 real bins, 32 known MIDI frequencies have matching local peaks");$finish;
 end
 initial begin #10000000;$fatal(1,"FFT timeout");end
endmodule
