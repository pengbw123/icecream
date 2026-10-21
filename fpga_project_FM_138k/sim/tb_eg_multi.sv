`timescale 1ns/1ps
module tb_eg_multi;
    reg pclk=0, wclk=0; always #10 pclk=~pclk; always #10 wclk=~wclk;
    reg reset_n=0;
    reg [10:0] h=0; reg [9:0] v=0;
    reg enable=1;
    reg we=0; reg [9:0] waddr=0; reg [7:0] wdata=0;
    wire ink; wire [2:0] cls;
    ui_eg_multi dut(.pclk(pclk),.video_reset_n(reset_n),.h(h),.v(v),
        .enable(enable),.wclk(wclk),.we(we),.waddr(waddr),.wdata(wdata),
        .ink(ink),.cls(cls));

    task wr(input [9:0] a, input [7:0] d);
        begin
            @(posedge wclk) begin waddr<=a; wdata<=d; we<=1'b1; end
            @(posedge wclk) we<=1'b0;
        end
    endtask

    task pixel(input [10:0] x, input [9:0] y, output [2:0] c, output i);
        begin
            h=x; v=y;
            repeat (4) @(posedge pclk);
            c=cls; i=ink;
        end
    endtask

    integer n; reg [2:0] c; reg i;
    initial begin
        repeat (5) @(posedge pclk);
        reset_n=1;
        for(n=0;n<768;n=n+1) wr(n[9:0], 8'd0);
        repeat (4) @(posedge pclk);

        pixel(16,176,c,i);
        if(!i||c!==3'd1) $fatal(1,"frame cls=%0d ink=%b",c,i);
        pixel(16+120,269,c,i);
        if(!i||c!==3'd2) $fatal(1,"curve cls=%0d ink=%b",c,i);
        pixel(16+120,275,c,i); if(!i||c!==3'd3) $fatal(1,"fill cls=%0d ink=%b",c,i);
        pixel(16+120,204,c,i); if(!i||c!==3'd4) $fatal(1,"grid cls=%0d ink=%b",c,i);
        pixel(16+120,200,c,i); if(i) $fatal(1,"outside curve should be transparent");

        wr(10'd2*128+63, 8'd255);
        repeat (4) @(posedge pclk);
        pixel(528+120,182,c,i);
        if(!i||c!==3'd2) $fatal(1,"tall curve cls=%0d ink=%b",c,i);

        enable=0;
        pixel(16+120,275,c,i); if(i) $fatal(1,"disabled canvas still inks");

        $display("PASS six-panel EG canvas frame/curve/fill/grid/disable");
        $finish;
    end
endmodule
