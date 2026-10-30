`timescale 1ns/1ps
module tb_gesture_gray;
 reg clk=0,cam=0,cam_run=1;always #10 clk=~clk;
 always begin #5.9;if(cam_run)cam=~cam;end
 reg reset_n=0,enable=1,fs=0,fg=0,fb=0,pw=0,done=0;
 reg [14:0] address=0;reg [15:0] pixel=0;
 wire busy,fw,fv;wire [9:0] fi;wire [7:0] value;wire [17:0] sum;
 gesture_gray_frontend dut(clk,cam,reset_n,enable,fs,fg,fb,pw,address,pixel,busy,fw,fv,fi,value,sum,done);
 reg [7:0] oracle[0:65535];integer expected=0,received=0,frames=0,total=0,tag=0;
 reg checking=0;
 function [15:0] color(input integer t,a);color=t==99?16'hffff:t==98?16'd0:(a*37+t*997)&65535;endfunction
 always @(negedge clk)begin
  if(fw)begin
   if(!checking)$fatal(1,"unexpected replay");
   if(fi!==received||value!==oracle[color(tag,(13+(received/32)*3)*160+33+(received%32)*3)])
    $fatal(1,"gray mismatch tag%0d index%0d value%0d",tag,received,value);
   expected=expected+value;received=received+1;total=total+1;
  end
  if(fv)begin if(received!=1024||sum!==expected)$fatal(1,"frame sum/count");frames=frames+1;end
 end
 task boundary(input good,input bad);
  begin @(negedge cam);fs=1;fg=good;fb=bad;@(negedge cam);fs=0;fg=0;fb=0;end
 endtask
 task pixels(input integer skip);
  begin for(integer a=0;a<19200;a=a+1)begin @(negedge cam);pw=a!=skip;address=a;pixel=color(tag,a);end
   @(negedge cam);pw=0;repeat(4)@(negedge cam);end
 endtask
 task ack;
  begin @(negedge clk);done=1;@(negedge clk);done=0;wait(!busy);repeat(5)@(negedge cam);end
 endtask
 task clear;
  begin reset_n=0;repeat(5)@(negedge clk);reset_n=1;repeat(12)@(negedge cam);end
 endtask
 task receive_frame;
  begin received=0;expected=0;checking=1;boundary(0,0);pixels(-1);boundary(1,0);
   wait(fv);repeat(4)@(negedge clk);end
 endtask
 integer before_frames;
 initial begin
  $readmemh("tmp/gray_vectors/gray.mem",oracle);
  clear;
  for(integer c=0;c<65536;c=c+1)begin
   pixel=c;#1;if(dut.roi.weighted[9:2]!==oracle[c])$fatal(1,"exhaustive color %0d",c);
  end
  for(tag=0;tag<4;tag=tag+1)begin
   receive_frame;
   // Illegal writes/publish while consumer holds the frame must be ignored.
   before_frames=frames;boundary(0,0);pixels(-1);boundary(1,0);
   repeat(2200)@(negedge clk);if(frames!=before_frames||!busy)$fatal(1,"busy frame overwrite");ack;
  end
  tag=99;receive_frame;if(sum!=261120)$fatal(1,"white sum overflow");ack;
  tag=98;receive_frame;if(sum!=0)$fatal(1,"black sum");ack;tag=4;
  checking=0;before_frames=frames;
  boundary(0,0);pixels(2113);boundary(1,0);repeat(2200)@(negedge clk);
  boundary(0,0);pixels(-1);boundary(1,1);repeat(2200)@(negedge clk);
  if(frames!=before_frames)$fatal(1,"missing/bad frame published");
  // Acquire while enabled, then disable during the frame: no partial publish.
  boundary(0,0);enable=0;pixels(-1);boundary(1,0);repeat(2200)@(negedge clk);
  if(frames!=before_frames)$fatal(1,"disabled frame published");
  enable=1;repeat(10)@(negedge cam);
  // Published jobs remain drainable after disable and camera clock stop.
  receive_frame;cam_run=0;enable=0;repeat(2500)@(negedge clk);
  if(!busy)$fatal(1,"bank released without done");
  done=1;@(negedge clk);done=0;repeat(10)@(negedge clk);
  cam_run=1;wait(!busy);enable=1;repeat(10)@(negedge cam);
  // Reset both domains with PCLK stopped and a job outstanding.
  receive_frame;cam_run=0;reset_n=0;repeat(8)@(negedge clk);reset_n=1;
  repeat(20)@(negedge clk);if(fw||fv)$fatal(1,"stale result after reset");
  cam_run=1;repeat(12)@(negedge cam);receive_frame;ack;
  $display("PASS gray frontend: %0d exact samples, 84.75MHz PCLK/50MHz system, sums, busy drop, missing/bad/disable, stopped PCLK, reset recovery",total);$finish;
 end
 initial begin #30000000;$fatal(1,"timeout");end
endmodule
