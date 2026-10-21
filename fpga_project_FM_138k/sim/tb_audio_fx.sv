`timescale 1ns/1ps
// Checks the audio_fx register file, defaults, readback and exact dry bypass.
module tb_audio_fx;
    reg clk = 0;
    always #10 clk = ~clk;      // 50 MHz
    reg reset_n = 0;
    reg sample_tick = 0;
    reg signed [15:0] dry = 16'sd1234;
    reg cfg_write = 0;
    reg [5:0] cfg_addr = 0;
    reg [15:0] cfg_value = 0;
    reg [5:0] read_addr = 0;
    wire [15:0] read_value;
    wire signed [15:0] sample_out;

    audio_fx dut(.clk(clk), .reset_n(reset_n), .sample_tick(sample_tick),
        .dry_sample(dry), .cfg_write(cfg_write), .cfg_addr(cfg_addr),
        .cfg_value(cfg_value), .read_addr(read_addr),
        .read_value(read_value), .sample_out(sample_out));

    task wr(input [5:0] a, input [15:0] v);
        begin
            @(posedge clk) begin cfg_addr <= a; cfg_value <= v; cfg_write <= 1'b1; end
            @(posedge clk) cfg_write <= 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task tick_once;
        begin
            sample_tick <= 1'b1; @(posedge clk);
            sample_tick <= 1'b0; @(posedge clk);
        end
    endtask

    task expect_reg(input [5:0] a, input [15:0] v, input [127:0] name);
        begin
            read_addr = a;
            repeat (2) @(posedge clk);
            if (read_value !== v) $fatal(1, "%0s: got %04h expected %04h", name, read_value, v);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        reset_n = 1;
        repeat (5) @(posedge clk);

        expect_reg(6'd0, 16'h0001, "global default");
        expect_reg(6'd3, 16'd99, "filter cutoff default");
        expect_reg(6'd6, 16'd20, "distortion gain default");
        expect_reg(6'd24, 16'd30, "reverb mix default");

        // register write/readback
        wr(6'd3, 16'h4321);
        expect_reg(6'd3, 16'h4321, "register write");
        wr(6'd24, 16'h0055);
        expect_reg(6'd24, 16'h0055, "register write 2");

        // step 1: the chain is dry, and bypass/master must still pass dry exactly
        tick_once;
        if (sample_out !== dry) $fatal(1, "master-on output %04h", sample_out);
        wr(6'd0, 16'h0003);      // bypass
        tick_once;
        if (sample_out !== dry) $fatal(1, "bypass output %04h", sample_out);
        wr(6'd0, 16'h0000);      // master off
        tick_once;
        if (sample_out !== dry) $fatal(1, "master-off output %04h", sample_out);

        $display("PASS audio_fx registers, defaults and dry bypass");
        $finish;
    end
endmodule
