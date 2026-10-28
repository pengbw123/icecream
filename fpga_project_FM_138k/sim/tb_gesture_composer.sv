`timescale 1ns/1ps
module tb_gesture_composer;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,cfg_write=0,suspend=0,observe_valid=0,out_ready=1;
    reg [9:0] cfg_address=0;reg [15:0] cfg_value=0;reg [31:0] observe_data=0;
    reg gesture_valid=0;reg [3:0] gesture_action=0;
    wire gesture_ready,gesture_allowed,gesture_cancel;
    wire consume_input,out_valid;wire [31:0] out_data,status,detail;
    ai_melody_composer #(.CLOCKS_PER_US(1),.GESTURE_ENABLED(1)) dut(.*);
    integer ons=0,held=-1,epoch_saved;
    always @(posedge clk)if(reset_n&&out_valid&&out_ready)begin
        if(out_data[23:20]==9)begin
            if(held!=-1)$fatal(1,"overlapping gesture notes");held=out_data[14:8];ons=ons+1;
        end else if(out_data[23:20]==8)held=-1;
    end
    task cfg(input [9:0] a,input [15:0] d);
        begin @(negedge clk);cfg_write=1;cfg_address=a;cfg_value=d;
            @(negedge clk);cfg_write=0;repeat(3)@(negedge clk);end
    endtask
    task gesture(input [3:0] a);
        begin @(negedge clk);gesture_action=a;gesture_valid=1;
            wait(gesture_ready);@(negedge clk);gesture_valid=0;repeat(4)@(negedge clk);end
    endtask
    task quiet;
        begin repeat(50)@(negedge clk);if(held!=-1||out_valid||dut.on_pending)$fatal(1,"stop left a hanging note");end
    endtask
    initial begin
        repeat(3)@(negedge clk);reset_n=1;
        gesture_action=2;gesture_valid=1;repeat(10)@(negedge clk);
        if(gesture_ready||gesture_allowed||dut.running)$fatal(1,"gesture escaped session ownership");gesture_valid=0;
        cfg('h3c1,40000);cfg('h3c2,0);cfg('h3c0,1);
        gesture(2);wait(ons>0);if(!dut.running)$fatal(1,"palm did not start");
        epoch_saved=dut.epoch;gesture(2);
        if(dut.epoch!=epoch_saved)$fatal(1,"held/repeated palm restarted phrase");
        gesture(4);if(dut.variation_steps==0)$fatal(1,"V did not request variation");
        // Manual STOP wins a simultaneous palm. The pending gesture is consumed.
        @(negedge clk);gesture_action=2;gesture_valid=1;cfg_write=1;cfg_address='h3c5;cfg_value=3;
        #1;if(!gesture_ready||!gesture_cancel)$fatal(1,"manual cancel handshake");
        @(negedge clk);gesture_valid=0;cfg_write=0;quiet();
        if(dut.running)$fatal(1,"palm beat manual STOP");
        gesture(2);wait(dut.running);
        // Default first pad toggles playback; it also outranks a palm.
        @(negedge clk);gesture_action=2;gesture_valid=1;observe_valid=1;observe_data=32'h00992464;
        #1;if(!gesture_cancel)$fatal(1,"pad priority");
        @(negedge clk);gesture_valid=0;observe_valid=0;quiet();
        if(dut.running)$fatal(1,"gesture beat pad STOP");
        cfg('h3c5,9);if(gesture_allowed)$fatal(1,"theme recording not protected");
        gesture_valid=1;gesture_action=2;repeat(10)@(negedge clk);
        if(!dut.theme_recording||dut.running)$fatal(1,"gesture interrupted theme");gesture_valid=0;
        cfg('h3c5,3);cfg('h3c5,12);if(gesture_allowed)$fatal(1,"learning not protected");cfg('h3c5,3);
        cfg('h3c5,10);if(gesture_allowed)$fatal(1,"rhythm not protected");cfg('h3c5,3);
        gesture(2);suspend=1;repeat(5)@(negedge clk);
        if(gesture_allowed||dut.running)$fatal(1,"suspended mode accepted gesture");suspend=0;
        gesture(2);
        @(negedge clk);observe_valid=1;observe_data=32'h00b07b00;
        @(negedge clk);observe_valid=0;quiet();
        if(gesture_allowed||!dut.panic_latched)$fatal(1,"gesture can bypass panic latch");
        cfg('h3c5,2);if(!gesture_allowed)$fatal(1,"manual START failed to recover panic");
        cfg('h3c5,3);gesture(1);if(dut.running)$fatal(1,"non-whitelisted gesture action");
        cfg('h3c0,0);quiet();
        $display("PASS gesture_composer: mode ownership, start/stop/variation, no held-palm restart, UI/pad priority, recordings, panic, cleanup");$finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
