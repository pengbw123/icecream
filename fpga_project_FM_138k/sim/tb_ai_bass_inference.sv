`timescale 1ns/1ps
module tb_ai_bass_inference;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,feature_write=0,start=0;
    reg [5:0] feature_index=0;reg [7:0] feature_value=0;
    wire busy,done;wire [2:0] action;wire [15:0] cycles;
    reg [2:0] score_index=0;wire signed [31:0] score;
    ai_bass_inference dut(.*);
    reg [7:0] inputs[0:7775];reg [2:0] actions[0:161];reg [31:0] scores[0:1295];
    integer n,i,first_cycles=0;
    initial begin
        $readmemh("src/generated/ai_bass/test_features.mem",inputs);
        $readmemh("src/generated/ai_bass/test_actions.mem",actions);
        $readmemh("src/generated/ai_bass/test_scores.mem",scores);
        repeat(4)@(negedge clk);reset_n=1;
        for(n=0;n<162;n=n+1)begin
            for(i=0;i<48;i=i+1)begin
                @(negedge clk);feature_index=i;feature_value=inputs[n*48+i];feature_write=1;
            end
            @(negedge clk);feature_write=0;start=1;
            @(negedge clk);start=0;
            // Concurrent rejected writes/start cannot corrupt an active snapshot.
            repeat(8)@(negedge clk);feature_write=1;feature_value=255;start=1;
            repeat(8)@(negedge clk);feature_write=0;start=0;
            wait(done);#1;
            if(action!==actions[n])$fatal(1,"Action vector %d got %d expected %d",n,action,actions[n]);
            if(n==0)first_cycles=cycles;
            if(cycles!=first_cycles||cycles>5000)$fatal(1,"Inference deadline/determinism");
            for(i=0;i<8;i=i+1)begin
                score_index=i;#1;if(score!==scores[n*8+i])$fatal(1,"Score vector %d class %d got %d expected %d",n,i,score,$signed(scores[n*8+i]));
            end
        end
        $display("PASS 162 trained INT8 vectors, all 1296 logits exact, busy isolation, fixed %d cycles / %d ns",first_cycles,first_cycles*20);$finish;
    end
    initial begin #100000000;$fatal(1,"AI inference timeout");end
endmodule
