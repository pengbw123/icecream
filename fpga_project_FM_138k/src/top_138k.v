// XiaoMeiGe ACG720, GW5AT-LV138PG484AC1/I0.
// PC configuration: onboard CH340, 115200 baud. MIDI bridge: GPIO0_3, 1 Mbaud.
module top_138k (
    input wire clk,
    input wire reset_button_n,
    input wire uart_rx_pin,
    output wire uart_tx_pin,
    input wire bridge_uart_rx_pin,
    output wire i2s_bclk, i2s_lrclk, i2s_din,
    output wire ws2812_data,
    output wire lcd_pclk,lcd_de,lcd_hsync,lcd_vsync,lcd_bl,
    output wire [4:0] lcd_r,lcd_b,
    output wire [5:0] lcd_g,
    inout wire tp_scl,tp_sda,tp_int,
    output wire tp_rst,
    output wire [4:0] status_led
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
    wire [4:0] voices,preset,algorithm;
    wire [47:0] operator_eg;
    wire [31:0] ui_event;
    wire ui_valid,ui_ready,external_ready,touch_present;
    wire signed [3:0] keyboard_octave;
    wire [6:0] master_volume;
    assign bridge_ready=external_ready;
    assign ui_ready=external_ready && !bridge_valid;
    touch_ui_controller u_ui (
        .clk(clk),.reset_n(reset_n),.tp_scl(tp_scl),.tp_sda(tp_sda),.tp_int(tp_int),.tp_rst(tp_rst),
        .uart_tx(uart_tx_pin),.midi_event_data(ui_event),.midi_event_valid(ui_valid),.midi_event_ready(ui_ready),
        .monitor_event(event_data),.monitor_event_valid(event_valid),
        .preset_index(preset),.algorithm(algorithm),.active_voices(voices),
        .touch_present(touch_present),.keyboard_octave(keyboard_octave),.master_volume(master_volume)
    );
    top #(.USB_HOST_ENABLED(0),.FM_AUDIO_ONLY(1)) u_audio (
        .clk(clk),.key_s2(~reset_n),.uart_rx_pin(uart_rx_pin),
        .uart_tx_pin(),.usb_host_dp(),.usb_host_dn(),
        .i2s_bclk(i2s_bclk),.i2s_lrclk(i2s_lrclk),.i2s_din(i2s_din),
        .lcd_resetn(),.lcd_clk(),.lcd_cs(),.lcd_dc(),.lcd_data(),
        .external_midi_event_data(bridge_valid?bridge_event:ui_event),
        .external_midi_event_valid(bridge_valid||ui_valid),
        .external_midi_event_ready(external_ready),
        .monitor_sample(pcm),.monitor_sample_tick(tick),
        .monitor_midi_event_data(event_data),.monitor_midi_event_valid(event_valid),
        .monitor_voice_count(voices),.monitor_preset(preset),
        .monitor_algorithm(algorithm),.monitor_operator_envelopes(operator_eg)
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
        .lcd_pclk(lcd_pclk),.lcd_de(lcd_de),.lcd_hsync(lcd_hsync),.lcd_vsync(lcd_vsync),
        .lcd_bl(lcd_bl),.lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b),.pll_locked(video_lock)
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
