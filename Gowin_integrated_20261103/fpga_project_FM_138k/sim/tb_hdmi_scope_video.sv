`timescale 1ns/1ps
module tb_hdmi_scope_video;
    reg clk = 0, pixel_clk = 0, reset_n = 0;
    always #10 clk = ~clk;
    always #20 pixel_clk = ~pixel_clk;
    reg sample_tick = 0;
    reg signed [15:0] audio_sample = 0;
    reg visual_mode = 0;
    wire video_reset_n, de, hsync, vsync;
    wire [7:0] red, green, blue;
    integer active_count = 0, hs_count = 0, vs_count = 0, unknown_count = 0;
    integer i,frame_multiplier=1,spectrum_probes=0,sb;
    reg spectrum_case=0,spectrum_write=0;
    reg [5:0] spectrum_address=0;reg [13:0] spectrum_data=0;
    reg [6:0] sl;
    initial begin
        spectrum_case=$test$plusargs("spectrum");
        #10000;
        if(spectrum_case)for(sb=0;sb<64;sb=sb+1)begin
            @(negedge clk);spectrum_address=sb;
            sl=sb==9?96:sb==23?64:sb==45?32:0;
            spectrum_data={sl,sl};spectrum_write=1;
            @(negedge clk);spectrum_write=0;
        end
    end
    hdmi_scope_video dut (
        .lesson_state(32'd0),.lesson_bank(1'b0),.lesson_count(8'd42),.lesson_write(1'b0),.lesson_address(7'd0),.lesson_data(32'd0),.midi_event_data(32'd0),.midi_event_valid(1'b0),
        .clk(clk), .reset_n(reset_n), .pixel_clk(pixel_clk),
        .pll_locked(1'b1), .sample_tick(sample_tick),
        .audio_sample(audio_sample), .visual_mode(visual_mode),.spectrum_enable(spectrum_case),.spectrum_write(spectrum_write),.spectrum_address(spectrum_address),.spectrum_data(spectrum_data),
        .xy_delay_samples(7'd24), .display_auto_gain(1'b1),
        .background_color(24'h080D18), .wave_color(24'h40EAD0),
        .xy_color(24'hFFB95A), .video_reset_n(video_reset_n),
        .red(red), .green(green), .blue(blue),
        .de(de), .hsync(hsync), .vsync(vsync)
    );
    initial begin
        frame_multiplier=spectrum_case?2:1;
        repeat (6) @(negedge pixel_clk);
        reset_n = 1;
        wait (video_reset_n);
        // Observe one complete 800 x 525 frame after reset release.
        repeat (2) @(posedge pixel_clk);
        for (i = 0; i < frame_multiplier*800*525; i = i + 1) begin
            @(negedge pixel_clk);
            if (^({de,hsync,vsync,red,green,blue}) === 1'bx)
                unknown_count = unknown_count + 1;
            if (de) active_count = active_count + 1;
            if(spectrum_case&&dut.u_spectrum_view.valid)begin
                if(dut.x==139&&dut.y==120)begin
                    if({red,green,blue}!==24'h40EAD0)$fatal(1,"Missing HDMI FFT bar");
                    spectrum_probes=spectrum_probes+1;
                end
                if(dut.x==143&&dut.y==200)begin
                    if({red,green,blue}===24'h40EAD0)$fatal(1,"Missing HDMI FFT gap");
                    spectrum_probes=spectrum_probes+1;
                end
            end
            if (!hsync) hs_count = hs_count + 1;
            if (!vsync) vs_count = vs_count + 1;
        end
        if (unknown_count || active_count != frame_multiplier*640*480 ||
            hs_count != frame_multiplier*96*525 || vs_count != frame_multiplier*2*800)
            $fatal(1,"bad HDMI raster: x=%0d de=%0d hs=%0d vs=%0d",
                   unknown_count, active_count, hs_count, vs_count);
        if(spectrum_case&&spectrum_probes!=2)$fatal(1,"HDMI FFT probes not visited %d",spectrum_probes);
        $display("PASS HDMI scope raster and RGB control signals");
        $finish;
    end
endmodule
