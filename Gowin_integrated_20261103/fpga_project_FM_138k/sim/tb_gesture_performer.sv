`timescale 1ns/1ps
module tb_gesture_performer;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,enable=1,track_enable=1,av=0,iv=0;
 reg [3:0] action=0;reg [31:0] idata=0;
 wire ir,pv,pr,restart,busy,cancel;wire [31:0] pd,od,status;
 wire [6:0] pb,ob;wire ov;wire [1:0] mode;
 reg base_arp=0;reg [7:0] cycle=0;
 always @(posedge clk)cycle<=cycle+1'b1;
 wire ready=cycle[2:0]!=0&&cycle[2:0]!=1;
 wire [159:0] cfg={32'd1200,32'd1200,32'd1600,32'd1600,(mode==2?32'h41:{31'd0,base_arp})};
 gesture_performer dut(.clk(clk),.reset_n(reset_n),.enable(enable),.track_enable(track_enable),
  .action_valid(av),.action(action),.action_ready(),.arp_enabled(status[1]==cfg[0]),
  .in_data(idata),.in_brightness(idata[6:0]),.in_valid(iv),.in_ready(ir),
  .out_data(pd),.out_brightness(pb),.out_valid(pv),.out_ready(pr),
  .mode(mode),.busy(busy),.cancel(cancel),.restart_arp(restart));
 midi_arpeggiator #(.CLOCKS_PER_US(1),.LIVE_PART_SUPPORT(1)) arp(
  .clk(clk),.reset_n(reset_n),.live_part(mode==2),.config_data(cfg),.suspend(1'b0),.sequence_mode(1'b0),
  .sync_step(1'b0),.sync_restart(restart),.external_sync(1'b0),
  .in_data(pd),.in_brightness(pb),.in_valid(pv),.in_ready(pr),
  .out_data(od),.out_brightness(ob),.out_valid(ov),.out_ready(ready),.status(status),.chord_notes());
 reg [127:0] keys=0,sounding=0;reg pedal=0;
 integer ons=0,arpons=0;reg [6:0] seq[0:63];
 reg stalled=0;reg [31:0] stalled_word;
 always @(posedge clk)begin
  if(!reset_n)begin keys<=0;sounding<=0;pedal<=0;ons<=0;arpons<=0;stalled<=0;end
  else begin
   if(stalled&&(!ov||od!==stalled_word))$fatal(1,"ARP changed stalled event");
   stalled<=ov&&!ready;stalled_word<=od;
   if(ov&&ready)begin
    if(od[23:20]==9&&od[6:0]!=0)begin
     ons<=ons+1;
     if(od[31:24]==8'h88)begin seq[arpons%64]<=od[14:8];arpons<=arpons+1;end
     if(!od[30])begin keys[od[14:8]]<=1;sounding[od[14:8]]<=1;end
    end else if(od[23:20]==8||(od[23:20]==9&&od[6:0]==0))begin
     if(!od[30])begin keys[od[14:8]]<=0;if(!pedal)sounding[od[14:8]]<=0;end
    end else if(od[23:20]==11&&!od[30])begin
     if(od[14:8]==64)begin pedal<=od[6];if(!od[6])sounding<=keys;end
     if(od[14:8]==123||od[14:8]==120)begin keys<=0;sounding<=0;end
    end
   end
  end
 end
 task send(input [31:0] word);
  begin @(negedge clk);idata=word;iv=1;do @(posedge clk);while(!ir);@(negedge clk);iv=0;repeat(10)@(negedge clk);end
 endtask
 task pose(input [3:0] a);
  begin @(negedge clk);action=a;av=1;@(negedge clk);av=0;end
 endtask
 task settled;begin wait(!busy);repeat(100)@(negedge clk);end endtask
 reg [127:0] chord;integer n;
 initial begin
  chord=(128'd1<<60)|(128'd1<<64)|(128'd1<<67);
  repeat(5)@(negedge clk);reset_n=1;
  send(32'h00903c50);send(32'h00904060);send(32'h00904370);
  if(sounding!==chord||ons!=3)$fatal(1,"Normal chord lost");
  pose(3);wait(mode==1);settled();
  if(sounding!==chord||ons!=3)$fatal(1,"Chop retriggered notes");
  repeat(1000)@(negedge clk);if(mode!=1)$fatal(1,"No-action/UNKNOWN changed mode");
  pose(4);wait(mode==2);settled();wait(arpons>=6);@(negedge clk);
  if(seq[0]!=60||seq[1]!=64||seq[2]!=67||seq[3]!=72||seq[4]!=76||seq[5]!=79)
   $fatal(1,"Cross-octave sequence incorrect: %d %d %d %d %d %d",seq[0],seq[1],seq[2],seq[3],seq[4],seq[5]);
  if(!arp.owner_live)$fatal(1,"Gesture ARP uses wrong patch part");
  pose(2);wait(mode==0);settled();
  if(sounding!==chord||status[1])$fatal(1,"Palm did not restore held chord %h",sounding);
  send(32'h00b0407f);send(32'h00803c00);send(32'h00804000);send(32'h00804300);
  pose(4);wait(mode==2);settled();repeat(2500)@(negedge clk);
  pose(2);wait(mode==0);settled();
  if(sounding!==chord||!pedal||keys!=0)$fatal(1,"Pedal-held chord replay incorrect");
  send(32'h00b04000);if(sounding!=0)$fatal(1,"Pedal release stuck notes");
  send(32'h00903c50);pose(4);wait(mode==2);settled();
  enable=0;wait(mode==0);settled();
  if(sounding!==(128'd1<<60))$fatal(1,"Control OFF lost physical key");
  enable=1;pose(4);wait(mode==2);settled();
  base_arp=1;track_enable=0;enable=0;wait(mode==0);settled();
  if(arp.owner_live)$fatal(1,"Manual ARP inherited gesture part");
  base_arp=0;repeat(200)@(negedge clk);send(32'h00b07b00);settled();
  if(sounding!=0)$fatal(1,"Cleanup stuck notes");
  $display("PASS gesture performer: normal/chop/6-note LIVE arpeggio, UNKNOWN retention, held/pedal restoration, control-off, manual ARP handoff, backpressure");$finish;
 end
 initial begin #10000000;$fatal(1,"Gesture performer timeout state=%d mode=%d enabled=%d",dut.state,mode,status[1]);end
endmodule
