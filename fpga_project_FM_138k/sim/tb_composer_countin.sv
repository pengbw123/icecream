`timescale 1ns/1ps
module tb_composer_countin;
    reg clk=0; always #10 clk=~clk;
    reg reset_n=0,cfg_write=0,suspend=0,observe_valid=0,out_ready=1;
    reg [9:0] cfg_address=0;reg [15:0] cfg_value=0;reg [31:0] observe_data=0;
    wire consume_input,out_valid,gesture_ready,gesture_allowed,gesture_cancel;
    wire [31:0] out_data,status,detail;
    wire gesture_valid=0;wire [3:0] gesture_action=0;
    ai_melody_composer #(.CLOCKS_PER_US(1)) dut(.*);
    integer cycles=0,start_cycle,end_cycle;
    always @(posedge clk)cycles=cycles+1;
    task cfg(input [9:0] a,input [15:0] v);
      begin @(negedge clk);cfg_address=a;cfg_value=v;cfg_write=1;@(negedge clk);cfg_write=0;end
    endtask
    initial begin
      repeat(4)@(negedge clk);reset_n=1;
      cfg('h3c1,10000);cfg('h3c2,0);cfg('h3c0,1);cfg('h3c5,10);
      wait(dut.record_mode==1);@(negedge clk);start_cycle=cycles;
      wait(dut.record_mode==2);@(negedge clk);end_cycle=cycles;
      if(end_cycle-start_cycle!=160001)$fatal(1,"count-in cycles=%0d",end_cycle-start_cycle);
      $display("PASS composer count-in: elapsed %0d cycles at 10000 cycles/step",end_cycle-start_cycle);$finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
