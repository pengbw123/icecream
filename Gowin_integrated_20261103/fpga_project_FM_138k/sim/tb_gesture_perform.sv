`timescale 1ns/1ps
module tb_gesture_perform;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,cfg_write=0,suspend=0,observe_valid=0,out_ready=1,gesture_valid=0;
 reg [9:0] cfg_address=0;reg [15:0] cfg_value=0;reg [31:0] observe_data=0;
 reg [3:0] gesture_action=0;
 wire consume_input,out_valid,gesture_ready,gesture_allowed,gesture_cancel;
 wire [31:0] out_data,status,detail;
 ai_melody_composer #(.CLOCKS_PER_US(1),.GESTURE_ENABLED(1)) dut(.*);
 integer held=-1,ons=0,offs=0;reg [15:0] saved[0:15];reg bank;
 always @(posedge clk)if(reset_n&&out_valid&&out_ready)begin
  if(out_data[23:20]==9)begin if(held!=-1)$fatal(1,"overlap");held=out_data[14:8];ons=ons+1;end
  else if(out_data[23:20]==8)begin if(held!=out_data[14:8])$fatal(1,"unmatched off");held=-1;offs=offs+1;end
 end
 task cfg(input [9:0] a,input [15:0] v);
  begin @(negedge clk);cfg_address=a;cfg_value=v;cfg_write=1;@(negedge clk);cfg_write=0;repeat(4)@(negedge clk);end
 endtask
 task gest(input [3:0] a);
  begin wait(gesture_ready);@(negedge clk);gesture_action=a;gesture_valid=1;@(negedge clk);gesture_valid=0;repeat(4)@(negedge clk);end
 endtask
 initial begin
  repeat(5)@(negedge clk);reset_n=1;
  cfg('h3c1,40000);cfg('h3c2,0);cfg('h3c0,1);cfg('h3c7,1);gest(2);
  wait(dut.step_index==5);gest(3);if(!dut.running)$fatal(1,"fist stopped transport");
  wait(dut.bar_lock);@(negedge clk);bank=dut.bar_play_bank;
  for(integer i=0;i<16;i=i+1)saved[i]=dut.bars[{bank,4'(i)}];
  repeat(1280100)@(negedge clk);
  for(integer i=0;i<16;i=i+1)if(saved[i]!==dut.bars[{bank,4'(i)}])$fatal(1,"loop overwritten");
  if(!dut.running||!dut.bar_lock||dut.misses)$fatal(1,"loop transport running%0d lock%0d misses%0d",dut.running,dut.bar_lock,dut.misses);
  gest(2);wait(!dut.bar_lock);if(!dut.running)$fatal(1,"resume stopped");
  gest(10);gest(11);wait(dut.density==110&&dut.direction==110);
  gest(3);wait(dut.bar_lock);gest(4);wait(!dut.var_pending);
  if(dut.bar_lock||!dut.running)$fatal(1,"variation did not resume");
  cfg('h3c5,3);repeat(500)@(negedge clk);
  if(dut.running||dut.bar_lock||held!=-1||ons!=offs)$fatal(1,"manual stop/drain");
  // BASIC retains STOP instead of loop, and PERFORM is explicitly selected.
  cfg('h3c7,0);gest(2);wait(dut.running);gest(3);repeat(500)@(negedge clk);
  if(dut.running||held!=-1)$fatal(1,"BASIC fist no longer stops");
  cfg('h3c7,1);gest(2);wait(dut.running);gest(3);cfg('h3c5,3);
  repeat(500)@(negedge clk);gest(2);repeat(4)@(negedge clk);
  if(dut.freeze_pending||dut.bar_lock)$fatal(1,"manual STOP retained loop request");
  cfg('h3c5,3);repeat(500)@(negedge clk);
  $display("PASS gesture_perform: fist first-bar wait and loop integrity, palm resume, beat XY, boundary variation, manual stop and NoteOff");$finish;
 end
 initial begin #200000000;$fatal(1,"timeout step%0d run%0d lock%0d pending%0d",dut.step_index,dut.running,dut.bar_lock,dut.freeze_pending);end
endmodule
