`timescale 1ns/1ps
module tb_gesture_events;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,enable=0,rv=0,ready=1;
    reg [1:0] cls=0;reg signed [31:0] s0=0,s1=0,s2=0;
    reg [14:0] energy=4000;
    wire av,tracking;wire [3:0] action;wire [1:0] stable;
    gesture_events #(.TIMEOUT_CYCLES(100)) dut(clk,reset_n,enable,rv,cls,s0,s1,s2,energy,av,ready,action,tracking,stable);
    integer count=0;reg [3:0] last=0;
    always @(posedge clk)if(av&&ready)begin count=count+1;last=action;end
    task result(input integer c,input integer margin);
        begin
            @(negedge clk);cls=c;s0=0;s1=0;s2=0;
            if(c==0)s0=margin;if(c==1)s1=margin;if(c==2)s2=margin;
            rv=1;@(negedge clk);rv=0;repeat(2)@(negedge clk);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);reset_n=1;
        repeat(4)result(0,8000);if(count)$fatal(1,"default disable");enable=1;
        result(0,8000);result(0,8000);if(count)$fatal(1,"unstable trigger");
        result(0,8000);if(count!=1||last!=3)$fatal(1,"fist stop");
        repeat(4)result(0,8000);if(count!=1)$fatal(1,"held repeat");
        result(1,8000);result(0,8000);result(1,8000);if(count!=1)$fatal(1,"flicker");
        repeat(2)result(1,8000);if(count!=2||last!=2)$fatal(1,"palm start");
        repeat(3)result(1,100);repeat(3)result(1,8000);
        if(count!=3)$fatal(1,"neutral rearm");
        ready=0;repeat(3)result(2,8000);if(!av||action!=4)$fatal(1,"V command");
        repeat(3)result(0,8000);if(!av||action!=4)$fatal(1,"backpressure data changed");
        ready=1;repeat(3)@(negedge clk);if(count!=4||last!=4)$fatal(1,"handshake");
        result(0,8000);if(count!=5||last!=3)$fatal(1,"deferred gesture");
        energy=256;repeat(3)result(2,8000);if(tracking||count!=5)$fatal(1,"blank rejection");
        energy=4000;repeat(3)result(2,8000);if(count!=6)$fatal(1,"V return");
        repeat(110)@(negedge clk);if(tracking||av)$fatal(1,"camera timeout");
        repeat(3)result(2,8000);if(count!=7)$fatal(1,"timeout rearm");
        ready=0;repeat(3)result(0,8000);enable=0;repeat(2)@(negedge clk);
        if(av||tracking)$fatal(1,"disable stale action");
        $display("PASS gesture_events: stability, release, margin/blank rejection, backpressure, timeout, disable");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
