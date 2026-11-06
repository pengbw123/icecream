`timescale 1ns/1ps
module tb_integrated_mode_guard;
    reg clk=0; always #10 clk=~clk;
    reg reset_button_n=0;
    wire uart_tx,bt_tx,chcs,chsck,chmosi,sdcs,sdclk,sdmosi,ib,il,id,am,ab,al,ad,ws,pclk,de,hs,vs,bl,tpr,sdio,ss,sl;
    wire [4:0] rr,bb; wire [5:0] gg; wire [7:0] led;
    tri cscl,csda,tscl,tsda,tint;
    top_138k dut(.clk(clk),.reset_button_n(reset_button_n),.uart_rx_pin(1'b1),.uart_tx_pin(uart_tx),
      .bluetooth_rx_pin(1'b1),.bluetooth_tx_pin(bt_tx),.tutorial_start_n(1'b1),.tutorial_stop_n(1'b1),
      .ch376_cs_n(chcs),.ch376_sck(chsck),.ch376_mosi(chmosi),.ch376_miso(1'b1),.ch376_int_n(1'b1),
      .sd_cs_n(sdcs),.sd_clk(sdclk),.sd_mosi(sdmosi),.sd_miso(1'b1),.i2s_bclk(ib),.i2s_lrclk(il),.i2s_din(id),
      .aud_mclk(am),.aud_bclk(ab),.aud_lrclk(al),.aud_dacdat(ad),.codec_scl(cscl),.codec_sda(csda),.ws2812_data(ws),
      .lcd_pclk(pclk),.lcd_de(de),.lcd_hsync(hs),.lcd_vsync(vs),.lcd_bl(bl),.lcd_r(rr),.lcd_b(bb),.lcd_g(gg),
      .tp_scl(tscl),.tp_sda(tsda),.tp_int(tint),.tp_rst(tpr),.seg7_dio(sdio),.seg7_sclk(ss),.seg7_rclk(sl),.status_led(led));
    reg [31:0] a=0,d=0; reg [1:0] req=2'b10;
    reg pkt=0; reg [7:0] cmd=0; reg [63:0] pay=0;
    reg aux=0; reg [9:0] auxaddr=0; reg [15:0] auxdata=0;
    task cycle; begin @(posedge clk); #1; end endtask
    task send_ui(input [5:0] regnum,input [31:0] val);
      begin @(negedge clk);a=32'h23000000+(regnum<<2);d=val;req=2'b01;cycle();@(negedge clk);req=2'b10;end
    endtask
    task send_guide(input [7:0] value);
      begin @(negedge clk);pkt=1;cmd=8'h70;pay={32'h44495547,24'd0,value};cycle();@(negedge clk);pkt=0;end
    endtask
    initial begin
      force dut.u_ui.address=a;force dut.u_ui.request=req;force dut.u_ui.write_data=d;
      force dut.u_tutorial.packet_valid=pkt;force dut.u_tutorial.command=cmd;force dut.u_tutorial.payload=pay;
      force dut.u_audio.aux_write_valid=aux;force dut.u_audio.aux_write_address=auxaddr;force dut.u_audio.aux_write_value=auxdata;
      repeat(3) cycle();reset_button_n=1; force dut.startup_count=16'hffff;
      force dut.u_tutorial.init_done=1'b1; repeat(220) cycle();
      if(!dut.u_tutorial.initialized) $fatal(1,"map init incomplete");
      // Simultaneous UART start and UI ARP enable: neither can enter.
      @(negedge clk);a=32'h23000090;d=1;req=1;pkt=1;cmd=8'h70;pay={32'h44495547,24'd0,8'd1};#1;
      $display("dbg busy=%b lock=%b ui_busy=%b req=%b addr=%h data=%h pkt=%b cmd=%h pay=%h", dut.upstream_mode_busy,dut.tutorial_mode_lock,dut.upstream_ui_busy,dut.u_ui.request,dut.u_ui.address,dut.u_ui.write_data,dut.u_tutorial.packet_valid,dut.u_tutorial.command,dut.u_tutorial.payload); if(!dut.upstream_mode_busy || !dut.tutorial_mode_lock) $fatal(1,"same-cycle intent absent");
      cycle();@(negedge clk);req=2;pkt=0;repeat(3)cycle();
      if(dut.arp_config[0] || dut.tutorial_running) $fatal(1,"same-cycle double start");
      send_guide(1);repeat(3)cycle();
      if(!dut.tutorial_running) $fatal(1,"guide failed to start");
      send_ui(36,1);send_ui(46,1);send_ui(28,3);repeat(3)cycle();
      if(dut.arp_config[0]||dut.u_ui.u_sequencer.running||dut.u_ui.u_lesson.enabled) $fatal(1,"UI start accepted while guide active");
      @(negedge clk);aux=1;auxaddr=10'h3f0;auxdata=1;cycle();@(negedge clk);aux=0;repeat(2)cycle();
      if(dut.u_audio.u_ai_bass.config_word[0]) $fatal(1,"AI bass enabled during guide");
      @(negedge clk);aux=1;auxaddr=10'h3c0;auxdata=1;cycle();@(negedge clk);aux=0;repeat(2)cycle();
      if(dut.u_audio.u_composer.session) $fatal(1,"composer enabled during guide");
      send_guide(0);
      // The registered suspend can outlive running by one clock. A new start
      // must not be accepted until that final suspension has cleared.
      send_ui(36,1);repeat(2)cycle();
      if(dut.arp_config[0])$fatal(1,"ARP enabled before guide suspension cleared");
      repeat(2)cycle();if(dut.tutorial_running) $fatal(1,"guide failed to stop");
      send_ui(36,1);repeat(4)cycle();if(!dut.arp_config[0])$fatal(1,"ARP enable failed");
      send_guide(1);repeat(3)cycle();if(dut.tutorial_running)$fatal(1,"guide started while ARP enabled");
      send_ui(36,0);repeat(10)cycle();
      // Exercise enabled-but-silent modes, plus cleanup state after stop.
      send_ui(46,1);repeat(5)cycle();if(!dut.u_ui.u_sequencer.running)$fatal(1,"SEQ did not start");
      send_guide(1);repeat(3)cycle();if(dut.tutorial_running||!dut.u_ui.u_sequencer.running)$fatal(1,"guide request disrupted active SEQ");
      send_ui(46,0);repeat(30)cycle();
      send_ui(28,3);repeat(4)cycle();if(!dut.u_ui.u_lesson.enabled)$fatal(1,"lesson did not start");
      send_guide(1);repeat(3)cycle();if(dut.tutorial_running)$fatal(1,"guide started while lesson enabled");
      send_ui(28,0);repeat(30)cycle();
      @(negedge clk);aux=1;auxaddr=10'h3f0;auxdata=1;cycle();@(negedge clk);aux=0;repeat(5)cycle();
      if(!dut.u_audio.u_ai_bass.config_word[0])$fatal(1,"bass did not enable");
      send_guide(1);repeat(3)cycle();if(dut.tutorial_running)$fatal(1,"guide started while bass enabled");
      @(negedge clk);aux=1;auxaddr=10'h3f0;auxdata=0;cycle();@(negedge clk);aux=0;repeat(20)cycle();
      @(negedge clk);aux=1;auxaddr=10'h3c0;auxdata=1;cycle();@(negedge clk);aux=0;repeat(5)cycle();
      if(!dut.u_audio.u_composer.session)$fatal(1,"composer did not enable");
      send_guide(1);repeat(3)cycle();if(dut.tutorial_running)$fatal(1,"guide started while composer enabled");
      @(negedge clk);aux=1;auxaddr=10'h3c0;auxdata=0;cycle();@(negedge clk);aux=0;repeat(20)cycle();
      // Packet and PC UART command overlap: neither may acquire ownership.
      @(negedge clk);aux=1;auxaddr=10'h3f0;auxdata=1;pkt=1;cmd=8'h70;pay={32'h44495547,24'd0,8'd1};#1;
      if(!dut.upstream_mode_busy||!dut.tutorial_mode_lock)$fatal(1,"same-cycle UART intent absent");
      cycle();@(negedge clk);pkt=0;aux=0;repeat(8)cycle();
      if(dut.tutorial_running||dut.u_audio.u_ai_bass.config_word[0])$fatal(1,"same-cycle UART double start");
      // Hold an upstream cleanup in progress to prove the guard persists under
      // backpressure, independently of the duration of a normal test run.
      force dut.u_ui.u_sequencer.reset_pending=1'b1;#1;
      if(!dut.upstream_mode_busy)$fatal(1,"SEQ cleanup not reported busy");
      send_guide(1);repeat(2)cycle();if(dut.tutorial_running)$fatal(1,"guide accepted during SEQ cleanup");
      release dut.u_ui.u_sequencer.reset_pending;repeat(5)cycle();
      $display("INTEGRATED_MODE_GUARD_OK simultaneous UI/UART, ARP, SEQ, lesson, AI and cleanup ownership");$finish;
    end
endmodule

