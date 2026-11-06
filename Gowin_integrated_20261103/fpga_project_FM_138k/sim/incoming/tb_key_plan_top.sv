`timescale 1ns/1ps
// Real top + JDY UART + behavioral CH376 + FM core + physical WS2812 stream.
// Upload frames are emitted by Android Score.uploadFrames(), not hand-built.
// The tutorial millisecond tick and CH376 startup waits are shortened only in
// simulation; the UART, 50 MHz logic and LED bit timing remain production values.
module tb_key_plan_top;
    localparam integer CPB=434,LEDS=160,BIT_CLOCKS=63,GAP=16000;
    localparam integer FRAME_CLOCKS=LEDS*24*BIT_CLOCKS+GAP+LEDS+20;
    reg clk=0;always #10 clk=~clk;
    reg reset_button_n=0,bt_rx=1,attached=1;
    wire uart_tx,bt_tx,chcs,chsck,chmosi,chmiso,chint,sdcs,sdclk,sdmosi,ib,il,id,am,ab,al,ad,ws,pclk,de,hs,vs,bl,tpr,sdio,ss,sl;
    wire [4:0] rr,bb;wire [5:0] gg;wire [7:0] led;tri1 cscl,csda,tscl,tsda,tint;
    top_138k dut(.clk(clk),.reset_button_n(reset_button_n),.uart_rx_pin(1'b1),.uart_tx_pin(uart_tx),
      .bluetooth_rx_pin(bt_rx),.bluetooth_tx_pin(bt_tx),.tutorial_start_n(1'b1),.tutorial_stop_n(1'b1),
      .ch376_cs_n(chcs),.ch376_sck(chsck),.ch376_mosi(chmosi),.ch376_miso(chmiso),.ch376_int_n(chint),
      .sd_cs_n(sdcs),.sd_clk(sdclk),.sd_mosi(sdmosi),.sd_miso(1'b1),.i2s_bclk(ib),.i2s_lrclk(il),.i2s_din(id),
      .aud_mclk(am),.aud_bclk(ab),.aud_lrclk(al),.aud_dacdat(ad),.codec_scl(cscl),.codec_sda(csda),.ws2812_data(ws),
      .lcd_pclk(pclk),.lcd_de(de),.lcd_hsync(hs),.lcd_vsync(vs),.lcd_bl(bl),.lcd_r(rr),.lcd_b(bb),.lcd_g(gg),
      .tp_scl(tscl),.tp_sda(tsda),.tp_int(tint),.tp_rst(tpr),.seg7_dio(sdio),.seg7_sclk(ss),.seg7_rclk(sl),.status_led(led));
    defparam dut.u_ch376.POWER_WAIT=1000;
    defparam dut.u_ch376.RESET_WAIT=2000;
    defparam dut.u_ch376.BUS_WAIT=1000;
    defparam dut.u_ch376.ATTACH_WAIT=1000;
    defparam dut.u_ch376.POLL_WAIT=500;
    defparam dut.u_ch376.CONTROL_TIMEOUT=2000000;
    defparam dut.u_ch376.IRQ_TIMEOUT=100000;
    // Accelerate only the player's 1 ms enable, not the UART decoder timeout.
    initial force dut.u_tutorial.auto_player.ms_div_cnt=16'd49999;
    ch376_usb_model keyboard(.cs_n(chcs),.sck(chsck),.mosi(chmosi),.miso(chmiso),.attached(attached),.interrupt_n(chint));
    wire [7:0] rx_byte;wire rx_valid;
    uart_rx #(.CLKS_PER_BIT(CPB)) monitor(.clk(clk),.reset_n(dut.reset_n),.rx(bt_tx),.data(rx_byte),.valid(rx_valid),.busy());
    reg [95:0] app_frames[0:10];
    reg [7:0] replies[0:255];int reply_count=0;
    int low_run=0,cell_tick=0,bit_number=0,highs=0;reg capturing=0,auto_leak=0;
    reg [LEDS*24-1:0] decoded=0,last_frame=0,expected=0;
    always @(posedge clk)begin #1;
        if(dut.reset_n)begin
            if(rx_valid)begin replies[reply_count]=rx_byte;reply_count++;end
            if(dut.key_plan_active&&dut.auto_midi_valid)auto_leak=1;
            if(!capturing&&ws&&low_run>=GAP)begin capturing=1;cell_tick=0;bit_number=0;highs=0;decoded=0;end
            if(capturing)begin
                if(ws)highs++;
                if(cell_tick==BIT_CLOCKS-1)begin
                    if(highs!=15&&highs!=33)$fatal(1,"invalid WS2812 pulse width");
                    decoded[(bit_number/24)*24+23-(bit_number%24)]=(highs==33);
                    cell_tick=0;highs=0;bit_number++;
                    if(bit_number==LEDS*24)begin capturing=0;last_frame=decoded;end
                end else cell_tick++;
            end
            if(ws)low_run=0;else low_run++;
        end else begin capturing=0;low_run=0;end
    end
    task automatic tick;@(posedge clk);#2;endtask
    task automatic byte_out(input reg [7:0] value);
        @(negedge clk);bt_rx=0;repeat(CPB)tick();
        for(int b=0;b<8;b++)begin @(negedge clk);bt_rx=value[b];repeat(CPB)tick();end
        @(negedge clk);bt_rx=1;repeat(CPB)tick();
    endtask
    task automatic request(input reg [7:0] cmd,input reg [63:0] body,input reg [7:0] status);
        reg [7:0] sum;int before_count,limit;
        before_count=reply_count;sum=cmd;byte_out('ha5);byte_out('h5a);byte_out(cmd);
        for(int b=0;b<8;b++)begin byte_out(body[b*8+:8]);sum^=body[b*8+:8];end byte_out(sum);
        limit=0;while(reply_count<before_count+6)begin tick();limit++;if(limit>CPB*1000)$fatal(1,"ACK timeout %h",cmd);end
        if(replies[before_count]!='ha5||replies[before_count+1]!='h5a||replies[before_count+2]!='hf0||
           replies[before_count+3]!=cmd||replies[before_count+4]!=status||replies[before_count+5]!=('hf0^cmd^status))
            $fatal(1,"ACK cmd=%h got=%h wanted=%h",cmd,replies[before_count+4],status);
    endtask
    task automatic app_frame(input int index,input reg [7:0] wanted);
        int before_count,limit;reg [7:0] cmd;
        before_count=reply_count;cmd=app_frames[index][16+:8];
        for(int i=0;i<12;i++)byte_out(app_frames[index][i*8+:8]);
        limit=0;while(reply_count<before_count+6)begin tick();limit++;if(limit>CPB*1000)$fatal(1,"App ACK timeout %0d",index);end
        if(replies[before_count]!='ha5||replies[before_count+1]!='h5a||replies[before_count+2]!='hf0||
           replies[before_count+3]!=cmd||replies[before_count+4]!=wanted||replies[before_count+5]!=('hf0^cmd^wanted))
            $fatal(1,"App frame %0d ACK got=%h expected=%h",index,replies[before_count+4],wanted);
    endtask
    function automatic integer gates(input int pitch,input int id);
        integer n;begin gates=0;
            for(n=0;n<32;n++)if(dut.u_audio.u_fm_poly_synth.voice_active[n] && dut.u_audio.u_fm_poly_synth.voice_gate[n] &&
                dut.u_audio.u_fm_poly_synth.voice_note[n]==pitch && dut.u_audio.u_fm_poly_synth.voice_key_id[n]==id)gates++;
        end
    endfunction
    function automatic integer all_gates;
        integer n;begin all_gates=0;for(n=0;n<32;n++)if(dut.u_audio.u_fm_poly_synth.voice_active[n]&&dut.u_audio.u_fm_poly_synth.voice_gate[n])all_gates++;end
    endfunction
    task automatic wait_gate(input int pitch,input int id,input int wanted);
        int count=0;while(gates(pitch,id)!=wanted)begin tick();count++;if(count>1000000)$fatal(1,"gate pitch=%0d id=%0d got=%0d expected=%0d",pitch,id,gates(pitch,id),wanted);end
    endtask
    task automatic key(input int pitch,input bit down);
        keyboard.queue_event({down?8'd80:8'd0,8'(pitch),down?8'h90:8'h80,down?8'h09:8'h08});
    endtask
    task automatic wait_notes(input reg[127:0] wanted);
        int n=0;while(dut.u_tutorial.auto_notes!==wanted)begin tick();n++;if(n>1000000)$fatal(1,"guide mask got=%h want=%h",dut.u_tutorial.auto_notes,wanted);end
    endtask
    task automatic wait_led;
        int n=0;while(last_frame!==expected)begin tick();n++;if(n>4*FRAME_CLOCKS)$fatal(1,"WS2812 guide frame missing");end
    endtask
    integer limit;localparam int KEY_A=67,KEY_B=55,KEY_C=72;
    localparam int ID_A=32+(KEY_A-48),ID_B=32+(KEY_B-48),ID_C=32+(KEY_C-48);
    initial begin
        $readmemh("sim/app_keyplan_trace.mem",app_frames);
        expected[0+:24]=24'h200000;expected[24+:24]=24'h200000;
        repeat(10)tick();@(negedge clk);reset_button_n=1;
        limit=0;while(!dut.tutorial_initialized||!dut.ch376_configured)begin tick();limit++;if(limit>3000000)$fatal(1,"boot stalled");end
        request('h73,64'h4449554700000000,0);
        request('h72,{32'h44495547,8'(KEY_A),8'd1,16'd0},0);
        request('h72,{32'h44495547,8'(KEY_B),8'd1,16'd1},0);
        request('h72,{32'h44495547,8'(KEY_C),8'd1,16'd2},0);
        for(int i=0;i<=8;i++)app_frame(i,0);
        if(dut.voices!=0)$fatal(1,"upload generated sound");
        request('h53,0,1);request('h59,0,1); // mapped data can only be used as manual practice
        key(60,1);wait_gate(60,0,1);app_frame(9,1); // pre-held key prevents mapped start
        key(60,0);wait_gate(60,0,0);
        app_frame(9,0);wait_notes((128'd1<<KEY_A)|(128'd1<<KEY_B));wait_led();
        if(all_gates()!=0||auto_leak)$fatal(1,"guide produced an automatic note");
        key(60,1);wait_gate(60,32+(60-48),1);repeat(100)tick();
        if(dut.u_tutorial.auto_notes!==((128'd1<<KEY_A)|(128'd1<<KEY_B)))$fatal(1,"wrong key advanced wait");
        key(60,0);wait_gate(60,32+(60-48),0);
        key(KEY_A,1);wait_gate(67,ID_A,1);key(KEY_B,1);wait_gate(67,ID_B,1);
        wait_notes(128'd1<<KEY_C);
        key(KEY_A,0);wait_gate(67,ID_A,0);
        if(gates(67,ID_B)!=1)$fatal(1,"releasing first same pitch killed second physical key");
        key(KEY_C,1);wait_gate(72,ID_C,1);
        key(KEY_B,0);wait_gate(67,ID_B,0);key(KEY_C,0);wait_gate(72,ID_C,0);
        limit=0;while(dut.auto_playing||dut.auto_flushing||dut.router_busy)begin tick();limit++;if(limit>1000000)$fatal(1,"normal completion stuck");end
        app_frame(9,0);wait_notes((128'd1<<KEY_A)|(128'd1<<KEY_B));key(KEY_A,1);wait_gate(67,ID_A,1);
        app_frame(10,0);if(gates(67,ID_A)!=1)$fatal(1,"stop silenced held performer note");
        key(KEY_A,0);wait_gate(67,ID_A,0);while(dut.auto_flushing||dut.router_busy)tick();
        app_frame(9,0);wait_notes((128'd1<<KEY_A)|(128'd1<<KEY_B));key(KEY_A,1);wait_gate(67,ID_A,1);key(KEY_B,1);wait_gate(67,ID_B,1);
        @(negedge clk);attached=0;
        limit=0;while(dut.ch376_configured||dut.auto_playing||dut.auto_flushing||dut.router_busy||gates(67,ID_A)||gates(67,ID_B))begin
            tick();limit++;if(limit>2000000)$fatal(1,"disconnect did not stop and release mapped keys");
        end
        if(auto_leak||dut.tutorial_reply_overflow)$fatal(1,"automatic note leaked or reply overflowed");
        $display("KEY_PLAN_TOP_OK App frames/JDY/CH376/LED/no-auto/held/wrong/unison/stop/disconnect");$finish;
    end
    initial begin #200000000;$fatal(1,"key-plan top timeout");end
endmodule
