// Camera tap -> feature mailbox -> optional plane compensation -> NN/actions.
// clk is the stable 50MHz system clock; camera_clk may stop without hanging it.
// reset_n must include camera capture/config reset as well as main reset.
module gesture_pipeline #(
    parameter WEIGHTS="src/generated/gesture/weights.mem",
    parameter BIASES="src/generated/gesture/biases.mem",
    parameter integer TIMEOUT_CYCLES=50000000,
    parameter integer SILHOUETTE=1, CANCEL_ENABLED=0, NORMALIZE=0,TEMPORAL=0
)(
    input wire clk,camera_clk,reset_n,
    input wire recognition_enable,control_enable,
    input wire frame_start,frame_good,frame_bad,pixel_write,
    input wire [14:0] pixel_address,input wire [7:0] pixel_data,
    output wire result_valid,output wire [1:0] class_id,
    output wire signed [31:0] score0,score1,score2,
    output wire tracking,output wire [1:0] stable_class,
    output wire action_valid,input wire action_ready,output wire [3:0] action,
    output wire inference_busy,output wire [15:0] inference_cycles,
    input wire cancel,
    output wire [14:0] result_energy,
    output wire [15:0] result_margin,output wire result_accepted,
    output reg [255:0] input_mask,output wire [3:0] reject_reason
);
    reg [1:0] enable_sync;
    always @(posedge camera_clk or negedge reset_n)
        if(!reset_n)enable_sync<=0;else enable_sync<={enable_sync[0],recognition_enable};
    wire source_write,source_publish,source_busy,feature_write,start;
    wire [7:0] source_index,feature_index;
    wire [6:0] source_value,feature_value;
    wire [14:0] source_energy,feature_energy;
    wire raw_done;wire [1:0] raw_class;
    gesture_roi #(.SILHOUETTE(NORMALIZE?0:SILHOUETTE)) roi(camera_clk,reset_n,enable_sync[1],frame_start,frame_good,frame_bad,
        pixel_write,pixel_address,pixel_data,source_busy,source_write,source_index,
        source_value,source_publish,source_energy);
    gesture_mailbox mailbox(camera_clk,clk,reset_n,source_write,source_index,source_value,
        source_publish,source_energy,source_busy,feature_write,feature_index,feature_value,
        start,feature_energy,raw_done);
    wire mlp_write,mlp_start;wire [7:0] mlp_index;wire [6:0] mlp_value;wire [14:0] mlp_energy;
    generate if(NORMALIZE)begin:g_normalize
        // Finish in-flight jobs even when recognition is disabled; mailbox
        // ownership is released only by raw_done, not the display enable.
        gesture_normalize normalizer(clk,reset_n,1'b1,feature_write,feature_index,feature_value,start,
            mlp_write,mlp_index,mlp_value,mlp_start,mlp_energy,reject_reason);
    end else begin:g_legacy
        assign mlp_write=feature_write;assign mlp_index=feature_index;assign mlp_value=feature_value;
        assign mlp_start=start;assign mlp_energy=feature_energy;
        assign reject_reason=feature_energy<768?4'd1:feature_energy>30000?4'd2:4'd0;
    end endgenerate
    reg [255:0] assembling_mask;
    always @(posedge clk)begin
        if(!reset_n)begin assembling_mask<=0;input_mask<=0;end
        else begin
            if(mlp_write)assembling_mask[mlp_index]<=mlp_value!=0;
            if(mlp_start)input_mask<=assembling_mask;
        end
    end
    gesture_mlp #(.WEIGHTS(WEIGHTS),.BIASES(BIASES)) mlp(clk,reset_n,mlp_write,
        mlp_index,mlp_value,mlp_start,inference_busy,raw_done,raw_class,score0,score1,score2,inference_cycles);
    gesture_score_gate score_gate(clk,reset_n,recognition_enable,raw_done,
        score0,score1,score2,raw_class,mlp_energy,result_valid,result_accepted,result_margin,class_id,result_energy);
    wire event_valid;
    assign action_valid=event_valid&&control_enable;
    generate if(TEMPORAL)begin:g_temporal
        gesture_vote_events #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.CANCEL_ENABLED(CANCEL_ENABLED)) events(clk,reset_n,
            recognition_enable,result_valid,class_id,result_accepted,event_valid,
            control_enable?action_ready:1'b1,action,tracking,stable_class,cancel);
    end else begin:g_consecutive
    gesture_events #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.CANCEL_ENABLED(CANCEL_ENABLED),.PRECHECKED(1)) events(clk,reset_n,
        recognition_enable,result_valid,class_id,score0,score1,score2,result_energy,
        event_valid,control_enable?action_ready:1'b1,action,tracking,stable_class,cancel,result_accepted);
    end endgenerate
endmodule
