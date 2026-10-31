`timescale 1ns/1ps
module tb_score_guard;
    reg external_busy=0;
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
    sunny_tutorial_system #(.CLK_HZ(CLOCK_HZ),.UART_CLKS_PER_BIT(CPB),.LED_COUNT(6),.EXTERNAL_GUARD(1),.SYNTH_VOICE_COUNT(32),
        .BIT_CYCLES(7),.T0H_CYCLES(2),.T1H_CYCLES(4),.RESET_CYCLES(32),.BUTTON_CYCLES(12),
        .MAP_FILE("sim/tutorial_map_test.mem")) dut(.*);
    wire [7:0] rx_byte;wire rx_valid;
    uart_rx #(.CLKS_PER_BIT(CPB)) monitor(.clk(clk),.reset_n(reset_n),.rx(bt_tx),.data(rx_byte),.valid(rx_valid),.busy());
    reg [7:0] replies[0:2047];int reply_count=0,event_count=0,checks=0;
    reg [31:0] events[0:127];
    always @(posedge clk)begin
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
        while(reply_count<before_count+count)begin tick();timeout++;if(timeout>CPB*400)$fatal(1,"ACK timed out");end
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
    reg [31:0] crc,held_word;
    int before_count,start_events,limit;
    reg [7:0] sum;
    initial begin
        repeat(4)tick();@(negedge clk);reset_n=1;while(!initialized)tick();
        before_count=reply_count;packet('h57,64'h0000000012345678);receive_bytes(before_count,20);
        if(replies[before_count+11]!=32||{replies[before_count+10],replies[before_count+9]}!=8192)$fatal(1,"Migrated capability is not 8192/32");
        external_busy=1;repeat(4)tick();request('h70,64'h4449554700000001,1);
        request('h50,64'h0000000000010002,0);event_upload(0,0,60,100);event_upload(1,200,60,0);
        crc=crc_event(crc_event(32'hffffffff,0,60,100),200,60,0);
        request('h52,{8'd0,8'd1,16'd2,~crc},0);request('h53,0,1);
        external_busy=0;repeat(4)tick();auto_midi_ready=0;request('h53,0,0);
        if(!auto_midi_valid)$fatal(1,"Score never issued note");held_word=auto_midi_event;
        external_busy=1;repeat(200)tick();
        if(!auto_flushing||auto_midi_event!==held_word||!auto_midi_valid)$fatal(1,"Mode takeover revoked pending event");
        auto_midi_ready=1;drain();repeat(1000)tick();
        if(event_count!=3||auto_flushing)$fatal(1,"Mode takeover duplicated cleanup or failed to stop");
        external_busy=0;repeat(4)tick();request('h53,0,0);drain();
        if(event_count!=7||reply_overflow)$fatal(1,"Score replay after takeover failed");
        $display("PASS imported Bluetooth integration: 8192 events/32 voices, busy NAK, edge-triggered mode cancellation, stalled event stability, bounded cleanup and replay");$finish;
    end
    initial begin #300000000; $fatal(1,"Score/tutorial system timeout"); end
endmodule
