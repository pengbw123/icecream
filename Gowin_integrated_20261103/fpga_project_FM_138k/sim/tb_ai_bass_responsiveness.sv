`timescale 1ns/1ps
module tb_ai_bass_responsiveness;
    localparam STEP=16000;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,cfg_write=0,suspend=0,observe_valid=0,out_ready=1;
    reg [9:0] cfg_address=0;reg [15:0] cfg_value=0;
    reg [31:0] observe_data=0;wire [31:0] out_data,status;wire out_valid;
    ai_bass_accompaniment #(.CLOCKS_PER_US(1)) dut(.*);
    integer case_id=-1,cycle=0,fd,ons,offs,vel_sum,gate_sum,held_note=-1,on_cycle,first_note;
    integer attacks[0:5],velocity_sum[0:5],duration_sum[0:5];
    reg stalled=0;reg [31:0] stalled_data;
    always @(posedge clk)begin
        cycle=cycle+1;
        if(reset_n)begin
            if(stalled&&out_valid&&out_data!==stalled_data)$fatal(1,"stalled AI event changed");
            stalled<=out_valid&&!out_ready;stalled_data<=out_data;
            if(observe_valid)$fwrite(fd,"%0d,%0d,LIVE,%02x,%0d,%0d\n",case_id,cycle,observe_data[23:16],observe_data[14:8],observe_data[6:0]);
            if(out_valid&&out_ready)begin
                $fwrite(fd,"%0d,%0d,BASS,%02x,%0d,%0d\n",case_id,cycle,out_data[23:16],out_data[14:8],out_data[6:0]);
                if(out_data[31:24]!=8'h40)$fatal(1,"AI ownership tag");
                if(out_data[23:20]==9)begin
                    if(held_note!=-1)$fatal(1,"overlapping bass gate");
                    if(out_data[6:0]==0||out_data[14:8]<31||out_data[14:8]>59)$fatal(1,"pitch/velocity bounds");
                    held_note=out_data[14:8];on_cycle=cycle;vel_sum=vel_sum+out_data[6:0];
                    if(ons==0)first_note=held_note;ons=ons+1;
                end else if(out_data[23:20]==8)begin
                    if(held_note!=-1)begin
                        if(held_note!=out_data[14:8])$fatal(1,"wrong bass release");
                        gate_sum=gate_sum+cycle-on_cycle;held_note=-1;offs=offs+1;
                    end
                end else $fatal(1,"unexpected AI event");
            end
        end
    end
    task cfg(input [9:0] a,input [15:0] v);
        begin @(negedge clk);cfg_address=a;cfg_value=v;cfg_write=1;@(negedge clk);cfg_write=0;end
    endtask
    task midi(input [7:0] st,input [6:0] n,input [6:0] v);
        begin @(negedge clk);observe_data={8'd0,st,1'b0,n,1'b0,v};observe_valid=1;@(negedge clk);observe_valid=0;end
    endtask
    task setup(input integer id,input integer mode);
        begin
            @(negedge clk);reset_n=0;repeat(5)@(negedge clk);reset_n=1;
            case_id=id;ons=0;offs=0;vel_sum=0;gate_sum=0;held_note=-1;first_note=-1;stalled=0;
            cfg('h3f1,STEP);cfg('h3f2,0);cfg('h3f3,(60<<8)|mode);cfg('h3f0,(70<<9)|9);
        end
    endtask
    integer kind,s,v,left_root,left_third,left_fifth,rh;
    initial begin
        fd=$fopen("tmp/ai_v2_pairs.csv","w");$fwrite(fd,"case,cycle,part,status,note,velocity\n");
        for(kind=0;kind<6;kind=kind+1)begin
            setup(kind,3);
            repeat(STEP*2)@(negedge clk);
            if(ons!=0)$fatal(1,"FOLLOW played before human input");
            v=kind==0?30:kind==1?110:80;
            left_root=kind==3?41:36;left_third=kind==3?45:kind==4?39:40;left_fifth=kind==3?48:43;
            midi('h90,left_root,v);midi('h90,left_third,v);midi('h90,left_fifth,v);
            repeat(1000)@(negedge clk);
            if(dut.lh_root!=(kind==3?5:0)||dut.lh_minor!=(kind==4))$fatal(1,"LH major/minor recognition");
            for(s=0;s<64;s=s+1)begin
                rh=72+(s%3)*2;
                if(kind==2)begin
                    midi('h90,rh,v);repeat(STEP/2-2)@(negedge clk);
                    midi('h80,rh,0);repeat(STEP/2-2)@(negedge clk);
                end else if(kind==5)begin
                    if(s%8==0)begin
                        midi('h90,72,v);repeat(STEP/4-2)@(negedge clk);midi('h80,72,0);
                        repeat(STEP*3/4-2)@(negedge clk);
                    end else repeat(STEP)@(negedge clk);
                end else begin
                    if(s%8==0)midi('h90,72,v);
                    if(s%8==6)midi('h80,72,0);
                    repeat(STEP-(s%8==0||s%8==6?2:0))@(negedge clk);
                end
            end
            midi('h80,72,0);midi('h80,left_root,0);midi('h80,left_third,0);midi('h80,left_fifth,0);
            repeat(STEP*6+10000)@(negedge clk);
            if(dut.armed||held_note!=-1||status[2:1]!=0)$fatal(1,"FOLLOW did not finish within one beat + processing margin");
            if(dut.lh_root!=(kind==3?5:0)||dut.lh_minor!=(kind==4))$fatal(1,"sequential chord release changed latched harmony");
            if(status[31:16]!=0)$fatal(1,"missed decision deadline");
            if(ons<8||ons!=offs)$fatal(1,"event accounting / no accompaniment");
            if(first_note!=(kind==3?41:36))$fatal(1,"first bass did not follow LH harmony");
            attacks[kind]=ons;velocity_sum[kind]=vel_sum;duration_sum[kind]=gate_sum;
            $display("PAIR case=%0d attacks=%0d mean_velocity=%0d mean_gate_clocks=%0d",kind,ons,vel_sum/ons,gate_sum/ons);
            cfg('h3f0,0);repeat(10000)@(negedge clk);
        end
        if(velocity_sum[1]/attacks[1] <= velocity_sum[0]/attacks[0]+30)$fatal(1,"soft/hard expression not audible enough");
        if(attacks[2]*4 < attacks[0]*5)$fatal(1,"dense rhythm failed to increase attack activity");
        if(duration_sum[5]/attacks[5] >= duration_sum[0]/attacks[0])$fatal(1,"staccato failed to shorten gates");
        setup(6,3);midi('h90,72,90);midi('hb0,64,127);midi('h80,72,0);
        repeat(STEP*7)@(negedge clk);
        if(!dut.armed||!dut.held[72])$fatal(1,"pedal failed to retain performer activity");
        midi('hb0,64,0);repeat(STEP*6)@(negedge clk);
        if(dut.armed||held_note!=-1)$fatal(1,"pedal release left bass hung");
        setup(7,2);repeat(STEP*24)@(negedge clk);
        if(ons<4)$fatal(1,"CONTINUE cannot play without input");
        midi('hb0,123,0);repeat(12000)@(negedge clk);
        if(!status[3]||status[0]||held_note!=-1)$fatal(1,"panic failed");
        $fclose(fd);
        $display("PASS V2 paired actual RTL: soft/hard, sparse/dense, C/F, major/minor, legato/staccato, silent start, release tail, sustain pedal, CONTINUE, panic and zero missed steps");$finish;
    end
    initial begin #1000000000;$fatal(1,"paired responsiveness timeout");end
endmodule
