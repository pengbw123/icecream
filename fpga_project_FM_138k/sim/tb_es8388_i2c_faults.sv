`timescale 1ns/1ps
// Physical-bus faults must release pins and report failure; an interrupted
// slave ACK must be clocked out so S4 reset does not require a power cycle.
module tb_es8388_i2c_faults;
    reg clk=0;
    always #10 clk=~clk;
    reg reset_n=0,start=0,hold_scl=0,hold_sda=0;
    tri1 scl,sda;
    assign scl=hold_scl?1'b0:1'bz;
    assign sda=hold_sda?1'b0:1'bz;
    wire done,failed;
    es8388_i2c_write #(.QUARTER_CLOCKS(8),.TIMEOUT_QUARTERS(80)) d(
        .clk(clk),.reset_n(reset_n),.start(start),.reg_addr(8'h17),.reg_data(8'h18),
        .scl(scl),.sda(sda),.done(done),.failed(failed));
    task launch;
        begin @(negedge clk);start=1;@(negedge clk);start=0;end
    endtask
    integer pulses;
    initial begin
        repeat(5) @(negedge clk);reset_n=1;
        hold_scl=1;launch;
        wait(done);#1;
        if(!failed || d.scl_low || d.sda_low) $fatal(1,"SCL timeout not released");
        hold_scl=0;hold_sda=1;launch;
        pulses=0;
        while(pulses<9) begin @(posedge scl);pulses=pulses+1;end
        // Simulate a slave finally finishing its interrupted data/ACK byte.
        @(negedge scl);hold_sda=0;
        wait(d.state==2);
        if(d.recovering) $fatal(1,"bus recovery did not finish");
        // No slave ACKs this time: an absent codec must fail cleanly.
        wait(done);#1;
        if(!failed || d.scl_low || d.sda_low) $fatal(1,"NACK did not release bus");
        launch;wait(done);#1;
        if(!failed) $fatal(1,"absent slave falsely accepted");
        $display("PASS ES8388 stuck-clock timeout, nine-clock bus recovery and NACK");
        $finish;
    end
    initial begin #200000;$fatal(1,"fault test timeout");end
endmodule
