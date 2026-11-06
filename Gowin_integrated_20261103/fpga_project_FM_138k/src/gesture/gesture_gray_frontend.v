// Experimental CNN input interface, not connected to production classifier.
// Enable is synchronized into PCLK. Disabling drops acquisition but drains
// any published job: consumers must still complete it, or reset both domains.
module gesture_gray_frontend(
 input wire clk,camera_clk,reset_n,enable,
 input wire frame_start,frame_good,frame_bad,pixel_write,
 input wire [14:0] pixel_address,input wire [15:0] pixel_rgb565,
 output wire busy,feature_write,frame_valid,
 output wire [9:0] feature_index,output wire [7:0] feature_value,
 output wire [17:0] feature_sum,input wire done
);
 reg [2:0] es;
 always @(posedge camera_clk or negedge reset_n)
  if(!reset_n)es<=0;else es<={es[1:0],enable};
 wire sw,publish;wire [9:0] si;wire [7:0] sv;wire [17:0] sum;
 gesture_gray_roi roi(camera_clk,reset_n,es[2],frame_start,frame_good,frame_bad,
  pixel_write,pixel_address,pixel_rgb565,busy,sw,si,sv,publish,sum);
 gesture_gray_mailbox mailbox(camera_clk,clk,reset_n,sw,si,sv,publish,sum,busy,
  feature_write,feature_index,feature_value,frame_valid,feature_sum,done);
endmodule
