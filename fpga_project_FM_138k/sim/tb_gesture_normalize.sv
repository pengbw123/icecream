`timescale 1ns/1ps
module tb_gesture_normalize;
    parameter N=1500;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,enable=1,wr=0,go=0;
    reg [7:0] idx=0;reg [6:0] value=0;
    wire fw,start;wire [7:0] fi;wire [6:0] fv;wire [14:0] energy;
    gesture_normalize dut(clk,reset_n,enable,wr,idx,value,go,fw,fi,fv,start,energy);
    reg [6:0] raw[0:N*256-1],expected[0:N*256-1];
    reg [14:0] energies[0:N-1];
    integer f,j,received=0;reg checking=0;
    always @(negedge clk)if(checking&&fw)begin
        if(fi!==received||fv!==expected[f*256+received])
            $fatal(1,"feature frame=%0d index=%0d got=%0d expected=%0d",f,received,fv,expected[f*256+received]);
        received=received+1;
    end
    initial begin
        $readmemh("tmp/plane_vectors/raw.mem",raw);
        $readmemh("tmp/plane_vectors/features.mem",expected);
        $readmemh("tmp/plane_vectors/energy.mem",energies);
        repeat(3)@(negedge clk);reset_n=1;
        for(f=0;f<N;f=f+1)begin
            for(j=0;j<256;j=j+1)begin @(negedge clk);wr=1;idx=j;value=raw[f*256+j];end
            @(negedge clk);wr=0;go=1;received=0;checking=1;
            @(negedge clk);go=0;
            wait(start);@(negedge clk);checking=0;
            if(received!=256||energy!==energies[f])$fatal(1,"frame=%0d count=%0d energy=%0d expected=%0d",f,received,energy,energies[f]);
        end
        // Abort partial capture and processing, then ensure no stale publish.
        wr=1;idx=0;value=80;@(negedge clk);wr=0;go=1;
        @(negedge clk);go=0;repeat(20)@(negedge clk);reset_n=0;
        @(negedge clk);reset_n=1;repeat(1500)begin @(negedge clk);if(start||fw)$fatal(1,"stale after reset");end
        $display("PASS gesture_normalize: %0d frames, %0d features, plane/shape energy bit exact, reset",N,N*256);$finish;
    end
    initial begin #200000000;$fatal(1,"timeout");end
endmodule
