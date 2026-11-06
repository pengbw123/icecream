// Single 1024x8 dual-clock bank. A published frame is immutable until done.
// Consumer gets an ordered stream followed by frame_valid; done must occur
// AFTER frame_valid. This intentionally allows CNN work to hold the bank.
module gesture_gray_mailbox(
 input wire source_clk,clk,reset_n,
 input wire sample_write,input wire [9:0] sample_index,
 input wire [7:0] sample_value,input wire publish,input wire [17:0] frame_sum,
 output wire busy,
 output reg feature_write,output reg [9:0] feature_index,
 output reg [7:0] feature_value,output reg frame_valid,
 output reg [17:0] feature_sum,input wire done
);
 reg [7:0] memory[0:1023] /* synthesis syn_ramstyle="block_ram" */;
 reg request,ack;reg [17:0] held_sum;
 reg [1:0] ack_sync,request_sync;reg [2:0] sr,mr;
 always @(posedge source_clk or negedge reset_n)
  if(!reset_n)sr<=0;else sr<={sr[1:0],1'b1};
 always @(posedge clk or negedge reset_n)
  if(!reset_n)mr<=0;else mr<={mr[1:0],1'b1};
 assign busy=!sr[2]||request!=ack_sync[1];
 always @(posedge source_clk)if(sr[2]&&sample_write&&!busy)memory[sample_index]<=sample_value;
 always @(posedge source_clk or negedge reset_n)begin
  if(!reset_n)begin request<=0;ack_sync<=0;held_sum<=0;end
  else if(!sr[2])begin request<=0;ack_sync<=0;held_sum<=0;end
  else begin ack_sync<={ack_sync[0],ack};
   if(publish&&!busy)begin held_sum<=frame_sum;request<=!request;end
  end
 end
 localparam IDLE=0,READ=1,SEND=2,VALID=3,WAIT=4;
 reg [2:0] state;reg [9:0] index;reg [7:0] q;
 always @(posedge clk)q<=memory[index];
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin ack<=0;request_sync<=0;state<=IDLE;index<=0;
   feature_write<=0;feature_index<=0;feature_value<=0;frame_valid<=0;feature_sum<=0;end
  else if(!mr[2])begin ack<=0;request_sync<=0;state<=IDLE;index<=0;
   feature_write<=0;feature_index<=0;feature_value<=0;frame_valid<=0;feature_sum<=0;end
  else begin request_sync<={request_sync[0],request};feature_write<=0;frame_valid<=0;
   case(state)
    IDLE:if(request_sync[1]!=ack)begin index<=0;feature_sum<=held_sum;state<=READ;end
    READ:state<=SEND;
    SEND:begin feature_write<=1;feature_index<=index;feature_value<=q;
     if(index==1023)state<=VALID;else begin index<=index+1'b1;state<=READ;end
    end
    VALID:begin frame_valid<=1;state<=WAIT;end
    WAIT:if(done)begin ack<=request_sync[1];state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
