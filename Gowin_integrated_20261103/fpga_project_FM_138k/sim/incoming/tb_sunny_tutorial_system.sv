`timescale 1ns/1ps
module tb_sunny_tutorial_system;
    parameter integer PHYSICAL_TIMING=0;
    localparam integer CPB=PHYSICAL_TIMING?434:8, LEDS=PHYSICAL_TIMING?160:6;
    localparam integer CLOCK_HZ=PHYSICAL_TIMING?50000000:100000;
    localparam integer BIT_CLOCKS=PHYSICAL_TIMING?63:7;
    localparam integer HIGH0=PHYSICAL_TIMING?15:2, HIGH1=PHYSICAL_TIMING?33:4;
    localparam integer GAP_CLOCKS=PHYSICAL_TIMING?16000:32;
    localparam integer STABLE_CLOCKS=PHYSICAL_TIMING?500000:12;
    localparam integer FRAME_CLOCKS=LEDS*24*BIT_CLOCKS+GAP_CLOCKS+LEDS+10;
    reg clk=0;
    always #10 clk=~clk;
    reg reset_n=0,bt_rx=1,start_button_n=1,stop_button_n=1;
    reg [31:0] live_midi_event=0;
    reg live_midi_valid=0;
    wire [31:0] key_midi_event=live_midi_event;
    wire key_midi_valid=live_midi_valid;
    wire [1:0] key_source=0;
    wire [31:0] auto_midi_event;
    wire auto_midi_valid,auto_playing,auto_flushing;
    wire auto_midi_ready=1;
    wire external_mode_busy=0,mode_lock;
    wire bt_tx,led_data,running,count_in,beat_active,initialized,mapping_missing,frame_done,reply_overflow;
    wire calibration_success;
    sunny_tutorial_system #(.CLK_HZ(CLOCK_HZ),.UART_CLKS_PER_BIT(CPB),.LED_COUNT(LEDS),
        .BIT_CYCLES(BIT_CLOCKS),.T0H_CYCLES(HIGH0),.T1H_CYCLES(HIGH1),.RESET_CYCLES(GAP_CLOCKS),
        .BUTTON_CYCLES(STABLE_CLOCKS),.MAP_FILE(PHYSICAL_TIMING?"src/generated/tutorial_led_map.mem":"sim/tutorial_map_test.mem")) dut(.key_plan_ready(1'b0),.keyboard_disconnected(1'b0),.key_plan_active(),.key_plan_first(),.key_plan_valid(),.key_plan_notes(),.phone_request_valid(),.phone_request_payload(),.phone_request_ready(1'b0),.phone_response_valid(1'b0),.phone_response_token(16'd0),.phone_response_status(8'd0),.phone_response_value(8'd0),.phone_response_was_write(1'b0),.tone_success(),.*);
    wire [7:0] rx_byte;
    wire rx_valid;
    uart_rx #(.CLKS_PER_BIT(CPB)) monitor(.clk(clk),.reset_n(reset_n),.rx(bt_tx),
        .data(rx_byte),.valid(rx_valid),.busy());
    reg [7:0] reply_bytes [0:511];
    int reply_count=0, frames=0;
    reg [LEDS*24-1:0] last_frame=0,decoded=0;
    int low_run=0,cell_tick=0,bit_number=0,highs=0;
    reg capturing=0;
    always @(posedge clk) begin
        #1;
        if (rx_valid) begin reply_bytes[reply_count]=rx_byte; reply_count++; end
        if (reset_n) begin
            if (!capturing && led_data && low_run>=GAP_CLOCKS) begin
                capturing=1; cell_tick=0; bit_number=0; highs=0; decoded=0;
            end
            if (capturing) begin
                if (led_data) highs++;
                if (cell_tick==BIT_CLOCKS-1) begin
                    if (highs!=HIGH0 && highs!=HIGH1) $fatal(1,"Serialized LED pulse width %0d",highs);
                    decoded[(bit_number/24)*24+23-(bit_number%24)]=(highs==HIGH1);
                    cell_tick=0; highs=0; bit_number++;
                    if (bit_number==LEDS*24) begin capturing=0;last_frame=decoded;frames++; end
                end else cell_tick++;
            end
            if (led_data) low_run=0; else low_run++;
        end else begin capturing=0;low_run=0;end
    end
    task automatic tick;
        @(posedge clk); #2;
    endtask
    task automatic send_byte(input reg [7:0] value);
        @(negedge clk);bt_rx=0;
        repeat(CPB)tick();
        for(int b=0;b<8;b++)begin @(negedge clk);bt_rx=value[b];repeat(CPB)tick();end
        @(negedge clk);bt_rx=1;repeat(CPB)tick();
    endtask
    task automatic request(input reg [7:0] cmd,input reg [31:0] data,
                           input reg [31:0] magic,input reg corrupt,input reg [7:0] expected_status);
        reg [63:0] body;
        reg [7:0] sum;
        int before_count,limit;
        before_count=reply_count;body={magic,data};sum=cmd;
        send_byte(8'ha5);send_byte(8'h5a);send_byte(cmd);
        for(int b=0;b<8;b++)begin send_byte(body[b*8+:8]);sum^=body[b*8+:8];end
        send_byte(sum^(corrupt?8'd1:8'd0));
        limit=0;
        while(reply_count<before_count+6)begin tick();limit++;if(limit>2*(FRAME_CLOCKS+CPB*70))$fatal(1,"Missing ACK cmd=%h",cmd);end
        if(reply_bytes[before_count]!=8'ha5||reply_bytes[before_count+1]!=8'h5a||
           reply_bytes[before_count+2]!=8'hf0||reply_bytes[before_count+3]!=cmd||
           reply_bytes[before_count+4]!=expected_status||
           reply_bytes[before_count+5]!=(8'hf0^cmd^expected_status))
            $fatal(1,"ACK mismatch cmd=%h status=%h expected=%h",cmd,reply_bytes[before_count+4],expected_status);
    endtask
    task automatic wait_frame(input reg [LEDS*24-1:0] value);
        int limit;
        limit=0;
        while(last_frame!=value)begin tick();limit++;if(limit>3*FRAME_CLOCKS)$fatal(1,"LED frame mismatch got=%h expected=%h",last_frame,value);end
    endtask
    reg [LEDS*24-1:0] expected;
    initial begin
        repeat(4)tick();@(negedge clk);reset_n=1;
        while(!initialized)tick();
        request(8'h75,0,32'h44495547,0,0);
        request(8'h50,0,0,0,1); // Old FM/score commands cannot alter tutorial or reach FM.
        request(8'h70,1,0,0,1);
        request(8'h70,1,32'h44495547,1,2);
        if(running)$fatal(1,"Invalid packet started playback");
        request(8'h71,((LEDS-1)<<8)|1,32'h44495547,0,0);
        expected=0;expected[(LEDS-1)*24+:24]=24'h080808;wait_frame(expected);
        request(8'h71,(LEDS<<8)|1,32'h44495547,0,1);
        wait_frame(expected);
        request(8'h71,0,32'h44495547,0,0);wait_frame(0);
        request(8'h73,0,32'h44495547,0,0);
        request(8'h72,(65<<24)|(1<<16)|0,32'h44495547,0,0);
        request(8'h72,(58<<24)|(1<<16)|1,32'h44495547,0,0);
        request(8'h72,(2<<16)|2,32'h44495547,0,0);
        request(8'h72,(60<<24)|(1<<16)|3,32'h44495547,0,0);
        request(8'h72,(62<<24)|(1<<16)|4,32'h44495547,0,0);
        request(8'h72,(65<<24)|(1<<16)|LEDS,32'h44495547,0,1);
        request(8'h74,100|(1<<8)|(254<<16),32'h44495547,0,0);
        request(8'h70,1,32'h44495547,0,0);
        if(!running||!count_in)$fatal(1,"Start/count-in missing");
        request(8'h74,100|(1<<8)|(254<<16),32'h44495547,0,1);
        request(8'h71,1,32'h44495547,0,1);
        while(count_in)tick();
        // Beat plus first green note (67-2=65), then first-note release and
        // same-pitch yellow preview; no MIDI/audio event is generated by practice.
        expected=0;expected[0+:24]=24'h200000;expected[2*24+:24]=24'h000020;
        wait_frame(expected);
        request(8'h70,0,32'h44495547,0,0);
        if(running||dut.expected_notes||dut.preview_notes)$fatal(1,"STOP did not clear masks");
        wait_frame(0);
        // Normal key feedback survives tutorial STOP.
        @(negedge clk);live_midi_event={8'h09,8'h90,8'd65,8'd80};live_midi_valid=1;
        tick();@(negedge clk);live_midi_valid=0;
        expected=0;expected[0+:24]=24'h200000;wait_frame(expected);
        @(negedge clk);live_midi_event={8'h08,8'h80,8'd65,8'd0};live_midi_valid=1;
        tick();@(negedge clk);live_midi_valid=0;wait_frame(0);
        // Button bounce cannot start; held key starts once and cannot restart
        // the count-in. Local STOP remains usable with no Bluetooth traffic.
        @(negedge clk);start_button_n=0;repeat(3)tick();
        @(negedge clk);start_button_n=1;repeat(20)tick();
        if(running)$fatal(1,"Bounce started tutorial");
        @(negedge clk);start_button_n=0;repeat(2*STABLE_CLOCKS+1000)tick();
        if(!running||dut.player.count_remaining>=400)$fatal(1,"Button did not start/held button restarted");
        @(negedge clk);stop_button_n=0;repeat(STABLE_CLOCKS+8)tick();
        if(running)$fatal(1,"Local STOP failed");
        wait_frame(0);
        if(reply_overflow)$fatal(1,"Unexpected reply overflow");
        $display("SUNNY_SYSTEM_OK physical_timing=%0d UART/magic/CRC/isolation/map/scan/count-in/green/stop/live-keys/buttons frames=%0d",PHYSICAL_TIMING,frames);
        $finish;
    end
    initial begin #2000000000;$fatal(1,"System timeout");end
endmodule
