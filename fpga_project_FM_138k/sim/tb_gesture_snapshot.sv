`timescale 1ns/1ps
module tb_gesture_snapshot;
    reg clk=0,pixel_clk=0,run=1,reset_n=0,latch=0;
    always begin #10;if(run)clk=~clk;end
    always #13 pixel_clk=~pixel_clk;
    reg [323:0] source_data=0;wire [323:0] video_data;
    gesture_video_snapshot #(.WIDTH(324)) dut(clk,pixel_clk,reset_n,latch,source_data,video_data);
    task boundary;
        begin @(negedge pixel_clk);latch=1;@(negedge pixel_clk);latch=0;end
    endtask
    reg [323:0] expected;
    initial begin
        repeat(6)@(negedge pixel_clk);reset_n=1;repeat(8)@(negedge pixel_clk);
        run=0;source_data={4'h3,{4{64'h0123456789abcdef}},64'hdeadbeefcafebabe};
        boundary;repeat(30)@(negedge pixel_clk);
        if(video_data!==0)$fatal(1,"stopped source produced data");
        source_data=~source_data;expected=source_data;run=1;
        repeat(15)@(negedge pixel_clk);
        if(video_data!==0)$fatal(1,"acknowledgment changed active-frame data");
        boundary;if(video_data!==expected)$fatal(1,"wide coherent payload");
        source_data=0;repeat(15)@(negedge pixel_clk);
        if(video_data!==expected)$fatal(1,"active-frame tear");
        boundary;if(video_data!==0)$fatal(1,"second transaction");
        // Reset an outstanding request, including when source clock is stopped.
        run=0;boundary;reset_n=0;repeat(5)@(negedge pixel_clk);
        if(video_data!==0)$fatal(1,"reset with stopped source");
        run=1;reset_n=1;source_data={324{1'b1}};repeat(10)@(negedge pixel_clk);
        boundary;repeat(15)@(negedge pixel_clk);boundary;
        if(video_data!=={324{1'b1}})$fatal(1,"reset recovery");
        $display("PASS gesture_snapshot: 324-bit coherent CDC, delayed ack in active frame held until blank, stopped clock, pending reset/recovery");$finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
