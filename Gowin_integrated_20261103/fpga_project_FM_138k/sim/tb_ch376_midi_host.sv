`timescale 1ns/1ps
module tb_ch376_midi_host;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,attached=1,ready=1,module_link=1;
    wire cs_n,sck,mosi,miso,int_n,valid,present,configured;
    wire [31:0] event_data;
    wire [7:0] fault;
    wire [15:0] vid,pid,ignored,naks;
    ch376_midi_host #(.POWER_WAIT(1000),.RESET_WAIT(2000),.BUS_WAIT(1000),.ATTACH_WAIT(1000),
        .POLL_WAIT(500),.CONTROL_TIMEOUT(2000000),.IRQ_TIMEOUT(100000)) dut(
        .clk(clk),.reset_n(reset_n),.spi_cs_n(cs_n),.spi_sck(sck),.spi_mosi(mosi),.spi_miso(module_link ? miso : 1'b1),
        .interrupt_n(int_n),.midi_event_data(event_data),.midi_event_valid(valid),.midi_event_ready(ready),
        .module_present(present),.configured(configured),.fault_code(fault),
        .vendor_id(vid),.product_id(pid),.ignored_words(ignored),.nak_count(naks));
    ch376_usb_model device(.cs_n(cs_n),.sck(sck),.mosi(mosi),.miso(miso),.attached(attached),.interrupt_n(int_n));
    logic [31:0] observed[$];
    reg stalled_last=0;
    reg [31:0] stalled_data;
    always @(posedge clk)if(reset_n)begin
        if(stalled_last)assert(valid && event_data==stalled_data) else $fatal(1,"stalled MIDI changed");
        stalled_last<=valid && !ready;stalled_data<=event_data;
        if(valid && ready)observed.push_back(event_data);
    end
    task automatic wait_count(input int n);
        int count=0;
        while(observed.size()<n && count<2000000)begin @(negedge clk);count++;end
        assert(observed.size()==n) else $fatal(1,"event count expected=%0d got=%0d state=%0d fault=%02x",n,observed.size(),dut.state,fault);
    endtask
    task automatic wait_configured;
        int count=0;
        while(!configured && count<3000000)begin @(negedge clk);count++;end
        assert(configured && present && fault==0 && vid==16'h1234 && pid==16'h5678)
            else $fatal(1,"enumeration failed state=%0d ctrl=%0d fault=%02x",dut.state,dut.u_control.state,fault);
    endtask
    task restart_host;
        reset_n=0;repeat(10)@(negedge clk);reset_n=1;
    endtask
    task automatic wait_fault(input byte unsigned code);
        int count=0;
        while(fault!=code && count<3000000)begin @(negedge clk);count++;end
        assert(fault==code && !configured) else $fatal(1,"expected fault=%02x got=%02x state=%0d",code,fault,dut.state);
    endtask
    initial begin
        repeat(10)@(negedge clk);reset_n=1;
        wait_configured();
        assert(device.full_descriptor_reads==1 && device.control_nak_used && device.alternate==1)
            else $fatal(1,"long descriptor/NAK/alternate not exercised");
        // 16 USB-MIDI events fill a full-speed 64-byte packet.
        ready=0;
        for(int j=0;j<16;j++)device.queue_event({8'h5a,byte'(60+j),8'h90,8'h09});
        wait(valid);repeat(2000)@(negedge clk);
        assert(observed.size()==0 && valid) else $fatal(1,"backpressure lost packet");
        ready=1;wait_count(16);
        foreach(observed[j])assert(observed[j]=={8'h09,8'h90,byte'(60+j),8'h7f}) else $fatal(1,"event order/layout/velocity");
        device.queue_event(32'h003c9009); // zero velocity note-on is a release
        device.queue_event(32'h28409129); // other channel, original velocity
        device.queue_event(32'hff05c00c); // two-byte program change
        device.queue_event(32'h0000f80f); // MIDI clock ignored by FM
        wait_count(19);repeat(5000)@(negedge clk);
        assert(observed[16]==32'h09903c00 && observed[17]==32'h29914028 && observed[18]==32'h0cc00500 && ignored==1 && naks>=2)
            else $fatal(1,"MIDI filtering or NAK handling");
        // STALL must clear halt on endpoint 0x83 and restart its DATA0 sequence.
        device.stall_request=1;device.queue_event(32'h403c8008);
        wait_count(20);assert(device.clear_count==1 && observed[19]==32'h08803c40) else $fatal(1,"STALL recovery");
        attached=0;wait_count(22);
        assert(observed[20]==32'h00b04000 && observed[21]==32'h00b07b00 && !configured)
            else $fatal(1,"unplug left sustain/notes on");
        repeat(10000)@(negedge clk);attached=1;wait_configured();
        device.queue_event(32'h503e9009);wait_count(23);
        assert((observed[22]&32'h00ffff00)==32'h00903e00 && device.enumerations==2) else $fatal(1,"replug did not re-enumerate");
        // A missing IRQ response must end in panic/recovery, never block forever.
        device.suppress_irq=1;device.interrupt_n=1;
        wait_count(25);
        assert(fault==8'hc1 && observed[23]==32'h00b04000 && observed[24]==32'h00b07b00)
            else $fatal(1,"IRQ timeout panic");
        device.suppress_irq=0;restart_host();wait_configured();
        // A corrupt SPI length above the 64-byte CH376 buffer is drained and rejected.
        device.queue_event(32'h403c9009);device.forced_read_length=65;
        wait_count(27);
        assert(fault==8'hc3 && observed[25]==32'h00b04000 && observed[26]==32'h00b07b00)
            else $fatal(1,"oversize CH376 buffer accepted");
        // Configuration length 4097 must be rejected before the long transfer.
        device.config_desc[2]=1;device.config_desc[3]=16;
        restart_host();wait_fault(8'h94);
        // USB MIDI 2.0 protocol is not a stream of MIDI 1.0 four-byte events.
        device.config_desc[2]=byte'(device.config_desc.size());device.config_desc[3]=0;
        device.config_desc[71]=2;device.config_desc[80]=2;
        restart_host();wait_fault(8'h94);
        device.config_desc[71]=0;device.config_desc[80]=0;
        device.config_desc[104]=0; // malformed endpoint bLength
        restart_host();wait_fault(8'h94);
        device.config_desc[104]=9;
        // A missing interrupt during enumeration has a separate bounded timeout.
        device.suppress_irq=1;device.interrupt_n=1;
        restart_host();wait_fault(8'he1);
        device.suppress_irq=0;module_link=0;
        restart_host();wait_fault(8'h81);
        assert(!present && observed.size()==27) else $fatal(1,"absent module emitted MIDI");
        module_link=1;
        for(int k=0;k<3;k++)begin
            device.device_desc[7]=byte'(16<<k);restart_host();wait_configured();
            assert(dut.ep0_size==(16<<k)) else $fatal(1,"EP0 maximum packet not applied");
        end
        $display("CH376_HOST_OK long_config=%0d ep0_mps=8/16/32/64 full_packet=64 events=%0d clears=%0d replug=1 irq_timeout=1 negatives=6",
            device.config_desc.size(),observed.size(),device.clear_count);$finish;
    end
    initial begin #300000000;$fatal(1,"host test timeout state=%0d fault=%02x",dut.state,fault);end
endmodule
