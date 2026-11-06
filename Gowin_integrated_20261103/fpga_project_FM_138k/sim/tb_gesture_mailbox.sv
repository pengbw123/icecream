`timescale 1ns/1ps
module tb_gesture_mailbox;
    reg clk=0,cam=0,cam_run=1;
    always #10 clk=~clk;
    always begin #7;if(cam_run)cam=~cam;end
    reg reset_n=0,wr=0,pub=0,done=0;
    reg [7:0] idx=0;reg [6:0] value=0;
    reg [14:0] energy=4567;
    wire busy,fw,start;wire [7:0] fi;wire [6:0] fv;wire [14:0] en;
    gesture_mailbox dut(cam,clk,reset_n,wr,idx,value,pub,energy,busy,fw,fi,fv,start,en,done);
    integer received=0,starts=0,i,round=0;
    reg check=1;
    always @(posedge clk)begin
        if(fw&&check)begin
            if(fi!==received||fv!==((received+round)&127))$fatal(1,"CDC feature mismatch %0d idx %0d value %0d",received,fi,fv);
            received=received+1;
        end
        if(start)begin
            starts=starts+1;
            if(received!=256||en!=4567)$fatal(1,"premature publish/energy");
        end
    end
    task send;
        begin
            for(i=0;i<256;i=i+1)begin @(negedge cam);wr=1;idx=i;value=(i+round)&127;end
            @(negedge cam);wr=0;pub=1;
            @(negedge cam);pub=0;
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);reset_n=1;repeat(8)@(negedge cam);
        send();wait(busy);
        // Attempt to overwrite held bank while destination is replaying it.
        repeat(5)begin @(negedge cam);wr=1;idx=0;value=127;pub=1;end
        @(negedge cam);wr=0;pub=0;energy=0;
        cam_run=0;
        wait(start);repeat(20)@(negedge clk);
        if(!busy||starts!=1)$fatal(1,"lost ownership");
        done=1;@(negedge clk);done=0;repeat(10)@(negedge clk);
        if(!busy)$fatal(1,"ack crossed stopped clock");
        cam_run=1;wait(!busy);
        round=1;received=0;energy=4567;send();wait(start);repeat(3)@(negedge clk);
        done=1;@(negedge clk);done=0;wait(!busy);
        if(starts!=2)$fatal(1,"repeat job");
        // Common reset while request is pending must not fabricate a new job.
        received=0;round=2;send();check=0;reset_n=0;repeat(4)@(negedge clk);reset_n=1;
        repeat(600)@(negedge clk);if(start||busy||fw||starts!=2)$fatal(1,"reset stale job");
        $display("PASS gesture_mailbox: async clocks, held bank/energy, stopped source, reset recovery");$finish;
    end
    initial begin #200000;$fatal(1,"timeout");end
endmodule
