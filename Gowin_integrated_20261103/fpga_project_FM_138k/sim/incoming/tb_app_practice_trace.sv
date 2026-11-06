`timescale 1ns/1ps
// Exact Android GATT frame capture, replayed into the matching 138K RTL.
module tb_app_practice_trace;
    localparam integer CLK_HZ=100000,CPB=8,LED_COUNT=64,EVENTS=12;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,bt_rx=1,key_valid=0;reg [31:0] key_event=0;
    wire bt_tx,playing,flushing,midi_valid,initialized,count_in;
    sunny_tutorial_system #(.CLK_HZ(CLK_HZ),.UART_CLKS_PER_BIT(CPB),.LED_COUNT(LED_COUNT),
        .BIT_CYCLES(7),.T0H_CYCLES(2),.T1H_CYCLES(4),.RESET_CYCLES(32),
        .MAP_FILE("sim/tutorial_map_test.mem")) dut (
        .clk(clk),.reset_n(reset_n),.external_mode_busy(1'b0),.mode_lock(),.bt_rx(bt_rx),.bt_tx(bt_tx),
        .start_button_n(1'b1),.stop_button_n(1'b1),.live_midi_event(32'd0),.live_midi_valid(1'b0),
        .key_midi_event(key_event),.key_midi_valid(key_valid),.key_source(2'd0),
        .auto_midi_event(),.auto_midi_valid(midi_valid),.auto_midi_ready(1'b1),
        .auto_playing(playing),.auto_flushing(flushing),.led_data(),.running(),.count_in(count_in),
        .beat_active(),.initialized(initialized),.mapping_missing(),.frame_done(),.reply_overflow());
    wire [7:0] rx_data;wire rx_valid;
    uart_rx #(.CLKS_PER_BIT(CPB)) monitor(.clk(clk),.reset_n(reset_n),.rx(bt_tx),.data(rx_data),.valid(rx_valid),.busy());
    reg [7:0] replies[0:1023];integer received=0;reg watch=0,leak=0;
    always @(posedge clk)begin #1;if(rx_valid)begin replies[received]=rx_data;received++;end if(watch&&midi_valid)leak=1;end
    task automatic tick;@(posedge clk);#2;endtask
    task automatic byte_out(input reg[7:0] v);
        @(negedge clk);bt_rx=0;repeat(CPB)tick();
        for(int i=0;i<8;i++)begin @(negedge clk);bt_rx=v[i];repeat(CPB)tick();end
        @(negedge clk);bt_rx=1;repeat(CPB)tick();
    endtask
    task automatic frame(input reg[95:0] p);
        int base,limit;reg[7:0] c;begin
            base=received;c=p[23:16];for(int i=0;i<12;i++)byte_out(p[i*8+:8]);
            limit=0;while(received<base+6)begin tick();limit++;if(limit>100000)$fatal(1,"ACK timeout %h",c);end
            if(replies[base]!='hA5||replies[base+1]!='h5A||replies[base+2]!='hF0||
                replies[base+3]!=c||replies[base+4]!=0||replies[base+5]!=('hF0^c))$fatal(1,"App frame rejected cmd=%h status=%h",c,replies[base+4]);
        end
    endtask
    task automatic press(input int note,input bit down);
        @(negedge clk);key_event={down?8'h09:8'h08,down?8'h90:8'h80,8'(note),down?8'd90:8'd0};key_valid=1;
        repeat(2)tick();@(negedge clk);key_valid=0;repeat(5)tick();
    endtask
    task automatic target(input int note);
        int limit=0;while(dut.auto_notes!==(128'd1<<note))begin tick();limit++;if(limit>20000)$fatal(1,"expected %0d got %h",note,dut.auto_notes);end
    endtask
    reg [95:0] packets[0:127],tmp;string fixture;int fd,rv,n=0,limit;int melody[0:5]='{60,60,67,67,69,69};
    initial begin
        if(!$value$plusargs("PACKETS=%s",fixture))$fatal(1,"Pass +PACKETS");
        fd=$fopen(fixture,"r");if(fd==0)$fatal(1,"Cannot open App capture");
        while(!$feof(fd))begin rv=$fscanf(fd,"%h\n",tmp);if(rv==1)begin packets[n]=tmp;n++;end end $fclose(fd);
        if(n<20||packets[1][23:16]!='h50||packets[n-1][23:16]!='h5A)$fatal(1,"Unexpected App capture");
        repeat(4)tick();@(negedge clk);reset_n=1;while(!initialized)tick();
        for(int i=0;i<n;i++)begin if(i==n-1)watch=1;frame(packets[i]);end
        if(!dut.score_loaded||!count_in||!dut.score_guide_only)$fatal(1,"Practice did not start with count-in");
        for(int i=0;i<EVENTS;i++)if(dut.auto_player.score_ram[i]!==packets[i+2][87:40])$fatal(1,"score RAM mismatch at %0d",i);
        limit=0;while(count_in)begin tick();limit++;if(limit>400000)$fatal(1,"count-in timeout");end
        for(int i=0;i<6;i++)begin target(melody[i]);press(melody[i],1);press(melody[i],0);end
        limit=0;while(playing||flushing)begin tick();limit++;if(limit>20000)$fatal(1,"score did not finish");end
        repeat(1000)tick();if(dut.auto_notes!=0||leak)$fatal(1,"score stuck or triggered synth");
        $display("APP_138K_PRACTICE_TRACE_OK frames=%0d events=%0d count-in/wait/repeated/CRC/RAM/no-audio",n,EVENTS);$finish;
    end
    initial begin #1000000000;$fatal(1,"test timeout");end
endmodule
