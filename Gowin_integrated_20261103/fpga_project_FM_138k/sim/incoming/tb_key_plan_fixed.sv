`timescale 1ns/1ps
// Fixed-tempo mapped playback consumes the real short App fixture.
module tb_key_plan_fixed;
    reg clk=0;always #5 clk=~clk;reg reset_n=0,cmd_valid=0;reg [7:0] cmd=0;reg [63:0] payload=0;
    wire done,error,loaded,playing,flushing,mapped;wire [127:0] mask;wire [24:0] valid;wire [174:0] pitches;
    reg [95:0] frames[0:10];
    score_player #(.CLK_HZ(10000),.RAM_DEPTH(2048),.MAX_EVENTS(2048),.ENABLE_KEY_PLAN(1)) dut(
        .clk(clk),.reset_n(reset_n),.cmd_valid(cmd_valid),.cmd_command(cmd),.cmd_payload(payload),.score_done(done),.score_error(error),
        .midi_event_data(),.midi_event_valid(),.midi_event_ready(1'b1),.volume_event_data(),.volume_event_valid(),.volume_event_ready(1'b1),
        .fresh_key_valid(1'b0),.fresh_key_note(7'd0),.key_plan_allowed(1'b1),.key_plan_active(mapped),.key_plan_first(),.key_plan_valid(valid),.key_plan_notes(pitches),
        .guide_count_in(),.guide_beat_active(),.guide_mask(mask),.loaded(loaded),.playing(playing),.flush_active(flushing),.upload_crc32());
    task automatic tick;@(posedge clk);#1;endtask
    task automatic command(input reg [7:0] c,input reg [63:0] d);
        @(negedge clk);cmd=c;payload=d;cmd_valid=1;@(negedge clk);cmd_valid=0;
        while(!done&&!error)tick();if(error)$fatal(1,"command %h rejected",c);tick();
    endtask
    task automatic run_rate(input int rate,output int elapsed);
        command('h5a,{24'h315047,16'd500,8'd0,8'd0,8'(rate)});
        while(mask!==((128'd1<<67)|(128'd1<<55)))tick();
        if(!valid[19]||!valid[7]||pitches[19*7+:7]!=67||pitches[7*7+:7]!=67)$fatal(1,"initial mapped chord invalid");
        elapsed=0;while(!mask[72])begin tick();elapsed++;if(elapsed>20000)$fatal(1,"fixed mapped score timing stuck");end
        if(!valid[24]||pitches[24*7+:7]!=72||!valid[7])$fatal(1,"fixed mapped next key/overlap invalid");
        command('h54,0);while(playing||flushing)tick();
        if(valid!=0||mask!=0)$fatal(1,"stop left mapped guide active");
    endtask
    integer slow,fast;
    initial begin
        $readmemh("sim/app_keyplan_trace.mem",frames);repeat(4)tick();@(negedge clk);reset_n=1;
        for(int i=1;i<=8;i++)command(frames[i][16+:8],frames[i][24+:64]);
        if(!loaded)$fatal(1,"mapped fixture did not seal");
        run_rate(50,slow);run_rate(150,fast);
        if(slow<9900||slow>10200||fast<3200||fast>3500||slow<fast*2)$fatal(1,"fixed timing slow=%0d fast=%0d",slow,fast);
        $display("KEY_PLAN_FIXED_OK actual App frames speed50=%0d speed150=%0d",slow,fast);$finish;
    end
    initial begin #5000000;$fatal(1,"fixed-mode timeout");end
endmodule
