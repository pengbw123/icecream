// System-clock telemetry and opt-in composer adapter around the camera tap.
// Camera reconfiguration resets the CDC and NN, but not menu configuration.
module gesture_controller #(
    parameter integer FRESH_CYCLES=50000000,NORMALIZE=1,TEMPORAL=1,
    parameter WEIGHTS="src/generated/gesture_plane/weights.mem",
    parameter BIASES="src/generated/gesture_plane/biases.mem"
)(
    input wire clk,camera_clk,reset_n,capture_reset_n,
    input wire camera_ready,input wire [2:0] camera_fault,
    input wire [2:0] config_data,
    input wire frame_start,frame_good,frame_bad,pixel_write,
    input wire [14:0] pixel_address,input wire [7:0] pixel_data,
    input wire allowed,cancel,action_ready,
    output reg action_valid,output reg [3:0] action,
    output wire [31:0] status,detail,
    output reg [255:0] debug_mask,output reg [3:0] debug_reason
);
    wire result_valid,busy,tracking;
    wire [1:0] class_id,stable_class;
    wire signed [31:0] s0,s1,s2;
    wire [15:0] cycles,filtered_margin;wire [14:0] energy;wire filtered_accepted;
    reg fresh;
    wire [255:0] input_mask;wire [3:0] reject_reason;
    reg [1:0] raw_class_q;
    wire control_active=config_data[0]&&config_data[1]&&allowed&&capture_reset_n&&fresh;
    wire network_action_valid;wire [3:0] network_action;
    wire queue_room=!action_valid||action_ready;
    wire network_ready=queue_room||!control_active||cancel;
    gesture_pipeline #(.CANCEL_ENABLED(1),.TIMEOUT_CYCLES(FRESH_CYCLES),.NORMALIZE(NORMALIZE),.TEMPORAL(TEMPORAL),
        .WEIGHTS(WEIGHTS),.BIASES(BIASES)) pipeline(
        .clk(clk),.camera_clk(camera_clk),.reset_n(reset_n&&capture_reset_n),
        .recognition_enable(config_data[0]),.control_enable(config_data[0]&&config_data[1]),.cancel(cancel),
        .frame_start(frame_start),.frame_good(frame_good),.frame_bad(frame_bad),
        .pixel_write(pixel_write),.pixel_address(pixel_address),.pixel_data(pixel_data),
        .result_valid(result_valid),.class_id(class_id),.score0(s0),.score1(s1),.score2(s2),
        .tracking(tracking),.stable_class(stable_class),.action_valid(network_action_valid),
        .action_ready(network_ready),.action(network_action),.inference_busy(busy),.inference_cycles(cycles),.result_energy(energy),
        .result_margin(filtered_margin),.result_accepted(filtered_accepted),.input_mask(input_mask),.reject_reason(reject_reason));
    wire position_valid;wire [3:0] position_action;
    gesture_position position(.clk(clk),.reset_n(reset_n&&capture_reset_n),
        .enable(control_active&&config_data[2]),.cancel(cancel),
        .sample_valid(result_valid&&filtered_accepted&&tracking&&stable_class==1&&class_id==1),
        .mask(input_mask),.valid(position_valid),.action(position_action),
        .ready(queue_room&&!network_action_valid&&!cancel));
    // Break the MIDI/pad eligibility -> control -> composer action path with
    // one elastic register. The composer still checks ownership at consumption.
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin action_valid<=0;action<=0;end
        else if(cancel||!control_active)action_valid<=0;
        else if(queue_room)begin
            action_valid<=network_action_valid||position_valid;
            if(network_action_valid)action<=network_action;else if(position_valid)action<=position_action;
        end
    end
    reg [31:0] age;
    reg [15:0] results,margin_q;
    reg [14:0] energy_q;
    reg accepted;
    reg [3:0] last_action;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            age<=0;fresh<=0;results<=0;margin_q<=0;energy_q<=0;accepted<=0;last_action<=0;
            debug_mask<=0;debug_reason<=0;raw_class_q<=0;
        end else begin
            if(!config_data[0]||!capture_reset_n)begin age<=0;fresh<=0;accepted<=0;end
            else if(result_valid)begin
                age<=0;fresh<=1;
                if(results!=65535)results<=results+1'b1;
                margin_q<=filtered_margin;energy_q<=energy;
                accepted<=filtered_accepted;
                debug_mask<=input_mask;debug_reason<=reject_reason;raw_class_q<=class_id;
            end else if(age<FRESH_CYCLES)begin
                age<=age+1'b1;
                if(age==FRESH_CYCLES-1)begin fresh<=0;accepted<=0;end
            end
            if(action_valid&&action_ready)last_action<=action;
            if(!config_data[0]||!config_data[1])last_action<=0;
        end
    end
    wire [1:0] last_code=last_action==3?2'd1:last_action==2?2'd2:last_action==4?2'd3:2'd0;
    // UI[63]: counter31:16, last action15:14(1STOP/2START/3VAR), active13,
    // pending12, stable class11:10, raw class9:8, busy7, stable6, fresh5,
    // fault4, ready3, available2, config1:0.
    assign status={results,last_code,control_active,action_valid,stable_class,raw_class_q,
        busy,tracking&&fresh,fresh,camera_fault!=0,camera_ready,1'b1,config_data[1:0]};
    // UI[35]: clipped logit margin[31:16], accepted15, foreground energy[14:0].
    assign detail={margin_q,accepted&&fresh,energy_q};
endmodule
