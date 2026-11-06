// Accepted-frame centroid, Q3 pixel coordinates. Sequential long division
// avoids a combinational divider and consumes no frame or block RAM.
module gesture_centroid(
 input wire clk,reset_n,enable,sample_valid,input wire [255:0] mask,
 input wire [1:0] class_id,output reg [31:0] packet
);
 reg [1:0] state,held_class;reg [255:0] held;
 reg [7:0] index;reg [8:0] count;reg [11:0] sx,sy;
 reg [8:0] divisor;reg [14:0] nx,ny,qx,qy;
 reg [9:0] rx,ry;reg [3:0] bit_index;
 wire [9:0] tx={rx[8:0],nx[14]},ty={ry[8:0],ny[14]};
 wire [14:0] next_qx={qx[13:0],tx>={1'b0,divisor}};
 wire [14:0] next_qy={qy[13:0],ty>={1'b0,divisor}};
 wire signed [8:0] surface_x=$signed({1'b0,next_qx[6:0],1'b0})-9'sd56;
 wire signed [8:0] surface_y=9'sd182-$signed({1'b0,next_qy[6:0],1'b0});
 wire [6:0] clamped_x=surface_x<0?7'd0:surface_x>127?7'd127:surface_x[6:0];
 wire [6:0] clamped_y=surface_y<0?7'd0:surface_y>127?7'd127:surface_y[6:0];
 wire [8:0] total=count+held[255];
 wire [11:0] total_x=sx+(held[255]?12'd15:12'd0);
 wire [11:0] total_y=sy+(held[255]?12'd15:12'd0);
 always @(posedge clk)begin
  if(!reset_n)begin state<=0;packet<=0;index<=0;held<=0;count<=0;sx<=0;sy<=0;
   divisor<=0;nx<=0;ny<=0;qx<=0;qy<=0;rx<=0;ry<=0;bit_index<=0;held_class<=0;end
  else if(!enable)begin state<=0;packet[15]<=0;end
  else case(state)
   0:if(sample_valid&&class_id<3)begin held<=mask;held_class<=class_id;index<=0;count<=0;sx<=0;sy<=0;state<=1;end
   1:begin
    if(index==255)begin
     if(total>=8&&total<=240)begin divisor<=total;nx<={total_x,3'b000};ny<={total_y,3'b000};
      qx<=0;qy<=0;rx<=0;ry<=0;bit_index<=14;state<=2;end
     else state<=0;
    end else begin
     if(held[index])begin count<=count+1'b1;sx<=sx+{8'd0,index[3:0]};sy<=sy+{8'd0,index[7:4]};end
     index<=index+1'b1;
    end
   end
   2:begin
    rx<=tx>={1'b0,divisor}?tx-{1'b0,divisor}:tx;
    ry<=ty>={1'b0,divisor}?ty-{1'b0,divisor}:ty;
    nx<={nx[13:0],1'b0};ny<={ny[13:0],1'b0};qx<=next_qx;qy<=next_qy;
    if(bit_index==0)begin
     // x: left=0/right=127, y: bottom=0/top=127; centred pixel bins.
     packet<={~packet[31],13'd0,held_class,1'b1,clamped_y,1'b0,clamped_x};
     state<=0;
    end else bit_index<=bit_index-1'b1;
   end
   default:state<=0;
  endcase
 end
endmodule
