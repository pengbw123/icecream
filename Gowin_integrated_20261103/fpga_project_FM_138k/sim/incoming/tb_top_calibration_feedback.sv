`timescale 1ns/1ps
// GPIO JDY calibration through the complete top to the RGB compositor.
// 32 LEDs instead of 160 are used only to shorten this transaction test.
module tb_top_calibration_feedback;
    localparam integer CPB=434;
    reg clk=0;always #10 clk=~clk;
    reg reset_button_n=0,bt_rx=1;
    wire uart_tx,bt_tx,chcs,chsck,chmosi,sdcs,sdclk,sdmosi,ib,il,id,am,ab,al,ad,ws,pclk,de,hs,vs,bl,tpr,sdio,ss,sl;
    wire [4:0] rr,bb;wire [5:0] gg;wire [7:0] led;
    tri1 cscl,csda,tscl,tsda,tint;
    top_138k dut(.clk(clk),.reset_button_n(reset_button_n),.uart_rx_pin(1'b1),.uart_tx_pin(uart_tx),
      .bluetooth_rx_pin(bt_rx),.bluetooth_tx_pin(bt_tx),.tutorial_start_n(1'b1),.tutorial_stop_n(1'b1),
      .ch376_cs_n(chcs),.ch376_sck(chsck),.ch376_mosi(chmosi),.ch376_miso(1'b1),.ch376_int_n(1'b1),
      .sd_cs_n(sdcs),.sd_clk(sdclk),.sd_mosi(sdmosi),.sd_miso(1'b1),.i2s_bclk(ib),.i2s_lrclk(il),.i2s_din(id),
      .aud_mclk(am),.aud_bclk(ab),.aud_lrclk(al),.aud_dacdat(ad),.codec_scl(cscl),.codec_sda(csda),.ws2812_data(ws),
      .lcd_pclk(pclk),.lcd_de(de),.lcd_hsync(hs),.lcd_vsync(vs),.lcd_bl(bl),.lcd_r(rr),.lcd_b(bb),.lcd_g(gg),
      .tp_scl(tscl),.tp_sda(tsda),.tp_int(tint),.tp_rst(tpr),.seg7_dio(sdio),.seg7_sclk(ss),.seg7_rclk(sl),.status_led(led));
    defparam dut.u_tutorial.LED_COUNT=32;
    defparam dut.u_tutorial.MAP_FILE="sim/calibration_test_map.mem";
    wire [7:0] rx_byte;wire rx_valid;
    uart_rx #(.CLKS_PER_BIT(CPB)) monitor(.clk(clk),.reset_n(dut.reset_n),.rx(bt_tx),.data(rx_byte),.valid(rx_valid),.busy());
    reg [7:0] replies[0:511];int reply_count=0,cover_pixels=0,white_pixels=0,green_pixels=0;
    always @(posedge clk) begin #1;if(dut.reset_n&&rx_valid)begin replies[reply_count]=rx_byte;reply_count++;end end
    always @(posedge pclk) begin
        #1;
        if(de && dut.u_video.cal_frame && dut.u_video.cal_cover)begin
            cover_pixels++;
            if(rr==5'h1f && gg==6'h3f && bb==5'h1f)white_pixels++;
            if(rr==5'h00 && gg==6'h16 && bb==5'h07)green_pixels++;
        end
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
        while(reply_count<before_count+6)begin tick();limit++;if(limit>CPB*3000)$fatal(1,"JDY ACK timeout cmd=%h",cmd);end
        if(replies[before_count]!='ha5||replies[before_count+1]!='h5a||replies[before_count+2]!='hf0||
           replies[before_count+3]!=cmd||replies[before_count+4]!=status||replies[before_count+5]!=('hf0^cmd^status))
            $fatal(1,"JDY ACK mismatch cmd=%h actual=%h expected=%h",cmd,replies[before_count+4],status);
    endtask
    int limit;
    initial begin
        repeat(10)tick();@(negedge clk);reset_button_n=1;
        limit=0;while(!dut.tutorial_initialized)begin tick();limit++;if(limit>200000)$fatal(1,"boot/map init stalled");end
        request('h73,64'h4449554700000000,0);
        for(int i=0;i<24;i++)request('h72,{32'h44495547,8'(48+i),8'd1,16'(i)},0);
        request('h77,64'h4449554700000000,1);
        if(dut.calibration_success||dut.u_video.cal_frame)$fatal(1,"partial mapping showed success");
        request('h72,{32'h44495547,8'd72,8'd1,16'd24},0);
        request('h77,64'h4449554700000000,0);
        if(!dut.calibration_success)$fatal(1,"completed mapping did not set success");
        $display("TOP_CALIBRATION complete ACK received; waiting for screen");$fflush();
        limit=0;while(white_pixels<100||green_pixels<1000)begin
            tick();limit++;
            if(limit>2000000)$fatal(1,"screen success banner missing cover=%0d white=%0d green=%0d",cover_pixels,white_pixels,green_pixels);
        end
        if(dut.tutorial_reply_overflow)$fatal(1,"JDY reply overflow");
        $display("TOP_CALIBRATION_FEEDBACK_OK partial rejection/25 mappings/ACK/RGB banner white=%0d green=%0d",white_pixels,green_pixels);
        $finish;
    end
    initial begin #200000000;$fatal(1,"top calibration feedback timeout");end
endmodule
