// Quantized CNN: conv3/stride2 x4, ReLU127, maxpool3, dense100x4.
// One signed MAC. Input is real u8 gray; there is no binary segmentation.
module gesture_gray_cnn #(
 parameter WEIGHTS="src/generated/gesture_gray/weights.mem",
 parameter BIASES="src/generated/gesture_gray/biases.mem"
)(
 input wire clk,reset_n,feature_write,input wire [9:0] feature_index,
 input wire [7:0] feature_value,input wire start,
 output reg busy,done,output reg [1:0] class_id,
 output reg signed [31:0] score0,score1,score2,score3,
 output reg [15:0] cycles
);
 reg [7:0] image[0:1023] /* synthesis syn_ramstyle="block_ram" */;
 reg signed [7:0] weights[0:435] /* synthesis syn_ramstyle="block_ram" */;
 reg signed [31:0] biases[0:7];reg [6:0] pooled[0:99];
 initial begin $readmemh(WEIGHTS,weights);$readmemh(BIASES,biases);end
 reg [3:0] state;
 localparam IDLE=0,INIT=1,LOAD=2,MAC=3,CONV=4,STORE=5,DENSE=6,SCORE=7,FINISH=8;
 reg [1:0] channel,output_id;reg [2:0] px,py,ix,iy,kx,ky;
 reg [3:0] term;reg [6:0] dense_index,hidden_index,max_value;
 reg signed [31:0] acc,best;reg signed [7:0] weight;
 reg [8:0] operand;
 wire signed [17:0] product=$signed({1'b0,operand})*$signed(weight);
 wire [4:0] row=({2'd0,py}*5'd3+{2'd0,iy})*5'd2+{2'd0,ky};
 wire [4:0] col=({2'd0,px}*5'd3+{2'd0,ix})*5'd2+{2'd0,kx};
 wire [8:0] wa=channel*9'd9+{5'd0,term};
 wire [8:0] da=9'd36+output_id*9'd100+{2'd0,dense_index};
 wire [6:0] clipped=acc<0?7'd0:(acc>>>7)>127?7'd127:acc[13:7];
 always @(posedge clk)begin
  if(feature_write&&!busy)image[feature_index]<=feature_value;
  if(!reset_n)begin state<=IDLE;busy<=0;done<=0;class_id<=0;score0<=0;score1<=0;score2<=0;score3<=0;cycles<=0;
   channel<=0;output_id<=0;px<=0;py<=0;ix<=0;iy<=0;kx<=0;ky<=0;term<=0;
   dense_index<=0;hidden_index<=0;max_value<=0;acc<=0;best<=0;operand<=0;weight<=0;
  end else begin
   done<=0;if(busy)cycles<=cycles+1'b1;
   case(state)
    IDLE:if(start)begin busy<=1;cycles<=0;channel<=0;px<=0;py<=0;ix<=0;iy<=0;hidden_index<=0;max_value<=0;state<=INIT;end
    INIT:begin acc<=biases[channel];term<=0;kx<=0;ky<=0;state<=LOAD;end
    LOAD:begin weight<=weights[wa];operand<={1'b0,image[{row,col}]};state<=MAC;end
    MAC:begin acc<=acc+product;
     if(term==8)state<=CONV;else begin term<=term+1'b1;if(kx==2)begin kx<=0;ky<=ky+1'b1;end else kx<=kx+1'b1;state<=LOAD;end
    end
    CONV:begin
     if(clipped>max_value)max_value<=clipped;
     if(ix==2&&iy==2)state<=STORE;
     else begin if(ix==2)begin ix<=0;iy<=iy+1'b1;end else ix<=ix+1'b1;state<=INIT;end
    end
    STORE:begin pooled[hidden_index]<=max_value;max_value<=0;ix<=0;iy<=0;
     if(hidden_index==99)begin output_id<=0;dense_index<=0;state<=DENSE;end
     else begin hidden_index<=hidden_index+1'b1;
      if(px==4)begin px<=0;if(py==4)begin py<=0;channel<=channel+1'b1;end else py<=py+1'b1;end else px<=px+1'b1;
      state<=INIT;
     end
    end
    DENSE:begin acc<=biases[4+output_id];dense_index<=0;state<=9;end
    9:begin weight<=weights[da];operand<={2'd0,pooled[dense_index]};state<=10;end
    10:begin acc<=acc+product;
     if(dense_index==99)state<=SCORE;else begin dense_index<=dense_index+1'b1;state<=9;end
    end
    SCORE:begin
     case(output_id)0:score0<=acc;1:score1<=acc;2:score2<=acc;3:score3<=acc;endcase
     if(output_id==0||acc>best)begin best<=acc;class_id<=output_id;end
     if(output_id==3)state<=FINISH;else begin output_id<=output_id+1'b1;state<=DENSE;end
    end
    FINISH:begin busy<=0;done<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
