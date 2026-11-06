`timescale 1ns/1ps
// Complete uploaded-score path through UART, the guide and the WS2812 output.
// Physical-rate parameters; stimulus does not model a real strip or phone.
module tb_uploaded_guide_led;
    localparam integer CLOCK_HZ=50000000, CPB=434, LEDS=160;
    localparam integer BIT_CLOCKS=63, HIGH0=15, HIGH1=33, GAP_CLOCKS=16000;
    localparam integer FRAME_CLOCKS=LEDS*24*BIT_CLOCKS+GAP_CLOCKS+LEDS+20;
    reg clk=0; always #10 clk=~clk;
    reg reset_n=0,bt_rx=1,start_button_n=1,stop_button_n=1;
    reg [31:0] live_midi_event=0,key_midi_event=0;
    reg live_midi_valid=0,key_midi_valid=0;
    reg [1:0] key_source=0;
    reg auto_midi_ready=0,external_mode_busy=0;
    wire bt_tx,led_data,running,count_in,beat_active,initialized,mapping_missing,frame_done,reply_overflow;
    wire [31:0] auto_midi_event;
    wire auto_midi_valid,auto_playing,auto_flushing,mode_lock,calibration_success;
    sunny_tutorial_system #(.CLK_HZ(CLOCK_HZ),.UART_CLKS_PER_BIT(CPB),.LED_COUNT(LEDS),
        .BIT_CYCLES(BIT_CLOCKS),.T0H_CYCLES(HIGH0),.T1H_CYCLES(HIGH1),
        .RESET_CYCLES(GAP_CLOCKS),.BUTTON_CYCLES(12),
        .MAP_FILE("src/generated/tutorial_led_map.mem")) dut(.phone_request_valid(),.phone_request_payload(),.phone_request_ready(1'b0),.phone_response_valid(1'b0),.phone_response_token(16'd0),.phone_response_status(8'd0),.phone_response_value(8'd0),.phone_response_was_write(1'b0),.tone_success(),.*);
    wire [7:0] rx_byte; wire rx_valid;
    uart_rx #(.CLKS_PER_BIT(CPB)) monitor(.clk(clk),.reset_n(reset_n),.rx(bt_tx),
        .data(rx_byte),.valid(rx_valid),.busy());

    reg [7:0] replies[0:1023];
    int reply_count=0,frames=0,low_run=0,cell_tick=0,bit_number=0,highs=0;
    reg capturing=0,guide_watch=0,saw_60=0,saw_64=0,guide_leak=0;
    reg [LEDS*24-1:0] decoded=0,last_frame=0,expect_60=0,expect_64=0;
    always @(posedge clk) begin
        #1;
        if (rx_valid) begin replies[reply_count]=rx_byte;reply_count++;end
        if (reset_n && guide_watch && auto_midi_valid) guide_leak=1;
        if (reset_n) begin
            if (!capturing && led_data && low_run>=GAP_CLOCKS) begin
                capturing=1;cell_tick=0;bit_number=0;highs=0;decoded=0;
            end
            if (capturing) begin
                if (led_data) highs++;
                if (cell_tick==BIT_CLOCKS-1) begin
                    if (highs!=HIGH0 && highs!=HIGH1) $fatal(1,"LED pulse width %0d",highs);
                    decoded[(bit_number/24)*24+23-(bit_number%24)]=(highs==HIGH1);
                    cell_tick=0;highs=0;bit_number++;
                    if (bit_number==LEDS*24) begin
                        capturing=0;last_frame=decoded;frames++;
                        if (guide_watch && decoded==expect_60) saw_60=1;
                        if (guide_watch && decoded==expect_64) saw_64=1;
                    end
                end else cell_tick++;
            end
            if (led_data) low_run=0; else low_run++;
        end else begin capturing=0;low_run=0;end
    end

    task automatic tick; @(posedge clk); #2; endtask
    task automatic byte_out(input reg [7:0] value);
        @(negedge clk);bt_rx=0;repeat(CPB)tick();
        for(int b=0;b<8;b++) begin @(negedge clk);bt_rx=value[b];repeat(CPB)tick();end
        @(negedge clk);bt_rx=1;repeat(CPB)tick();
    endtask
    task automatic request(input reg [7:0] cmd,input reg [63:0] body,input reg [7:0] status);
        reg [7:0] sum;int before_count,limit;
        sum=cmd;before_count=reply_count;
        byte_out('hA5);byte_out('h5A);byte_out(cmd);
        for(int b=0;b<8;b++)begin byte_out(body[b*8+:8]);sum^=body[b*8+:8];end
        byte_out(sum);limit=0;
        while(reply_count<before_count+6) begin
            tick();limit++;
            if(limit>2*FRAME_CLOCKS+CPB*600)$fatal(1,"ACK timeout command=%h",cmd);
        end
        if(replies[before_count]!='hA5||replies[before_count+1]!='h5A||
           replies[before_count+2]!='hF0||replies[before_count+3]!=cmd||
           replies[before_count+4]!=status||replies[before_count+5]!=('hF0^cmd^status))
            $fatal(1,"ACK mismatch command=%h status=%h expected=%h",cmd,replies[before_count+4],status);
    endtask
    function automatic [31:0] crc_event(input reg [31:0] crc,input reg [31:0] delay_ms,input reg [7:0] note,velocity);
        reg [47:0] bytes_in={velocity,note,delay_ms};reg [31:0] value=crc;
        for(int b=0;b<6;b++)begin
            value^={24'd0,bytes_in[b*8+:8]};
            for(int k=0;k<8;k++)value=(value>>1)^(value[0]?32'hEDB88320:32'd0);
        end
        return value;
    endfunction
    task automatic event_upload(input int index,delay_ms,note,velocity);
        request('h51,{8'(velocity),8'(note),32'(delay_ms),16'(index)},0);
    endtask
    task automatic wait_dark;
        int first_frame,limit;
        first_frame=frames;limit=0;
        while(frames<first_frame+3) begin
            tick();limit++;
            if(limit>4*FRAME_CLOCKS)$fatal(1,"LED frames stopped");
        end
        if(last_frame!=0)$fatal(1,"LED output did not clear after guide stopped");
    endtask
    reg [31:0] crc;
    int limit;
    initial begin
        expect_60[0+:24]=24'h200000;expect_64[24+:24]=24'h200000;
        repeat(4)tick();@(negedge clk);reset_n=1;
        while(!initialized)tick();
        request('h73,64'h4449554700000000,0);
        request('h72,{32'h44495547,8'd60,8'd1,16'd0},0);
        request('h72,{32'h44495547,8'd64,8'd1,16'd1},0);
        request('h50,64'h0000000000010004,0);
        event_upload(0,0,60,90);event_upload(1,35,60,0);
        event_upload(2,0,64,80);event_upload(3,35,64,0);
        crc=32'hFFFFFFFF;
        crc=crc_event(crc,0,60,90);crc=crc_event(crc,35,60,0);
        crc=crc_event(crc,0,64,80);crc=crc_event(crc,35,64,0);
        request('h52,{8'd0,8'd1,16'd4,~crc},0);
        guide_watch=1;
        request('h59,0,0);
        // No more Bluetooth traffic while the complete score is running.
        limit=0;while(auto_playing||auto_flushing) begin tick();limit++;if(limit>CLOCK_HZ/2)$fatal(1,"Guide did not finish");end
        wait_dark();
        if(!saw_60||!saw_64||guide_leak)$fatal(1,"LED frames or silent guide missing: 60=%0d 64=%0d leak=%0d",saw_60,saw_64,guide_leak);
        // Local stop works independently of the phone after another start.
        saw_60=0;request('h59,0,0);
        limit=0;while(!saw_60)begin tick();limit++;if(limit>3*FRAME_CLOCKS)$fatal(1,"Restart did not light note 60");end
        @(negedge clk);stop_button_n=0;repeat(40)tick();@(negedge clk);stop_button_n=1;
        limit=0;while(auto_playing||auto_flushing)begin tick();limit++;if(limit>CLOCK_HZ/2)$fatal(1,"Local stop failed");end
        wait_dark();
        if(guide_leak||reply_overflow)$fatal(1,"Guide leaked MIDI or reply FIFO overflowed");
        $display("UPLOADED_GUIDE_LED_OK UART/CRC/160-LED physical-rate frames/offline finish/local stop/no audio frames=%0d",frames);
        $finish;
    end
    initial begin #400000000; $fatal(1,"Uploaded LED guide timeout");end
endmodule
