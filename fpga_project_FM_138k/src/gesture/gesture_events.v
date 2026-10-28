// Optional, default-disabled control adapter. ONE clock domain with MLP.
// Class 0=fist -> STOP(3), 1=palm -> START(2), 2=V -> VARIATION(4).
// These are composer action codes, not MIDI notes. Wire only after explicit
// user enable. Network scores are logits; margin is NOT a probability.
module gesture_events #(
    parameter integer STABLE_FRAMES=3, RELEASE_FRAMES=3,
    parameter integer TIMEOUT_CYCLES=50000000,
    parameter integer MIN_MARGIN=2048, MIN_ENERGY=768, MAX_ENERGY=30000,
    parameter integer CANCEL_ENABLED=0, PRECHECKED=0
)(
    input wire clk,reset_n,enable,result_valid,
    input wire [1:0] class_id,
    input wire signed [31:0] score0,score1,score2,
    input wire [14:0] feature_energy,
    output reg action_valid,input wire action_ready,
    output reg [3:0] action,
    output reg tracking,output reg [1:0] stable_class,
    input wire cancel,input wire prechecked_accepted
);
    reg signed [31:0] best,runner;
    reg signed [32:0] margin;
    always @* begin
        best=score0;runner=score1;
        if(score1>score0)begin best=score1;runner=score0;end
        if(score2>best)begin runner=best;best=score2;end
        else if(score2>runner)runner=score2;
        margin=$signed({best[31],best})-$signed({runner[31],runner});
    end
    wire accepted=PRECHECKED?prechecked_accepted:
        class_id<3&&margin>=MIN_MARGIN&&feature_energy>=MIN_ENERGY&&feature_energy<=MAX_ENERGY;
    reg [1:0] candidate,latched;
    reg latched_valid;
    localparam COUNT_BITS=$clog2((STABLE_FRAMES>RELEASE_FRAMES?STABLE_FRAMES:RELEASE_FRAMES)+1);
    reg [(COUNT_BITS<1?1:COUNT_BITS)-1:0] consecutive,released;
    reg [31:0] age;
    always @(posedge clk)begin
        if(!reset_n||!enable)begin
            action_valid<=0;action<=0;tracking<=0;stable_class<=0;
            candidate<=0;latched<=0;latched_valid<=0;consecutive<=0;released<=0;age<=0;
        end else begin
            if(action_valid&&action_ready)action_valid<=0;
            if(age<TIMEOUT_CYCLES)age<=age+1'b1;
            if(age==TIMEOUT_CYCLES-1)begin
                tracking<=0;consecutive<=0;released<=0;latched_valid<=0;
                // An unconsumed command is stale after loss of camera.
                action_valid<=0;
            end
            if(result_valid)begin
                age<=0;
                if(accepted)begin
                    released<=0;
                    if(candidate==class_id)begin
                        if(consecutive<STABLE_FRAMES)consecutive<=consecutive+1;
                    end else begin candidate<=class_id;consecutive<=1;end
                    if((candidate==class_id&&consecutive>=STABLE_FRAMES-1)||STABLE_FRAMES==1)begin
                        tracking<=1;stable_class<=class_id;
                        // Hold an outstanding action stable under backpressure.
                        // A new gesture is retried on later result frames.
                        if((!latched_valid||latched!=class_id)&&(!action_valid||action_ready))begin
                            action_valid<=1;action<=class_id==0?4'd3:class_id==1?4'd2:4'd4;
                            latched_valid<=1;latched<=class_id;
                        end
                    end
                end else begin
                    tracking<=0;consecutive<=0;
                    if(released<RELEASE_FRAMES)released<=released+1;
                    if(released>=RELEASE_FRAMES-1)latched_valid<=0;
                end
            end
            // Manual UI/pad commands invalidate pending actions. Remember the
            // current candidate so a held palm cannot immediately undo STOP.
            if(CANCEL_ENABLED&&cancel)begin
                action_valid<=0;consecutive<=0;released<=0;
                if(result_valid&&accepted)begin latched<=class_id;latched_valid<=1;end
                else if(consecutive!=0||tracking)begin latched<=candidate;latched_valid<=1;end
            end
        end
    end
endmodule
