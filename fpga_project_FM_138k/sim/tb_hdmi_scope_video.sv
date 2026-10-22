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
    integer i;
    hdmi_scope_video dut (
        .clk(clk), .reset_n(reset_n), .pixel_clk(pixel_clk),
        .pll_locked(1'b1), .sample_tick(sample_tick),
        .audio_sample(audio_sample), .visual_mode(visual_mode),
        .xy_delay_samples(7'd24), .display_auto_gain(1'b1),
        .background_color(24'h080D18), .wave_color(24'h40EAD0),
        .xy_color(24'hFFB95A), .video_reset_n(video_reset_n),
        .red(red), .green(green), .blue(blue),
        .de(de), .hsync(hsync), .vsync(vsync)
    );
    initial begin
        repeat (6) @(negedge pixel_clk);
        reset_n = 1;
        wait (video_reset_n);
        // Observe one complete 800 x 525 frame after reset release.
        repeat (2) @(posedge pixel_clk);
        for (i = 0; i < 800*525; i = i + 1) begin
            @(negedge pixel_clk);
            if (^({de,hsync,vsync,red,green,blue}) === 1'bx)
                unknown_count = unknown_count + 1;
            if (de) active_count = active_count + 1;
            if (!hsync) hs_count = hs_count + 1;
            if (!vsync) vs_count = vs_count + 1;
        end
        if (unknown_count || active_count != 640*480 ||
            hs_count != 96*525 || vs_count != 2*800)
            $fatal(1,"bad HDMI raster: x=%0d de=%0d hs=%0d vs=%0d",
                   unknown_count, active_count, hs_count, vs_count);
        $display("PASS HDMI scope raster and RGB control signals");
        $finish;
    end
endmodule
