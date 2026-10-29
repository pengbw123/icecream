// Divide-free 16x16 foreground centroid with three zones and hysteresis.
// Only accepted stable palms may update targets. Invalid frames hold values.
module gesture_position(
 input wire clk,reset_n,enable,cancel,sample_valid,
 input wire [255:0] mask,
 output wire valid,output wire [3:0] action,input wire ready
);
 reg busy;reg [255:0] held;reg [7:0] index;
 reg [8:0] count;reg [11:0] sx,sy;
 reg [1:0] xzone,yzone,sentx,senty;
 wire [11:0] c5={count,2'b00}+count;
 wire [11:0] c6={count,2'b00}+{count,1'b0};
 wire [11:0] c7={count,3'b000}-count;
 wire [11:0] c8={count,3'b000};
 wire [11:0] c9={count,3'b000}+count;
 wire [11:0] c10={count,3'b000}+{count,1'b0};
 function [1:0] zone(input [11:0] sum,input [1:0] old,
 input [11:0] a,b,c,d,e,f);
 begin
  if(old==0)zone=sum>f?2:sum>c?1:0;
  else if(old==2)zone=sum<a?0:sum<d?1:2;
  else zone=sum<b?0:sum>e?2:1;
 end endfunction
 assign valid=enable&&((xzone!=sentx)||(yzone!=senty));
 assign action=xzone!=sentx?4'd8+{2'd0,xzone}:4'd11+{2'd0,yzone};
 always @(posedge clk)begin
  if(!reset_n||!enable)begin busy<=0;held<=0;index<=0;count<=0;sx<=0;sy<=0;
   xzone<=1;yzone<=1;sentx<=1;senty<=1;end
  else begin
   if(valid&&ready)begin if(xzone!=sentx)sentx<=xzone;else senty<=yzone;end
   if(!busy&&sample_valid)begin held<=mask;index<=0;count<=0;sx<=0;sy<=0;busy<=1;end
   else if(busy)begin
    if(held[index])begin count<=count+1'b1;sx<=sx+{8'd0,index[3:0]};sy<=sy+{8'd0,index[7:4]};end
    if(index==255)begin busy<=0;
     // Last sample is at the ROI corner, normally background. Include it
     // explicitly to keep the arithmetic correct for every possible mask.
     xzone<=zone(sx+(held[255]?12'd15:12'd0),xzone,
      c5+(held[255]?5:0),c6+(held[255]?6:0),c7+(held[255]?7:0),
      c8+(held[255]?8:0),c9+(held[255]?9:0),c10+(held[255]?10:0));
     yzone<=zone(sy+(held[255]?12'd15:12'd0),yzone,
      c5+(held[255]?5:0),c6+(held[255]?6:0),c7+(held[255]?7:0),
      c8+(held[255]?8:0),c9+(held[255]?9:0),c10+(held[255]?10:0));
    end else index<=index+1'b1;
   end
   if(cancel)begin busy<=0;sentx<=xzone;senty<=yzone;xzone<=xzone;yzone<=yzone;end
  end
 end
endmodule
