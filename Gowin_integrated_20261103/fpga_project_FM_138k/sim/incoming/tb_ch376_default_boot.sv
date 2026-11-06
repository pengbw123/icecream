`timescale 1ns/1ps
// Default production timing, real 50 MHz clock and a behavioural CH376/USB
// device. No startup delay overrides: exercises the actual boot wait counts.
module tb_ch376_default_boot;
    localparam integer CLOCK_HZ=50000000;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,attached=1,ready=1;
    wire cs_n,sck,mosi,miso,int_n,valid,present,configured;
    wire [31:0] data;wire [7:0] fault;wire [15:0] vid,pid,ignored,naks;
    ch376_midi_host dut(.clk(clk),.reset_n(reset_n),.spi_cs_n(cs_n),.spi_sck(sck),.spi_mosi(mosi),
        .spi_miso(miso),.interrupt_n(int_n),.midi_event_data(data),.midi_event_valid(valid),.midi_event_ready(ready),
        .module_present(present),.configured(configured),.fault_code(fault),
        .vendor_id(vid),.product_id(pid),.ignored_words(ignored),.nak_count(naks));
    ch376_usb_model device(.cs_n(cs_n),.sck(sck),.mosi(mosi),.miso(miso),.attached(attached),.interrupt_n(int_n));
    logic [31:0] observed[$];
    always @(posedge clk)if(reset_n && valid && ready)observed.push_back(data);
    int count;
    task automatic wait_events(input int expected);
        int ticks=0;
        while(observed.size()<expected && ticks<5000000)begin @(negedge clk);ticks++;end
        if(observed.size()!=expected)$fatal(1,"event timeout expected=%0d got=%0d fault=%h",expected,observed.size(),fault);
    endtask
    initial begin
        repeat(10)@(negedge clk);reset_n=1;
        count=0;while(!configured && count<CLOCK_HZ)begin @(negedge clk);count++;end
        if(!configured||!present||fault!=0||vid!=16'h1234||pid!=16'h5678)
            $fatal(1,"default boot failed cycles=%0d state=%0d fault=%h",count,dut.state,fault);
        if(count<CLOCK_HZ/10)$fatal(1,"default power wait was bypassed");
        device.queue_event({8'd80,8'd60,8'h90,8'h09});
        device.queue_event({8'd0,8'd60,8'h80,8'h08});
        wait_events(2);
        if(observed[0][23:8]!=16'h903c||observed[0][6:0]==0||observed[1][23:8]!=16'h803c)
            $fatal(1,"default boot MIDI key events malformed");
        $display("CH376_DEFAULT_BOOT_OK configured after %0d cycles (%0d ms), default 50MHz waits, note on/off",count,count/50000);
        $finish;
    end
    initial begin #1200000000;$fatal(1,"default CH376 test timeout");end
endmodule
