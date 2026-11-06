// Validated 160x120 stream -> central96x96 -> 32x32 cell-center samples.
// RGB565 input preserves grayscale precision before RGB332 preview reduction.
// frame_good/start may coincide. Incomplete/busy/bad frames never publish.
module gesture_gray_roi(
 input wire clk,reset_n,enable,frame_start,frame_good,frame_bad,
 input wire pixel_write,input wire [14:0] pixel_address,
 input wire [15:0] pixel_rgb565,input wire busy,
 output reg sample_write,output reg [9:0] sample_index,
 output reg [7:0] sample_value,output reg publish,
 output reg [17:0] frame_sum
);
 wire [7:0] r={pixel_rgb565[15:11],pixel_rgb565[15:13]};
 wire [7:0] g={pixel_rgb565[10:5],pixel_rgb565[10:9]};
 wire [7:0] b={pixel_rgb565[4:0],pixel_rgb565[4:2]};
 wire [9:0] weighted={2'd0,r}+{1'd0,g,1'b0}+{2'd0,b}+10'd2;
 reg collecting;reg [10:0] count;reg [14:0] target;reg [17:0] sum;
 wire complete=enable&&collecting&&frame_good&&!frame_bad&&count==1024&&!busy;
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin collecting<=0;count<=0;target<=2113;sum<=0;
   sample_write<=0;sample_index<=0;sample_value<=0;publish<=0;frame_sum<=0;end
  else begin
   sample_write<=0;publish<=0;
   if(!enable)begin collecting<=0;count<=0;sum<=0;end
   else begin
    if(complete)begin publish<=1;frame_sum<=sum;end
    if(frame_start)begin collecting<=!busy&&!complete;count<=0;target<=2113;sum<=0;end
    else if(frame_bad)collecting<=0;
    else if(collecting&&busy)collecting<=0;
    else if(collecting&&pixel_write&&count<1024)begin
     if(pixel_address==target)begin
      sample_write<=1;sample_index<=count[9:0];sample_value<=weighted[9:2];
      sum<=sum+{10'd0,weighted[9:2]};count<=count+1'b1;
      target<=target+(count[4:0]==31?15'd387:15'd3);
     end else if(pixel_address>target)collecting<=0;
    end
   end
  end
 end
endmodule
