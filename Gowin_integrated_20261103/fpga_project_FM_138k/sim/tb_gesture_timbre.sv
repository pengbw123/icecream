`timescale 1ns/1ps
module tb_gesture_timbre;
 reg clk=0;always #10 clk=~clk;
 reg reset_n=0,enable=0,sample_valid=0;reg [255:0] mask=0;reg [1:0] cls=1;
 wire [31:0] packet;reg live_busy=0,loader_ready=1,loader_busy=0;reg [6:0] current=0;
 wire preset_valid,expression;wire [6:0] preset,b,v;wire [31:0] status;
 reg [31:0] injected;reg use_injected=0;wire [31:0] input_packet=use_injected?injected:packet;
 gesture_centroid pos(clk,reset_n,enable,sample_valid,mask,cls,packet);
 gesture_timbre_control dut(clk,reset_n,1'b1,enable,input_packet,live_busy,loader_ready,loader_busy,current,preset_valid,preset,expression,b,v,status);
 task centroid(input integer x,y,input integer c);
  reg old;begin old=packet[31];mask=0;cls=c;
   for(integer j=0;j<4;j++)for(integer i=0;i<4;i++)mask[(y+j)*16+x+i]=1;
   @(negedge clk);sample_valid=1;@(negedge clk);sample_valid=0;
   wait(packet[31]!=old);@(negedge clk);
  end endtask
 task load(input integer expected);
  begin wait(preset_valid);if(preset!=expected)$fatal(1,"wrong patch %d expected %d",preset,expected);
   @(negedge clk);loader_busy=1;current=preset;repeat(120)@(negedge clk);loader_busy=0;
   repeat(4)@(negedge clk);end
 endtask
 integer bx,vy;
 initial begin
  repeat(4)@(negedge clk);reset_n=1;enable=1;loader_ready=0;
  centroid(0,0,1);if(packet[6:0]!=0||packet[14:8]!=127)$fatal(1,"top-left map %h",packet);
  centroid(12,12,1);if(packet[6:0]!=127||packet[14:8]!=0)$fatal(1,"bottom-right map %h",packet);
  // Invalid/empty foreground must not publish a fake coordinate or class.
  injected=packet;mask=0;sample_valid=1;@(negedge clk);sample_valid=0;repeat(300)@(negedge clk);
  if(packet!==injected)$fatal(1,"empty mask published");
  centroid(6,6,1);live_busy=1;loader_ready=1;repeat(30)@(negedge clk);
  if(preset_valid||!status[17])$fatal(1,"changed held/tail voices");
  live_busy=0;load(44);repeat(2200)@(negedge clk);
  if(!expression||b<60||b>67||v<28||v>34)$fatal(1,"smoothing/center %d %d",b,v);
  // Same pose never reloads, including across multiple coordinate updates.
  loader_ready=0;centroid(10,0,1);repeat(2200)@(negedge clk);
  if(b!=127||v!=63)$fatal(1,"smooth endpoint %d %d",b,v);
  if(status[17])$fatal(1,"same pose reloaded");
  bx=b;vy=v;mask=0;repeat(100)@(negedge clk);if(b!=bx||v!=vy)$fatal(1,"unknown did not hold");
  centroid(6,6,0);loader_ready=1;load(0);
  centroid(6,6,2);load(85);
  enable=0;repeat(5)@(negedge clk);if(expression||preset_valid)$fatal(1,"disabled expression active");
  $display("PASS gesture timbre: all poses/coordinates, empty/unknown hold, LIVE-tail wait, no repeated load, smooth expression, disable");$finish;
 end
 initial begin #1000000;$fatal(1,"gesture unit timeout state=%d",dut.state);end
endmodule
