`timescale 1ns/1ps
module tb_audio_performance_monitor;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,tick=0,busy=0,pending=0,start=0,done=0,steal=0,accept=0,stall=0,drop=0;
    reg snapshot=0,clear_stats=0;
    reg [4:0] index=0;reg [7:0] voices=0;reg signed [15:0] pcm=0;
    wire [31:0] data;
    audio_performance_monitor dut(.clk(clk),.reset_n(reset_n),.sample_tick(tick),
        .engine_busy(busy),.sample_pending(pending),.render_start(start),.render_done(done),
        .voice_steal(steal),.midi_accept(accept),.midi_stall(stall),.bridge_drop(drop),
        .active_voices(voices),.audio_sample(pcm),.snapshot(snapshot),.clear_stats(clear_stats),
        .read_index(index),.read_data(data));
    task step;begin @(posedge clk);#1;@(negedge clk);end endtask
    task snap;begin snapshot=1;step();snapshot=0;end endtask
    task check(input [4:0] i,input [31:0] value);begin
        index=i;#1;if(data!==value)$fatal(1,"word %d actual=%h expected=%h",i,data,value);
    end endtask
    initial begin
        repeat(3)step();reset_n=1;step();snap();check(0,32'h50455231);check(2,1024);
        // Tick -> two wait clocks -> consume -> four compute clocks -> done.
        tick=1;pcm=-32768;step();tick=0;pending=1;busy=1;
        accept=1;voices=3;step();accept=0;stall=1;step();stall=0;
        start=1;step();start=0;pending=0;
        repeat(3)step();done=1;step();done=0;busy=0;
        snap();check(4,1);check(5,{16'd4,16'd4});check(6,{16'd7,16'd7});
        check(8,0);check(9,0);check(12,1);check(13,{16'd16,8'd3,8'd3});check(14,1);check(15,32768);
        // Snapshot stays stable despite live activity; coincident events count once.
        steal=1;drop=1;accept=1;step();steal=0;drop=0;accept=0;
        check(10,0);check(11,0);check(12,1);
        snap();check(10,1);check(11,1);check(12,2);
        // A request still pending at the next tick is both late and coalesced.
        tick=1;step();tick=0;pending=1;step();tick=1;step();tick=0;
        snap();check(8,1);check(9,1);
        // CLEAR never changes playback inputs and leaves the held snapshot alone.
        clear_stats=1;step();clear_stats=0;check(8,1);snap();check(8,0);check(9,0);check(10,0);check(11,0);
        // Clear in-flight, then complete. Timing remains tied to the original tick.
        start=1;busy=1;step();start=0;pending=0;step();clear_stats=1;step();clear_stats=0;
        done=1;step();done=0;busy=0;snap();check(4,1);check(5,{16'd3,16'd3});
        // Production-width counters saturate rather than wrapping to zero.
        @(negedge clk);dut.steals=32'hffffffff;steal=1;step();steal=0;snap();check(10,32'hffffffff);
        index=31;#1;if(data!==0)$fatal(1,"Out-of-range word did not read zero");
        clear_stats=1;step();clear_stats=0;pending=0;busy=0;
        tick=1;step();tick=0;repeat(2)step();busy=1;repeat(3)step();busy=0;repeat(2)step();tick=1;step();tick=0;
        snap();check(3,8);check(7,{16'd3,16'd3});
        // A result committed on the DAC latch edge misses that deadline,
        // although there is no overwritten pending request.
        pending=1;start=1;busy=1;step();start=0;pending=0;step();tick=1;done=1;step();tick=0;done=0;busy=0;
        snap();check(8,1);check(9,0);
        $display("PASS telemetry timing, snapshots, deadlines, lost ticks, clear-in-flight and saturation");$finish;
    end
    initial begin #1000000;$fatal(1,"Timeout");end
endmodule
