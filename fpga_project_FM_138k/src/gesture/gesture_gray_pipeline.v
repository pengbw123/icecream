// Full gray camera frontend -> CNN -> four-class margin gate -> vote/actions.
module gesture_gray_pipeline #(parameter integer TIMEOUT_CYCLES=50000000,VECTOR_PREVIEW=1,SELF_TEST=0)(
 input wire clk,camera_clk,reset_n,enable,control,cancel,ready,
 input wire frame_start,frame_good,frame_bad,pixel_write,
 input wire [14:0] pixel_address,input wire [15:0] pixel_rgb565,
 output reg result_valid,accepted,output reg [1:0] class_id,
 output reg [14:0] energy,output reg [15:0] margin,
 output wire tracking,output wire [1:0] stable_class,
 output wire action_valid,output wire [3:0] action,output wire busy,
 output reg [255:0] mask,output reg [2047:0] preview,output reg [3:0] reason,
 output wire sample_write,output wire [9:0] sample_index,output wire [7:0] sample_value
);
 wire fw,start,done,mail_busy;wire [9:0] fi;wire [7:0] fv;wire [17:0] sum;
 // Display the same normalized samples presented to the CNN, rather than
 // the earlier raw camera stream. The position mask still uses raw gray.
 // A runtime selector keeps the input RAM and datapath live in synthesis.
 // Diagnostic build: control OFF = white reference, ON = camera input.
 wire [7:0] cnn_value=(SELF_TEST&&!control)?8'hff:nv;
 assign sample_write=nw;assign sample_index=ni;assign sample_value=cnn_value;
 wire [1:0] cls;wire signed [31:0] s0,s1,s2,s3;wire [15:0] cycles;
 gesture_gray_frontend frontend(clk,camera_clk,reset_n,enable,frame_start,frame_good,frame_bad,
  pixel_write,pixel_address,pixel_rgb565,mail_busy,fw,start,fi,fv,sum,done);
 wire nw,ns;wire [9:0] ni;wire [7:0] nv;
 gesture_gray_adapt adapt(clk,reset_n,fw,fi,fv,start,nw,ni,nv,ns);
 gesture_gray_cnn cnn(clk,reset_n,nw,ni,cnn_value,ns,busy,done,cls,s0,s1,s2,s3,cycles);
 reg [255:0] assembling_mask;reg [2047:0] assembling_preview;
 wire [7:0] average=sum[17:10];
 wire [7:0] mi={fi[9:6],fi[4:1]};
 always @(posedge clk)begin
  if(!reset_n)begin assembling_mask<=0;assembling_preview<=0;end
  else if(fw&&fi[5]&&fi[0])begin
   assembling_mask[mi]<=({1'b0,fv}+9'd8)<{1'b0,average};
  end
  if(reset_n&&nw&&ni[5]&&ni[0]&&VECTOR_PREVIEW)
   assembling_preview[{{ni[9:6],ni[4:1]},3'b000}+:8]<=cnn_value;
 end
 reg [2:0] valid;
 reg signed [31:0] ab,abr,cd,cdr,top,runner;
 reg signed [32:0] difference;
 reg [1:0] c1,c2,c3;
 always @(posedge clk)begin
  if(!reset_n||!enable)begin
   valid<=0;result_valid<=0;accepted<=0;class_id<=0;energy<=0;margin<=0;mask<=0;preview<=0;reason<=0;
   ab<=0;abr<=0;cd<=0;cdr<=0;top<=0;runner<=0;difference<=0;c1<=0;c2<=0;c3<=0;
  end else begin
   valid<={valid[1:0],done};result_valid<=valid[2];
   if(done)begin ab<=s0>s1?s0:s1;abr<=s0>s1?s1:s0;cd<=s2>s3?s2:s3;cdr<=s2>s3?s3:s2;c1<=cls;end
   if(valid[0])begin
    top<=ab>cd?ab:cd;
    runner<=ab>cd?(abr>cd?abr:cd):(cdr>ab?cdr:ab);c2<=c1;
   end
   if(valid[1])begin difference<=$signed({top[31],top})-$signed({runner[31],runner});c3<=c2;end
   if(valid[2])begin
    accepted<=!SELF_TEST&&c3<3&&difference>=2048;class_id<=c3;
    margin<=difference>65535?16'hffff:difference[15:0];
    // Gray telemetry E is mean luminance, not binary foreground area.
    energy<={7'd0,average};mask<=assembling_mask;preview<=assembling_preview;reason<=c3==3?4'd5:4'd0;
   end
  end
 end
 wire event_valid;
 gesture_vote_events #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.CANCEL_ENABLED(1)) events(
  clk,reset_n,enable,result_valid,class_id,accepted,event_valid,control?ready:1'b1,action,tracking,stable_class,cancel);
 assign action_valid=event_valid&&control;
endmodule
