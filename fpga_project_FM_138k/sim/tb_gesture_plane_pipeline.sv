`timescale 1ns/1ps
module tb_gesture_plane_pipeline;
    reg clk=0,cam=0,cam_run=1;
    always #10 clk=~clk;
    always begin #7;if(cam_run)cam=~cam;end
    reg reset_n=0,enable=1,controls=0,fs=0,fg=0,fb=0,pw=0;
    reg [14:0] addr=0;reg [7:0] data=255;
    wire result_valid,tracking,av,busy;
    wire [1:0] cls,stable;wire [3:0] action;wire [15:0] cycles;
    wire [14:0] result_energy;
    wire [255:0] debug_mask;wire [3:0] reject_reason;
    wire signed [31:0] s0,s1,s2;
    gesture_pipeline #(.NORMALIZE(1),.WEIGHTS("src/generated/gesture_plane/weights.mem"),.BIASES("src/generated/gesture_plane/biases.mem"),.TIMEOUT_CYCLES(200000)) dut(clk,cam,reset_n,enable,controls,
        fs,fg,fb,pw,addr,data,result_valid,cls,s0,s1,s2,tracking,stable,av,1'b1,action,busy,cycles,1'b0,result_energy,,,debug_mask,reject_reason);
    reg [7:0] images[0:383999];reg [31:0] scores[0:4499];
    reg [14:0] energies[0:1499];
    reg [6:0] features[0:383999];reg [3:0] reasons[0:1499];
    integer results=0,expected=0,i;
    always @(posedge clk)begin
        if(av)$fatal(1,"controls disabled but action escaped");
        if(result_valid)begin
            if(s0!==scores[expected*3]||s1!==scores[expected*3+1]||s2!==scores[expected*3+2])
                $fatal(1,"full camera->ROI->CDC->NN score mismatch image %0d",expected);
            if(result_energy!==energies[expected])$fatal(1,"pipeline energy mismatch");
            if(reject_reason!==reasons[expected])$fatal(1,"pipeline reason mismatch");
            for(integer k=0;k<256;k=k+1)if(debug_mask[k] !== (features[expected*256+k]!=0))$fatal(1,"pipeline exact input mask mismatch");
            results=results+1;
        end
    end
    task boundary(input good,input bad);
        begin @(negedge cam);fs=1;fg=good;fb=bad;
            @(negedge cam);fs=0;fg=0;fb=0;end
    endtask
    task frame(input integer image_id);
        integer p,x,y,sample_index;
        begin
            for(p=0;p<19200;p=p+1)begin
                @(negedge cam);pw=1;addr=p;x=p%160;y=p/160;data=255;
                if(x>=32&&x<128&&y>=12&&y<108)begin
                    sample_index=((y-12)/6)*16+(x-32)/6;
                    data=images[image_id*256+sample_index];
                end
            end
            @(negedge cam);pw=0;repeat(4)@(negedge cam);
        end
    endtask
    initial begin
        $readmemh("tmp/plane_vectors/packed.mem",images);
        $readmemh("tmp/plane_vectors/scores.mem",scores);
        $readmemh("tmp/plane_vectors/energy.mem",energies);
        $readmemh("tmp/plane_vectors/features.mem",features);$readmemh("tmp/plane_vectors/reason.mem",reasons);
        repeat(5)@(negedge clk);reset_n=1;repeat(10)@(negedge cam);
        for(i=0;i<12;i=i+1)begin
            expected=i<9?(i/3)*372+(i%3)*124:(i==9?1116:i==10?1244:1499);boundary(0,0);frame(expected);boundary(1,0);
            wait(result_valid);repeat(2)@(negedge clk);wait(!dut.source_busy);
            if(results!=i+1)$fatal(1,"missing job");
        end
        boundary(0,0);frame(0);boundary(1,1);repeat(14000)@(negedge clk);
        if(results!=12)$fatal(1,"bad camera frame classified");
        // Disable recognition and stop PCLK during normalization. Raw inference
        // must still finish, otherwise the mailbox would never release again.
        expected=1499;boundary(0,0);frame(expected);boundary(1,0);
        wait(dut.g_normalize.normalizer.state==1);enable=0;cam_run=0;
        repeat(16000)@(negedge clk);
        if(results!=12||busy)$fatal(1,"disabled in-flight inference leaked/hung");
        cam_run=1;wait(!dut.source_busy);enable=1;repeat(10)@(negedge cam);
        expected=0;boundary(0,0);frame(expected);boundary(1,0);
        wait(result_valid);repeat(2)@(negedge clk);wait(!dut.source_busy);
        if(results!=13)$fatal(1,"reenable mailbox deadlock");
        // No camera clock: stable system domain keeps running, no spurious results.
        cam_run=0;repeat(1000)@(negedge clk);
        if(av||busy)$fatal(1,"stopped camera leaked command");
        $display("PASS gesture_plane_pipeline: 13 RGB332 results, exposure/gradient/random/blank, ROI/CDC/normalize/NN scores and energy exact, bad frames, stopped clock, disable during normalize and reenable");$finish;
    end
    initial begin #40000000;$fatal(1,"timeout");end
endmodule
