`timescale 1ns/1ps
// Checks the envelope preview panel geometry and pipeline alignment.
module tb_eg_curve;
    reg pclk = 0;
    always #15 pclk = ~pclk;      // 33.3 MHz
    reg wclk = 0;
    always #10 wclk = ~wclk;      // 50 MHz
    reg reset_n = 0;
    reg [10:0] h = 0;
    reg [9:0]  v = 0;
    reg enable = 1;
    reg we = 0;
    reg [7:0] waddr = 0;
    reg [8:0] wdata = 0;
    wire ink;
    wire [1:0] cls;

    ui_eg_curve dut(.pclk(pclk), .video_reset_n(reset_n), .h(h), .v(v), .enable(enable),
        .wclk(wclk), .we(we), .waddr(waddr), .wdata(wdata), .ink(ink), .cls(cls));

    task wr(input [7:0] a, input [8:0] d);
        begin
            @(posedge wclk) begin waddr <= a; wdata <= d; we <= 1'b1; end
            @(posedge wclk) we <= 1'b0;
        end
    endtask

    task check(input [9:0] px, input [9:0] py, input [1:0] exp_cls, input [127:0] name);
        begin
            h = px; v = py;
            repeat (4) @(posedge pclk);
            if (cls !== exp_cls)
                $fatal(1, "%0s: class %0d expected %0d", name, cls, exp_cls);
        end
    endtask

    integer i;
    initial begin
        repeat (4) @(posedge pclk);
        reset_n = 1;
        repeat (4) @(posedge pclk);
        // flat top level: panel fully filled, top edge highlighted
        for (i = 0; i < 192; i = i + 1) wr(i[7:0], 9'd255);
        repeat (4) @(posedge pclk);
        check(10'd640, 10'd120, 2'd1, "fill");
        check(10'd640, 10'd96,  2'd2, "edge");
        check(10'd640, 10'd90,  2'd0, "outside");
        // flat bottom level: only the baseline row, grid visible above it
        for (i = 0; i < 192; i = i + 1) wr(i[7:0], 9'd0);
        repeat (4) @(posedge pclk);
        check(10'd646, 10'd300, 2'd0, "not-filled");
        check(10'd646, 10'd351, 2'd2, "baseline");
        check(10'd640, 10'd160, 2'd3, "grid");
        // disabled panel draws nothing
        enable = 0;
        repeat (4) @(posedge pclk);
        check(10'd646, 10'd351, 2'd0, "disabled");
        $display("PASS envelope curve panel fill/edge/grid/disable");
        $finish;
    end
endmodule



