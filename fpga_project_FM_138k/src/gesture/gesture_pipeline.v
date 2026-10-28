// Standalone camera tap -> feature mailbox -> NN -> optional composer actions.
// Not instantiated in the instrument top until real-camera calibration passes.
// clk is the stable 50MHz system clock; camera_clk may stop without hanging it.
// reset_n must include camera capture/config reset as well as main reset.
module gesture_pipeline #(
    parameter WEIGHTS="src/generated/gesture/weights.mem",
    parameter BIASES="src/generated/gesture/biases.mem",
    parameter integer TIMEOUT_CYCLES=50000000,
    parameter integer SILHOUETTE=1
)(
    input wire clk,camera_clk,reset_n,
    input wire recognition_enable,control_enable,
    input wire frame_start,frame_good,frame_bad,pixel_write,
    input wire [14:0] pixel_address,input wire [7:0] pixel_data,
    output wire result_valid,output wire [1:0] class_id,
    output wire signed [31:0] score0,score1,score2,
    output wire tracking,output wire [1:0] stable_class,
    output wire action_valid,input wire action_ready,output wire [3:0] action,
    output wire inference_busy,output wire [15:0] inference_cycles
);
    reg [1:0] enable_sync;
    always @(posedge camera_clk or negedge reset_n)
        if(!reset_n)enable_sync<=0;else enable_sync<={enable_sync[0],recognition_enable};
    wire source_write,source_publish,source_busy,feature_write,start;
    wire [7:0] source_index,feature_index;
    wire [6:0] source_value,feature_value;
    wire [14:0] source_energy,feature_energy;
    gesture_roi #(.SILHOUETTE(SILHOUETTE)) roi(camera_clk,reset_n,enable_sync[1],frame_start,frame_good,frame_bad,
        pixel_write,pixel_address,pixel_data,source_busy,source_write,source_index,
        source_value,source_publish,source_energy);
    gesture_mailbox mailbox(camera_clk,clk,reset_n,source_write,source_index,source_value,
        source_publish,source_energy,source_busy,feature_write,feature_index,feature_value,
        start,feature_energy,result_valid);
    gesture_mlp #(.WEIGHTS(WEIGHTS),.BIASES(BIASES)) mlp(clk,reset_n,feature_write,
        feature_index,feature_value,start,inference_busy,result_valid,class_id,score0,score1,score2,inference_cycles);
    gesture_events #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) events(clk,reset_n,
        recognition_enable&&control_enable,result_valid,class_id,score0,score1,score2,feature_energy,
        action_valid,action_ready,action,tracking,stable_class);
endmodule
