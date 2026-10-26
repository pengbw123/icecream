`timescale 1ns/1ps
module tb_ai_bass_accompaniment;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,cfg_write=0,suspend=0,observe_valid=0,out_ready=1;
    reg [9:0] cfg_address=0;reg [15:0] cfg_value=0;
    reg [31:0] observe_data=0;wire [31:0] out_data,status;wire out_valid;
    ai_bass_accompaniment #(.CLOCKS_PER_US(1)) dut(.*);
    integer ons=0,offs=0,held_note=-1,n,i,old_phase;
    reg stalled=0;reg [31:0] stalled_data;
    always @(negedge clk) if($test$plusargs("debug")&&reset_n&&(dut.step_tick||dut.infer_start||dut.infer_done))
        $display("DBG step=%b start=%b done=%b state=%d rem=%d phase=%d active=%b off=%b on=%b head=%d/%d gate=%d snap=%d/%d settings=%h",
          dut.step_tick,dut.infer_start,dut.infer_done,dut.build_state,dut.remaining,dut.phase,dut.active,dut.off_pending,dut.on_pending,dut.articulation,dut.degree,dut.gate_class,dut.snapshot_root,dut.snapshot_phase,dut.settings);
    always @(negedge clk) if($test$plusargs("debug")&&dut.step_tick)
        $display("GUARD busy=%b outvalid=%b enabled=%b",dut.infer_busy,dut.out_valid,dut.enabled);
    always @(posedge clk)if(reset_n)begin
        if(stalled&&out_valid&&out_data!==stalled_data)$fatal(1,"AI output changed under backpressure");
        // STOP may explicitly cancel an unaccepted NoteOn.
        stalled<=out_valid&&!out_ready;stalled_data<=out_data;
        if(out_valid&&out_ready)begin
            if(out_data[31:24]!==8'h40)$fatal(1,"AI escaped BACKING tag");
            if(out_data[23:16]==8'h90)begin
                if(held_note!=-1)$fatal(1,"AI overlapped monophonic notes");
                if(out_data[14:8]<31||out_data[14:8]>59||out_data[6:0]!=70)$fatal(1,"AI note range/velocity");
                held_note=out_data[14:8];ons=ons+1;
            end else if(out_data[23:16]==8'h80)begin
                if(held_note!=-1&&out_data[14:8]!=held_note)$fatal(1,"Wrong AI NoteOff");
                held_note=-1;offs=offs+1;
            end else $fatal(1,"Unexpected AI MIDI");
        end
    end
    task cfg(input [9:0] a,input [15:0] v);
        begin @(negedge clk);cfg_address=a;cfg_value=v;cfg_write=1;@(negedge clk);cfg_write=0;end
    endtask
    task midi(input [31:0] v);
        begin @(negedge clk);observe_data=v;observe_valid=1;@(negedge clk);observe_valid=0;end
    endtask
    task stopped;
        begin
            repeat(10000)@(negedge clk);
            if(status[2:0]!=0||held_note!=-1)$fatal(1,"AI STOP left active/pending/busy %h note %d",status,held_note);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);reset_n=1;
        cfg(10'h3f1,10000);cfg(10'h3f2,0);cfg(10'h3f0,(70<<9)|5);
        midi(32'h00903c64);midi(32'h00903c64);
        if($countones(dut.held)!=1)$fatal(1,"Duplicate human NoteOn inflated held count");
        midi(32'h00903c00);
        if(dut.held!=0)$fatal(1,"Zero velocity NoteOn failed release");
        for(n=0;n<64;n=n+1)begin
            midi(32'h00903c64|(n%12)<<8);repeat(3000)@(negedge clk);
            midi(32'h00803c00|(n%12)<<8);repeat(7000)@(negedge clk);
        end
        if(ons<2||status[31:16]!=0)$fatal(1,"No learned bass output / missed inference %d %h",ons,status);
        old_phase=dut.phase;cfg(10'h3f1,12000);cfg(10'h3f0,(70<<9)|5);
        if(dut.phase!=old_phase)$fatal(1,"Live timing edit reset transport");
        cfg(10'h3f0,0);stopped();
        cfg(10'h3f0,(70<<9)|1);repeat(20000)@(negedge clk);
        suspend=1;stopped();suspend=0;repeat(20000)@(negedge clk);
        midi(32'h00b07b00);repeat(10000)@(negedge clk);
        if(!status[3]||status[0]||held_note!=-1)$fatal(1,"External panic did not latch stop");
        cfg(10'h3f0,0);stopped();cfg(10'h3f0,(70<<9)|1);
        out_ready=0;wait(out_valid);repeat(30)@(negedge clk);out_ready=1;
        repeat(2)@(negedge clk);cfg(10'h3f0,0);stopped();
        $display("PASS trained bass events: %d on/%d off, same-note accounting, zero-velocity off, live tempo, scoped STOP, suspend, panic, backpressure; no deadline misses",ons,offs);$finish;
    end
    initial begin #100000000;$fatal(1,"AI accompaniment timeout ons=%d status=%h",ons,status);end
endmodule
