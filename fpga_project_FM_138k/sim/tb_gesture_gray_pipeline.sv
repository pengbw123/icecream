`timescale 1ns/1ps
module tb_gesture_gray_pipeline;
 reg clk=0,cam=0,run=1;always #10 clk=~clk;
 always begin #5.9;if(run)cam=~cam;end
 reg reset_n=0,enable=1,control=0,cancel=0,ready=1,fs=0,fg=0,fb=0,pw=0;
 reg [14:0] address=0;reg [15:0] pixel=0;
 wire rv,accepted,tracking,av,busy;wire [1:0] cls,stable;wire [14:0] energy;
 wire [15:0] margin;wire [3:0] action,reason;wire [255:0] mask;wire [2047:0] preview;
 gesture_gray_pipeline #(.TIMEOUT_CYCLES(100000)) dut(clk,cam,reset_n,enable,control,cancel,ready,
  fs,fg,fb,pw,address,pixel,rv,accepted,cls,energy,margin,tracking,stable,av,action,busy,mask,preview,reason,,,);
 reg [15:0] images[0:565247],ids[0:3];reg [7:0] grays[0:565247];reg [31:0] scores[0:2207];
 integer results=0,actions=0,expected=0,sum=0;integer best,runner;reg signed [32:0] gap;
 always @(posedge clk)if(av&&ready)begin actions=actions+1;if(!control)$fatal(1,"disabled control leaked");end
 task boundary(input good,input bad);
  begin @(negedge cam);fs=1;fg=good;fb=bad;@(negedge cam);fs=0;fg=0;fb=0;end
 endtask
 task frame(input integer id);
  integer x,y,k;
  begin expected=id;boundary(0,0);
   for(integer p=0;p<19200;p=p+1)begin
    @(negedge cam);pw=1;address=p;pixel=16'hffff;x=p%160;y=p/160;
    if(x>=32&&x<128&&y>=12&&y<108)begin k=((y-12)/3)*32+(x-32)/3;pixel=images[id*1024+k];end
   end
   @(negedge cam);pw=0;repeat(4)@(negedge cam);boundary(1,0);
   wait(rv);@(negedge clk);
   best=0;runner=1;
   for(integer c=1;c<4;c=c+1)if($signed(scores[id*4+c])>$signed(scores[id*4+best]))best=c;
   runner=best==0?1:0;
   for(integer c=0;c<4;c=c+1)if(c!=best&&$signed(scores[id*4+c])>$signed(scores[id*4+runner]))runner=c;
   gap=$signed(scores[id*4+best])-$signed(scores[id*4+runner]);
   if(cls!==best||accepted!==(best<3&&gap>=2048)||margin!==(gap>65535?16'hffff:gap[15:0]))$fatal(1,"class/margin/accepted");
   if(dut.s0!==scores[id*4]||dut.s1!==scores[id*4+1]||dut.s2!==scores[id*4+2]||dut.s3!==scores[id*4+3])$fatal(1,"gray pipeline scores");
   sum=0;for(integer q=0;q<1024;q=q+1)sum=sum+grays[id*1024+q];
   if(energy!==(sum>>10))$fatal(1,"gray mean");
   for(integer q=0;q<256;q=q+1)begin k=(2*(q/16)+1)*32+2*(q%16)+1;
    if(preview[q*8+:8]!==grays[id*1024+k])$fatal(1,"gray preview mismatch");
    if(mask[q]!==((grays[id*1024+k]+8)<(sum>>10)))$fatal(1,"position-only mask mismatch");
   end
   if(reason!==(best==3?4'd5:4'd0))$fatal(1,"other reason");
   results=results+1;repeat(8)@(negedge clk);wait(!dut.mail_busy);
  end
 endtask
 initial begin
  $readmemh("tmp/gray_cnn_vectors/rgb565.mem",images);$readmemh("tmp/gray_cnn_vectors/gray.mem",grays);
  $readmemh("tmp/gray_cnn_vectors/scores.mem",scores);$readmemh("tmp/gray_cnn_vectors/ids.mem",ids);
  repeat(5)@(negedge clk);reset_n=1;repeat(12)@(negedge cam);
  repeat(4)frame(ids[1]);if(!tracking||stable!=1||actions)$fatal(1,"display only");
  control=1;repeat(4)frame(ids[1]);if(actions)$fatal(1,"arming replayed palm");
  repeat(3)frame(ids[3]);if(tracking||actions)$fatal(1,"OTHER not rejected");
  repeat(3)frame(ids[0]);if(actions!=1||action!=3)$fatal(1,"fist command");
  repeat(4)frame(ids[1]);if(actions!=2||action!=2)$fatal(1,"palm command");
  cancel=1;@(negedge clk);cancel=0;repeat(4)frame(ids[1]);if(actions!=2)$fatal(1,"manual cancel held palm");
  repeat(4)frame(ids[2]);if(actions!=3||action!=4)$fatal(1,"V command");
  run=0;repeat(100020)@(negedge clk);if(tracking||av)$fatal(1,"stopped PCLK timeout");
  reset_n=0;repeat(5)@(negedge clk);reset_n=1;run=1;enable=0;repeat(12)@(negedge cam);
  $display("PASS gray pipeline: %0d exact RGB565/CDC/CNN results, 4-class margins, true gray preview, position mask, opt-in commands, OTHER/rearm/manual priority and stopped-clock timeout",results);$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
