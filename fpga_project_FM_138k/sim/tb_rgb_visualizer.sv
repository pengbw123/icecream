`timescale 1ns/1ps
// Behavioral PLL/ODDR for raster verification only, not electrical modelling.
module video_pll #(parameter PIXEL_DIV=30,ENABLE_SERIAL=0)
    (input clkin,output reg pixel_clk=0,output serial_clk,output reg lock=0);
    always #15 pixel_clk=~pixel_clk;
    assign serial_clk=0;
    initial #200 lock=1;
endmodule
module ODDR(output reg Q0,output Q1,input D0,D1,TX,CLK);
    always @(posedge CLK)Q0<=D0;
    always @(negedge CLK)Q0<=D1;
    assign Q1=TX;
endmodule
module tb_rgb_visualizer;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0;
    reg [9:0] sample_div=0;
    reg tick=0;
    reg signed [15:0] pcm=0;
    integer quiet_case=0,max_display_height=0,current_height;
    integer messy_case=0;
    reg show_wave=0;
    wire [3:0] test_page=$test$plusargs("arp")?4'd10:$test$plusargs("seq")?4'd11:4'd0;
    integer page_probes=0;
    reg spectrum_case=0,spectrum_write=0;
    reg [5:0] spectrum_address=0;
    reg [13:0] spectrum_data=0;
    integer spectrum_probes=0,sb;reg [6:0] sl;
    initial begin
        spectrum_case=$test$plusargs("spectrum");
        #10000;
        if(spectrum_case)forever begin
          for(sb=0;sb<64;sb=sb+1)begin
            @(negedge clk);spectrum_address=sb;
            sl=sb==9?96:sb==23?64:sb==45?32:0;
            spectrum_data={sl,sl};spectrum_write=1;
            @(negedge clk);spectrum_write=0;
          end
          #1000000;
        end
    end
    real phase=0;
    always @(negedge clk)begin
        sample_div=sample_div+1;
        tick=sample_div==0;
        if(tick)begin phase=phase+0.033;
            if(messy_case)
                pcm=$rtoi(9000*$sin(phase)+6000*$sin(2.71*phase+1.3)
                         +4000*$sin(5.3*phase+0.7)+2500*$sin(11.7*phase));
            else
                pcm=quiet_case?$rtoi(100*$sin(phase)):$rtoi(18000*$sin(phase)+5000*$sin(3*phase));end
    end
    reg [31:0] event_word=0;
    reg event_valid=0;
    wire pclk,de,hs,vs,bl,lock;
    wire [4:0] r,b;
    wire [5:0] g;
    rgb_visualizer dut(
        .lesson_state(32'd0),.lesson_bank(1'b0),.lesson_count(8'd42),.lesson_write(1'b0),.lesson_address(7'd0),.lesson_data(32'd0),.clk(clk),.reset_n(reset_n),.sample_tick(tick),.audio_sample(pcm),
        .midi_event_data(event_word),.midi_event_valid(event_valid),.active_voice_count(5'd3),
        .preset_index(7'd10),.algorithm(5'd4),.operator_envelopes(48'hB090603080D0),
        .touch_present(1'b1),.keyboard_octave(4'sd0),.master_volume(7'd96),
        .visual_mode(!show_wave),.spectrum_enable(spectrum_case),.spectrum_write(spectrum_write),.spectrum_address(spectrum_address),.spectrum_data(spectrum_data),.xy_delay_samples(7'd24),
        .display_auto_gain(1'b1),.menu_page(test_page),.algorithm_flags(48'd0),
        .background_color(24'h080D18),.wave_color(24'h40EAD0),.xy_color(24'hFFB95A),
        .text_write(1'b0),.text_address(12'd0),.text_data(16'd0),
        .palette_write(1'b0),.palette_index(4'd0),.palette_data(24'd0),.text_enable(1'b0),.eg_we(1'b0),.eg_addr(8'd0),.eg_data(9'd0),
        .eg2_we(1'b0),.eg2_addr(10'd0),.eg2_data(8'd0),.eg2_enable(1'b0),
        .algo_we(1'b0),.algo_addr(15'd0),.algo_data(8'd0),.algo_enable(1'b0),
        .lcd_pclk(pclk),.lcd_de(de),.lcd_hsync(hs),.lcd_vsync(vs),.lcd_bl(bl),
        .lcd_r(r),.lcd_g(g),.lcd_b(b),.pll_locked(lock));
    task note_on(input [6:0] note);
        begin @(negedge clk);event_word={8'd0,8'h90,1'b0,note,8'd100};event_valid=1;
            @(negedge clk);event_valid=0;end
    endtask
    integer file_handle,pixels,row_pixels=0,rows=0;
    reg de_prev=0;
    // Display-level continuity check: the RGB565 waveform colour must form an
    // unbroken band in every plot column and overlap between neighbouring
    // columns.  This is the regression for "messy waveform shows break points".
    localparam [15:0] WAVE565={5'd8,6'd58,5'd26};
    integer col_lo[0:511],col_hi[0:511],col_n[0:511];
    integer probe_x,probe_y,plot_x,i;
    reg wave_pixel;
    initial begin
        quiet_case=$test$plusargs("quiet");
        messy_case=$test$plusargs("messy");
        show_wave=$test$plusargs("wave")||messy_case;
        repeat(20)@(negedge clk);reset_n=1;
        note_on(48);note_on(52);note_on(55);
        repeat(2)begin wait(dut.frame_latch);@(posedge dut.pclk);wait(!dut.frame_latch);end
        wait(!de);@(posedge de);
        file_handle=$fopen(test_page==10?"tmp/rgb_arp_preview.ppm":test_page==11?"tmp/rgb_seq_preview.ppm":spectrum_case?"tmp/rgb_spectrum_preview.ppm":messy_case?"tmp/rgb_messy_preview.ppm":show_wave?"tmp/rgb_wave_preview.ppm"
            :quiet_case?"tmp/rgb_quiet_preview.ppm":"tmp/rgb_preview.ppm","wb");
        $fwrite(file_handle,"P6\n800 480\n255\n");
        pixels=0;
        for(i=0;i<512;i=i+1)begin col_lo[i]=0;col_hi[i]=0;col_n[i]=0;end
        while(pixels<800*480)begin
            @(posedge pclk);
            if(de)begin
                if(^{r,g,b}===1'bx)$fatal(1,"Unknown RGB output");
                $fwrite(file_handle,"%c%c%c",{r,r[4:2]},{g,g[5:4]},{b,b[4:2]});
                probe_x=pixels%800;probe_y=pixels/800;
                if(test_page!=0)begin
                    if((probe_x==20&&probe_y==470)||(probe_x==790&&probe_y==470)||
                        (probe_x==50&&probe_y==370)||(probe_x==100&&probe_y==200))begin
                        if(probe_x==20&&{r,g,b}!==WAVE565)$fatal(1,"ARP/SEQ pressed C key hidden");
                        if(probe_x==790&&{r,g,b}!=={5'd30,6'd62,5'd31})$fatal(1,"ARP/SEQ full-width final key hidden");
                        if(probe_x==50&&{r,g,b}!=={5'd2,6'd6,5'd4})$fatal(1,"ARP/SEQ black key geometry");
                        if(probe_x==100&&{r,g,b}!=={5'd1,6'd3,5'd3})$fatal(1,"ARP/SEQ editor background not flat");
                        page_probes=page_probes+1;
                    end
                end
                if(spectrum_case)begin
                    if((probe_x==91&&probe_y==120)||(probe_x==203&&probe_y==200)||(probe_x==379&&probe_y==280))begin
                        if({r,g,b}!==WAVE565)$fatal(1,"Missing spectrum bar at %d,%d rgb=%h level=%d peak=%d valid=%b mode=%b x=%d y=%d bank=%b mem9=%h",probe_x,probe_y,{r,g,b},dut.spectrum_level,dut.spectrum_peak,dut.spectrum_valid,dut.spectrum_frame,dut.x,dut.y,dut.u_spectrum_view.display_bank,dut.u_spectrum_view.snapshots[9]);
                        spectrum_probes=spectrum_probes+1;
                    end
                    if((probe_x==95&&probe_y==200)||(probe_x==59&&probe_y==280)||(probe_x==203&&probe_y==150))begin
                        if({r,g,b}===WAVE565)$fatal(1,"Spectrum gap/height mismatch at %d,%d",probe_x,probe_y);
                        spectrum_probes=spectrum_probes+1;
                    end
                end
                if(probe_x>=16&&probe_x<528&&probe_y>=96&&probe_y<352)begin
                    plot_x=probe_x-16;wave_pixel={r,g,b}==WAVE565;
                    if(wave_pixel)begin
                        if(col_n[plot_x]==0)begin
                            col_lo[plot_x]=probe_y-96;col_hi[plot_x]=probe_y-96;
                        end else begin
                            if(probe_y-96<col_lo[plot_x])col_lo[plot_x]=probe_y-96;
                            if(probe_y-96>col_hi[plot_x])col_hi[plot_x]=probe_y-96;
                        end
                        col_n[plot_x]=col_n[plot_x]+1;
                    end
                end
                pixels=pixels+1;row_pixels=row_pixels+1;
            end
            if(de_prev&&!de)begin
                if(row_pixels!=800)$fatal(1,"Active row width %0d",row_pixels);
                rows=rows+1;row_pixels=0;
            end
            de_prev=de;
        end
        if(rows!=479||row_pixels!=800)$fatal(1,"Frame row count %0d",rows);
        for(i=0;i<512;i=i+1)begin
            if(!spectrum_case&&col_n[i]>0)begin
                if(col_n[i]!=col_hi[i]-col_lo[i]+1)
                    $fatal(1,"Wave column %0d has holes: n=%0d lo=%0d hi=%0d",
                        i,col_n[i],col_lo[i],col_hi[i]);
                if(i<511&&col_n[i+1]>0&&(col_lo[i+1]>col_hi[i]||col_hi[i+1]<col_lo[i]))
                    $fatal(1,"Wave break between columns %0d and %0d",i,i+1);
            end
        end
        if(test_page!=0&&page_probes!=4)$fatal(1,"ARP/SEQ missing keyboard probes");
        if(spectrum_case&&spectrum_probes!=6)$fatal(1,"Missing spectrum pixel probes");
        if(quiet_case && max_display_height<30)$fatal(1,"Quiet waveform remained invisible: %d",max_display_height);
        $fclose(file_handle);$display("PASS RGB/XY raster, stable pixels and PLL-loss recovery, quiet=%0d messy=%0d height=%0d",
            quiet_case,messy_case,max_display_height);$finish;
    end
    // Bank ownership is checked at every audio write, not just by image shape.
    always @(posedge clk)if(dut.capture_reset_n&&dut.u_wave.state==4)
        begin
            if(dut.u_wave.write_bank==dut.u_wave.display_bank)$fatal(1,"Audio overwrote displayed waveform bank");
            current_height=$signed({1'b0,dut.u_wave.point_y})-128;
            if(current_height<0)current_height=-current_height;
            if(current_height>max_display_height)max_display_height=current_height;
        end
    always @(posedge clk)if(dut.capture_reset_n && (dut.u_xy.state==0 || dut.u_xy.drawing))
        if(dut.u_xy.write_bank==dut.u_xy.display_bank)$fatal(1,"Audio overwrote displayed XY bank");
    initial begin
        #20000000;force dut.u_video_pll.lock=0;
        #10000;release dut.u_video_pll.lock;dut.u_video_pll.lock=1;
    end
    initial begin #100000000;$fatal(1,"Raster timeout");end
endmodule


