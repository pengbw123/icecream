`timescale 1ns/1ps
module tb_gesture_vote_events;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,enable=1,rv=0,accepted=0,ready=1,cancel=0;reg [1:0] cls=0;
    wire av,tracking;wire [3:0] action;wire [1:0] stable;
    gesture_vote_events #(.TIMEOUT_CYCLES(100),.CANCEL_ENABLED(1)) dut(clk,reset_n,enable,rv,cls,accepted,av,ready,action,tracking,stable,cancel);
    integer actions=0;
    always @(posedge clk)if(av&&ready)actions=actions+1;
    task sample(input [1:0] c,input ok);
        begin @(negedge clk);cls=c;accepted=ok;rv=1;@(negedge clk);rv=0;repeat(3)@(negedge clk);end
    endtask
    task clear;
        begin reset_n=0;repeat(2)@(negedge clk);reset_n=1;actions=0;end
    endtask
    task check(input tr,input [1:0] c,input integer n);
        begin if(tracking!==tr||(tr&&stable!==c)||actions!=n)$fatal(1,"tracking=%0d class=%0d actions=%0d expected=%0d/%0d/%0d",tracking,stable,actions,tr,c,n);end
    endtask
    initial begin
        clear;
        // Majority acquisition tolerates a single rejected frame.
        sample(1,1);sample(1,1);sample(0,0);check(0,0,0);sample(1,1);check(1,1,1);
        sample(2,1);check(1,1,1);sample(1,1);check(1,1,1);
        repeat(5)sample(1,1);
        // Three competing votes cannot switch a confirmed label.
        sample(2,1);sample(2,1);sample(2,1);check(1,1,1);
        sample(2,1);check(1,2,2);repeat(6)sample(2,1);check(1,2,2);
        sample(0,0);check(1,2,2);sample(0,0);check(1,2,2);sample(0,0);check(0,0,2);
        repeat(3)sample(2,1);check(1,2,3);
        // Five conflicting, split results expire a held label without issuing
        // a new command. Reacquiring the same held gesture does not retrigger.
        sample(0,1);sample(1,1);sample(0,1);sample(1,1);sample(0,1);check(0,0,3);
        repeat(3)sample(2,1);check(1,2,3);
        // Manual cancel flushes vote history and preserves held-palm latch.
        clear;repeat(3)sample(1,1);check(1,1,1);
        cancel=1;@(negedge clk);cancel=0;repeat(7)sample(1,1);check(1,1,1);
        clear;sample(1,1);sample(1,1);cancel=1;@(negedge clk);cancel=0;
        repeat(5)sample(1,1);check(1,1,0);
        // Backpressure: command stays stable until accepted.
        clear;ready=0;repeat(3)sample(0,1);
        if(!av||action!=3)$fatal(1,"pending STOP");repeat(10)@(negedge clk);
        if(!av||action!=3)$fatal(1,"pending changed");ready=1;repeat(3)@(negedge clk);check(1,0,1);
        // Loss of frames expires both tracking and unconsumed commands.
        ready=0;repeat(4)sample(1,1);repeat(105)@(negedge clk);
        if(tracking||av)$fatal(1,"stale command after timeout");
        enable=0;@(negedge clk);if(tracking||av)$fatal(1,"disable");
        $display("PASS gesture_vote_events: 3/5 acquisition, 4/5 switch, jitter/reject tolerance, ambiguity expiry, no held repeats, manual priority, backpressure, timeout");$finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
