`timescale 1ns/1ps
// Full RGB top: a modelled CH376 keyboard must still play through the FM core
// while a phone-uploaded score drives LEDs without injecting score audio.
// This test shortens CH376 boot waits and uses 32 LEDs to reduce runtime.
module tb_top_guide_concurrent;
    localparam integer CPB=434, LEDS=32, BIT_CLOCKS=63, HIGH0=15, HIGH1=33, GAP_CLOCKS=16000;
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
    defparam dut.u_tutorial.LED_COUNT=32;
    defparam dut.u_tutorial.MAP_FILE="sim/calibration_test_map.mem";
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
    reg [7:0] replies[0:511];int reply_count=0,frames=0;
    reg saw_manual_on=0,saw_manual_off=0,saw_voice=0,saw_pcm=0,guide_leak=0,watch_guide=0;
    reg saw_60=0,saw_64=0;
    reg [LEDS*24-1:0] decoded=0,last_frame=0,expect_60=0,expect_64=0;
    int low_run=0,cell_tick=0,bit_number=0,highs=0;reg capturing=0;
    always @(posedge clk)begin
        #1;
        if(dut.reset_n)begin
            if(rx_valid)begin replies[reply_count]=rx_byte;reply_count++;end
            if(watch_guide && dut.event_valid)begin
                if(dut.event_data[23:8]==16'h9043 && dut.event_data[6:0]!=0)saw_manual_on=1;
                if(dut.event_data[23:8]==16'h8043 || (dut.event_data[23:8]==16'h9043 && dut.event_data[6:0]==0))saw_manual_off=1;
                if((dut.event_data[23:8]==16'h903c || dut.event_data[23:8]==16'h9040) && dut.event_data[6:0]!=0)guide_leak=1;
            end
            if(watch_guide && dut.u_tutorial.auto_midi_valid)guide_leak=1;
            if(watch_guide && dut.voices!=0)saw_voice=1;
            if(watch_guide && dut.tick && dut.pcm!=0)saw_pcm=1;
            if(!capturing && ws && low_run>=GAP_CLOCKS)begin capturing=1;cell_tick=0;bit_number=0;highs=0;decoded=0;end
            if(capturing)begin
                if(ws)highs++;
                if(cell_tick==BIT_CLOCKS-1)begin
                    if(highs!=HIGH0 && highs!=HIGH1)$fatal(1,"WS2812 pulse width %0d",highs);
                    decoded[(bit_number/24)*24+23-(bit_number%24)]=(highs==HIGH1);
                    cell_tick=0;highs=0;bit_number++;
                    if(bit_number==LEDS*24)begin
                        capturing=0;last_frame=decoded;frames++;
                        if(watch_guide && decoded==expect_60)saw_60=1;
                        if(watch_guide && decoded==expect_64)saw_64=1;
                    end
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
    function automatic [31:0] crc_event(input reg [31:0] crc,input reg [31:0] delay_ms,input reg [7:0] note,velocity);
        reg [47:0] bytes_in={velocity,note,delay_ms};reg [31:0] value=crc;
        for(int b=0;b<6;b++)begin value^={24'd0,bytes_in[b*8+:8]};
            for(int k=0;k<8;k++)value=(value>>1)^(value[0]?32'hEDB88320:32'd0);end
        return value;
    endfunction
    task automatic event_upload(input int index,delay_ms,note,velocity);
        request('h51,{8'(velocity),8'(note),32'(delay_ms),16'(index)},0);
    endtask
    reg [31:0] crc;int limit,first_frame;
    initial begin
        expect_60[0+:24]=24'h200000;expect_64[24+:24]=24'h200000;
        repeat(10)tick();@(negedge clk);reset_button_n=1;
        limit=0;while(!dut.tutorial_initialized||!dut.ch376_configured)begin
            tick();limit++;if(limit>3000000)$fatal(1,"boot or CH376 model did not become ready");
        end
        request('h72,{32'h44495547,8'd60,8'd1,16'd0},0);
        request('h72,{32'h44495547,8'd64,8'd1,16'd1},0);
        request('h50,64'h0000000000010004,0);
        event_upload(0,0,60,90);event_upload(1,24,60,0);
        event_upload(2,0,64,80);event_upload(3,24,64,0);
        crc=32'hffffffff;crc=crc_event(crc,0,60,90);crc=crc_event(crc,24,60,0);
        crc=crc_event(crc,0,64,80);crc=crc_event(crc,24,64,0);
        request('h52,{8'd0,8'd1,16'd4,~crc},0);
        watch_guide=1;request('h59,0,0);
        if(!dut.auto_playing)$fatal(1,"score guide did not start");
        keyboard.queue_event({8'd80,8'd67,8'h90,8'h09});
        limit=0;while(!saw_manual_on||!saw_voice||!saw_pcm||!saw_60)begin
            tick();limit++;if(limit>900000)$fatal(1,"simultaneous guide/manual path stalled on=%b voice=%b pcm=%b led60=%b",saw_manual_on,saw_voice,saw_pcm,saw_60);
        end
        if(!dut.auto_playing)$fatal(1,"manual note was observed only after guide ended");
        keyboard.queue_event({8'd0,8'd67,8'h80,8'h08});
        limit=0;while(!saw_manual_off)begin tick();limit++;if(limit>900000)$fatal(1,"manual note release not propagated");end
        limit=0;while(dut.auto_playing||dut.auto_flushing)begin tick();limit++;if(limit>4000000)$fatal(1,"guide did not finish");end
        first_frame=frames;limit=0;while(frames<first_frame+3)begin tick();limit++;if(limit>4*FRAME_CLOCKS)$fatal(1,"LED frames stopped");end
        if(!saw_64||last_frame!=0||guide_leak||dut.tutorial_reply_overflow)
            $fatal(1,"guide/manual conflict or LED error led64=%b dark=%b leak=%b overflow=%b",saw_64,last_frame==0,guide_leak,dut.tutorial_reply_overflow);
        $display("TOP_GUIDE_CONCURRENT_OK UART upload/CRC/LED frames/modelled CH376 manual on+off/FM PCM/no score audio");
        $finish;
    end
    initial begin #200000000;$fatal(1,"top guide concurrent timeout");end
endmodule
