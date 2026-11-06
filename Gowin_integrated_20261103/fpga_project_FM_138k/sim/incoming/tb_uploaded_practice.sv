`timescale 1ns/1ps
// Uploaded-score practice over the real 138K UART decoder and score engine.
module tb_uploaded_practice;
    parameter integer PHYSICAL_TIMING=0;
    localparam integer CLK_HZ=PHYSICAL_TIMING?50000000:100000,CPB=PHYSICAL_TIMING?434:8;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,bt_rx=1,key_valid=0;reg [31:0] key_event=0;reg [1:0] key_source=0;
    wire bt_tx,playing,flushing,midi_valid,initialized,beat_active,count_in;
    sunny_tutorial_system #(.CLK_HZ(CLK_HZ),.UART_CLKS_PER_BIT(CPB),.LED_COUNT(6),
        .BIT_CYCLES(7),.T0H_CYCLES(2),.T1H_CYCLES(4),.RESET_CYCLES(32),
        .MAP_FILE("sim/tutorial_map_test.mem")) dut (
        .clk(clk),.reset_n(reset_n),.external_mode_busy(1'b0),.mode_lock(),.bt_rx(bt_rx),.bt_tx(bt_tx),
        .start_button_n(1'b1),.stop_button_n(1'b1),.live_midi_event(32'd0),.live_midi_valid(1'b0),
        .key_midi_event(key_event),.key_midi_valid(key_valid),.key_source(key_source),
        .auto_midi_event(),.auto_midi_valid(midi_valid),.auto_midi_ready(1'b1),
        .auto_playing(playing),.auto_flushing(flushing),.led_data(),.running(),.count_in(count_in),
        .beat_active(beat_active),.initialized(initialized),.mapping_missing(),.frame_done(),.reply_overflow());
    wire [7:0] rx_data;wire rx_valid;
    uart_rx #(.CLKS_PER_BIT(CPB)) monitor(.clk(clk),.reset_n(reset_n),.rx(bt_tx),.data(rx_data),.valid(rx_valid),.busy());
    reg [7:0] replies[0:4095];integer received=0;reg watch=0,leak=0;
    always @(posedge clk)begin #1;if(rx_valid)begin replies[received]=rx_data;received++;end if(watch&&midi_valid)leak=1;end
    task automatic tick;@(posedge clk);#2;endtask
    task automatic byte_out(input reg[7:0] v);
        @(negedge clk);bt_rx=0;repeat(CPB)tick();
        for(int i=0;i<8;i++)begin @(negedge clk);bt_rx=v[i];repeat(CPB)tick();end
        @(negedge clk);bt_rx=1;repeat(CPB)tick();
    endtask
    task automatic cmd(input reg[7:0] c,input reg[63:0] body,input reg[7:0] wanted);
        int base,cycles;reg[7:0] check;begin
            base=received;check=c;byte_out('hA5);byte_out('h5A);byte_out(c);
            for(int i=0;i<8;i++)begin byte_out(body[i*8+:8]);check^=body[i*8+:8];end byte_out(check);
            cycles=0;while(received<base+6)begin tick();cycles++;if(cycles>CPB*1200)$fatal(1,"ACK timeout %h",c);end
            if(replies[base]!='hA5||replies[base+1]!='h5A||replies[base+2]!='hF0||replies[base+3]!=c||
               replies[base+4]!=wanted||replies[base+5]!=('hF0^c^wanted))$fatal(1,"ACK %h got %h wanted %h",c,replies[base+4],wanted);
        end
    endtask
    function automatic[31:0] crc_event(input reg[31:0] crc,input reg[31:0] delay_ms,input reg[7:0] note,velocity);
        reg[47:0] bytes_in={velocity,note,delay_ms};reg[31:0] v=crc;
        for(int b=0;b<6;b++)begin v^={24'd0,bytes_in[b*8+:8]};for(int k=0;k<8;k++)v=(v>>1)^(v[0]?32'hEDB88320:0);end return v;
    endfunction
    task automatic event_upload(input int index,delay_ms,note,velocity);
        cmd('h51,{8'(velocity),8'(note),32'(delay_ms),16'(index)},0);
    endtask
    task automatic press(input int note,input bit down);
        @(negedge clk);key_event={down?8'h09:8'h08,down?8'h90:8'h80,8'(note),down?8'd90:8'd0};key_valid=1;
        repeat(2)tick();@(negedge clk);key_valid=0;repeat(4)tick();
    endtask
    task automatic wait_mask(input reg[127:0] mask);
        int limit=0;while(dut.auto_notes!==mask)begin tick();limit++;if(limit>20000)$fatal(1,"mask expected %h got %h",mask,dut.auto_notes);end
    endtask
    task automatic wait_end;
        int limit=0;while(playing||flushing)begin tick();limit++;if(limit>CLK_HZ/2)$fatal(1,"practice failed to finish");end repeat(200)tick();
        if(dut.auto_notes!=0||leak)$fatal(1,"mask stuck or MIDI leaked");
    endtask
    function automatic[63:0] practice(input int speed,input int wait_key,input int beats,input int beat_ms);
        return {24'h315047,16'(beat_ms),8'(beats),8'(wait_key),8'(speed)};
    endfunction
    reg [31:0] crc;integer first,limit,elapsed50,elapsed150,timed50,timed150;
    initial begin
        repeat(4)tick();@(negedge clk);reset_n=1;while(!initialized)tick();
        cmd('h50,64'h0000000000010008,0);crc='hFFFFFFFF;
        event_upload(0,0,60,90);crc=crc_event(crc,0,60,90);
        event_upload(1,0,64,90);crc=crc_event(crc,0,64,90);
        event_upload(2,30,60,0);crc=crc_event(crc,30,60,0);
        event_upload(3,0,64,0);crc=crc_event(crc,0,64,0);
        event_upload(4,0,67,90);crc=crc_event(crc,0,67,90);
        event_upload(5,25,67,0);crc=crc_event(crc,25,67,0);
        event_upload(6,0,60,90);crc=crc_event(crc,0,60,90);
        event_upload(7,20,60,0);crc=crc_event(crc,20,60,0);
        cmd('h52,{8'd0,8'd1,16'd8,~crc},0);
        cmd('h5A,practice(49,1,0,20),1);cmd('h5A,practice(100,2,0,20),1);
        press(60,1);watch=1;cmd('h5A,practice(100,1,0,20),0);
        wait_mask((128'd1<<60)|(128'd1<<64));repeat(10000)tick();
        if(!playing)$fatal(1,"wait-key advanced without playing");
        press(60,1);press(65,1);repeat(100)tick();
        if(dut.auto_notes!==((128'd1<<60)|(128'd1<<64)))$fatal(1,"held or incorrect note accepted");
        press(64,1);wait_mask(128'd1<<60);press(60,0);press(60,1);
        wait_mask(128'd1<<67);press(67,1);wait_mask(128'd1<<60);
        press(60,1);repeat(100)tick();if(dut.auto_notes!==(128'd1<<60))$fatal(1,"repeated held note accepted");
        press(60,0);press(60,1);wait_end();press(60,0);press(64,0);press(65,0);press(67,0);
        // Count-in and fixed-rate timing use the uploaded score's beat metadata.
        cmd('h5A,practice(50,0,4,20),0);if(!count_in||!beat_active)$fatal(1,"missing count-in first beat");
        elapsed50=0;while(count_in)begin tick();elapsed50++;if(elapsed50>CLK_HZ/5)$fatal(1,"50%% count-in timeout");end
        cmd('h54,0,0);while(playing||flushing)tick();
        cmd('h5A,practice(150,0,4,20),0);if(!count_in)$fatal(1,"missing fast count-in");
        elapsed150=0;while(count_in)begin tick();elapsed150++;if(elapsed150>CLK_HZ/10)$fatal(1,"150%% count-in timeout");end
        if(!(elapsed50>elapsed150*2))$fatal(1,"count-in speed did not scale: %0d %0d",elapsed50,elapsed150);
        wait_end();
        cmd('h5A,practice(50,0,0,20),0);timed50=0;while(playing||flushing)begin tick();timed50++;if(timed50>CLK_HZ/3)$fatal(1,"slow score timeout");end
        cmd('h5A,practice(150,0,0,20),0);timed150=0;while(playing||flushing)begin tick();timed150++;if(timed150>CLK_HZ/3)$fatal(1,"fast score timeout");end
        if(timed50<=timed150*2)$fatal(1,"score speed did not scale: %0d %0d",timed50,timed150);
        cmd('h5A,practice(100,1,0,20),0);wait_mask((128'd1<<60)|(128'd1<<64));cmd('h54,0,0);wait_end();
        cmd('h59,0,0);wait_end();if(leak)$fatal(1,"score guide triggered synth MIDI");
        $display("UPLOADED_PRACTICE_OK physical=%0d wait/chord/repeated/wrong/held/count-in/rate/stop/old-59/no-audio",PHYSICAL_TIMING);$finish;
    end
    initial begin #1000000000;$fatal(1,"test timeout");end
endmodule
