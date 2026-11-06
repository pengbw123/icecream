// Five-result voting with asymmetric acquisition/switch thresholds.
// Three votes acquire; four votes switch. Rejected results occupy the window
// but never vote. Three rejections release; five nonmatching results expire a
// held label. Commands are edge-latched independently of display hysteresis.
module gesture_vote_events #(
    parameter integer TIMEOUT_CYCLES=50000000,CANCEL_ENABLED=0
)(
    input wire clk,reset_n,enable,result_valid,
    input wire [1:0] class_id,input wire accepted,
    output reg action_valid,input wire action_ready,output reg [3:0] action,
    output reg tracking,output reg [1:0] stable_class,input wire cancel
);
    reg [1:0] history[0:3];reg [3:0] valid;
    reg [1:0] latched;reg latched_valid;
    reg [2:0] rejected,unmatched;reg [31:0] age;
    reg [2:0] votes;integer i;
    always @*begin
        votes=accepted&&class_id<3?3'd1:3'd0;
        for(integer k=0;k<4;k=k+1)
            if(valid[k]&&history[k]==class_id)votes=votes+1'b1;
    end
    wire confirm=accepted&&class_id<3&&votes>=(tracking&&class_id!=stable_class?4:3);
    always @(posedge clk)begin
        if(!reset_n||!enable)begin
            tracking<=0;stable_class<=0;action_valid<=0;action<=0;
            valid<=0;latched<=0;latched_valid<=0;rejected<=0;unmatched<=0;age<=0;
            for(i=0;i<4;i=i+1)history[i]<=0;
        end else begin
            if(action_valid&&action_ready)action_valid<=0;
            if(age<TIMEOUT_CYCLES)age<=age+1'b1;
            if(age==TIMEOUT_CYCLES-1)begin
                tracking<=0;valid<=0;latched_valid<=0;action_valid<=0;rejected<=0;unmatched<=0;
            end
            if(result_valid)begin
                age<=0;history[0]<=class_id;valid<={valid[2:0],accepted&&class_id<3};
                for(i=1;i<4;i=i+1)history[i]<=history[i-1];
                if(accepted)rejected<=0;else if(rejected<3)rejected<=rejected+1'b1;
                if(accepted&&tracking&&class_id==stable_class)unmatched<=0;
                else if(unmatched<5)unmatched<=unmatched+1'b1;
                if(confirm)begin
                    tracking<=1;stable_class<=class_id;unmatched<=0;
                    if((!latched_valid||latched!=class_id)&&(!action_valid||action_ready))begin
                        action_valid<=1;action<=class_id==0?4'd3:class_id==1?4'd2:4'd4;
                        latched<=class_id;latched_valid<=1;
                    end
                end else if((!accepted&&rejected>=2)||(tracking&&unmatched>=4))begin
                    tracking<=0;valid<=0;action_valid<=0;unmatched<=0;
                    if(!accepted&&rejected>=2)latched_valid<=0;
                end
            end
            if(CANCEL_ENABLED&&cancel)begin
                action_valid<=0;valid<=0;rejected<=0;unmatched<=0;
                // A held stable palm must not undo a manual STOP, even if a
                // single contradictory raw result happens on the cancel edge.
                if(confirm)begin latched<=class_id;latched_valid<=1;end
                else if(tracking)begin latched<=stable_class;latched_valid<=1;end
                else if(result_valid&&accepted)begin latched<=class_id;latched_valid<=1;end
                else if(valid[0])begin latched<=history[0];latched_valid<=1;end
            end
        end
    end
endmodule
