`timescale 1ns/1ps
// Real held-out RGB332 images -> ROI/CDC/NN/filter -> actual composer transport.
module tb_gesture_controller;
    reg clk=0,cam=0,cam_run=1;always #10 clk=~clk;
    always begin #7;if(cam_run)cam=~cam;end
    reg reset_n=0,capture_reset_n=1,camera_ready=1;
    reg [2:0] camera_fault=0;reg [1:0] config_data=0;
    reg fs=0,fg=0,fb=0,pw=0;reg [14:0] addr=0;reg [7:0] data=255;
    wire action_valid,allowed,cancel,action_ready;wire [3:0] action;
    wire [31:0] gesture_status,gesture_detail;
    gesture_controller #(.FRESH_CYCLES(200000),.NORMALIZE(0),.TEMPORAL(0),
        .WEIGHTS("src/generated/gesture/weights.mem"),.BIASES("src/generated/gesture/biases.mem")) dut(clk,cam,reset_n,capture_reset_n,
        camera_ready,camera_fault,config_data,fs,fg,fb,pw,addr,data,
        allowed,cancel,action_ready,action_valid,action,gesture_status,gesture_detail,,,16'd0,,,,,);
    reg cfg_write=0;reg [9:0] cfg_address=0;reg [15:0] cfg_value=0;
    wire [31:0] out_data,status,detail;wire out_valid;
    ai_melody_composer #(.CLOCKS_PER_US(1),.GESTURE_ENABLED(1)) composer(
        .clk(clk),.reset_n(reset_n),.cfg_write(cfg_write),.cfg_address(cfg_address),.cfg_value(cfg_value),
        .suspend(1'b0),.observe_data(32'd0),.observe_valid(1'b0),.out_data(out_data),.out_valid(out_valid),.out_ready(1'b1),
        .status(status),.detail(detail),.gesture_valid(action_valid),.gesture_action(action),
        .gesture_ready(action_ready),.gesture_allowed(allowed),.gesture_cancel(cancel));
    reg [7:0] images[0:95231];reg [31:0] scores[0:1115];reg [7:0] labels[0:371];
    integer ids[0:2];integer i,c,actions=0,ons=0,held=-1,saved_actions;
    reg signed [31:0] best,runner;
    always @(posedge clk)begin
        if(action_valid&&action_ready)actions=actions+1;
        if(out_valid)begin
            if(out_data[23:20]==9)begin
                if(held!=-1)$fatal(1,"overlapping notes");held=out_data[14:8];ons=ons+1;
            end else if(out_data[23:20]==8)held=-1;
        end
    end
    task cfg(input [9:0] a,input [15:0] v);
        begin @(negedge clk);cfg_write=1;cfg_address=a;cfg_value=v;
            @(negedge clk);cfg_write=0;repeat(5)@(negedge clk);end
    endtask
    task boundary(input good);
        begin @(negedge cam);fs=1;fg=good;@(negedge cam);fs=0;fg=0;end
    endtask
    task frame(input integer id);
        integer p,x,y,q;
        begin
            boundary(0);
            for(p=0;p<19200;p=p+1)begin
                @(negedge cam);pw=1;addr=p;x=p%160;y=p/160;data=255;
                if(id>=0&&x>=32&&x<128&&y>=12&&y<108)begin
                    q=((y-12)/6)*16+(x-32)/6;data=images[id*256+q];
                end
            end
            @(negedge cam);pw=0;repeat(4)@(negedge cam);boundary(1);
            wait(dut.result_valid);repeat(12)@(negedge clk);
            wait(!dut.g_legacy.pipeline.source_busy);
        end
    endtask
    initial begin
        $readmemh("src/generated/gesture/test_rgb332.mem",images);
        $readmemh("src/generated/gesture/test_scores.mem",scores);
        $readmemh("src/generated/gesture/test_labels.mem",labels);
        for(c=0;c<3;c=c+1)begin
            ids[c]=-1;
            for(i=0;i<372;i=i+1)if(labels[i]==c&&ids[c]<0)begin
                best=$signed(scores[i*3+c]);runner=-2147483647;
                for(integer j=0;j<3;j=j+1)if(j!=c&&$signed(scores[i*3+j])>runner)runner=$signed(scores[i*3+j]);
                if(best-runner>10000)ids[c]=i;
            end
            if(ids[c]<0)$fatal(1,"missing correct strong held-out sample");
        end
        repeat(5)@(negedge clk);reset_n=1;config_data=1;repeat(10)@(negedge cam);
        repeat(3)frame(ids[1]);
        if(!gesture_status[6]||gesture_status[31:16]!=3||actions||ons)$fatal(1,"display-only recognition or telemetry");
        cfg('h3c0,1);config_data=3;
        repeat(4)frame(ids[1]);if(composer.running||actions)$fatal(1,"arming replayed a held palm");
        repeat(3)frame(-1);repeat(3)frame(ids[1]);
        if(!composer.running||actions!=1)$fatal(1,"new palm did not start");
        wait(ons>0);cfg('h3c5,3);repeat(4)frame(ids[1]);
        if(composer.running||actions!=1||held!=-1)$fatal(1,"held palm undid manual STOP");
        repeat(3)frame(ids[0]);repeat(3)frame(ids[1]);
        if(!composer.running)$fatal(1,"gesture change did not rearm");
        saved_actions=actions;repeat(3)frame(ids[2]);
        if(actions!=saved_actions+1||composer.variation_steps==0)$fatal(1,"V variation");
        repeat(3)frame(ids[0]);repeat(60)@(negedge clk);
        if(composer.running||held!=-1)$fatal(1,"fist stop left notes");
        cam_run=0;repeat(200010)@(negedge clk);
        if(gesture_status[5]||gesture_status[6]||gesture_detail[15]||action_valid)$fatal(1,"stopped camera retained fresh result/action");
        capture_reset_n=0;camera_ready=0;repeat(5)@(negedge clk);
        if(gesture_status[3]||gesture_status[5]||action_valid)$fatal(1,"camera reset state");
        config_data=0;repeat(3)@(negedge clk);
        if(action_valid||gesture_status[13])$fatal(1,"disabled control");
        $display("PASS gesture_controller: held-out frames to actual composer, display-only/arming, manual override, start/stop/variation, no hanging notes, PCLK loss/reset");$finish;
    end
    initial begin #100000000;$fatal(1,"timeout");end
endmodule
