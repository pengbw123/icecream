`timescale 1ns/1ps
module tb_138k_io;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0;
    reg [31:0] tx_event=0;
    reg tx_valid=0;
    wire tx_ready,serial;
    midi_frame_tx tx(.clk(clk),.reset_n(reset_n),.event_data(tx_event),
        .event_valid(tx_valid),.event_ready(tx_ready),.tx(serial));
    wire [31:0] rx_event;
    wire rx_valid;
    reg rx_ready=0;
    reg raw_mode=0,raw_pin=1;
    wire [15:0] drops;
    midi_bridge_rx rx(.clk(clk),.reset_n(reset_n),.rx_pin(raw_mode?raw_pin:serial),
        .midi_event_data(rx_event),.midi_event_valid(rx_valid),
        .midi_event_ready(rx_ready),.dropped_events(drops));
    wire led;
    ws2812_keys leds(.clk(clk),.reset_n(reset_n),.midi_event_data(rx_event),
        .midi_event_valid(rx_valid&&rx_ready),.led_data(led));

    task send_event(input [31:0] event_word);
        begin
            wait(tx_ready);@(negedge clk);tx_event=event_word;tx_valid=1;
            @(negedge clk);tx_valid=0;
        end
    endtask
    task raw_byte(input [7:0] value);
        integer k;
        begin
            @(negedge clk);raw_pin=0;repeat(50)@(negedge clk);
            for(k=0;k<8;k=k+1)begin raw_pin=value[k];repeat(50)@(negedge clk);end
            raw_pin=1;repeat(50)@(negedge clk);
        end
    endtask
    task receive_event(input [31:0] expected,input integer hold_cycles);
        begin
            wait(rx_valid);
            if (rx_event!==expected) $fatal(1,"UART event mismatch %h != %h",rx_event,expected);
            repeat(hold_cycles) begin
                @(negedge clk);
                if (!rx_valid || rx_event!==expected) $fatal(1,"Backpressure did not hold event");
            end
            @(negedge clk);rx_ready=1;@(negedge clk);rx_ready=0;
        end
    endtask

    // Verify actual pulse widths and serialized GRB bits on the output pin.
    reg [23:0] first_color=0;
    realtime edge_time,high_time;
    integer b;
    initial begin
        wait(reset_n);
        for (b=0;b<24;b=b+1) begin
            @(posedge led);edge_time=$realtime;
            @(negedge led);high_time=$realtime-edge_time;
            if (high_time!=400.0 && high_time!=800.0) $fatal(1,"WS2812 high width %f",high_time);
            first_color={first_color[22:0],high_time==800.0};
        end
        if (first_color!==24'h007F00) $fatal(1,"WS2812 C3 color %h",first_color);
        $display("PASS WS2812 first LED color and 400/800 ns pulse widths");
    end

    // TMDS data recovery and physical DC-disparity check, independently
    // reconstructing all input bytes from transmitted 10-bit symbols.
    reg [7:0] pixel=8'hFF;
    reg de=0,c0=0,c1=0;
    wire [9:0] symbol;
    tmds_encoder enc(.clk(clk),.reset_n(reset_n),.data(pixel),.de(de),.c0(c0),.c1(c1),.symbol(symbol));
    reg [7:0] qm,recovered;
    integer i,j,n1,dc;
    initial begin
        wait(reset_n);dc=0;
        for (i=0;i<1024;i=i+1) begin
            @(negedge clk);de=1;pixel=(i*73)^(i>>2);
            @(posedge clk);#1;
            qm=symbol[9] ? ~symbol[7:0] : symbol[7:0];
            recovered[0]=qm[0];
            for (j=1;j<8;j=j+1) recovered[j]=symbol[8] ? qm[j]^qm[j-1] : ~(qm[j]^qm[j-1]);
            if (recovered!==pixel) $fatal(1,"TMDS byte recovery failed data=%h symbol=%h qm=%h recovered=%h",pixel,symbol,qm,recovered);
            n1=0;for(j=0;j<10;j=j+1)n1=n1+symbol[j];
            dc=dc+2*n1-10;
            if(dc>8 || dc< -8 || dc!==$signed(enc.disparity)) $fatal(1,"TMDS disparity %0d",dc);
        end
        @(negedge clk);de=0;c0=0;c1=0;@(posedge clk);#1;
        if(symbol!==10'b1101010100)$fatal(1,"TMDS control code failed");
        $display("PASS TMDS 1024-symbol recovery, bounded disparity and control code");
    end

    initial begin
        repeat(10)@(negedge clk);reset_n=1;
        send_event(32'h0090307F);receive_event(32'h0090307F,200);
        // Wait for LED serializer to sample the C3 state before releasing.
        #1000000;
        send_event(32'h00803040);receive_event(32'h00803040,0);
        send_event(32'h00E03050);receive_event(32'h00E03050,0);
        send_event(32'h00B01B1F);receive_event(32'h00B01B1F,0);
        wait(tx_ready);raw_mode=1;
        raw_byte(8'hA5);raw_byte(8'h5A);raw_byte(8'h30);
        #3000000;
        if(rx_valid)$fatal(1,"Truncated frame generated event");
        raw_mode=0;
        send_event(32'h00903C60);receive_event(32'h00903C60,0);
        if(drops!=0)$fatal(1,"Unexpected UART drops");
        $display("PASS UART events, bend, CC, backpressure and truncated-frame recovery");
        $finish;
    end
    initial begin #10000000;$fatal(1,"Test timeout");end
endmodule
