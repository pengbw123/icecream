`timescale 1ns/1ps
// Complete RTL top, GPIO UART, behavioral CH376 SPI peripheral, and WS2812 output.
// Only CH376 startup wait parameters are shortened; the top reset, 50 MHz clock,
// UART and 160-LED serializer retain their production values.
module tb_top_boot_jdy_ch376;
    localparam integer CPB=434, LEDS=160, BIT_CLOCKS=63, HIGH0=15, HIGH1=33, GAP_CLOCKS=16000;
    localparam integer FRAME_CLOCKS=LEDS*24*BIT_CLOCKS+GAP_CLOCKS+LEDS+20;
    reg clk=0;always #10 clk=~clk;
    reg reset_button_n=0,bt_rx=1,attached=1;
    wire uart_tx,bt_tx,chcs,chsck,chmosi,chmiso,chint,sdcs,sdclk,sdmosi,ib,il,id,am,ab,al,ad,ws,pclk,de,hs,vs,bl,tpr,sdio,ss,sl;
    wire [4:0] rr,bb;wire [5:0] gg;wire [7:0] led;
    tri1 cscl,csda,tscl,tsda,tint;
    top_138k dut(.clk(clk),.reset_button_n(reset_button_n),.uart_rx_pin(1'b1),.uart_tx_pin(uart_tx),
      .bluetooth_rx_pin(bt_rx),.bluetooth_tx_pin(bt_tx),.tutorial_start_n(1'b1),.tutorial_stop_n(1'b1),
      .ch376_cs_n(chcs),.ch376_sck(chsck),.ch376_mosi(chmosi),.ch376_miso(chmiso),.ch376_int_n(chint),
      .sd_cs_n(sdcs),.sd_clk(sdclk),.sd_mosi(sdmosi),.sd_miso(1'b1),.i2s_bclk(ib),.i2s_lrclk(il),.i2s_din(id),
      .aud_mclk(am),.aud_bclk(ab),.aud_lrclk(al),.aud_dacdat(ad),.codec_scl(cscl),.codec_sda(csda),.ws2812_data(ws),
      .lcd_pclk(pclk),.lcd_de(de),.lcd_hsync(hs),.lcd_vsync(vs),.lcd_bl(bl),.lcd_r(rr),.lcd_b(bb),.lcd_g(gg),
      .tp_scl(tscl),.tp_sda(tsda),.tp_int(tint),.tp_rst(tpr),.seg7_dio(sdio),.seg7_sclk(ss),.seg7_rclk(sl),.status_led(led));
    // 100 ms / 50 ms / 20 ms / 100 ms hardware waits are simulated shorter.
    defparam dut.u_ch376.POWER_WAIT=1000;
    defparam dut.u_ch376.RESET_WAIT=2000;
    defparam dut.u_ch376.BUS_WAIT=1000;
    defparam dut.u_ch376.ATTACH_WAIT=1000;
    defparam dut.u_ch376.POLL_WAIT=500;
    defparam dut.u_ch376.CONTROL_TIMEOUT=2000000;
    defparam dut.u_ch376.IRQ_TIMEOUT=100000;
    ch376_usb_model keyboard(.cs_n(chcs),.sck(chsck),.mosi(chmosi),.miso(chmiso),.attached(attached),.interrupt_n(chint));
    wire [7:0] rx_byte;wire rx_valid;
    uart_rx #(.CLKS_PER_BIT(CPB)) monitor(.clk(clk),.reset_n(dut.reset_n),.rx(bt_tx),.data(rx_byte),.valid(rx_valid),.busy());

    reg [7:0] replies[0:255];int reply_count=0,pclk_count=0,i2s_count=0,frames=0;
    reg saw_de=0,saw_key_on=0,saw_key_off=0,saw_voice=0,saw_pcm=0;
    reg [LEDS*24-1:0] decoded=0,last_frame=0,expected_on=0;
    int low_run=0,cell_tick=0,bit_number=0,highs=0;
    reg capturing=0;
    always @(posedge pclk) begin pclk_count++;if(de)saw_de=1;end
    always @(posedge ib) i2s_count++;
    always @(posedge clk) begin
        #1;
        if (dut.reset_n) begin
            if(rx_valid)begin replies[reply_count]=rx_byte;reply_count++;end
            if(dut.event_valid && dut.event_data[23:8]==16'h903c && dut.event_data[6:0]!=0)saw_key_on=1;
            if(dut.event_valid && (dut.event_data[23:8]==16'h803c ||
               (dut.event_data[23:8]==16'h903c && dut.event_data[6:0]==0)))saw_key_off=1;
            if(dut.voices!=0)saw_voice=1;
            if(dut.tick && dut.pcm!=0)saw_pcm=1;
            if(!capturing && ws && low_run>=GAP_CLOCKS)begin
                capturing=1;cell_tick=0;bit_number=0;highs=0;decoded=0;
            end
            if(capturing)begin
                if(ws)highs++;
                if(cell_tick==BIT_CLOCKS-1)begin
                    if(highs!=HIGH0 && highs!=HIGH1)$fatal(1,"WS2812 pulse width %0d",highs);
                    decoded[(bit_number/24)*24+23-(bit_number%24)]=(highs==HIGH1);
                    cell_tick=0;highs=0;bit_number++;
                    if(bit_number==LEDS*24)begin capturing=0;last_frame=decoded;frames++;end
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
        for(int b=0;b<8;b++)begin byte_out(body[b*8+:8]);sum^=body[b*8+:8];end
        byte_out(sum);limit=0;
        while(reply_count<before_count+6)begin tick();limit++;if(limit>2*FRAME_CLOCKS+CPB*600)$fatal(1,"JDY ACK timed out cmd=%h",cmd);end
        if(replies[before_count]!='ha5||replies[before_count+1]!='h5a||replies[before_count+2]!='hf0||
           replies[before_count+3]!=cmd||replies[before_count+4]!=status||replies[before_count+5]!=('hf0^cmd^status))
            $fatal(1,"JDY ACK mismatch cmd=%h actual=%h expected=%h",cmd,replies[before_count+4],status);
    endtask
    task automatic wait_frame(input reg [LEDS*24-1:0] expected);
        int limit=0;
        while(last_frame!=expected)begin tick();limit++;if(limit>4*FRAME_CLOCKS)$fatal(1,"LED frame missing expected=%h",expected[47:0]);end
    endtask
    int limit;
    initial begin
        expected_on[0+:24]=24'h200000;
        repeat(10)tick();@(negedge clk);reset_button_n=1;
        repeat(65530)tick();if(dut.reset_n)$fatal(1,"top reset released before startup counter completed");
        repeat(10)tick();if(!dut.reset_n)$fatal(1,"top reset did not release");
        $display("TOP_BOOT reset_released");$fflush();
        limit=0;while(!dut.tutorial_initialized)begin tick();limit++;if(limit>2*FRAME_CLOCKS)$fatal(1,"tutorial initialization stalled");end
        if(!dut.video_lock || !bl || pclk_count<100 || !saw_de || i2s_count<100)
            $fatal(1,"screen/audio clocks did not start lock=%b bl=%b pclk=%0d de=%b i2s=%0d",dut.video_lock,bl,pclk_count,saw_de,i2s_count);
        $display("TOP_BOOT video/audio clocks and tutorial ready");$fflush();
        request('h75,64'h4449554700000000,0);
        request('h72,{32'h44495547,8'd60,8'd1,16'd0},0);
        $display("TOP_BOOT JDY probe and mapping ACK OK");$fflush();
        limit=0;while(!dut.ch376_configured)begin tick();limit++;if(limit>3000000)$fatal(1,"CH376 model did not enumerate fault=%h",dut.ch376_fault);end
        if(!dut.ch376_present||dut.ch376_fault!=0)$fatal(1,"CH376 status invalid");
        $display("TOP_BOOT CH376 enumerated");$fflush();
        keyboard.queue_event({8'd80,8'd60,8'h90,8'h09});
        limit=0;while(!saw_key_on||!saw_voice||!saw_pcm)begin
            tick();limit++;if(limit>1000000)$fatal(1,"key/audio path stalled event=%b voice=%b pcm=%b",saw_key_on,saw_voice,saw_pcm);
        end
        wait_frame(expected_on);
        keyboard.queue_event({8'd0,8'd60,8'h80,8'h08});
        limit=0;while(!saw_key_off)begin tick();limit++;if(limit>1000000)$fatal(1,"key release not propagated");end
        wait_frame(0);
        if(dut.tutorial_reply_overflow)$fatal(1,"JDY reply FIFO overflow");
        $display("TOP_BOOT_JDY_CH376_OK real reset/JDY UART/modelled CH376/SPI/MIDI/FM PCM/RGB/160-LED frames=%0d",frames);
        $finish;
    end
    initial begin #100000000;$fatal(1,"top boot integration timeout");end
endmodule
