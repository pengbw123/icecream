// Diagnostic-only gray preview. Two RAM banks replace thousands of reset FFs.
// A published bank is immutable until HDMI selects it at vertical blank.
// While waiting for that acknowledgement new diagnostic frames are skipped;
// camera capture and CNN inference never wait for the monitor.
module gesture_gray_preview(
 input wire clk,pixel_clk,reset_n,sample_write,
 input wire [9:0] sample_index,input wire [7:0] sample_value,
 input wire result_valid,frame_latch,input wire [7:0] read_address,
 output reg [7:0] read_data,output reg valid
);
 reg [7:0] memory[0:511] /* synthesis syn_ramstyle="block_ram" */;
 reg request,ack,collecting;reg [8:0] count;
 reg [1:0] ack_sync,request_sync;
 wire available=ack_sync[1]==request;
 // First feature starts a complete frame; never start halfway through one.
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin request<=0;ack_sync<=0;collecting<=0;count<=0;end
  else begin
   ack_sync<={ack_sync[0],ack};
   if(sample_write&&sample_index==0)begin collecting<=available;count<=0;end
   if(sample_write&&collecting&&sample_index[5]&&sample_index[0])count<=count+1'b1;
   if(result_valid)begin
    if(collecting&&count==256)request<=!request;
    collecting<=0;
   end
  end
 end
 // Unreset RAM write/read processes infer a true dual-clock block RAM.
 always @(posedge clk)
  if(reset_n&&sample_write&&collecting&&sample_index[5]&&sample_index[0])
   memory[{!request,sample_index[9:6],sample_index[4:1]}]<=sample_value;
 reg bank;
 always @(posedge pixel_clk or negedge reset_n)begin
  if(!reset_n)begin request_sync<=0;ack<=0;bank<=0;valid<=0;end
  else begin
   request_sync<={request_sync[0],request};
   if(frame_latch&&request_sync[1]!=ack)begin
    bank<=request_sync[1];ack<=request_sync[1];valid<=1;
   end
  end
 end
 always @(posedge pixel_clk)read_data<=memory[{bank,read_address}];
endmodule
