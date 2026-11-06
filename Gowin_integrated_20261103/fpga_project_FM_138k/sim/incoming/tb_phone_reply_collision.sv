`timescale 1ns/1ps
module tb_phone_reply_collision;
    reg clk=0;always #10 clk=~clk;reg reset_n=0,valid=0,phone_valid=0;
    reg [7:0] command=8'h75,status=0;reg [71:0] phone_frame;
    wire tx,overflow;wire [7:0] rx_data;wire rx_valid;
    uart_status_reply #(.CLKS_PER_BIT(8),.ENABLE_PHONE(1)) dut(.clk(clk),.reset_n(reset_n),.valid(valid),.command(command),.status(status),
        .capability_valid(1'b0),.capability_nonce(32'd0),.reliable_valid(1'b0),.reliable_frame(256'd0),.reliable_ready(),
        .phone_valid(phone_valid),.phone_frame(phone_frame),.tx(tx),.overflow(overflow));
    uart_rx #(.CLKS_PER_BIT(8)) monitor(.clk(clk),.reset_n(reset_n),.rx(tx),.data(rx_data),.valid(rx_valid),.busy());
    reg [7:0] bytes[0:31];integer count=0;
    always @(posedge clk)if(rx_valid)begin bytes[count]=rx_data;count=count+1;end
    initial begin
        phone_frame={8'hf4^8'h78^8'h00^8'ha5^8'h5a^8'h33,8'h33,16'h5aa5,8'h00,8'h78,8'hf4,8'h5a,8'ha5};
        repeat(5)@(negedge clk);reset_n=1;
        @(negedge clk);valid=1;phone_valid=1;
        @(negedge clk);valid=0;phone_valid=0;
        wait(count==15);@(negedge clk);
        if(bytes[0]!='ha5||bytes[1]!='h5a||bytes[2]!='hf0||bytes[3]!='h75||bytes[4]!=0||bytes[5]!=('hf0^'h75))
            $fatal(1,"legacy reply lost in collision");
        if(bytes[6]!='ha5||bytes[7]!='h5a||bytes[8]!='hf4||bytes[9]!='h78||bytes[10]!=0||bytes[11]!='ha5||bytes[12]!='h5a||bytes[13]!='h33||bytes[14]!=('hf4^'h78^'ha5^'h5a^'h33))
            $fatal(1,"phone reply lost or corrupted in collision");
        if(overflow)$fatal(1,"unexpected reply overflow");
        $display("PHONE_REPLY_COLLISION_OK legacy+phone simultaneous, embedded header bytes, FIFO ordering");$finish;
    end
    initial begin #1000000;$fatal(1,"reply timeout");end
endmodule
