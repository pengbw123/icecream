`timescale 1ns/1ps
module tb_ch376_input_path;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,consume=0;
    reg [31:0] packet=0,ui_data=32'h80905063,bridge_data=32'h00903055;
    reg usb_valid=0,ui_valid=0,bridge_valid=0;
    wire decoded_valid;wire [31:0] decoded;
    wire usb_ready,ui_ready,bridge_ready,merged_valid,merged_ready,out_valid;
    wire [31:0] merged_data,out_data;
    usb_midi_event_decode u_decode(.packet(packet),.valid(decoded_valid),.event_data(decoded));
    midi_event_arbiter3 u_arb(.clk(clk),.reset_n(reset_n),
        .data0({8'd0,decoded[23:0]}),.valid0(usb_valid&&decoded_valid),.ready0(usb_ready),
        .data1(bridge_data),.valid1(bridge_valid),.ready1(bridge_ready),
        .data2(ui_data),.valid2(ui_valid),.ready2(ui_ready),
        .event_data(merged_data),.event_valid(merged_valid),.event_ready(merged_ready));
    midi_input_queue u_queue(.clk(clk),.reset_n(reset_n),.in_data(merged_data),
        .in_valid(merged_valid),.in_ready(merged_ready),.out_data(out_data),.out_valid(out_valid),.out_ready(consume));
    reg [31:0] expected[0:63];integer tail=0,head=0,usb_seen=0,ui_seen=0,bridge_seen=0;
    reg stalled=0;reg [31:0] held;
    always @(posedge clk)if(reset_n)begin
        if(usb_valid&&decoded_valid&&usb_ready)begin
            expected[tail]={8'd0,decoded[23:0]};tail=tail+1;usb_seen=usb_seen+1;
        end
        if(bridge_valid&&bridge_ready)begin expected[tail]=bridge_data;tail=tail+1;bridge_seen=bridge_seen+1;end
        if(ui_valid&&ui_ready)begin expected[tail]=ui_data;tail=tail+1;ui_seen=ui_seen+1;end
        if(stalled&&(!out_valid||out_data!==held))$fatal(1,"Input queue changed a stalled event");
        if(out_valid&&consume)begin
            if(head>=tail||out_data!==expected[head])$fatal(1,"Input queue lost/reordered event %d",head);
            if(out_data[23:16]==8'h90&&out_data[14:8]>=60&&out_data[14:8]<68)
                if(out_data[31:24]!==0||out_data[6:0]!==127)$fatal(1,"USB owner metadata or velocity calibration");
            head=head+1;
        end
        stalled=out_valid&&!consume;held=out_data;
    end
    initial begin
        repeat(4)@(negedge clk);reset_n=1;
        // Both owner-tag bits are set in cable 15; they must not escape USB.
        packet={8'd80,8'd60,8'h90,8'hf9};usb_valid=1;ui_valid=1;bridge_valid=1;
        repeat(8)@(negedge clk);
        if(u_queue.count!==2||merged_ready!==0)$fatal(1,"Queue did not hold backpressure");
        consume=1;#1;if(merged_ready!==0)$fatal(1,"Ready depends combinationally on downstream ready");
        consume=0;
        repeat(4)@(negedge clk);
        for(integer cycle=0;cycle<160;cycle=cycle+1)begin
            consume=(cycle%5)!=0;
            @(posedge clk);#1;@(negedge clk);
            if(usb_seen>=8)usb_valid=0;else packet={8'd80,8'(60+usb_seen),8'h90,8'hf9};
            if(ui_seen>=8)ui_valid=0;else ui_data={8'h80,8'h90,8'(80+ui_seen),8'd99};
            if(bridge_seen>=8)bridge_valid=0;else bridge_data={8'd0,8'h90,8'(48+bridge_seen),8'd85};
        end
        consume=1;repeat(10)@(negedge clk);
        if(head!=24||tail!=24||usb_seen!=8||ui_seen!=8||bridge_seen!=8)$fatal(1,"Input fairness/drop counts");
        $display("PASS CH376 ingress: velocity 0..80, USB owner-tag stripping, UI tags, three-source fairness, registered ready and stall stability");$finish;
    end
    initial begin #1000000;$fatal(1,"Input path timeout");end
endmodule
