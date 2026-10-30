// Temporary HDMI camera monitor; the RGB UI/audio chain stays independent.
module camera_hdmi_tx #(parameter integer GESTURE_ENABLED=0)(
    input wire clk,reset_n,input wire camera_pclk,camera_href,camera_vsync,
    input wire [7:0] camera_data,inout wire camera_scl,camera_sda,
    output wire camera_xclk,camera_reset_n,camera_pwdn,
    output wire hdmi_clk_p,hdmi_clk_n,output wire [2:0] hdmi_data_p,hdmi_data_n,
    output wire hdmi_oe,pll_locked,config_ready,stream_stale,
    output wire [2:0] config_fault,
    input wire [2:0] gesture_config,
    input wire gesture_allowed,gesture_cancel,gesture_action_ready,
    output wire gesture_action_valid,output wire [3:0] gesture_action,
    output wire [31:0] gesture_status,gesture_detail
);
    wire pixel_clk,serial_clk;
    video_pll #(.PIXEL_DIV(40),.ENABLE_SERIAL(1)) u_video_pll(
        .clkin(clk),.pixel_clk(pixel_clk),.serial_clk(serial_clk),.lock(pll_locked));
    wire camera_ref_locked;
    camera_reference_pll u_camera_pll(.clkin(clk),.reset_n(reset_n),.clkout(camera_xclk),.lock(camera_ref_locked));
    assign camera_pwdn=1'b0; // Explicitly wake the sensor, as in the board ch59.
    reg [2:0] sys_reset_sync,video_reset_sync,cam_reset_sync;
    wire common_reset_n=reset_n&&pll_locked;
    wire camera_common_n=reset_n&&camera_ref_locked;
    always @(posedge clk or negedge camera_common_n)
        if(!camera_common_n)sys_reset_sync<=0;else sys_reset_sync<={sys_reset_sync[1:0],1'b1};
    always @(posedge pixel_clk or negedge common_reset_n)
        if(!common_reset_n)video_reset_sync<=0;else video_reset_sync<={video_reset_sync[1:0],1'b1};
    wire capture_common_n=camera_common_n&&config_ready;
    always @(posedge camera_pclk or negedge capture_common_n)
        if(!capture_common_n)cam_reset_sync<=0;else cam_reset_sync<={cam_reset_sync[1:0],1'b1};
    wire frame_start,frame_good,frame_bad,pixel_write,frame_toggle,bad_toggle;
    wire [14:0] pixel_address,read_address;wire [7:0] pixel_data,read_data;
    wire [15:0] pixel_rgb565;wire [15:0] chip_id;wire [7:0] capture_status;
    wire debug_request,debug_ack;wire [71:0] debug_packet;
    ov5640_config u_config(.clk(clk),.reset_n(sys_reset_sync[2]),.frame_toggle(frame_toggle),
        .camera_reset_n(camera_reset_n),.scl(camera_scl),.sda(camera_sda),
        .ready(config_ready),.fault(config_fault),.chip_id(chip_id));
    ov5640_capture #(.WIDTH(800),.HEIGHT(480),.WARMUP_FRAMES(10),
        .CROP_X(80),.CROP_WIDTH(640),.SAMPLE_X(4),.SAMPLE_Y(4)) u_capture(
        .pclk(camera_pclk),.reset_n(cam_reset_sync[2]),
        .data(camera_data),.href(camera_href),.vsync(camera_vsync),
        .pixel_write(pixel_write),.pixel_address(pixel_address),.pixel_data(pixel_data),.pixel_rgb565(pixel_rgb565),
        .frame_start(frame_start),.frame_good(frame_good),.frame_bad(frame_bad),
        .frame_toggle(frame_toggle),.bad_toggle(bad_toggle),
        .debug_request(debug_request),.debug_packet(debug_packet),.debug_ack(debug_ack),.capture_status(capture_status));
    wire buffer_valid,present_pulse,frame_latch,drop_toggle;
    camera_framebuffer u_buffer(.pclk(camera_pclk),.pixel_clk(pixel_clk),.reset_n(capture_common_n&&pll_locked),
        .frame_start(frame_start),.frame_good(frame_good),.pixel_write(pixel_write),
        .pixel_address(pixel_address),.pixel_data(pixel_data),.frame_latch(frame_latch),
        .read_address(read_address),.read_data(read_data),.valid(buffer_valid),
        .present_pulse(present_pulse),.drop_toggle(drop_toggle));
    wire [7:0] red,green,blue;wire de,hsync,vsync;
    wire [2371:0] gesture_video_data;
    generate if(GESTURE_ENABLED)begin:g_gesture
        wire [255:0] mask;wire [3:0] reason;wire [2047:0] gray;
        gesture_controller #(.GRAY(1)) u_gesture(.clk(clk),.camera_clk(camera_pclk),.reset_n(sys_reset_sync[2]),
            .capture_reset_n(capture_common_n),.camera_ready(config_ready),.camera_fault(config_fault),
            .config_data(gesture_config),.frame_start(frame_start),.frame_good(frame_good),.frame_bad(frame_bad),
            .pixel_write(pixel_write),.pixel_address(pixel_address),.pixel_data(pixel_data),
            .allowed(gesture_allowed),.cancel(gesture_cancel),.action_ready(gesture_action_ready),
            .action_valid(gesture_action_valid),.action(gesture_action),.status(gesture_status),.detail(gesture_detail),
            .debug_mask(mask),.debug_reason(reason),.pixel_rgb565(pixel_rgb565),.debug_gray(gray));
        gesture_video_snapshot #(.WIDTH(2372)) snapshot(.clk(clk),.pixel_clk(pixel_clk),.reset_n(common_reset_n),
            .frame_latch(frame_latch),.source_data({gray,reason,mask,gesture_detail,gesture_status}),.video_data(gesture_video_data));
    end else begin
        assign gesture_action_valid=0;assign gesture_action=0;assign gesture_status=0;assign gesture_detail=0;
        assign gesture_video_data=0;
    end endgenerate
    camera_hdmi_video #(.GESTURE_ENABLED(GESTURE_ENABLED),.GRAY_PREVIEW(1)) u_video(.pixel_clk(pixel_clk),.reset_n(video_reset_sync[2]),
        .gesture_status(gesture_video_data[31:0]),.gesture_detail(gesture_video_data[63:32]),
        .gesture_gray(gesture_video_data[2371:324]),.gesture_mask(gesture_video_data[319:64]),.gesture_reason(gesture_video_data[323:320]),
        .config_ready(config_ready),.config_fault(config_fault),.buffer_valid(buffer_valid),
        .present_pulse(present_pulse),.pixel_data(read_data),.bad_toggle(bad_toggle),.drop_toggle(drop_toggle),
        .camera_pclk(camera_pclk),.camera_href(camera_href),.camera_vsync(camera_vsync),.chip_id(chip_id),
        .debug_request(debug_request),.debug_packet(debug_packet),.debug_ack(debug_ack),.capture_status(capture_status),
        .frame_latch(frame_latch),.read_address(read_address),.red(red),.green(green),.blue(blue),
        .de(de),.hsync(hsync),.vsync(vsync),.stream_stale(stream_stale));
    assign hdmi_oe=video_reset_sync[2];
    wire [9:0] r,g,b;
    tmds_encoder u_r(.clk(pixel_clk),.reset_n(video_reset_sync[2]),.data(red),.de(de),.c0(1'b0),.c1(1'b0),.symbol(r));
    tmds_encoder u_g(.clk(pixel_clk),.reset_n(video_reset_sync[2]),.data(green),.de(de),.c0(1'b0),.c1(1'b0),.symbol(g));
    tmds_encoder u_b(.clk(pixel_clk),.reset_n(video_reset_sync[2]),.data(blue),.de(de),.c0(hsync),.c1(vsync),.symbol(b));
    tmds_lane u_clock(.pixel_clk(pixel_clk),.serial_clk(serial_clk),.reset_n(video_reset_sync[2]),.symbol(10'b1111100000),.out_p(hdmi_clk_p),.out_n(hdmi_clk_n));
    tmds_lane u_red(.pixel_clk(pixel_clk),.serial_clk(serial_clk),.reset_n(video_reset_sync[2]),.symbol(r),.out_p(hdmi_data_p[2]),.out_n(hdmi_data_n[2]));
    tmds_lane u_green(.pixel_clk(pixel_clk),.serial_clk(serial_clk),.reset_n(video_reset_sync[2]),.symbol(g),.out_p(hdmi_data_p[1]),.out_n(hdmi_data_n[1]));
    tmds_lane u_blue(.pixel_clk(pixel_clk),.serial_clk(serial_clk),.reset_n(video_reset_sync[2]),.symbol(b),.out_p(hdmi_data_p[0]),.out_n(hdmi_data_n[0]));
endmodule
