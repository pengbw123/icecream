`timescale 1ns/1ps
module tb_scope_touch_latency;
    parameter integer HALF_DIV=8,QUIET=32,PULSE=50000;
    localparam integer PERIOD=128*HALF_DIV;
    localparam integer TIMEOUT=PERIOD*4;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,enable=1,valid=0,ready=1,headphone=0;
    reg [31:0] data=0;
    reg [7:0] voices=0;
    reg signed [15:0] sample=0;
    wire bclk,lrclk,din,hdin,tick,start_pin,done_pin;
    i2s_tx #(.BCLK_HALF_DIV(HALF_DIV),.OUTPUT_SELECT_ENABLED(1)) tx(
        .clk(clk),.reset_n(reset_n),.headphone_select(headphone),.headphone_din(hdin),
        .sample_left(sample),.sample_right(sample),.sample_tick(tick),
        .i2s_bclk(bclk),.i2s_lrclk(lrclk),.i2s_din(din));
    scope_touch_latency #(.QUIET_FRAMES(QUIET),.PULSE_CLOCKS(PULSE),.TIMEOUT_CLOCKS(TIMEOUT)) dut(
        .clk(clk),.reset_n(reset_n),.enable(enable),.event_valid(valid),.event_ready(ready),
        .event_data(data),.active_voices(voices),.bclk(bclk),.lrclk(lrclk),
        .serial_data(din|hdin),.start_marker(start_pin),.done_marker(done_pin));
    integer clocks=0,starts=0,dones=0,checks=0;
    time start_time=0,done_time=0,physical_word_time=0;
    reg [15:0] physical_shift=0;
    // Independent receiver samples at physical BCLK edges. LRCLK is observed
    // separately; wait a full frame after reset before qualification checks.
    integer physical_bit=-1;reg physical_aligned=0;
    always @(negedge lrclk) if(reset_n)begin physical_aligned=1;physical_bit=0;physical_shift=0;end
    always @(posedge bclk) if(reset_n && physical_aligned && !lrclk)begin
        if(physical_bit>0 && physical_bit<=16)begin
            physical_shift={physical_shift[14:0],din|hdin};
            if(physical_bit==16 && ($signed(physical_shift)>32 || $signed(physical_shift)<-32))
                physical_word_time=$time;
        end
        physical_bit=physical_bit+1;
    end
    always @(posedge clk) clocks<=clocks+1;
    always @(posedge start_pin)begin starts=starts+1;start_time=$time;end
    always @(posedge done_pin)begin
        dones=dones+1;done_time=$time;
        if(done_time-physical_word_time!=20)$fatal(1,"Done is not exactly 20 ns after the physical last data-bit edge: %0d",done_time-physical_word_time);
    end
    task ck(input bit condition,input string label_text);
        begin if(!condition)$fatal(1,"FAIL %s",label_text);checks=checks+1;end
    endtask
    task cycles(input integer n);repeat(n)@(negedge clk);endtask
    task reset_all;
        begin
            @(negedge clk);reset_n=0;valid=0;ready=1;enable=1;voices=0;sample=0;
            physical_aligned=0;physical_bit=-1;
            cycles(4);reset_n=1;cycles(PERIOD*(QUIET+3));
            ck(dut.qualified,"quiet qualification after real I2S frames");
        end
    endtask
    task event_packet(input [31:0] packet,input integer stall);
        begin
            @(negedge clk);valid=1;data=packet;ready=(stall==0);
            if(stall!=0)begin
                cycles(stall);ck(!start_pin,"stalled valid must not mark accepted input");ready=1;
            end
            @(negedge clk);valid=0;
        end
    endtask
    task success(input signed [15:0] value,input integer stall);
        integer a,b;
        begin
            reset_all();a=starts;b=dones;
            event_packet(32'h00903c64,stall);
            ck(starts==a+1,"one accepted NoteOn start marker");
            voices=1;cycles(15);sample=value;
            cycles(PERIOD*3);
            ck(dones==b+1,"one qualified transmitted audio completion");
            ck(done_time>start_time,"causal positive latency");
            ck(!dut.pending,"completed measurement disarmed");
            cycles(PULSE+1);
            ck(!start_pin&&!done_pin,"both marker pulses expire including production 1 ms width");
        end
    endtask
    integer a,b;
    initial begin
        success(16'sd1000,0);
        success(-16'sd1000,0);
        success(-16'sd32768,11);
        headphone=1;success(16'sd33,0); // The other physical I2S output route.
        success(-16'sd33,0);
        reset_all();a=starts;b=dones;
        event_packet(32'h00803c00,0);event_packet(32'h00903c00,0);
        event_packet(32'h80903c64,0);event_packet(32'h00b01464,0);
        cycles(PERIOD);ck(starts==a&&dones==b,"off, zero velocity, backing and CC ignored");
        reset_all();a=starts;voices=1;event_packet(32'h00903c64,0);
        ck(starts==a,"existing active voice rejects attribution");
        reset_all();a=starts;enable=0;event_packet(32'h00903c64,0);
        ck(starts==a,"disabled mode does not start");
        reset_all();a=starts;sample=16'sd33;cycles(PERIOD*2);
        event_packet(32'h00903c64,0);ck(starts==a,"nonquiet output rejects attribution");
        reset_all();a=starts;b=dones;sample=16'sd32;cycles(PERIOD*2);
        event_packet(32'h00903c64,0);voices=1;cycles(PERIOD*3);
        ck(starts==a+1&&dones==b,"positive threshold is quiet, not onset");
        cycles(TIMEOUT);sample=16'sd200;cycles(PERIOD*2);
        ck(dones==b&&!dut.pending,"timeout cannot create a false completion later");
        reset_all();b=dones;event_packet(32'h00903c64,0);voices=1;
        event_packet(32'h00904064,0);sample=16'sd200;cycles(PERIOD*2);
        ck(dones==b&&!dut.pending,"overlapping NoteOn cancels without success");
        reset_all();b=dones;event_packet(32'h00903c64,0);enable=0;
        sample=16'sd200;cycles(PERIOD*2);
        ck(dones==b&&!dut.pending,"mode interruption cancels without success");
        reset_all();b=dones;event_packet(32'h00903c64,0);voices=2;
        sample=16'sd200;cycles(PERIOD*2);
        ck(dones==b&&!dut.pending,"multiple active voices cancel onset attribution");
        reset_all();event_packet(32'h00903c64,0);reset_n=0;cycles(2);
        ck(!start_pin&&!done_pin&&!dut.pending,"reset clears markers and pending");
        $display("PASS scope_touch_latency HALF_DIV=%0d checks=%0d starts=%0d completions=%0d",HALF_DIV,checks,starts,dones);
        $finish;
    end
    initial begin #100000000;$fatal(1,"simulation watchdog");end
endmodule
