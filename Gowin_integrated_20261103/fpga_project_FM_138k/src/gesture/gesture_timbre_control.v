// Gesture timbre selection and smooth LIVE-only expression. No MIDI events
// are generated. Switching waits for LIVE voices to retire, including tails;
// BACKING activity never delays a change. Invalid frames keep last targets.
module gesture_timbre_control(
 input wire clk,reset_n,sample_tick,enable,
 input wire [31:0] position_packet,input wire live_busy,loader_ready,loader_busy,
 input wire [6:0] current_preset,
 output reg preset_valid,output reg [6:0] preset,
 output wire expression_enable,output reg [6:0] brightness,vibrato,
 output wire [31:0] status
);
 reg seen,was_enabled;reg [1:0] requested_class;
 reg wanted_valid;reg [6:0] target_x,target_y;reg [3:0] smooth_tick;
 reg [1:0] state;reg [6:0] loading_preset;
 wire frame_changed=position_packet[15]&&position_packet[31]!=seen;
 wire [6:0] desired=requested_class==0?7'd0:requested_class==1?7'd44:7'd85;
 wire pending=wanted_valid&&(current_preset!=desired);
 assign expression_enable=enable&&wanted_valid&&state==0&&!loader_busy;
 assign status={7'd0,enable,5'd0,state!=0,pending,wanted_valid,1'b0,vibrato,1'b0,brightness};
 always @(posedge clk)begin
  if(!reset_n)begin seen<=0;was_enabled<=0;requested_class<=1;wanted_valid<=0;
   target_x<=64;target_y<=0;brightness<=64;vibrato<=0;smooth_tick<=0;
   state<=0;loading_preset<=0;preset_valid<=0;preset<=0;end
  else begin
   preset_valid<=0;was_enabled<=enable;
   if(!enable)begin wanted_valid<=0;seen<=position_packet[31];end
   else if(frame_changed||(!was_enabled&&position_packet[15]))begin
    seen<=position_packet[31];requested_class<=position_packet[17:16];wanted_valid<=1;
    // Two-LSB dead band prevents tiny centroid noise from chasing a target.
    if({1'b0,position_packet[6:0]}+8'd2<{1'b0,target_x}||{1'b0,target_x}+8'd2<{1'b0,position_packet[6:0]})target_x<=position_packet[6:0];
    if({1'b0,position_packet[14:8]}+8'd2<{1'b0,target_y}||{1'b0,target_y}+8'd2<{1'b0,position_packet[14:8]})target_y<=position_packet[14:8];
   end
   if(sample_tick)begin
    smooth_tick<=smooth_tick+1'b1;
    if(smooth_tick==0)begin
     if(brightness<target_x)brightness<=brightness+1'b1;else if(brightness>target_x)brightness<=brightness-1'b1;
     if(vibrato<(target_y>>1))vibrato<=vibrato+1'b1;else if(vibrato>(target_y>>1))vibrato<=vibrato-1'b1;
    end
   end
   case(state)
    0:if(enable&&pending&&!live_busy&&loader_ready)begin
     preset<=desired;loading_preset<=desired;preset_valid<=1;state<=1;end
    1:if(loader_busy)state<=2;
    2:if(!loader_busy)state<=0;
    default:state<=0;
   endcase
  end
 end
endmodule
