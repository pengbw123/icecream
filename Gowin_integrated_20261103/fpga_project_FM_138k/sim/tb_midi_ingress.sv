`timescale 1ns/1ps
// Real top input arbitration/mailbox, with only downstream readiness stubbed.
// Separate audio integration tests exercise the actual downstream consumers.
module tb_midi_ingress;
    reg clk=0; always #10 clk=~clk;
    reg reset=1,ext_valid=0,uart_valid=0,usb_toggle=0,consumer_ready=0;
    reg [31:0] ext_data=0,uart_data=0,usb_data=0;
    reg [6:0] uart_brightness=0;
    wire ext_ready,monitor_valid;
    wire [31:0] monitor_data;
    top dut(.clk(clk),.key_s2(reset),.arp_config(160'd0),.arp_suspend(1'b0),.sequence_active(1'b0),
        .headphone_select(1'b0),.uart_rx_pin(1'b1),.ui_command_valid(1'b0),.ui_command(8'd0),.ui_payload(64'd0),
        .fx_write(1'b0),.fx_index(4'd0),.fx_value(32'd0),.fx_read_index(4'd0),
        .external_midi_event_data(ext_data),.external_midi_event_valid(ext_valid),.external_midi_event_ready(ext_ready),
        .monitor_midi_event_data(monitor_data),.monitor_midi_event_valid(monitor_valid),
        .perf_snapshot(1'b0),.perf_clear(1'b0),.perf_index(5'd0),.perf_bridge_drop(1'b0));
    function [31:0] event_word(input integer source_id,index);
        event_word={8'd0,(8'h90+source_id[7:0]),1'b0,(7'd40+index[6:0]),1'b0,7'd80};
    endfunction
    reg [31:0] expected[0:255];reg [6:0] expected_brightness[0:255];
    integer write_count=0,read_count=0,usb_accepted=0,ext_accepted=0,uart_accepted=0;
    integer seen_usb=0,seen_ext=0,seen_uart=0,cycle=0;
    reg stalled=0;reg [31:0] held;reg [6:0] held_brightness;
    always @(posedge clk) if(!reset)begin
        cycle=cycle+1;
        if(stalled && (!dut.selected_midi_valid || dut.selected_midi_data!==held || dut.selected_brightness!==held_brightness))
            $fatal(1,"Input register changed during backpressure");
        if(monitor_valid)begin
            if(read_count>=write_count || monitor_data!==expected[read_count] || dut.selected_brightness!==expected_brightness[read_count])
                $fatal(1,"Ingress drop/duplicate/order/data at %0d got %h expected %h",read_count,monitor_data,expected[read_count]);
            case(monitor_data[23:16])
                8'h90:begin
                    if(monitor_data!==(event_word(0,seen_usb)|32'd47))$fatal(1,"USB mailbox order/calibration");
                    seen_usb=seen_usb+1;
                end
                8'h91:begin if(monitor_data!==event_word(1,seen_ext))$fatal(1,"External order");seen_ext=seen_ext+1;end
                8'h92:begin if(monitor_data!==event_word(2,seen_uart))$fatal(1,"UART order");seen_uart=seen_uart+1;end
                default:$fatal(1,"Unexpected event");
            endcase
            read_count=read_count+1;
        end
        if(dut.ingress_buffer_ready && dut.ingress_mux_valid)begin
            expected[write_count]=dut.ingress_mux_data;expected_brightness[write_count]=dut.ingress_mux_brightness;
            write_count=write_count+1;
        end
        if(dut.midi_event_valid && dut.raw_midi_event_ready)usb_accepted=usb_accepted+1;
        if(ext_valid&&ext_ready)ext_accepted=ext_accepted+1;
        if(uart_valid&&dut.uart_midi_event_ready)uart_accepted=uart_accepted+1;
        stalled=dut.selected_midi_valid&&!consumer_ready;
        held=dut.selected_midi_data;held_brightness=dut.selected_brightness;
    end
    integer a,b,c,k;reg [31:0] rng=32'h720138;
    initial begin
        force dut.usb_midi_event_data=usb_data;
        force dut.usb_midi_event_toggle=usb_toggle;
        force dut.uart_midi_event_data=uart_data;
        force dut.uart_midi_event_valid=uart_valid;
        force dut.uart_midi_event_brightness=uart_brightness;
        force dut.ingress_ready=consumer_ready;
        repeat(5)@(negedge clk);reset=0;
        fork
            begin
                for(a=0;a<48;a=a+1)begin
                    @(negedge clk);usb_data=event_word(0,a);usb_toggle=~usb_toggle;
                    wait(dut.midi_event_ack_toggle==usb_toggle);
                    repeat(a%3)@(negedge clk);
                end
            end
            begin
                for(b=0;b<48;b=b+1)begin
                    @(negedge clk);ext_data=event_word(1,b);ext_valid=1;
                    do @(posedge clk);while(!ext_ready);
                    @(negedge clk);ext_valid=0;
                    repeat(b%4)@(negedge clk);
                end
            end
            begin
                for(c=0;c<48;c=c+1)begin
                    @(negedge clk);uart_data=event_word(2,c);uart_brightness=7'd127-c;uart_valid=1;
                    do @(posedge clk);while(!dut.uart_midi_event_ready);
                    @(negedge clk);uart_valid=0;
                    repeat(c%2)@(negedge clk);
                end
            end
            begin
                repeat(25)@(negedge clk);
                for(k=0;k<1500;k=k+1)begin
                    @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
                    consumer_ready=rng[1]|rng[4];
                end
                consumer_ready=1;
            end
        join
        repeat(30)@(negedge clk);
        if(read_count!=144 || write_count!=144 || seen_usb!=48 || seen_ext!=48 || seen_uart!=48 ||
            usb_accepted!=48 || ext_accepted!=48 || uart_accepted!=48 || dut.selected_midi_valid || dut.midi_event_valid)
            $fatal(1,"Unbalanced arbitration accepted %0d/%0d/%0d seen %0d/%0d/%0d total %0d/%0d",usb_accepted,ext_accepted,uart_accepted,seen_usb,seen_ext,seen_uart,read_count,write_count);
        // A reset must flush a pending transaction.
        @(negedge clk);consumer_ready=0;ext_data=event_word(1,0);ext_valid=1;
        do @(posedge clk);while(!ext_ready);
        @(negedge clk);ext_valid=0;reset=1;
        repeat(3)@(negedge clk);
        if(dut.selected_midi_valid||dut.midi_event_valid)$fatal(1,"Reset did not flush ingress");
        $display("PASS real top MIDI ingress: 144 events, three concurrent sources, mailbox ack/hold, calibrated velocity, brightness, long/random stalls, stable payload, priority, no drops/duplicates, reset flush");$finish;
    end
    initial begin #1000000;$fatal(1,"Ingress timeout");end
endmodule
