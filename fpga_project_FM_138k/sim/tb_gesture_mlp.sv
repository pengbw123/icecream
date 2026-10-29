`timescale 1ns/1ps
module tb_gesture_mlp;
    parameter MODEL_DIR="src/generated/gesture";
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,wr=0,start=0;
    reg [7:0] index=0;reg [6:0] value=0;
    wire busy,done;wire [1:0] class_id;wire [15:0] cycles;
    wire signed [31:0] s0,s1,s2;
    gesture_mlp #(.WEIGHTS({MODEL_DIR,"/weights.mem"}),.BIASES({MODEL_DIR,"/biases.mem"})) dut(clk,reset_n,wr,index,value,start,busy,done,class_id,s0,s1,s2,cycles);
    reg [7:0] features[0:95231];
    reg [31:0] scores[0:1115];
    reg [7:0] labels[0:371];
    integer i,j,correct=0,expected_class;
    initial begin
        $readmemh({MODEL_DIR,"/test_features.mem"},features);
        $readmemh({MODEL_DIR,"/test_scores.mem"},scores);
        $readmemh({MODEL_DIR,"/test_labels.mem"},labels);
        repeat(3)@(negedge clk);reset_n=1;
        for(i=0;i<372;i=i+1)begin
            for(j=0;j<256;j=j+1)begin
                @(negedge clk);wr=1;index=j;value=features[i*256+j];
            end
            @(negedge clk);wr=0;start=1;
            @(negedge clk);start=0;
            // Illegal writes/start during busy must not modify an active job.
            repeat(4)@(negedge clk);
            wr=1;index=0;value=127;start=1;
            @(negedge clk);wr=0;start=0;
            wait(done);@(negedge clk);
            if(s0!==scores[i*3]||s1!==scores[i*3+1]||s2!==scores[i*3+2])
                $fatal(1,"score mismatch image %0d got %0d/%0d/%0d expected %0d/%0d/%0d",i,s0,s1,s2,
                    $signed(scores[i*3]),$signed(scores[i*3+1]),$signed(scores[i*3+2]));
            expected_class=0;
            if($signed(scores[i*3+1])>$signed(scores[i*3]))expected_class=1;
            if($signed(scores[i*3+2])>$signed(scores[i*3+expected_class]))expected_class=2;
            if(class_id!==expected_class||busy||cycles!=12486)$fatal(1,"class/busy/latency %0d cycles %0d",i,cycles);
            if(class_id==labels[i])correct=correct+1;
            @(negedge clk);if(done)$fatal(1,"done must pulse once");
        end
        // Reset in the middle of a job; no stale result may escape.
        start=1;@(negedge clk);start=0;repeat(100)@(negedge clk);
        reset_n=0;@(negedge clk);reset_n=1;repeat(13000)@(negedge clk);
        if(done||busy)$fatal(1,"reset did not abort");
        $display("PASS gesture_mlp: all 1116 logits bit-exact; %0d/372 classified correctly; cycles=%0d",correct,12486);
        $finish;
    end
    initial begin #200000000;$fatal(1,"timeout");end
endmodule
