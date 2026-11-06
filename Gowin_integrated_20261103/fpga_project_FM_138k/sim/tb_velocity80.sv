`timescale 1ns/1ps
// USB/PLL stubs only supply idle pins; calibration is the actual bridge RTL.
module usb_pll(input clkin,output clkout0,clkout1,lock);
    assign clkout0=clkin;assign clkout1=clkin;assign lock=1;
endmodule
module usb_midi_host(input clk_48m,clk_cpu_bram_96m,reset,input cpu_uart_rx,
    inout usb_dp,usb_dn,output cpu_uart_tx,output [31:0] midi_event_data,
    output midi_event_toggle,input midi_event_ack_toggle,output midi_connected,
    input [31:0] debug_pll_unlock_count,output debug_reset_n,debug_cpu_fetch,debug_uart_write,
    output [31:0] debug_cpu_addr);
    assign cpu_uart_tx=1;assign midi_event_data=0;assign midi_event_toggle=0;
    assign midi_connected=0;assign debug_reset_n=0;assign debug_cpu_fetch=0;
    assign debug_uart_write=0;assign debug_cpu_addr=0;
endmodule
module tb_velocity80;
    reg clk=0;always #10 clk=~clk;
    reg [31:0] stimulus=0;
    top_bridge dut(.clk(clk),.key_s2(1'b0),.uart_rx_pin(1'b1));
    reg reset_n=0,valid=0;
    wire [6:0] preset,depth,porta;
    wire preset_valid;
    midi_performance_control perf(.clk(clk),.reset_n(reset_n),.midi_event_data(stimulus),
        .midi_event_valid(valid),.preset_select(preset),.preset_select_valid(preset_valid),
        .vibrato_depth(depth),.portamento_time(porta));
    integer raw,expected,previous=0,actual;
    initial begin
        force dut.usb_event=stimulus;
        for(raw=0;raw<128;raw=raw+1)begin
            stimulus={16'h0090,8'd60,1'b0,raw[6:0]};#1;
            actual=dut.calibrated[6:0];expected=raw>=80?127:(raw*127+40)/80;
            if(actual<previous||actual>expected+1||actual<expected-1)$fatal(1,"Velocity curve %d -> %d",raw,actual);
            if(raw==0&&actual!=0 || raw==20&&actual!=32 || raw>=80&&actual!=127)$fatal(1,"Velocity endpoint %d -> %d",raw,actual);
            previous=actual;
        end
        stimulus=32'h00993c14;#1;if(dut.calibrated!==stimulus)$fatal(1,"Pad was rescaled");
        stimulus=32'h00b00114;#1;if(dut.calibrated!==stimulus)$fatal(1,"Controller was rescaled");
        @(negedge clk);reset_n=1;
        for(raw=0;raw<128;raw=raw+1)begin
            @(negedge clk);stimulus={16'h00b0,8'd27,1'b0,raw[6:0]};valid=1;
            @(negedge clk);valid=0;
            if(!preset_valid||preset!=raw)$fatal(1,"CC27 truncated factory ID %d",raw);
        end
        @(negedge clk);stimulus=32'h00b00150;valid=1;
        @(negedge clk);valid=0;if(depth!=80)$fatal(1,"Mod strip depth changed");
        $display("PASS actual bridge 0..80 velocity calibration, decimal 20->32, pad/CC bypass and 128 preset CC selection");$finish;
    end
endmodule
