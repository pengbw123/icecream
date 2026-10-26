`timescale 1ns/1ps
module tb_ai_melody_inference;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,feature_write=0,start=0;
    reg [6:0] feature_index=0;reg [7:0] feature_value=0;
    wire busy,done;wire [15:0] cycles;
    wire [1:0] articulation,gate_class,dynamic_class;wire [4:0] interval_class,interval_alt;
    reg [5:0] score_index=0;wire signed [31:0] score;
    ai_melody_inference dut(.*);
    reg [7:0] inputs[0:20735];reg [31:0] scores[0:5831];reg [15:0] policies[0:161];
    integer n,i;
    initial begin
        $readmemh("src/generated/ai_composer/test_features.mem",inputs);
        $readmemh("src/generated/ai_composer/test_scores.mem",scores);
        $readmemh("src/generated/ai_composer/test_policy.mem",policies);
        repeat(4)@(negedge clk);reset_n=1;
        for(n=0;n<162;n=n+1)begin
            for(i=0;i<128;i=i+1)begin @(negedge clk);feature_index=i;feature_value=inputs[n*128+i];feature_write=1;end
            @(negedge clk);feature_write=0;start=1;@(negedge clk);start=0;
            repeat(8)@(negedge clk);feature_write=1;feature_value=255;start=1;
            repeat(8)@(negedge clk);feature_write=0;start=0;
            wait(done);#1;
            if({interval_alt,dynamic_class,gate_class,interval_class,articulation}!==policies[n])$fatal(1,"Composer heads/top2 mismatch vector %d got %h expected %h",n,{interval_alt,dynamic_class,gate_class,interval_class,articulation},policies[n]);
            if(cycles!=15912)$fatal(1,"Composer cycle deadline %d",cycles);
            for(i=0;i<36;i=i+1)begin score_index=i;#1;if(score!==scores[n*36+i])$fatal(1,"Composer vector %d score %d mismatch %d/%d",n,i,score,$signed(scores[n*36+i]));end
        end
        $display("PASS melody INT8: 162 vectors, 5832 logits and four heads/top2 exact, busy isolation, 15912 clocks / 318.24 us");$finish;
    end
    initial begin #200000000;$fatal(1,"Melody inference timeout");end
endmodule
