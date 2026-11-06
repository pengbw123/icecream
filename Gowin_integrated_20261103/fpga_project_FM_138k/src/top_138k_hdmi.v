// XiaoMeiGe ACG720, GW5AT-LV138PG484AC1/I0.
// PC: CH340 at 115200 baud. Keyboard: external CH376S, SPI mode 0.
module top_138k_hdmi #(parameter integer LEGACY_BRIDGE_ENABLED=0,CH376_ENABLED=1,GESTURE_GRAY=1,GESTURE_SELF_TEST=0) (
    input wire clk,
    input wire reset_button_n,
    input wire uart_rx_pin,
    output wire uart_tx_pin,
    input wire bridge_uart_rx_pin,
    input wire bluetooth_rx_pin,output wire bluetooth_tx_pin,
    input wire tutorial_start_n,tutorial_stop_n,
    output wire ch376_cs_n,ch376_sck,ch376_mosi,
    input wire ch376_miso,ch376_int_n,
    output wire sd_cs_n,sd_clk,sd_mosi,input wire sd_miso,
    output wire i2s_bclk, i2s_lrclk, i2s_din,
    output wire aud_mclk, aud_bclk, aud_lrclk, aud_dacdat,
    inout wire codec_scl, codec_sda,
    output wire ws2812_data,
    output wire lcd_pclk,lcd_de,lcd_hsync,lcd_vsync,lcd_bl,
    output wire [4:0] lcd_r,lcd_b,
    output wire [5:0] lcd_g,
    inout wire tp_scl,tp_sda,tp_int,
    output wire tp_rst,
    output wire seg7_dio,seg7_sclk,seg7_rclk,
    output wire [7:0] status_led,
    output wire latency_probe,
    output wire scope_note_start,scope_audio_done,
    output wire hdmi_clk_p, hdmi_clk_n,
    output wire [2:0] hdmi_data_p, hdmi_data_n,
    output wire hdmi_oe,
    input wire camera_pclk,camera_href,camera_vsync,
    input wire [7:0] camera_data,
    inout wire camera_scl,camera_sda,
    output wire camera_xclk,camera_reset_n,camera_pwdn
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
    wire bridge_drop,perf_snapshot,perf_clear;
    wire [4:0] perf_index;
    wire [31:0] perf_data;
    generate if(LEGACY_BRIDGE_ENABLED)begin:g_legacy_bridge
    midi_bridge_rx u_bridge_rx (
        .clk(clk),.reset_n(reset_n),.rx_pin(bridge_uart_rx_pin),
        .midi_event_data(bridge_event),.midi_event_valid(bridge_valid),
        .midi_event_ready(bridge_ready),.dropped_events(bridge_dropped),.dropped_pulse(bridge_drop)
    );
    end else begin
        assign bridge_event=0;assign bridge_valid=0;assign bridge_dropped=0;assign bridge_drop=0;
    end endgenerate

    wire signed [15:0] pcm;
    wire tick, event_valid;
    wire [31:0] event_data;
    localparam integer AUDIO_VOICES=32;
    wire [31:0] voice_mask;
    wire [7:0] voices;wire [4:0] algorithm;
    seg8_audio_status u_seg8(.clk(clk),.reset_n(reset_n),
        .sample_tick(tick),.audio_sample(pcm),.active_voices(voices),
        .data(seg7_dio),.shift_clk(seg7_sclk),.latch_clk(seg7_rclk));
    wire [6:0] preset;
    wire [47:0] operator_eg;
    wire [31:0] ui_event;
    wire ui_valid,ui_ready,external_ready,touch_present;
    wire signed [3:0] keyboard_octave;
    wire [6:0] master_volume;
    wire visual_mode,spectrum_enable,linear_enable;
    wire poly_test_active,poly_test_valid,poly_test_ready;wire [31:0] poly_test_data;
    wire linear_write;wire [8:0] linear_address;wire [13:0] linear_data;
    wire spectrum_write;
    wire [5:0] spectrum_address;
    wire [13:0] spectrum_data;
    audio_spectrum_analyzer u_spectrum(.linear_write(linear_write),.linear_address(linear_address),.linear_data(linear_data),.clk(clk),.reset_n(reset_n),
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
    wire [31:0] usb_event,merged_event,input_event,live_input_event;
    wire live_input_valid,live_input_ready;
    wire [31:0] score_event;wire score_valid,score_ready,score_playing,score_flushing;
    wire tutorial_running,tutorial_count_in,tutorial_beat,tutorial_initialized,tutorial_missing,tutorial_frame_done,tutorial_reply_overflow;
    wire usb_valid,usb_ready,merged_valid,merged_ready,input_valid;
    wire ch376_present,ch376_configured;
    wire [31:0] routed_usb_event;
    wire routed_usb_valid,routed_usb_ready,router_busy;
    wire key_plan_active,key_plan_poly_available;
    wire [6:0] key_plan_first;
    wire [24:0] key_plan_valid;
    wire [174:0] key_plan_notes;
    reg keyboard_was_configured;
    always @(posedge clk or negedge reset_n)
        if(!reset_n)keyboard_was_configured<=0;else keyboard_was_configured<=ch376_configured;
    wire keyboard_disconnected=keyboard_was_configured&&!ch376_configured;
    wire phone_request_valid,phone_request_ready,phone_response_valid,phone_response_was_write;
    wire [63:0] phone_request_payload;
    wire [15:0] phone_response_token;
    wire [7:0] phone_response_status,phone_response_value;
    wire tutorial_mode_lock,calibration_success,tone_success,upstream_ui_busy,external_auto_request;
    wire upstream_mode_busy;
    reg guide_suspend;
    reg [3:0] auto_request_history;
    always @(posedge clk or negedge reset_n)
        if(!reset_n)auto_request_history<=0;else auto_request_history<={auto_request_history[2:0],external_auto_request};
    
    wire [7:0] ch376_fault;
    generate if(CH376_ENABLED)begin:g_ch376
    ch376_midi_host u_ch376(.clk(clk),.reset_n(reset_n),
        .spi_cs_n(ch376_cs_n),.spi_sck(ch376_sck),.spi_mosi(ch376_mosi),
        .spi_miso(ch376_miso),.interrupt_n(ch376_int_n),
        .midi_event_data(usb_event),.midi_event_valid(usb_valid),.midi_event_ready(usb_ready),
        .module_present(ch376_present),.configured(ch376_configured),.fault_code(ch376_fault),
        .vendor_id(),.product_id(),.ignored_words(),.nak_count());
    end else begin:g_no_ch376
        assign ch376_cs_n=1'b1;assign ch376_sck=1'b0;assign ch376_mosi=1'b0;
        assign usb_event=0;assign usb_valid=0;
        assign ch376_present=0;assign ch376_configured=0;assign ch376_fault=0;
    end endgenerate
    // Identity tags are added only after stripping USB transport metadata.
    score_key_router u_key_router(.clk(clk),.reset_n(reset_n),
        .enabled(key_plan_active),.first_key(key_plan_first),.target_valid(key_plan_valid),.target_notes(key_plan_notes),
        .disconnect(keyboard_disconnected),.in_data({8'd0,usb_event[23:0]}),.in_valid(usb_valid),.in_ready(usb_ready),
        .out_data(routed_usb_event),.out_valid(routed_usb_valid),.out_ready(routed_usb_ready),.busy(router_busy));
    midi_event_arbiter3 u_midi_inputs(.clk(clk),.reset_n(reset_n),
        .data0(routed_usb_event),.valid0(routed_usb_valid),.ready0(routed_usb_ready),
        .data1(bridge_event),.valid1(bridge_valid),.ready1(bridge_ready),
        .data2(ui_event),.valid2(ui_valid),.ready2(ui_ready),
        .event_data(merged_event),.event_valid(merged_valid),.event_ready(merged_ready));
    midi_input_queue u_input_queue(.clk(clk),.reset_n(reset_n),
        .in_data(merged_event),.in_valid(merged_valid),.in_ready(merged_ready),
        .out_data(live_input_event),.out_valid(live_input_valid),.out_ready(live_input_ready));
    score_event_arbiter u_score_merge(.clk(clk),.reset_n(reset_n),
        .usb_event_valid(live_input_valid),.usb_event_data(live_input_event),.usb_event_ack(live_input_ready),
        .player_event_valid(score_valid),.player_event_data({8'h88,score_event[23:0]}),
        .player_event_urgent(score_flushing),.player_event_ack(score_ready),
        .midi_event_data(input_event),.midi_event_valid(input_valid),.midi_event_ready(external_ready));
    wire [31:0] lesson_state,lesson_data;
    wire lesson_bank,lesson_write;
    wire [7:0] lesson_count;
    wire [6:0] lesson_address;
    wire sequencer_active;
    wire [31:0] ai_status,composer_status,composer_detail;wire [159:0] arp_config;wire [31:0] arp_status;wire [127:0] arp_notes;
    wire latency_marker;
    wire [2:0] gesture_config;wire [31:0] gesture_position_packet,gesture_surface_status;
    wire [31:0] gesture_status,gesture_detail;wire [1:0] gesture_audio_mode;wire [31:0] camera_gesture_status;
    assign gesture_status={camera_gesture_status[31:16],gesture_audio_mode,camera_gesture_status[13:0]};
    wire gesture_valid,gesture_ready,gesture_allowed,gesture_cancel;
    wire [3:0] gesture_action;
    wire test_view=menu_page==0&&visual_mode&&spectrum_enable;
    wire test_button_press,test_stop_press;
    reg test_button_owned;
    always @(posedge clk)if(!reset_n||tutorial_start_n)test_button_owned<=0;
    else if(test_view||poly_test_active)test_button_owned<=1;
    debounced_press u_poly_stop_button(.clk(clk),.reset_n(reset_n),.button_n(tutorial_stop_n),.pressed(test_stop_press));
    debounced_press u_poly_test_button(.clk(clk),.reset_n(reset_n),.button_n(tutorial_start_n),.pressed(test_button_press));
    reg [11:0] test_quiet;
    wire test_modes_idle=!arp_config[0]&&!sequencer_active&&!composer_status[0]&&!ai_status[0]&&!lesson_state[16]&&!score_playing&&!score_flushing&&!tutorial_running;
    always @(posedge clk)if(!reset_n||voices!=0||merged_valid||!test_modes_idle)test_quiet<=0;
    else if(!(&test_quiet))test_quiet<=test_quiet+1'b1;
    polyphony_test32 u_poly_test(.clk(clk),.reset_n(reset_n),.press((test_button_press&&(test_view||poly_test_active))||(test_stop_press&&poly_test_active)),
        .allowed(test_view&&test_modes_idle&&(&test_quiet)),.active(poly_test_active),.valid(poly_test_valid),.data(poly_test_data),.ready(poly_test_ready));
    touch_ui_controller #(.VOICE_CAPACITY(AUDIO_VOICES),.GESTURE_ENABLED(1),.PHONE_ENABLED(1)) u_ui (
        .external_guide_active(tutorial_mode_lock||guide_suspend),.external_guide_suspend(guide_suspend),.external_mode_busy(upstream_ui_busy),
        .phone_request_valid(phone_request_valid),.phone_request_payload(phone_request_payload),.phone_request_ready(phone_request_ready),
        .phone_response_valid(phone_response_valid),.phone_response_token(phone_response_token),
        .phone_response_status(phone_response_status),.phone_response_value(phone_response_value),.phone_response_was_write(phone_response_was_write),
        .gesture_surface_status(gesture_surface_status),.gesture_config(gesture_config),.gesture_status(gesture_status),.gesture_detail(gesture_detail),
        .perf_data(perf_data),.perf_index(perf_index),.perf_snapshot(perf_snapshot),.perf_clear(perf_clear),
        .sequencer_active(sequencer_active),.arp_config(arp_config),.ai_status(ai_status),.composer_status(composer_status),.composer_detail(composer_detail),.arp_status(arp_status),.arp_notes(arp_notes),
        .lesson_state(lesson_state),.lesson_bank(lesson_bank),.lesson_count(lesson_count),
        .lesson_write(lesson_write),.lesson_address(lesson_address),.lesson_data(lesson_data),

        .clk(clk),.reset_n(reset_n),.sd_cs_n(sd_cs_n),.sd_clk(sd_clk),.sd_mosi(sd_mosi),.sd_miso(sd_miso),
        .tp_scl(tp_scl),.tp_sda(tp_sda),.tp_int(tp_int),.tp_rst(tp_rst),
        .uart_tx(uart_tx_pin),.midi_event_data(ui_event),.midi_event_valid(ui_valid),.midi_event_ready(ui_ready),
        .monitor_event(event_data),.monitor_event_valid(event_valid),
        .preset_index(preset),.algorithm(algorithm),.active_voices(voices),
        .touch_present(touch_present),.keyboard_octave(keyboard_octave),.master_volume(master_volume),
        .linear_enable(linear_enable),.visual_mode(visual_mode),.spectrum_enable(spectrum_enable),.headphone_select(headphone_select),.xy_delay_samples(xy_delay_samples),.display_auto_gain(display_auto_gain),
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
    assign upstream_mode_busy=upstream_ui_busy||external_auto_request||(|auto_request_history)||poly_test_active||
        arp_config[0]||(|arp_status[4:1])||(|ai_status[2:0])||(|composer_status[3:0])||gesture_config[1];
    always @(posedge clk or negedge reset_n)
        if(!reset_n)guide_suspend<=0;
        else guide_suspend<=tutorial_running||score_playing||score_flushing||(tutorial_mode_lock&&!upstream_mode_busy);
    top #(.FM_VOICE_COUNT(AUDIO_VOICES),.USB_HOST_ENABLED(0),.FM_AUDIO_ONLY(0),.FX2_ENABLED(1),.OUTPUT_SELECT_ENABLED(1),.GESTURE_ENABLED(1),.EXTERNAL_SCORE_ENABLED(1),.BOARD_LATENCY_INPUT(1),.POLY_TEST_ENABLED(1),.MIDI_TRACE_ENABLED(0),.MAPPED_KEY_SUPPORT(1)) u_audio (
        .external_guide_active(tutorial_mode_lock||guide_suspend),.external_auto_request(external_auto_request),
        .key_plan_active(key_plan_active),.key_plan_poly_available(key_plan_poly_available),
        .trace_usb_accept(usb_valid&&usb_ready),.trace_usb_data(usb_event),
        .poly_test_active(poly_test_active),.poly_test_valid(poly_test_valid),.poly_test_data(poly_test_data),.poly_test_ready(poly_test_ready),
        .board_latency_valid(merged_valid&&merged_ready),.board_latency_data(merged_event),
        .external_score_active(score_playing||score_flushing||poly_test_active),.latency_marker(latency_marker),.gesture_valid(gesture_valid),.gesture_action(gesture_action),
        .gesture_ready(gesture_ready),.gesture_allowed(gesture_allowed),.gesture_cancel(gesture_cancel),
        .gesture_timbre_mode(gesture_config[2]),.gesture_position_packet(gesture_position_packet),.gesture_surface_status(gesture_surface_status),
        .gesture_control(gesture_config[0]&&gesture_config[1]),.gesture_mode(gesture_audio_mode),
        .perf_data(perf_data),.perf_index(perf_index),.perf_snapshot(perf_snapshot),.perf_clear(perf_clear),.perf_bridge_drop(bridge_drop),
        .arp_config(arp_config),.arp_suspend(lesson_state[16]||sequencer_active||guide_suspend),.sequence_active(sequencer_active),.ai_status(ai_status),.composer_status(composer_status),.composer_detail(composer_detail),.arp_status(arp_status),.arp_notes(arp_notes),
        .clk(clk),.key_s2(~reset_n),.uart_rx_pin(uart_rx_pin),
        .headphone_select(headphone_select),.headphone_din(headphone_din),
        .ui_command_valid(ui_command_valid),.ui_command(ui_command),.ui_payload(ui_command_payload),
        .ui_command_ready(ui_command_ready),
        .fx_write(1'b0),.fx_index(4'd0),.fx_value(32'd0),
        .fx_read_index(4'd0),.fx_read_value(),
        .uart_tx_pin(),.usb_host_dp(),.usb_host_dn(),
        .i2s_bclk(i2s_bclk),.i2s_lrclk(i2s_lrclk),.i2s_din(i2s_din),
        .lcd_resetn(),.lcd_clk(),.lcd_cs(),.lcd_dc(),.lcd_data(),
        .external_midi_event_data(input_event),
        .external_midi_event_valid(input_valid),
        .external_midi_event_ready(external_ready),
        .monitor_sample(pcm),.monitor_sample_tick(tick),
        .monitor_midi_event_data(event_data),.monitor_midi_event_valid(event_valid),
        .monitor_voice_count(voices),.monitor_voice_mask(voice_mask),.monitor_preset(preset),
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
    // Isolate UI/source arbitration from the wait-for-key 128-note lookup.
    // This observes acceptance one clock later; it never feeds MIDI ready.
    wire [31:0] tutorial_key_event;wire tutorial_key_valid;wire [1:0] tutorial_key_source;
    midi_input_observer u_key_observer(.clk(clk),.reset_n(reset_n),
        .usb_data(usb_event),.bridge_data(bridge_event),.ui_data(ui_event),
        .usb_accept(usb_valid&&usb_ready),.bridge_accept(bridge_valid&&bridge_ready),.ui_accept(ui_valid&&ui_ready),
        .event_data(tutorial_key_event),.event_valid(tutorial_key_valid),.source(tutorial_key_source));
    sunny_tutorial_system #(.SCORE_MAX_EVENTS(8192),.SYNTH_VOICE_COUNT(AUDIO_VOICES),.PHONE_ENABLED(1),.KEY_PLAN_ENABLED(1)) u_tutorial(
        .external_mode_busy(upstream_mode_busy),.external_busy(1'b0),.mode_lock(tutorial_mode_lock),
        .calibration_success(calibration_success),.tone_success(tone_success),
        .phone_request_valid(phone_request_valid),.phone_request_payload(phone_request_payload),.phone_request_ready(phone_request_ready),
        .phone_response_valid(phone_response_valid),.phone_response_token(phone_response_token),
        .phone_response_status(phone_response_status),.phone_response_value(phone_response_value),.phone_response_was_write(phone_response_was_write),
        .key_plan_ready(ch376_configured&&!keyboard_disconnected&&!router_busy&&key_plan_poly_available&&
            !usb_valid&&!routed_usb_valid&&!merged_valid&&!live_input_valid&&!tutorial_key_valid),
        .keyboard_disconnected(keyboard_disconnected),.key_plan_active(key_plan_active),.key_plan_first(key_plan_first),
        .key_plan_valid(key_plan_valid),.key_plan_notes(key_plan_notes),
        .clk(clk),.reset_n(reset_n),.bt_rx(bluetooth_rx_pin),.bt_tx(bluetooth_tx_pin),
        .start_button_n((test_view||poly_test_active||test_button_owned)?1'b1:tutorial_start_n),.stop_button_n(tutorial_stop_n),
        .live_midi_event(event_data),.live_midi_valid(event_valid),
        .key_midi_event(tutorial_key_event),.key_midi_valid(tutorial_key_valid),.key_source(tutorial_key_source),
        .auto_midi_event(score_event),.auto_midi_valid(score_valid),.auto_midi_ready(score_ready),
        .auto_playing(score_playing),.auto_flushing(score_flushing),.led_data(ws2812_data),
        .running(tutorial_running),.count_in(tutorial_count_in),.beat_active(tutorial_beat),
        .initialized(tutorial_initialized),.mapping_missing(tutorial_missing),
        .frame_done(tutorial_frame_done),.reply_overflow(tutorial_reply_overflow));
    wire video_lock;
    rgb_visualizer u_video (.calibration_success(calibration_success|tone_success),.active_voice_mask(voice_mask),.linear_enable(linear_enable),.linear_write(linear_write),.linear_address(linear_address),.linear_data(linear_data),
        .lesson_state(lesson_state),.lesson_bank(lesson_bank),.lesson_count(lesson_count),
        .lesson_write(lesson_write),.lesson_address(lesson_address),.lesson_data(lesson_data),

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
    wire camera_ready,camera_stale;wire [2:0] camera_fault;
    camera_hdmi_tx #(.GESTURE_ENABLED(1),.GESTURE_GRAY(GESTURE_GRAY),.GESTURE_SELF_TEST(GESTURE_SELF_TEST)) u_hdmi (
        .gesture_config(gesture_config),.gesture_allowed(gesture_allowed),.gesture_cancel(gesture_cancel),
        .gesture_position_packet(gesture_position_packet),.gesture_action_valid(gesture_valid),.gesture_action_ready(gesture_ready),.gesture_action(gesture_action),
        .gesture_status(camera_gesture_status),.gesture_detail(gesture_detail),
        .clk(clk), .reset_n(reset_n),
        .camera_pclk(camera_pclk),.camera_href(camera_href),.camera_vsync(camera_vsync),
        .camera_data(camera_data),.camera_scl(camera_scl),.camera_sda(camera_sda),
        .camera_xclk(camera_xclk),.camera_reset_n(camera_reset_n),.camera_pwdn(camera_pwdn),
        .config_ready(camera_ready),.config_fault(camera_fault),.stream_stale(camera_stale),
        .hdmi_clk_p(hdmi_clk_p),
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
    // Additional historical dual-pin probe; the existing P7-15 interval marker stays intact.
    scope_touch_latency u_scope_latency(.clk(clk),.reset_n(reset_n),
        .enable(menu_page==0&&!upstream_mode_busy&&!tutorial_running&&!score_playing&&!score_flushing&&!lesson_state[16]),
        .event_valid(ui_valid),.event_ready(ui_ready),.event_data(ui_event),.active_voices(voices),
        .bclk(i2s_bclk),.lrclk(i2s_lrclk),.serial_data(i2s_din|headphone_din),
        .start_marker(scope_note_start),.done_marker(scope_audio_done));
    assign latency_probe=latency_marker;
    assign status_led={ch376_fault!=0,ch376_configured,ch376_present,bridge_dropped!=0||tutorial_reply_overflow,touch_present,event_hold!=0,video_lock,heartbeat[25]};
endmodule
