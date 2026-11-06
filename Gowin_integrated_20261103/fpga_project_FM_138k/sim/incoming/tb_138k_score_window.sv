`timescale 1ns/1ps
// Full Android capture at scaled clocks, or a bounded 50MHz/115200 batch.
// Eight events arrive continuously, faster than the BLE pacing.
module tb_138k_score_window;
    parameter integer PHYSICAL_TIMING=0;
    localparam CPB=PHYSICAL_TIMING?434:8,N=PHYSICAL_TIMING?32:1574;
    localparam CLOCK_HZ=PHYSICAL_TIMING?50000000:100000;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,bt_rx=1;
    wire bt_tx,loaded;
    wire overflow,initialized;
    sunny_tutorial_system #(.CLK_HZ(CLOCK_HZ),.UART_CLKS_PER_BIT(CPB),.LED_COUNT(6),
        .BIT_CYCLES(7),.T0H_CYCLES(2),.T1H_CYCLES(4),.RESET_CYCLES(32),
        .MAP_FILE("sim/tutorial_map_test.mem")) dut (
        .clk(clk),.reset_n(reset_n),.external_mode_busy(1'b0),.mode_lock(),.bt_rx(bt_rx),.bt_tx(bt_tx),.start_button_n(1'b1),.stop_button_n(1'b1),
        .live_midi_event(32'd0),.live_midi_valid(1'b0),.key_midi_event(32'd0),.key_midi_valid(1'b0),.key_source(2'd0),
        .auto_midi_event(),.auto_midi_valid(),.auto_midi_ready(1'b1),.auto_playing(),.auto_flushing(),
        .led_data(),.running(),.count_in(),.beat_active(),.initialized(initialized),.mapping_missing(),.frame_done(),.reply_overflow(overflow));
    assign loaded=dut.score_loaded;
    wire [7:0] rx_data;wire rx_valid;
    uart_rx #(.CLKS_PER_BIT(CPB)) monitor(.clk(clk),.reset_n(reset_n),.rx(bt_tx),.data(rx_data),.valid(rx_valid),.busy());
    reg [7:0] replies[0:9999];int received=0,checks=0,groups=0;
    reg [95:0] packets[0:1576];string fixture;
    always @(posedge clk)begin #1;if(rx_valid)begin replies[received]=rx_data;received++;end end
    task automatic tick;@(posedge clk);#2;endtask
    task automatic byte_out(input reg [7:0] value);
        @(negedge clk);bt_rx=0;repeat(CPB)tick();
        for(int b=0;b<8;b++)begin @(negedge clk);bt_rx=value[b];repeat(CPB)tick();end
        @(negedge clk);bt_rx=1;repeat(CPB)tick();
    endtask
    task automatic raw_packet(input reg [95:0] p);
        for(int b=0;b<12;b++)byte_out(p[b*8+:8]);
    endtask
    task automatic reply_check(input int base,count,input reg [7:0] command,status);
        int waited=0;
        while(received<base+count*6)begin tick();waited++;if(waited>CPB*1000)$fatal(1,"Missing window ACK");end
        for(int n=0;n<count;n++)begin
            if(replies[base+n*6]!='hA5||replies[base+n*6+1]!='h5A||replies[base+n*6+2]!='hF0||
                replies[base+n*6+3]!=command||replies[base+n*6+4]!=status||replies[base+n*6+5]!=('hF0^command^status))
                $fatal(1,"Window ACK mismatch at %0d",base+n*6);
            checks++;
        end
    endtask
    task automatic command_packet(input reg [7:0] command,input reg [63:0] body,input reg [7:0] status);
        reg [95:0] p={8'd0,body,command,8'h5A,8'hA5};reg [7:0] sum=command;int base=received;
        for(int b=0;b<8;b++)sum^=body[b*8+:8];p[95:88]=sum;
        raw_packet(p);reply_check(base,1,command,status);
    endtask
    function automatic [31:0] crc_event(input reg [31:0] previous,input reg [47:0] event_bytes);
        reg [31:0] value=previous;
        for(int b=0;b<6;b++)begin value^={24'd0,event_bytes[b*8+:8]};for(int k=0;k<8;k++)value=(value>>1)^(value[0]?32'hEDB88320:0);end
        return value;
    endfunction
    int base,count;reg [31:0] crc;
    initial begin
        if(!$value$plusargs("PACKETS=%s",fixture))$fatal(1,"Pass Android capture with +PACKETS=");
        $readmemh(fixture,packets);repeat(4)tick();@(negedge clk);reset_n=1;while(!initialized)tick();
        base=received;raw_packet(packets[0]);reply_check(base,1,8'h55,0);groups++;
        command_packet(8'h50,{8'd0,8'd0,8'd0,8'd0,8'd0,8'd1,16'(N)},0);groups++;crc=32'hFFFFFFFF;
        for(int at=0;at<N;at+=8)begin
            count=N-at<8?N-at:8;base=received;
            for(int k=0;k<count;k++)begin raw_packet(packets[at+k+2]);crc=crc_event(crc,packets[at+k+2][87:40]);end
            reply_check(base,count,8'h51,0);groups++;
            if(overflow)$fatal(1,"Reply FIFO overflow during batch");
        end
        if(loaded)$fatal(1,"Loaded before CRC seal");
        // A cleanly framed but wrong whole-score CRC must not unlock PLAY.
        command_packet(8'h52,{8'd0,8'd1,16'(N),(~crc)^32'd1},1);
        if(loaded)$fatal(1,"Wrong CRC was accepted");
        command_packet(8'h52,{8'd0,8'd1,16'(N),~crc},0);groups++;
        if(!loaded||groups!=(N+7)/8+3)$fatal(1,"Full window upload not committed");
        for(int i=0;i<N;i++)begin if(dut.auto_player.score_ram[i]!==packets[i+2][87:40])$fatal(1,"RAM differs at %0d",i);checks++;end
        // Omit an EVENT: later indices and SEAL must reject, never partly load.
        command_packet(8'h50,64'h0000000000010008,0);crc=32'hFFFFFFFF;
        for(int i=0;i<8;i++)begin
            crc=crc_event(crc,packets[i+2][87:40]);
            if(i!=3)begin base=received;raw_packet(packets[i+2]);reply_check(base,1,8'h51,i<3?0:1);end
        end
        command_packet(8'h52,{8'd0,8'd1,16'd8,~crc},1);command_packet(8'h53,64'd0,1);
        if(loaded||overflow)$fatal(1,"Partial loaded or FIFO overflow");
        $display("SCORE_WINDOW_138K_OK events=%0d groups=%0d checks=%0d physical=%0d clock=%0d cpb=%0d Android-bytes CRC/drop/RAM",N,groups,checks,PHYSICAL_TIMING,CLOCK_HZ,CPB);$finish;
    end
    initial begin #10000000000;$fatal(1,"Window test timeout");end
endmodule
