`timescale 1ns/1ps
module tb_step_sequencer;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,suspend=0,cw=0,aw=0,sw=0,clear=0,hv=0,ready=1;
    reg [31:0] control=0,sd=0,human=0;
    reg [6:0] address=0;
    wire [6:0] edit_address;wire [31:0] edit_data,status,midi;
    wire valid;
    reg [127:0] timing={32'd7000,32'd7000,32'd10000,32'd10000};
    step_sequencer #(.CLOCKS_PER_US(1)) dut(.clk(clk),.reset_n(reset_n),.suspend(suspend),
        .control_write(cw),.control_data(control),.timing_data(timing),
        .address_write(aw),.address_data(address),.read_address(address),.step_write(sw),.step_data(sd),.clear_pattern(clear),
        .edit_address(edit_address),.edit_data(edit_data),.human_event(human),.human_valid(hv),
        .midi_data(midi),.midi_valid(valid),.midi_ready(ready),.status(status));
    integer ons=0,offs=0,cycles=0;
    integer pitch[0:255],velocity[0:255],on_at[0:255],off_at[0:255];
    reg [127:0] sounding=0;
    always @(posedge clk)begin
        cycles=cycles+1;
        if(valid&&ready)begin
            if(midi[23:20]==9)begin
                if(!midi[31]||midi[6:0]==0||sounding[midi[14:8]])$fatal(1,"Bad sequence Note On");
                sounding[midi[14:8]]=1;pitch[ons]=midi[14:8];velocity[ons]=midi[6:0];on_at[ons]=cycles;ons=ons+1;
            end else if(midi[23:20]==8)begin
                if(!sounding[midi[14:8]])$fatal(1,"Sequence unowned Note Off");
                sounding[midi[14:8]]=0;off_at[offs]=cycles;offs=offs+1;
            end else $fatal(1,"Sequencer must not clear human notes with CC");
        end
    end
    task ctrl(input [31:0] word);
        begin @(negedge clk);control=word;cw=1;@(negedge clk);cw=0;end
    endtask
    task select_step(input [6:0] a);
        begin @(negedge clk);address=a;aw=1;@(negedge clk);aw=0;repeat(3)@(negedge clk);end
    endtask
    task write_step(input [6:0] a,input [31:0] w);
        begin select_step(a);sd=w;sw=1;@(negedge clk);sw=0;repeat(3)@(negedge clk);end
    endtask
    task record_note(input [7:0] st,input [6:0] n,input [6:0] v);
        begin @(negedge clk);human={8'd0,st,1'b0,n,1'b0,v};hv=1;@(negedge clk);hv=0;end
    endtask
    integer base_on,base_off,k;reg [31:0] stalled;
    initial begin #30000000;$fatal(1,"Sequencer timeout state=%0d status=%h",dut.state,status);end
    initial begin
        repeat(5)@(negedge clk);reset_n=1;wait(!status[2]);
        select_step(0);if(edit_data!==32'h8000603c)$fatal(1,"Factory pattern init");
        select_step(16);if(edit_data!==0)$fatal(1,"Other factory bank must be empty");
        ctrl(32'h3c1);wait(ons>=3);
        if(pitch[0]!=60||pitch[1]!=62||pitch[2]!=64||velocity[0]!=96)$fatal(1,"Factory playback");
        if(off_at[0]-on_at[0]<7000||off_at[0]-on_at[0]>7010)$fatal(1,"Sequence gate");
        ctrl(32'h3c0);wait(!status[2]&&!status[3]);if(sounding!=0)$fatal(1,"STOP stuck");
        write_step(16,32'h8000503c);write_step(17,32'h40000000);write_step(18,0);
        base_on=ons;base_off=offs;ctrl(32'h89);wait(offs>base_off);
        if(pitch[base_on]!=60||velocity[base_on]!=80)$fatal(1,"Manual step edit");
        if(off_at[base_off]-on_at[base_on]<20000||off_at[base_off]-on_at[base_on]>20040)$fatal(1,"Tie length");
        wait(ons>=base_on+2);if(on_at[base_on+1]-on_at[base_on]<30000)$fatal(1,"REST did not consume a step");
        ctrl(32'h88);wait(!status[2]&&!status[3]);
        // Four successive nonzero Note Ons enter four steps; Note Off is ignored.
        select_step(32);ctrl(32'hd2);
        record_note(8'h90,60,80);record_note(8'h80,60,0);record_note(8'h90,64,90);
        record_note(8'h90,67,70);record_note(8'h90,127,127);
        if(edit_address!=32)$fatal(1,"Record wrap / Note Off handling");
        write_step(32,0);if(!status[4])$fatal(1,"Manual edit during recording not rejected");
        ctrl(32'hd0);wait(!status[2]);select_step(32);
        if(edit_data!==32'h8000503c)$fatal(1,"Recorded note/velocity corrupted");
        select_step(35);if(edit_data!==32'h80007f7f)$fatal(1,"Full range recorded note");
        base_on=ons;ctrl(32'hd1);wait(ons>=base_on+4);
        if(pitch[base_on]!=60||pitch[base_on+1]!=64||pitch[base_on+2]!=67||pitch[base_on+3]!=127)$fatal(1,"Recorded pattern playback");
        // Pattern change uses a new bank at the next boundary, beginning at 0.
        base_on=ons;ctrl(32'h3c1);wait(ons>base_on);
        if(pitch[base_on]!=60)$fatal(1,"Pattern switch did not restart new bank");
        @(negedge clk);ready=0;wait(valid);stalled=midi;
        ctrl(32'h3c0);repeat(50)begin @(negedge clk);if(!valid||midi!==stalled)$fatal(1,"Stopped pending event changed");end
        ready=1;wait(!status[2]&&!status[3]);if(sounding!=0)$fatal(1,"Backpressure STOP stuck");
        ctrl(32'h3c1);wait(status[3]);@(negedge clk);suspend=1;
        wait(!status[3]&&!status[0]);repeat(5)@(negedge clk);suspend=0;
        wait(!status[2]);repeat(15000)@(negedge clk);if(status[0]||sounding!=0)$fatal(1,"Suspension restarted sequence");
        select_step(32);@(negedge clk);clear=1;@(negedge clk);clear=0;wait(!status[2]);
        for(k=32;k<48;k=k+1)begin select_step(k[6:0]);if(edit_data!==0)$fatal(1,"Pattern clear");end
        select_step(0);if(edit_data!==32'h8000603c)$fatal(1,"Clear corrupted other bank");
        ctrl(32'h3c1);wait(status[3]);record_note(8'hb0,123,0);
        wait(!status[0]&&!status[2]&&!status[3]);if(sounding!=0)$fatal(1,"External All Notes Off did not stop transport");
        $display("PASS sequencer factory/8 banks, looping, note/rest/tie, gate/velocity/range, record wrap, edit isolation, bank change, stalls, STOP and suspend");$finish;
    end
endmodule
