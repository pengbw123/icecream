`timescale 1ns/1ps
module tb_138k_score_tutorial;
    wire external_busy=0;
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
    sunny_tutorial_system #(.CLK_HZ(CLOCK_HZ),.UART_CLKS_PER_BIT(CPB),.LED_COUNT(6),
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
        request('h75,64'h4449554700000000,0);
        request('h76,64'h4449554700000002,1);
        request('h76,64'h4449554700000001,0);
        request('h55,0,0);
        before_count=reply_count;packet('h57,64'h0000000012345678);receive_bytes(before_count,20);
        sum=0;for(int b=2;b<20;b++)sum^=replies[before_count+b];
        if(sum || replies[before_count+2]!='hF1 ||
            {replies[before_count+8],replies[before_count+7],replies[before_count+6],replies[before_count+5]}!=32'h12345678 ||
            {replies[before_count+10],replies[before_count+9]}!=8192 || replies[before_count+11]!=16 ||
            replies[before_count+13]!=1 || replies[before_count+18]!=1)$fatal(1,"Capacity/nonce/voice/v1 capability mismatch");
        request('h56,20,1);request('h53,0,1);request('h50,64'h0000000000010000,1);
        request('h50,64'h0000000000012001,1); // 8193 is outside physical score RAM.
        request('h50,64'h0000000000010004,0);
        request('h51,64'h5A3C000000000001,1); // Wrong index.
        event_upload(0,0,60,90);event_upload(1,20,60,0);event_upload(2,0,64,80);event_upload(3,20,64,0);
        crc=32'hFFFFFFFF;
        crc=crc_event(crc,0,60,90);crc=crc_event(crc,20,60,0);crc=crc_event(crc,0,64,80);crc=crc_event(crc,20,64,0);
        request('h52,{8'd0,8'd1,16'd4,(~crc)^32'd1},1);request('h53,0,1);
        request('h52,{8'd0,8'd1,16'd4,~crc},0);
        // Sunny transpose never touches the stored score's original pitch.
        request('h74,64'h44495547000C0064,0);
        request('h70,64'h4449554700000001,0);
        if(!running)$fatal(1,"Sunny did not start");
        request('h53,0,1);request('h76,64'h4449554700000000,1);
        request('h70,64'h4449554700000000,0);
        auto_midi_ready=0;start_events=event_count;request('h53,0,0);
        limit=0;while(!auto_midi_valid)begin tick();limit++;if(limit>50)$fatal(1,"Missing auto NoteOn");end
        held_word=auto_midi_event;
        if(held_word!={8'h09,8'h90,8'd60,8'd90})$fatal(1,"Autoplay pitch changed by Sunny transpose");
        request('h70,64'h4449554700000001,1);
        @(negedge clk);start_button_n=0;repeat(40)tick();@(negedge clk);start_button_n=1;
        if(running)$fatal(1,"S0 started Sunny during autoplay");
        request('h71,64'h4449554700000001,1);
        request('h54,0,0);
        if(!auto_flushing||!auto_midi_valid||auto_midi_event!=held_word)$fatal(1,"STOP revoked stalled valid/data");
        repeat(100)tick();if(auto_midi_event!=held_word)$fatal(1,"Stalled STOP data changed");
        auto_midi_ready=1;drain();
        if(event_count!=start_events+3||events[start_events]!=held_word||events[start_events+1]!=32'h0BB04000||events[start_events+2]!=32'h0BB07B00)
            $fatal(1,"STOP drain/flush duplicated/dropped events");
        start_events=event_count;request('h53,0,0);drain();
        if(event_count!=start_events+6||events[start_events]!=32'h09903C5A||events[start_events+1]!=32'h08803C00||
            events[start_events+2]!=32'h09904050||events[start_events+3]!=32'h08804000||
            events[start_events+4]!=32'h0BB04000||events[start_events+5]!=32'h0BB07B00)$fatal(1,"Autoplay sequence/end flush mismatch");
        // Offline physical STOP must work without any phone packet.
        request('h53,0,0);@(negedge clk);stop_button_n=0;repeat(40)tick();
        @(negedge clk);stop_button_n=1;drain();
        if(running||auto_playing)$fatal(1,"S1 did not stop both modes");
        // BEGIN invalidates an older committed tune, even if the new upload is abandoned.
        request('h50,64'h0000000000010004,0);event_upload(0,0,60,90);request('h53,0,1);
        request('h76,64'h4449554700000000,0);
        if(reply_overflow)$fatal(1,"Reply FIFO overflow");
        $display("SCORE_TUTORIAL_138K_OK physical=%0d checks=%0d cap/CRC/notes/transpose/NAK/mutex/S0/S1/stalled-stop/end/invalidate",PHYSICAL_TIMING,checks);
        $finish;
    end
    initial begin #300000000; $fatal(1,"Score/tutorial system timeout"); end
endmodule
