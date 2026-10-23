`timescale 1ns/1ps
module tb_lesson_loader;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0;
    tri1 scl,sda,intpin;
    wire [31:0] event_word,state;wire valid,bank;
    wire [7:0] count;
    touch_ui_controller dut(.clk(clk),.reset_n(reset_n),.tp_scl(scl),.tp_sda(sda),.tp_int(intpin),
        .midi_event_data(event_word),.midi_event_valid(valid),.midi_event_ready(1'b1),
        .monitor_event(32'd0),.monitor_event_valid(1'b0),.preset_index(7'd0),.algorithm(5'd0),.active_voices(5'd0),
        .command_ready(1'b1),.fx_read_value(32'd0),.patch_read_data(16'd0),.patch_read_valid(1'b0),
        .lesson_state(state),.lesson_bank(bank),.lesson_count(count));
    defparam dut.u_lesson.CLOCKS_PER_MS=1;
    reg [31:0] addr=0,wd=0;reg [1:0] req=2;
    task wr(input integer index,input [31:0] value);begin
        @(negedge clk);addr=32'h23000000+index*4;wd=value;req=1;
        @(negedge clk);req=2;repeat(3)@(negedge clk);
    end endtask
    initial begin
        force dut.address=addr;force dut.write_data=wd;force dut.request=req;
        #100;reset_n=1;
        wr(31,1);wr(32,0);wr(33,{16'd4,9'd8,7'd72});
        if(dut.upload_count!=1||dut.upload_error)$fatal(1,"Valid upload rejected count=%d err=%b uploading=%b entryok=%b state=%h addr=%h req=%b",dut.upload_count,dut.upload_error,dut.uploading,dut.entry_ok,state,dut.address,dut.request);
        wr(28,32'h640f);if(state[16])$fatal(1,"Playback started before commit");
        wr(34,32'h00100001);
        if(!bank||count!=1||dut.uploading)$fatal(1,"Commit metadata invalid");
        wr(28,32'h640f);wait(valid);
        if(event_word!==32'h80904860)$fatal(1,"Uploaded score did not play");
        wr(31,1);if(dut.uploading)$fatal(1,"Upload allowed during playback");
        wr(28,0);repeat(10)@(negedge clk);
        wr(31,1);wr(32,0);wr(33,{16'd0,9'd8,7'd40});
        if(!dut.upload_error)$fatal(1,"Out-of-range note accepted");
        wr(34,32'h00100001);if(!dut.uploading)$fatal(1,"Errored upload committed");
        wr(31,1);wr(32,1);wr(33,{16'd0,9'd8,7'd60});
        if(!dut.upload_error)$fatal(1,"Non-contiguous upload accepted");
        wr(31,1);wr(32,0);wr(33,{16'd0,9'd8,7'd60});
        wr(32,1);wr(33,{16'd4,9'd8,7'd64});
        if(!dut.upload_error)$fatal(1,"Polyphonic overlap accepted by monophonic loader");
        wr(31,2);if(bank||count!=42||dut.uploading)$fatal(1,"Factory restore invalid");
        wr(28,32'h640f);wait(valid);
        if(event_word[14:8]!=60)$fatal(1,"Factory ROM corrupted by upload");
        $display("PASS lesson upload commit/range/order/overlap/isolation/factory restore");$finish;
    end
    initial begin #10000000;$fatal(1,"Loader timeout");end
endmodule
