// XiaoMeiGe ACG720, GW5AT-LV138PG484AC1/I0.
// PC configuration: onboard CH340, 115200 baud. MIDI bridge: GPIO0_3, 1 Mbaud.
module top_138k_hdmi (
    input wire clk,
    input wire reset_button_n,
    input wire uart_rx_pin,
    output wire uart_tx_pin,
    input wire bridge_uart_rx_pin,
    output wire i2s_bclk, i2s_lrclk, i2s_din,
    output wire aud_mclk, aud_bclk, aud_lrclk, aud_dacdat,
    inout wire codec_scl, codec_sda,
    output wire ws2812_data,
    output wire lcd_pclk,lcd_de,lcd_hsync,lcd_vsync,lcd_bl,
    output wire [4:0] lcd_r,lcd_b,
    output wire [5:0] lcd_g,
    inout wire tp_scl,tp_sda,tp_int,
    output wire tp_rst,
    output wire [4:0] status_led,
    output wire hdmi_clk_p, hdmi_clk_n,
    output wire [2:0] hdmi_data_p, hdmi_data_n,
    output wire hdmi_oe
);
    // S4 is active low. Hold startup reset for 1.31 ms and release on clk.
    reg [15:0] startup_count = 0;
    always @(posedge clk or negedge reset_button_n)
        if (!reset_button_n) startup_count <= 0;
        else if (!(&startup_count)) startup_count <= startup_count + 1'b1;
    wire reset_n = &startup_count;
    wire [31:0] bridge_event;
    wire bridge_valid, bridge_ready;
    wire [15:0] bridge_dropped;
    midi_bridge_rx u_bridge_rx (
        .clk(clk),.reset_n(reset_n),.rx_pin(bridge_uart_rx_pin),
        .midi_event_data(bridge_event),.midi_event_valid(bridge_valid),
        .midi_event_ready(bridge_ready),.dropped_events(bridge_dropped)
    );
    wire signed [15:0] pcm;
    wire tick, event_valid;
    wire [31:0] event_data;
    wire [4:0] voices,algorithm;
    wire [6:0] preset;
    wire [47:0] operator_eg;
    wire [31:0] ui_event;
    wire ui_valid,ui_ready,external_ready,touch_present;
    wire signed [3:0] keyboard_octave;
    wire [6:0] master_volume;
    wire visual_mode,spectrum_enable;
    wire spectrum_write;
    wire [5:0] spectrum_address;
    wire [13:0] spectrum_data;
    audio_spectrum_analyzer u_spectrum(.clk(clk),.reset_n(reset_n),
        .sample_tick(tick),.audio_sample(pcm),.bin_write(spectrum_write),
        .bin_address(spectrum_address),.bin_data(spectrum_data));
    wire headphone_select, headphone_din;
    wire [6:0] xy_delay_samples;
    wire display_auto_gain;
    wire [3:0] menu_page;
    wire [23:0] background_color,wave_color,xy_color;
    wire text_write;
    wire [11:0] text_address;
    wire [15:0] text_data;
    wire palette_write;
    wire [3:0] palette_index;
    wire [23:0] palette_data;
    wire text_enable;
    wire eg_we;wire [7:0] eg_addr;wire [8:0] eg_data;
wire eg2_we;wire [9:0] eg2_addr;wire [7:0] eg2_data;wire eg2_enable;
    wire algo_we;wire [14:0] algo_addr;wire [7:0] algo_data;wire algo_enable;
    wire ui_command_valid,ui_command_ready;
    wire [7:0] ui_command;
    wire [63:0] ui_command_payload;
    wire [15:0] readback_data;
    wire readback_valid;
    assign bridge_ready=external_ready;
    assign ui_ready=external_ready && !bridge_valid;
    touch_ui_controller u_ui (
        .clk(clk),.reset_n(reset_n),.tp_scl(tp_scl),.tp_sda(tp_sda),.tp_int(tp_int),.tp_rst(tp_rst),
        .uart_tx(uart_tx_pin),.midi_event_data(ui_event),.midi_event_valid(ui_valid),.midi_event_ready(ui_ready),
        .monitor_event(event_data),.monitor_event_valid(event_valid),
        .preset_index(preset),.algorithm(algorithm),.active_voices(voices),
        .touch_present(touch_present),.keyboard_octave(keyboard_octave),.master_volume(master_volume),
        .visual_mode(visual_mode),.spectrum_enable(spectrum_enable),.headphone_select(headphone_select),.xy_delay_samples(xy_delay_samples),.display_auto_gain(display_auto_gain),
        .menu_page(menu_page),.background_color(background_color),.wave_color(wave_color),.xy_color(xy_color),
        .text_write(text_write),.text_address(text_address),.text_data(text_data),
        .palette_write(palette_write),.palette_index(palette_index),.palette_data(palette_data),
        .text_enable(text_enable),.eg_we(eg_we),.eg_addr(eg_addr),.eg_data(eg_data),
        .eg2_we(eg2_we),.eg2_addr(eg2_addr),.eg2_data(eg2_data),.eg2_enable(eg2_enable),
        .algo_we(algo_we),.algo_addr(algo_addr),.algo_data(algo_data),.algo_enable(algo_enable),
        .command_valid(ui_command_valid),.command(ui_command),.command_payload(ui_command_payload),.command_ready(ui_command_ready),
        .patch_read_data(readback_data),.patch_read_valid(readback_valid),
        .fx_write(),.fx_index(),.fx_value(),.fx_read_value(32'd0),.numeric_display()
    );
    top #(.USB_HOST_ENABLED(0),.FM_AUDIO_ONLY(0),.FX2_ENABLED(1),.OUTPUT_SELECT_ENABLED(1)) u_audio (
        .clk(clk),.key_s2(~reset_n),.uart_rx_pin(uart_rx_pin),
        .headphone_select(headphone_select),.headphone_din(headphone_din),
        .ui_command_valid(ui_command_valid),.ui_command(ui_command),.ui_payload(ui_command_payload),
        .ui_command_ready(ui_command_ready),
        .fx_write(1'b0),.fx_index(4'd0),.fx_value(32'd0),
        .fx_read_index(4'd0),.fx_read_value(),
        .uart_tx_pin(),.usb_host_dp(),.usb_host_dn(),
        .i2s_bclk(i2s_bclk),.i2s_lrclk(i2s_lrclk),.i2s_din(i2s_din),
        .lcd_resetn(),.lcd_clk(),.lcd_cs(),.lcd_dc(),.lcd_data(),
        .external_midi_event_data(bridge_valid?bridge_event:ui_event),
        .external_midi_event_valid(bridge_valid||ui_valid),
        .external_midi_event_ready(external_ready),
        .monitor_sample(pcm),.monitor_sample_tick(tick),
        .monitor_midi_event_data(event_data),.monitor_midi_event_valid(event_valid),
        .monitor_voice_count(voices),.monitor_preset(preset),
        .monitor_algorithm(algorithm),.monitor_operator_envelopes(operator_eg),
        .readback_data(readback_data),.readback_valid(readback_valid)
    );
    // Mirror the final, master-volume-controlled I2S stream to OUT1.
    wire codec_ready, codec_init_error;
    es8388_output u_codec (
        .clk(clk),.reset_n(reset_n),
        .i2s_bclk(i2s_bclk),.i2s_lrclk(i2s_lrclk),.i2s_data(headphone_din),
        .aud_mclk(aud_mclk),.aud_bclk(aud_bclk),.aud_lrclk(aud_lrclk),
        .aud_dacdat(aud_dacdat),.codec_scl(codec_scl),.codec_sda(codec_sda),
        .ready(codec_ready),.init_error(codec_init_error)
    );
    ws2812_keys u_leds (
        .clk(clk),.reset_n(reset_n),.midi_event_data(event_data),
        .midi_event_valid(event_valid),.led_data(ws2812_data)
    );
    wire video_lock;
    rgb_visualizer u_video (
        .clk(clk),.reset_n(reset_n),.sample_tick(tick),.audio_sample(pcm),
        .midi_event_data(event_data),.midi_event_valid(event_valid),
        .active_voice_count(voices),.preset_index(preset),.algorithm(algorithm),
        .operator_envelopes(operator_eg),.touch_present(touch_present),
        .keyboard_octave(keyboard_octave),.master_volume(master_volume),
        .visual_mode(visual_mode),.spectrum_enable(spectrum_enable),
        .spectrum_write(spectrum_write),.spectrum_address(spectrum_address),.spectrum_data(spectrum_data),.xy_delay_samples(xy_delay_samples),
        .display_auto_gain(display_auto_gain),.menu_page(menu_page),.algorithm_flags(48'd0),
        .background_color(background_color),.wave_color(wave_color),.xy_color(xy_color),
        .text_write(text_write),.text_address(text_address),.text_data(text_data),
        .palette_write(palette_write),.palette_index(palette_index),.palette_data(palette_data),
        .text_enable(text_enable),.eg_we(eg_we),.eg_addr(eg_addr),.eg_data(eg_data),
        .eg2_we(eg2_we),.eg2_addr(eg2_addr),.eg2_data(eg2_data),.eg2_enable(eg2_enable),
        .algo_we(algo_we),.algo_addr(algo_addr),.algo_data(algo_data),.algo_enable(algo_enable),
        .lcd_pclk(lcd_pclk),.lcd_de(lcd_de),.lcd_hsync(lcd_hsync),.lcd_vsync(lcd_vsync),
        .lcd_bl(lcd_bl),.lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b),.pll_locked(video_lock)
    );
    wire hdmi_video_lock;
    hdmi_scope_tx u_hdmi (
        .clk(clk), .reset_n(reset_n), .sample_tick(tick),
        .audio_sample(pcm), .visual_mode(visual_mode),.spectrum_enable(spectrum_enable),
        .spectrum_write(spectrum_write),.spectrum_address(spectrum_address),.spectrum_data(spectrum_data),
        .xy_delay_samples(xy_delay_samples),
        .display_auto_gain(display_auto_gain),
        .background_color(background_color), .wave_color(wave_color),
        .xy_color(xy_color), .hdmi_clk_p(hdmi_clk_p),
        .hdmi_clk_n(hdmi_clk_n), .hdmi_data_p(hdmi_data_p),
        .hdmi_data_n(hdmi_data_n), .hdmi_oe(hdmi_oe),
        .pll_locked(hdmi_video_lock)
    );
    reg [25:0] heartbeat;
    reg [23:0] event_hold;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin heartbeat<=0;event_hold<=0;end
        else begin
            heartbeat<=heartbeat+1'b1;
            if (event_valid) event_hold<=24'd5000000;
            else if (event_hold!=0) event_hold<=event_hold-1'b1;
        end
    end
    assign status_led={bridge_dropped!=0,touch_present,event_hold!=0,video_lock,heartbeat[25]};
endmodule
