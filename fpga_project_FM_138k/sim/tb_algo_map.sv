`timescale 1ns/1ps
// Checks the 2bpp algorithm-map canvas: addressing, colour classes and enable.
module tb_algo_map;
    reg pclk = 0;
    always #15 pclk = ~pclk;
    reg wclk = 0;
    always #10 wclk = ~wclk;
    reg reset_n = 0;
    reg [10:0] h = 0;
    reg [9:0]  v = 0;
    reg enable = 1;
    reg we = 0;
    reg [14:0] waddr = 0;
    reg [7:0]  wdata = 0;
    wire ink;
    wire [1:0] cls;

    ui_algo_map dut(.pclk(pclk), .video_reset_n(reset_n), .h(h), .v(v), .enable(enable),
        .wclk(wclk), .we(we), .waddr(waddr), .wdata(wdata), .ink(ink), .cls(cls));

    task wr(input [14:0] a, input [7:0] d);
        begin
            @(posedge wclk) begin waddr <= a; wdata <= d; we <= 1'b1; end
            @(posedge wclk) we <= 1'b0;
        end
    endtask

    // Program one 2bpp pixel.
    task put(input integer x, input integer y, input [1:0] c);
        reg [16:0] pix;
        reg [14:0] a;
        reg [7:0]  d;
        reg [1:0]  sh;
        begin
            pix = (y << 9) + x;
            a = pix[16:2];
            sh = pix[1:0];
            d = 8'h00;
            d[sh*2 + 1 -: 2] = c;
            wr(a, d);
        end
    endtask

    integer i;
    task check(input integer x, input integer y, input [1:0] exp_cls, input [127:0] name);
        begin
            h = x; v = y;
            repeat (4) @(posedge pclk);
            if (cls !== exp_cls)
                $fatal(1, "%0s: class %0d expected %0d", name, cls, exp_cls);
        end
    endtask

    initial begin
        repeat (4) @(posedge pclk);
        reset_n = 1;
        repeat (4) @(posedge pclk);
        for (i = 0; i < 8192; i = i + 1) wr(i[14:0], 8'd0);
        repeat (4) @(posedge pclk);
        put(0, 0, 2'd1);
        put(10, 20, 2'd2);
        put(511, 255, 2'd3);
        repeat (4) @(posedge pclk);
        check(144, 160, 2'd1, "class1");
        check(154, 180, 2'd2, "class2");
        check(655, 415, 2'd3, "class3");
        check(200, 200, 2'd0, "transparent");
        check(100, 160, 2'd0, "left-out");
        check(144, 100, 2'd0, "top-out");
        enable = 0;
        repeat (4) @(posedge pclk);
        check(144, 160, 2'd0, "disabled");
        $display("PASS algorithm map canvas pixels/classes/disable");
        $finish;
    end
endmodule

