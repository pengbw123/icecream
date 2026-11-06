`timescale 1ns/1ps
module tb_key_plan_capability;
    reg clk=0;always #5 clk=~clk;reg reset_n=0,cap=0;wire tx,rx_valid;wire [7:0] rx_data;
    uart_status_reply #(.CLKS_PER_BIT(8),.CLK_HZ(100000),.SCORE_MAX_EVENTS(8192),.SYNTH_VOICE_COUNT(32),.ENABLE_KEY_PLAN(1)) dut(
        .clk(clk),.reset_n(reset_n),.valid(1'b0),.command(8'd0),.status(8'd0),.capability_valid(cap),.capability_nonce(32'h12345678),
        .reliable_valid(1'b0),.reliable_frame(256'd0),.reliable_ready(),.phone_valid(1'b0),.phone_frame(72'd0),.tx(tx),.overflow());
    uart_rx #(.CLKS_PER_BIT(8)) monitor(.clk(clk),.reset_n(reset_n),.rx(tx),.data(rx_data),.valid(rx_valid),.busy());
    reg [7:0] data[0:19];integer n=0;reg [7:0] sum=0;
    always @(posedge clk)if(rx_valid)begin data[n]=rx_data;n++;end
    initial begin
        repeat(4)@(negedge clk);reset_n=1;@(negedge clk);cap=1;@(negedge clk);cap=0;
        wait(n==20);for(int i=2;i<20;i++)sum^=data[i];
        if(data[0]!='ha5||data[1]!='h5a||data[2]!='hf1||data[4]!='h57||
           data[5]!='h78||data[6]!='h56||data[7]!='h34||data[8]!='h12||data[9]!=0||data[10]!=32||
           data[11]!=32||data[12]!=8||data[13]!=5||data[18]!=1||sum!=0)$fatal(1,"capability frame mismatch flag=%h xor=%h",data[13],sum);
        $display("KEY_PLAN_CAPABILITY_OK flags=5 capacity=8192 voices=32 nonce/xor");$finish;
    end
    initial begin #1000000;$fatal(1,"capability timeout");end
endmodule
