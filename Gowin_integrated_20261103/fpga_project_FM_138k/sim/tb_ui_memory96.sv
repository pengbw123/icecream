`timescale 1ns/1ps
module tb_ui_memory96;
    reg clk=0;always #10 clk=~clk;
    reg [14:0] code_addr=0,data_addr=0;
    reg [3:0] we=0;reg [31:0] data_in=0;
    wire [31:0] code_out,data_out;
    m_lm_mc #(.FIRMWARE_FILE("src/ui_firmware/firmware.hex"),
        .FIRMWARE_HIGH_FILE("src/ui_firmware/firmware_high.hex"),.DATA_BYTES(98304)) dut(
        .CLK(clk),.w_addr1(code_addr),.r_odata1(code_out),.w_we(we),.w_addr2(data_addr),
        .r_odata2(data_out),.w_idata(data_in));
    task wr(input [14:0] a,input [31:0] d,input [3:0] mask);
        begin @(negedge clk);data_addr=a;data_in=d;we=mask;@(negedge clk);we=0;end
    endtask
    task rd(input [14:0] a,input [31:0] expected);
        begin @(negedge clk);data_addr=a;@(posedge clk);#1;
            if(data_out!==expected)$fatal(1,"96KiB memory %h got %h expected %h",a,data_out,expected);end
    endtask
    reg [31:0] code_zero,code_high;
    initial begin
        repeat(3)@(negedge clk);code_zero=code_out;
        code_addr=15'h4000;repeat(3)@(negedge clk);code_high=code_out;
        wr(0,32'h12345678,15);wr(15'h1fff,32'h01020304,15);
        wr(15'h3fff,32'hdeadbeef,15);wr(15'h4000,32'h87654321,15);wr(15'h5fff,32'hacbdcedf,15);
        rd(0,32'h12345678);rd(15'h4000,32'h87654321);
        rd(15'h3fff,32'hdeadbeef);rd(15'h5fff,32'hacbdcedf);rd(15'h1fff,32'h01020304);
        wr(15'h4000,32'h00aa0000,4'b0100);wr(15'h1fff,32'h000000bb,4'b0001);
        rd(15'h4000,32'h87aa4321);rd(15'h1fff,32'h010203bb);rd(0,32'h12345678);
        code_addr=0;repeat(3)@(negedge clk);if(code_out!==code_zero)$fatal(1,"Data writes changed instruction ROM");
        code_addr=15'h4000;repeat(3)@(negedge clk);if(code_out!==code_high)$fatal(1,"High data writes changed instruction ROM");
        $display("PASS explicit 64+32KiB RAM: bank boundaries, no alias, byte stores, one-clock read and instruction independence");$finish;
    end
endmodule
