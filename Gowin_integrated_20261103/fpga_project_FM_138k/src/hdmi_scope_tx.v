// HDMI1 video-only output. Bank 7 also carries 3.3 V RGB-panel pins,
// so the vendor DVI TX LVDS25E buffer cannot coexist with that panel.
// Reuse the proven RTL TMDS encoder and paired 3.3 V ODDR outputs instead.
module hdmi_scope_tx (
    input wire [31:0] lesson_state,
    input wire lesson_bank,input wire [7:0] lesson_count,
    input wire lesson_write,input wire [6:0] lesson_address,input wire [31:0] lesson_data,
    input wire [31:0] midi_event_data,input wire midi_event_valid,
    input wire clk, reset_n, sample_tick,
    input wire signed [15:0] audio_sample,
    input wire visual_mode,
    input wire spectrum_enable,spectrum_write,
    input wire [5:0] spectrum_address,
    input wire [13:0] spectrum_data,
    input wire [6:0] xy_delay_samples,
    input wire display_auto_gain,
    input wire [23:0] background_color, wave_color, xy_color,
    output wire hdmi_clk_p, hdmi_clk_n,
    output wire [2:0] hdmi_data_p, hdmi_data_n,
    output wire hdmi_oe, pll_locked
);
    wire pixel_clk, serial_clk, video_reset_n;
    wire [7:0] red, green, blue;
    wire de, hsync, vsync;
    video_pll #(.PIXEL_DIV(40), .ENABLE_SERIAL(1)) u_video_pll (
        .clkin(clk), .pixel_clk(pixel_clk), .serial_clk(serial_clk),
        .lock(pll_locked)
    );
    hdmi_scope_video u_scope (
        .lesson_state(lesson_state),.lesson_bank(lesson_bank),.lesson_count(lesson_count),
        .lesson_write(lesson_write),.lesson_address(lesson_address),.lesson_data(lesson_data),
        .midi_event_data(midi_event_data),.midi_event_valid(midi_event_valid),

        .clk(clk), .reset_n(reset_n), .pixel_clk(pixel_clk),
        .pll_locked(pll_locked), .sample_tick(sample_tick),
        .audio_sample(audio_sample), .visual_mode(visual_mode),
        .spectrum_enable(spectrum_enable),.spectrum_write(spectrum_write),
        .spectrum_address(spectrum_address),.spectrum_data(spectrum_data),
        .xy_delay_samples(xy_delay_samples),
        .display_auto_gain(display_auto_gain),
        .background_color(background_color), .wave_color(wave_color),
        .xy_color(xy_color), .video_reset_n(video_reset_n),
        .red(red), .green(green), .blue(blue),
        .de(de), .hsync(hsync), .vsync(vsync)
    );
    assign hdmi_oe = video_reset_n;
    wire [9:0] red_symbol, green_symbol, blue_symbol;
    tmds_encoder u_r (.clk(pixel_clk), .reset_n(video_reset_n),
        .data(red), .de(de), .c0(1'b0), .c1(1'b0), .symbol(red_symbol));
    tmds_encoder u_g (.clk(pixel_clk), .reset_n(video_reset_n),
        .data(green), .de(de), .c0(1'b0), .c1(1'b0), .symbol(green_symbol));
    tmds_encoder u_b (.clk(pixel_clk), .reset_n(video_reset_n),
        .data(blue), .de(de), .c0(hsync), .c1(vsync),
        .symbol(blue_symbol));
    tmds_lane u_clock (.pixel_clk(pixel_clk), .serial_clk(serial_clk),
        .reset_n(video_reset_n), .symbol(10'b1111100000),
        .out_p(hdmi_clk_p), .out_n(hdmi_clk_n));
    tmds_lane u_red (.pixel_clk(pixel_clk), .serial_clk(serial_clk),
        .reset_n(video_reset_n), .symbol(red_symbol),
        .out_p(hdmi_data_p[2]), .out_n(hdmi_data_n[2]));
    tmds_lane u_green (.pixel_clk(pixel_clk), .serial_clk(serial_clk),
        .reset_n(video_reset_n), .symbol(green_symbol),
        .out_p(hdmi_data_p[1]), .out_n(hdmi_data_n[1]));
    tmds_lane u_blue (.pixel_clk(pixel_clk), .serial_clk(serial_clk),
        .reset_n(video_reset_n), .symbol(blue_symbol),
        .out_p(hdmi_data_p[0]), .out_n(hdmi_data_n[0]));
endmodule
