`timescale 1ns/1ps
module tb_i2s_output_select;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,select_hp=0;
    reg [15:0] left=16'h8123,right=16'h5a96;
    wire tick,bclk,lrclk,speaker,hp;
    i2s_tx #(.BCLK_HALF_DIV(2),.OUTPUT_SELECT_ENABLED(1)) dut(
        .clk(clk),.reset_n(reset_n),.headphone_select(select_hp),.headphone_din(hp),
        .sample_left(left),.sample_right(right),.sample_tick(tick),
        .i2s_bclk(bclk),.i2s_lrclk(lrclk),.i2s_din(speaker));
    integer slot,frame;reg expected;
    task check_frame(input route);
        begin
            @(posedge tick);
            for(slot=0;slot<64;slot=slot+1)begin
                @(negedge bclk);#1;
                expected=0;
                if(slot>=1&&slot<=16)expected=left[16-slot];
                if(slot>=33&&slot<=48)expected=right[48-slot];
                if(speaker!==(route?1'b0:expected)||hp!==(route?expected:1'b0))
                    $fatal(1,"route=%0d slot=%0d speaker=%b hp=%b expected=%b",route,slot,speaker,hp,expected);
                if(slot==10)select_hp=!route; // switching mid-frame must not tear bits
            end
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);reset_n=1;
        check_frame(0);check_frame(1);check_frame(0);
        $display("PASS I2S exclusive speaker/headphone, stereo bits, padding and frame-boundary switching");$finish;
    end
    initial begin #1000000;$fatal(1,"I2S routing timeout");end
endmodule
