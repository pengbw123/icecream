// Four registered stages: pair ranking, final ranking, signed difference,
// threshold. No 32-bit comparator->mux->comparator->subtractor->event fanout.
// Scores remain unchanged in the MLP until the mailbox releases this result.
module gesture_score_gate(
    input wire clk,reset_n,enable,input_valid,
    input wire signed [31:0] score0,score1,score2,
    input wire [1:0] input_class,input wire [14:0] input_energy,
    output reg result_valid,accepted,
    output reg [15:0] margin,
    output reg [1:0] result_class,output reg [14:0] result_energy
);
    reg [2:0] valid;
    reg signed [31:0] pair_best,pair_runner,third,top,second;
    reg signed [32:0] difference;
    reg [1:0] c1,c2,c3;reg [14:0] e1,e2,e3;
    always @(posedge clk)begin
        if(!reset_n||!enable)begin
            valid<=0;result_valid<=0;accepted<=0;margin<=0;result_class<=0;result_energy<=0;
            pair_best<=0;pair_runner<=0;third<=0;top<=0;second<=0;difference<=0;
            c1<=0;c2<=0;c3<=0;e1<=0;e2<=0;e3<=0;
        end else begin
            valid<={valid[1:0],input_valid};result_valid<=valid[2];
            if(input_valid)begin
                pair_best<=score1>score0?score1:score0;
                pair_runner<=score1>score0?score0:score1;
                third<=score2;c1<=input_class;e1<=input_energy;
            end
            if(valid[0])begin
                top<=third>pair_best?third:pair_best;
                second<=third>pair_best?pair_best:third>pair_runner?third:pair_runner;
                c2<=c1;e2<=e1;
            end
            if(valid[1])begin
                difference<=$signed({top[31],top})-$signed({second[31],second});
                c3<=c2;e3<=e2;
            end
            if(valid[2])begin
                margin<=difference>65535?16'hffff:difference[15:0];
                accepted<=difference>=2048&&e3>=768&&e3<=30000&&c3<3;
                result_class<=c3;result_energy<=e3;
            end
        end
    end
endmodule
