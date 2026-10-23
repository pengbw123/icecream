// Independent 640x480 raster for the HDMI connector. Capture and drawing
// reuse the same RTL scopes as the 800x480 panel; the UI CPU draws no pixels.
module hdmi_scope_video (
    input wire clk, reset_n, pixel_clk, pll_locked,
    input wire sample_tick,
    input wire signed [15:0] audio_sample,
    input wire visual_mode,
    input wire spectrum_enable,spectrum_write,
    input wire [5:0] spectrum_address,
    input wire [13:0] spectrum_data,
    input wire [6:0] xy_delay_samples,
    input wire display_auto_gain,
    input wire [23:0] background_color, wave_color, xy_color,
    output wire video_reset_n,
    output wire [7:0] red, green, blue,
    output wire de, hsync, vsync
);
    reg [2:0] reset_sync = 0;
    always @(posedge pixel_clk or negedge reset_n or negedge pll_locked)
        if (!reset_n || !pll_locked) reset_sync <= 0;
        else reset_sync <= {reset_sync[1:0], 1'b1};
    assign video_reset_n = reset_sync[2];

    // Losing the video PLL resets both owners of each capture bank.
    reg [1:0] capture_reset_sync = 0;
    always @(posedge clk or negedge video_reset_n)
        if (!video_reset_n) capture_reset_sync <= 0;
        else capture_reset_sync <= {capture_reset_sync[0], 1'b1};
    wire capture_reset_n = capture_reset_sync[1];

    reg [9:0] hcount, vcount, x, y;
    wire frame_latch = (hcount == 0 && vcount == 480);
    always @(posedge pixel_clk or negedge video_reset_n)
        if (!video_reset_n) begin
            hcount <= 0; vcount <= 0; x <= 0; y <= 0;
        end else begin
            x <= hcount; y <= vcount;
            if (hcount == 799) begin
                hcount <= 0;
                vcount <= (vcount == 524) ? 10'd0 : vcount + 1'b1;
            end else hcount <= hcount + 1'b1;
        end
    assign de = (x < 640 && y < 480);
    assign hsync = !(x >= 656 && x < 752);
    assign vsync = !(y >= 490 && y < 492);

    reg [1:0] mode_sync, auto_sync;
    reg [6:0] delay_meta, delay_sync;
    reg [23:0] bg_meta, bg_sync, wave_meta, wave_sync, xy_meta, xy_sync;
    reg mode_frame;
    reg [1:0] spectrum_sync;
    reg spectrum_frame;
    reg [23:0] bg_frame, wave_frame, xy_frame;
    always @(posedge pixel_clk or negedge video_reset_n)
        if (!video_reset_n) begin
            mode_sync <= 0; auto_sync <= 0; delay_meta <= 24; delay_sync <= 24;
            spectrum_sync<=0;spectrum_frame<=0;
            bg_meta <= 24'h080D18; bg_sync <= 24'h080D18;
            wave_meta <= 24'h40EAD0; wave_sync <= 24'h40EAD0;
            xy_meta <= 24'hFFB95A; xy_sync <= 24'hFFB95A;
            mode_frame <= 0; bg_frame <= 24'h080D18;
            wave_frame <= 24'h40EAD0; xy_frame <= 24'hFFB95A;
        end else begin
            mode_sync <= {mode_sync[0], visual_mode};
            spectrum_sync<={spectrum_sync[0],spectrum_enable};
            auto_sync <= {auto_sync[0], display_auto_gain};
            delay_meta <= xy_delay_samples; delay_sync <= delay_meta;
            bg_meta <= background_color; bg_sync <= bg_meta;
            wave_meta <= wave_color; wave_sync <= wave_meta;
            xy_meta <= xy_color; xy_sync <= xy_meta;
            if (frame_latch) begin
                mode_frame <= mode_sync[1]; bg_frame <= bg_sync;
                spectrum_frame<=spectrum_sync[1];
                wave_frame <= wave_sync; xy_frame <= xy_sync;
            end
        end

    wire [9:0] local_x = hcount - 10'd64;
    wire [9:0] local_y = vcount - 10'd96;
    wire [7:0] wave_min, wave_max;
    wire wave_valid, xy_pixel;
    audio_wave_scope u_wave (
        .clk(clk), .reset_n(capture_reset_n), .sample_tick(sample_tick),
        .auto_gain(display_auto_gain), .audio_sample(audio_sample),
        .pixel_clk(pixel_clk), .video_reset_n(video_reset_n),
        .frame_latch(frame_latch), .pixel_address(local_x[8:0]),
        .y_min(wave_min), .y_max(wave_max), .valid(wave_valid)
    );
    audio_xy_scope u_xy (
        .clk(clk), .reset_n(capture_reset_n), .sample_tick(sample_tick),
        .audio_sample(audio_sample), .delay_samples(xy_delay_samples),
        .auto_gain(display_auto_gain), .pixel_clk(pixel_clk),
        .video_reset_n(video_reset_n), .frame_latch(frame_latch),
        .pixel_address({local_y[7:1], local_x[8:1]}), .pixel_on(xy_pixel)
    );
    wire [6:0] spectrum_level,spectrum_peak;
    wire spectrum_valid;
    audio_spectrum_snapshot u_spectrum_view (
        .clk(clk),.reset_n(capture_reset_n),.bin_write(spectrum_write),
        .bin_address(spectrum_address),.bin_data(spectrum_data),
        .pixel_clk(pixel_clk),.video_reset_n(video_reset_n),.frame_latch(frame_latch),
        .pixel_address(local_x[8:3]),.level(spectrum_level),.peak(spectrum_peak),.valid(spectrum_valid));
    wire [9:0] spectrum_height=({3'd0,spectrum_level}*10'd7)/10'd3;
    wire [9:0] spectrum_peak_height=({3'd0,spectrum_peak}*10'd7)/10'd3;

    reg [23:0] rgb;
    always @* begin
        rgb = bg_frame;
        if (x >= 64 && x < 576 && y >= 96 && y < 352) begin
            rgb = 24'h101013;
            if (x[5:0] == 0 || y == 96 || y == 160 || y == 224 ||
                y == 288 || y == 351) rgb = 24'h303038;
            if (!spectrum_frame && !mode_frame && wave_valid &&
                y >= 10'd96 + wave_min - 1'b1 &&
                y <= 10'd96 + wave_max + 1'b1) rgb = wave_frame;
            if (!spectrum_frame && mode_frame && xy_pixel) rgb = xy_frame;
            if(spectrum_frame)begin
                rgb=bg_frame;
                if(y<320)begin
                    if(x[5:0]==0 || y==96 || y==170 || y==245 || y==319)rgb=24'h303038;
                    if(spectrum_valid && spectrum_level!=0 && x[2:0]!=7 &&
                       y>=320-spectrum_height)rgb=wave_frame;
                    if(spectrum_valid && spectrum_peak!=0 && x[2:0]!=7 &&
                       y==320-spectrum_peak_height)rgb=xy_frame;
                end
            end
        end
        if (!de) rgb = 0;
    end
    assign {red, green, blue} = rgb;
endmodule
