// Whole-frame gray illumination/contrast normalization, matched by gray_adapt.py.
// Two-by-two corner maxima estimate white background; global min estimates black.
// Span >=32 bounds gain on flat/noisy frames. Preserve grayscale, never binarize.
module gesture_gray_adapt(
 input wire clk,reset_n,input_write,input wire [9:0] input_index,
 input wire [7:0] input_value,input wire input_start,
 output reg feature_write,output reg [9:0] feature_index,
 output reg [7:0] feature_value,output reg start
);
 reg [7:0] samples[0:1023] /* synthesis syn_ramstyle="block_ram" */;
 reg [15:0] reciprocal[0:255] /* synthesis syn_ramstyle="distributed_ram" */;
 integer k;initial for(k=0;k<256;k=k+1)reciprocal[k]=65535/(k<32?32:k);
 reg [7:0] tl,tr,bl,br,black,q,background,darkness;
 reg [12:0] left,right;reg [17:0] plane;
 reg [15:0] gain;reg [23:0] product;
 reg [9:0] index;reg [3:0] state;
 wire [5:0] dx=6'd32-{1'b0,index[4:0]},dy=6'd32-{1'b0,index[9:5]};
 wire [7:0] span=background>black&&background-black>=32?background-black:8'd32;
 always @(posedge clk)begin
  if(input_write&&state==0)samples[input_index]<=input_value;
  q<=samples[index];
  if(!reset_n)begin state<=0;index<=0;feature_write<=0;feature_index<=0;feature_value<=0;start<=0;
   tl<=0;tr<=0;bl<=0;br<=0;black<=255;left<=0;right<=0;plane<=0;background<=0;darkness<=0;gain<=0;product<=0;end
  else begin
   feature_write<=0;start<=0;
   if(input_write&&state==0)begin
    if(input_index==0)begin tl<=input_value;tr<=0;bl<=0;br<=0;black<=input_value;end
    else begin
     if(input_value<black)black<=input_value;
     if(input_index[9:5]<2&&input_index[4:0]<2&&input_value>tl)tl<=input_value;
     if(input_index[9:5]<2&&input_index[4:0]>=30&&input_value>tr)tr<=input_value;
     if(input_index[9:5]>=30&&input_index[4:0]<2&&input_value>bl)bl<=input_value;
     if(input_index[9:5]>=30&&input_index[4:0]>=30&&input_value>br)br<=input_value;
    end
   end
   case(state)
    0:if(input_start)begin index<=0;state<=1;end
    1:state<=2;
    2:begin left<=tl*dy+bl*{1'b0,index[9:5]};right<=tr*dy+br*{1'b0,index[9:5]};state<=3;end
    3:begin plane<=(left>>5)*dx+(right>>5)*{1'b0,index[4:0]};state<=4;end
    4:begin background<=plane>>5;state<=5;end
    5:begin darkness<=background>q?background-q:8'd0;gain<=reciprocal[span];state<=6;end
    6:begin product<=darkness*gain;state<=7;end
    7:begin feature_write<=1;feature_index<=index;feature_value<=product[23:8]>=255?8'd0:8'd255-product[15:8];
      if(index==1023)state<=8;else begin index<=index+1'b1;state<=1;end end
    8:begin start<=1;state<=0;end
    default:state<=0;
   endcase
  end
 end
endmodule
