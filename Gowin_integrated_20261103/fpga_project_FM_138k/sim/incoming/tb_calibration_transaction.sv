`timescale 1ns/1ps
module tb_calibration_transaction;
    parameter integer PHYSICAL_TIMING=0;
    localparam integer CPB=PHYSICAL_TIMING?434:8;
    localparam integer CLOCK_HZ=PHYSICAL_TIMING?50000000:100000;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,bt_rx=1,start_button_n=1,stop_button_n=1;
    reg [31:0] live_midi_event=0,key_midi_event=0;
    reg live_midi_valid=0,key_midi_valid=0;
    reg [1:0] key_source=0;
    wire bt_tx,led_data,running,count_in,beat_active,initialized,mapping_missing,frame_done,reply_overflow;
    wire [31:0] auto_midi_event;
    wire auto_midi_valid,auto_playing,auto_flushing;
    reg auto_midi_ready=1;
    reg external_mode_busy=0;
    wire mode_lock;
    wire calibration_success;
    sunny_tutorial_system #(.CLK_HZ(CLOCK_HZ),.UART_CLKS_PER_BIT(CPB),.LED_COUNT(32),
        .BIT_CYCLES(7),.T0H_CYCLES(2),.T1H_CYCLES(4),.RESET_CYCLES(32),.BUTTON_CYCLES(12),
        .MAP_FILE("sim/calibration_test_map.mem")) dut(.phone_request_valid(),.phone_request_payload(),.phone_request_ready(1'b0),.phone_response_valid(1'b0),.phone_response_token(16'd0),.phone_response_status(8'd0),.phone_response_value(8'd0),.phone_response_was_write(1'b0),.tone_success(),.*);
    wire [7:0] rx_byte;wire rx_valid;
    uart_rx #(.CLKS_PER_BIT(CPB)) monitor(.clk(clk),.reset_n(reset_n),.rx(bt_tx),.data(rx_byte),.valid(rx_valid),.busy());
    reg [7:0] replies[0:2047];int reply_count=0,event_count=0,checks=0;
    reg [31:0] events[0:127];
    reg guide_watch=0, guide_leak=0, saw_note60=0, saw_note64=0;
    always @(posedge clk)begin
        if(reset_n&&guide_watch)begin
            if(auto_midi_valid)guide_leak=1;
            if(dut.auto_notes[60])saw_note60=1;
            if(dut.auto_notes[64])saw_note64=1;
        end
        if(reset_n&&auto_midi_valid&&auto_midi_ready)begin events[event_count]=auto_midi_event;event_count++;end
        #1;if(rx_valid)begin replies[reply_count]=rx_byte;reply_count++;end
    end
    task automatic tick;@(posedge clk);#2;endtask
    task automatic byte_out(input reg [7:0] value);
        @(negedge clk);bt_rx=0;repeat(CPB)tick();
        for(int b=0;b<8;b++)begin @(negedge clk);bt_rx=value[b];repeat(CPB)tick();end
        @(negedge clk);bt_rx=1;repeat(CPB)tick();
    endtask
    task automatic packet(input reg [7:0] cmd,input reg [63:0] body);
        reg [7:0] sum=cmd;
        byte_out('hA5);byte_out('h5A);byte_out(cmd);
        for(int b=0;b<8;b++)begin byte_out(body[b*8+:8]);sum^=body[b*8+:8];end
        byte_out(sum);
    endtask
    task automatic receive_bytes(input int before_count,count);
        int timeout=0;
        while(reply_count<before_count+count)begin tick();timeout++;if(timeout>CPB*3000)$fatal(1,"ACK timed out");end
    endtask
    task automatic request(input reg [7:0] cmd,input reg [63:0] body,input reg [7:0] status);
        int before_count=reply_count;
        packet(cmd,body);receive_bytes(before_count,6);
        if(replies[before_count]!='hA5||replies[before_count+1]!='h5A||replies[before_count+2]!='hF0||
           replies[before_count+3]!=cmd||replies[before_count+4]!=status||replies[before_count+5]!=('hF0^cmd^status))
            $fatal(1,"ACK mismatch cmd=%h got=%h expected=%h",cmd,replies[before_count+4],status);
        checks++;
    endtask
    function automatic [31:0] crc_event(input reg [31:0] crc,input reg [31:0] delay_ms,input reg [7:0] note,velocity);
        reg [47:0] bytes_in={velocity,note,delay_ms};reg [31:0] value=crc;
        for(int b=0;b<6;b++)begin
            value^={24'd0,bytes_in[b*8+:8]};
            for(int bit_n=0;bit_n<8;bit_n++)value=(value>>1)^(value[0]?32'hEDB88320:32'd0);
        end
        return value;
    endfunction
    task automatic event_upload(input int index,delay_ms,note,velocity);
        request('h51,{8'(velocity),8'(note),32'(delay_ms),16'(index)},0);
    endtask
    task automatic drain;
        int limit=0;
        while(auto_playing||auto_flushing||auto_midi_valid)begin tick();limit++;if(limit>CLOCK_HZ/2)$fatal(1,"Autoplay did not finish");end
        if(dut.player.held_notes)$fatal(1,"Automatic events leaked into held keys");
    endtask

    task automatic map_note(input int led,note);
        request('h72,{32'h44495547,8'(note),8'd1,16'(led)},0);
    endtask
    initial begin
        repeat(4)tick();@(negedge clk);reset_n=1;while(!initialized)tick();
        request('h77,64'h4449554700000000,1);
        request('h73,64'h4449554700000000,0);
        for(int i=0;i<24;i++)map_note(i,48+i);
        request('h77,64'h4449554700000000,1);
        if(calibration_success)$fatal(1,"partial transaction succeeded");
        map_note(24,72);request('h72,64'h4449554700020019,0);
        request('h77,64'h4449554700000000,0);
        if(!calibration_success)$fatal(1,"banner not enabled after complete map");
        if(!PHYSICAL_TIMING)begin repeat(CLOCK_HZ*4+20)tick();if(calibration_success)$fatal(1,"banner did not automatically expire");end
        request('h73,64'h4449554700000000,0);if(calibration_success)$fatal(1,"new clear did not hide banner");
        for(int i=0;i<25;i++)map_note(i,48+i);
        map_note(25,48);request('h77,64'h4449554700000000,1);
        request('h73,64'h4449554700000000,0);
        for(int i=0;i<25;i++)map_note(i,48+i);
        map_note(0,90);request('h77,64'h4449554700000000,1);
        request('h73,64'h4449554700000000,0);
        for(int i=0;i<25;i++)map_note(i,48+i);
        request('h72,64'h4449554700020019,0);request('h72,64'h444955470002001a,0);
        request('h77,64'h4449554700000000,1);
        request('h73,64'h4449554700000000,0);
        for(int i=0;i<25;i++)map_note(i,48+i);
        request('h70,64'h4449554700000001,0);request('h70,64'h4449554700000000,0);
        repeat(10)tick();request('h77,64'h4449554700000000,1);
        request('h73,64'h4449554700000000,0);
        for(int i=0;i<25;i++)map_note(i,48+i);
        if(!PHYSICAL_TIMING)begin repeat(CLOCK_HZ*15+100)tick();request('h77,64'h4449554700000000,1);end
        $display("CALIBRATION_TRANSACTION_OK physical=%0d partial, complete, duplicate note/LED/beat, clear; timeout and expiry tested only in fast mode", PHYSICAL_TIMING);$finish;
    end
endmodule

