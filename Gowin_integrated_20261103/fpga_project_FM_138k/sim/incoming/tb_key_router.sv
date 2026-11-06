`timescale 1ns/1ps
module tb_key_router;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,enabled=0,disconnect=0,in_valid=0,out_ready=1;
    reg [6:0] first_key=48;reg [24:0] target_valid=0;reg [174:0] target_notes=0;
    reg [31:0] in_data=0;wire [31:0] out_data;wire in_ready,out_valid,busy;
    reg [31:0] seen[0:31];integer count=0;
    score_key_router dut(.clk(clk),.reset_n(reset_n),.enabled(enabled),.first_key(first_key),
        .target_valid(target_valid),.target_notes(target_notes),.disconnect(disconnect),
        .in_data(in_data),.in_valid(in_valid),.in_ready(in_ready),.out_data(out_data),.out_valid(out_valid),.out_ready(out_ready),.busy(busy));
    always @(posedge clk)if(reset_n&&out_valid&&out_ready)begin seen[count]=out_data;count=count+1;end
    task automatic tick;@(posedge clk);#1;endtask
    task automatic send(input int note,input bit down);
        @(negedge clk);in_data={8'd0,down?8'h90:8'h80,8'(note),down?8'd100:8'd0};in_valid=1;
        while(!in_ready)tick();tick();
        @(negedge clk);in_valid=0;repeat(2)tick();
    endtask
    function automatic bit istag(input reg[31:0] d,input int index,input int pitch,input bit down);
        return d[29]&&!d[31]&&!d[30]&&!d[28]&&{d[16],d[27:24]}==index&&
               d[14:8]==pitch&&d[23:20]==(down?4'h9:4'h8);
    endfunction
    initial begin
        repeat(3)tick();@(negedge clk);reset_n=1;enabled=1;
        target_valid[1]=1;target_notes[1*7+:7]=67;target_valid[20]=1;target_notes[20*7+:7]=67;
        repeat(3)tick();send(49,1);send(68,1);
        if(count!=2||!istag(seen[0],1,67,1)||!istag(seen[1],20,67,1))$fatal(1,"distinct tagged simultaneous pitches");
        send(49,1);if(count!=2)$fatal(1,"duplicate press accepted");
        target_notes[1*7+:7]=72;target_valid[1]=0;enabled=0;first_key=0;
        send(49,0);send(68,0);
        if(count!=4||!istag(seen[2],1,67,0)||!istag(seen[3],20,67,0))$fatal(1,"release did not retain original pitch/key after stop or base change");
        enabled=1;first_key=48;target_valid[1]=1;target_notes[1*7+:7]=60;target_valid[20]=1;target_notes[20*7+:7]=72;
        repeat(3)tick();out_ready=0;send(49,1);
        if(!out_valid||!istag(out_data,1,60,1))$fatal(1,"backpressure failed to retain event");
        repeat(7)tick();if(!out_valid||!istag(out_data,1,60,1))$fatal(1,"output changed while stalled");
        out_ready=1;repeat(3)tick();send(68,1);if(count!=6)$fatal(1,"stall lost or duplicated an event");
        @(negedge clk);disconnect=1;@(negedge clk);disconnect=0;enabled=0;
        repeat(80)tick();if(busy||count!=8||!istag(seen[6],1,60,0)||!istag(seen[7],20,72,0))$fatal(1,"disconnect did not release each captured pitch");
        send(60,1);if(count!=9||seen[8]!==32'h00903c64)$fatal(1,"legacy passthrough changed");
        $display("KEY_ROUTER_OK identity, held pitch, duplicate, stall, stop, disconnect, passthrough");$finish;
    end
    initial begin #500000;$fatal(1,"router timeout");end
endmodule
