`timescale 1ns/1ps
module tb_sd_spi_byte;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,select=0,write_en=0,miso=1;
    reg [1:0] address=0;reg [31:0] write_data=0;
    wire [31:0] read_data;wire cs_n,sck,mosi;
    sd_spi_byte dut(.*);
    reg [7:0] received=0,reply=8'h96;
    integer bitn=0,rises=0;
    always @(posedge sck)begin received={received[6:0],mosi};rises=rises+1;end
    always @(negedge sck)begin bitn=bitn+1;if(bitn<8)miso=reply[7-bitn];end
    task wr(input [1:0] a,input [31:0] d);begin
        @(negedge clk);select=1;write_en=1;address=a;write_data=d;
        @(negedge clk);select=0;write_en=0;
    end endtask
    task byte_test(input integer fast);integer start;begin
        wr(0,fast?2:0);if(cs_n)$fatal(1,"CS did not assert");
        bitn=0;rises=0;received=0;miso=reply[7];start=$time;
        wr(2,8'ha5);wait(!dut.busy);#1;
        if(rises!=8||sck||received!==8'ha5||dut.result!==reply)$fatal(1,"SPI byte TX/RX mismatch %h %h",received,dut.result);
        if($time-start<(fast?1600:40000))$fatal(1,"SPI clock too fast");
        wr(0,1);if(!cs_n)$fatal(1,"CS release");
    end endtask
    initial begin
        repeat(4)@(negedge clk);reset_n=1;byte_test(0);byte_test(1);
        wr(2,0);wr(0,5);if(dut.busy||sck||!cs_n||!mosi)$fatal(1,"SPI abort unsafe");
        $display("PASS SD SPI byte mode0, slow/fast, RX/TX, idle and abort");$finish;
    end
    initial begin #1000000;$fatal(1,"SD byte timeout");end
endmodule
