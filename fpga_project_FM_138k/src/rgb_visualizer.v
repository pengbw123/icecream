// 800x480 TFT V3.0 RGB565 raster generated entirely in RTL; no framebuffer.
// The 512-point waveform is a ping-pong snapshot. Audio writes one bank;
// video switches banks only in vertical blanking, then releases the old bank.
module rgb_visualizer #(
    // Fallback only: 1 forwards an inverted pixel clock.  Keep at 0 to match
    // the vendor TFT example and this panel's sampling edge.
    parameter integer PIXEL_CLK_INVERT = 0
) (
    input wire [31:0] lesson_state,
    input wire lesson_bank,input wire [7:0] lesson_count,
    input wire lesson_write,input wire [6:0] lesson_address,input wire [31:0] lesson_data,
    input wire clk, input wire reset_n,
    input wire sample_tick, input wire signed [15:0] audio_sample,
    input wire [31:0] midi_event_data, input wire midi_event_valid,
    input wire [31:0] active_voice_mask,
    input wire [7:0] active_voice_count,input wire [4:0] algorithm,
    input wire [6:0] preset_index,
    input wire [47:0] operator_envelopes,
    input wire touch_present,
    input wire signed [3:0] keyboard_octave,
    input wire [6:0] master_volume,
    input wire visual_mode,linear_enable,linear_write,input wire [8:0] linear_address,input wire [13:0] linear_data,
    input wire spectrum_enable,spectrum_write,
    input wire [5:0] spectrum_address,
    input wire [13:0] spectrum_data,
    input wire [6:0] xy_delay_samples,
    input wire [3:0] menu_page,input wire [47:0] algorithm_flags,
    input wire [23:0] background_color,wave_color,xy_color,
    input wire text_write,input wire [11:0] text_address,input wire [15:0] text_data,
    input wire palette_write,input wire [3:0] palette_index,input wire [23:0] palette_data,
    input wire text_enable,
    input wire eg_we,input wire [7:0] eg_addr,input wire [8:0] eg_data,
    input wire eg2_we,input wire [9:0] eg2_addr,input wire [7:0] eg2_data,input wire eg2_enable,
    input wire algo_we,input wire [14:0] algo_addr,input wire [7:0] algo_data,
    input wire algo_enable,
    input wire display_auto_gain,
    output wire lcd_pclk,
    output reg lcd_de,lcd_hsync,lcd_vsync,
    output wire lcd_bl,
    output reg [4:0] lcd_r,lcd_b,
    output reg [5:0] lcd_g,
    output wire pll_locked
);
    wire pclk, sclk;
    video_pll #(.PIXEL_DIV(30),.ENABLE_SERIAL(0)) u_video_pll (.clkin(clk), .pixel_clk(pclk),
        .serial_clk(sclk), .lock(pll_locked));
    reg [2:0] video_reset_sync = 0;
    always @(posedge pclk or negedge reset_n or negedge pll_locked)
        if (!reset_n || !pll_locked) video_reset_sync <= 0;
        else video_reset_sync <= {video_reset_sync[1:0],1'b1};
    wire video_reset_n = video_reset_sync[2];
    // Loss of video lock invalidates both sides of the ownership handshake.
    // Reset capture too; otherwise display resets to bank 1 while audio might
    // still be writing bank 1. Release is synchronized to the audio clock.
    reg [1:0] capture_reset_sync=0;
    always @(posedge clk or negedge video_reset_n)
        if(!video_reset_n)capture_reset_sync<=0;
        else capture_reset_sync<={capture_reset_sync[0],1'b1};
    wire capture_reset_n=capture_reset_sync[1];
    assign lcd_bl = video_reset_n;

    reg [10:0] hcount, x;
    reg [9:0] vcount, y;
    wire frame_latch = hcount == 0 && vcount == 480;
    wire menu_ink;wire [23:0] menu_color;
    wire [383:0] ui_palette;
    wire [23:0] ui_fg=ui_palette[1*24 +:24],ui_grid=ui_palette[11*24 +:24];
    wire [23:0] ui_panel=ui_palette[5*24 +:24],ui_dim=ui_palette[2*24 +:24];
    wire [23:0] ui_on=ui_palette[9*24 +:24],ui_soft=ui_palette[14*24 +:24];
    reg [3:0] page_meta,page_sync,page_frame;
    reg [23:0] bg_meta,bg_sync,bg_frame,wc_meta,wc_sync,wc_frame,xc_meta,xc_sync,xc_frame;
    reg [47:0] flags_meta,flags_sync,flags_frame;
    always @(posedge pclk)begin
        page_meta<=menu_page;page_sync<=page_meta;
        bg_meta<=background_color;bg_sync<=bg_meta;wc_meta<=wave_color;wc_sync<=wc_meta;
        xc_meta<=xy_color;xc_sync<=xc_meta;flags_meta<=algorithm_flags;flags_sync<=flags_meta;
        if(!video_reset_n)begin page_frame<=0;bg_frame<=24'h080D18;wc_frame<=24'h40EAD0;xc_frame<=24'hFFB95A;flags_frame<=0;end
        else if(frame_latch)begin page_frame<=page_sync;bg_frame<=bg_sync;wc_frame<=wc_sync;xc_frame<=xc_sync;flags_frame<=flags_sync;end
    end
    generate if(1)begin:g_menu_text
        // Character-cell menu layer.  Phase 0 keeps it disabled on the
        // performance page (page_frame==0) so the verified play screen is
        // unchanged; the page firmware drives it later.
        rtl_char_display u_menu(.clk(clk),.reset_n(reset_n),
            .text_write(text_write),.text_address(text_address),.text_data(text_data),
            .palette_write(palette_write),.palette_index(palette_index),.palette_data(palette_data),
            .pclk(pclk),.video_reset_n(video_reset_n),.h(hcount),.v(vcount),
            .enabled(text_enable),.ink(menu_ink),.color(menu_color),.palette_colors(ui_palette));
    end endgenerate
    wire xy_pixel,wave_valid;
    wire [7:0] wave_min,wave_max;
    wire [10:0] xy_read_x=hcount-11'd16;
    wire [9:0] xy_read_y=vcount-10'd96;
    audio_xy_scope u_xy (
        .clk(clk),.reset_n(capture_reset_n),.sample_tick(sample_tick),.audio_sample(audio_sample),
        .delay_samples(xy_delay_samples),.auto_gain(display_auto_gain),
        .pixel_clk(pclk),.video_reset_n(video_reset_n),.frame_latch(frame_latch),
        .pixel_address({xy_read_y[7:1],xy_read_x[8:1]}),.pixel_on(xy_pixel)
    );
    audio_wave_scope u_wave (
        .clk(clk),.reset_n(capture_reset_n),.sample_tick(sample_tick),.audio_sample(audio_sample),
        .auto_gain(display_auto_gain),.pixel_clk(pclk),.video_reset_n(video_reset_n),
        .frame_latch(frame_latch),.pixel_address(xy_read_x[8:0]),
        .y_min(wave_min),.y_max(wave_max),.valid(wave_valid)
    );
    wire [6:0] spectrum_level,spectrum_peak;
    wire spectrum_valid;
    audio_spectrum_snapshot u_spectrum_view (
        .clk(clk),.reset_n(capture_reset_n),.bin_write(spectrum_write),
        .bin_address(spectrum_address),.bin_data(spectrum_data),
        .pixel_clk(pclk),.video_reset_n(video_reset_n),.frame_latch(frame_latch),
        .pixel_address(xy_read_x[8:3]),.level(spectrum_level),.peak(spectrum_peak),.valid(spectrum_valid));
    wire [6:0] linear_level,linear_peak;wire linear_valid;
    audio_spectrum_snapshot #(.ADDRESS_BITS(9)) u_linear_view(
        .clk(clk),.reset_n(capture_reset_n),.bin_write(linear_write),.bin_address(linear_address),.bin_data(linear_data),
        .pixel_clk(pclk),.video_reset_n(video_reset_n),.frame_latch(frame_latch),.pixel_address(xy_read_x[8:0]),
        .level(linear_level),.peak(linear_peak),.valid(linear_valid));
    reg [1:0] linear_sync;reg linear_frame;
    always @(posedge pclk or negedge video_reset_n)if(!video_reset_n)begin linear_sync<=0;linear_frame<=0;end
    else begin linear_sync<={linear_sync[0],linear_enable};if(frame_latch)linear_frame<=linear_sync[1];end
    wire [9:0] linear_height=({3'd0,linear_level}*10'd7)/10'd3;
    wire [9:0] spectrum_height=({3'd0,spectrum_level}*10'd7)/10'd3;
    wire [9:0] spectrum_peak_height=({3'd0,spectrum_peak}*10'd7)/10'd3;
    always @(posedge pclk or negedge video_reset_n) begin
        if (!video_reset_n) begin hcount<=0; vcount<=0; x<=0; y<=0; end
        else begin
            x <= hcount; y <= vcount;
            if (hcount == 1055) begin
                hcount <= 0;
                if (vcount == 524) vcount <= 0;
                else vcount <= vcount + 1'b1;
            end else hcount <= hcount + 1'b1;
        end
    end
    wire de = x < 800 && y < 480;
    wire hsync = !(x >= 840 && x < 968);
    wire vsync = !(y >= 490 && y < 492);


    // Event visual state describes physical key-down, independently of pedal tails.
    reg [127:0] keys_down;
    wire [7:0] status=midi_event_data[23:16];
    wire [6:0] note=midi_event_data[14:8];
    wire [6:0] velocity=midi_event_data[6:0];
    reg [7:0] peak;
    reg [15:0] peak_decay;
    reg [23:0] clip_hold;
    wire [15:0] magnitude=audio_sample[15] ? -audio_sample : audio_sample;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin keys_down<=0; peak<=0; peak_decay<=0; clip_hold<=0; end
        else begin
            if (midi_event_valid) begin
                if (status[7:4]==4'h9) keys_down[note]<=velocity!=0;
                else if (status[7:4]==4'h8) keys_down[note]<=0;
            end
            if (midi_event_valid && status[7:4]==4'hB && (note==120 || note==123)) keys_down<=0;
            if (clip_hold!=0) clip_hold<=clip_hold-1'b1;
            if (sample_tick) begin
                peak_decay<=peak_decay+1'b1;
                if (magnitude[15:8]>peak) peak<=magnitude[15:8];
                else if (peak_decay[7:0]==0 && peak!=0) peak<=peak-1'b1;
                if (magnitude>=16'd32000) clip_hold<=24'd12500000;
            end
        end
    end
    reg [127:0] keys_meta, keys_sync, keys_frame;
    reg [6:0] volume_meta,volume_sync,volume_frame;
    reg signed [3:0] octave_meta,octave_sync,octave_frame;
    reg [1:0] touch_sync;
    reg touch_frame;
    reg [1:0] visual_sync;
    reg visual_frame;
    reg [31:0] voice_mask_meta,voice_mask_sync,voice_mask_frame;
    reg [1:0] spectrum_sync;
    reg spectrum_frame;
    reg [1:0] auto_sync;
    reg auto_frame;
    reg [6:0] delay_meta,delay_sync,delay_frame;
    reg [47:0] eg_meta, eg_sync, eg_frame;
    reg [6:0] preset_meta,preset_sync,preset_frame;
    reg [7:0] voices_meta,voices_sync,voices_frame;
    reg [4:0] alg_meta,alg_sync,alg_frame;
    reg [7:0] peak_meta,peak_sync,peak_frame;
    reg [1:0] clip_sync;
    reg clip_frame;
    always @(posedge pclk or negedge video_reset_n) begin
        if (!video_reset_n) begin
            keys_meta<=0;keys_sync<=0;keys_frame<=0;eg_meta<=0;eg_sync<=0;eg_frame<=0;
            preset_meta<=0;preset_sync<=0;preset_frame<=0;voices_meta<=0;voices_sync<=0;voices_frame<=0;
            alg_meta<=0;alg_sync<=0;alg_frame<=0;peak_meta<=0;peak_sync<=0;peak_frame<=0;
            clip_sync<=0;clip_frame<=0;
            volume_meta<=96;volume_sync<=96;volume_frame<=96;
            octave_meta<=0;octave_sync<=0;octave_frame<=0;touch_sync<=0;touch_frame<=0;
            visual_sync<=0;visual_frame<=0;delay_meta<=24;delay_sync<=24;delay_frame<=24;
            spectrum_sync<=0;spectrum_frame<=0;voice_mask_meta<=0;voice_mask_sync<=0;voice_mask_frame<=0;
            auto_sync<=0;auto_frame<=0;
        end else begin
            voice_mask_meta<=active_voice_mask;voice_mask_sync<=voice_mask_meta;
            keys_meta<=keys_down;keys_sync<=keys_meta;
            eg_meta<=operator_envelopes;eg_sync<=eg_meta;
            preset_meta<=preset_index;preset_sync<=preset_meta;
            voices_meta<=active_voice_count;voices_sync<=voices_meta;
            alg_meta<=algorithm;alg_sync<=alg_meta;
            peak_meta<=peak;peak_sync<=peak_meta;clip_sync<={clip_sync[0],clip_hold!=0};
            volume_meta<=master_volume;volume_sync<=volume_meta;
            octave_meta<=keyboard_octave;octave_sync<=octave_meta;
            touch_sync<={touch_sync[0],touch_present};
            visual_sync<={visual_sync[0],visual_mode};
            spectrum_sync<={spectrum_sync[0],spectrum_enable};
            auto_sync<={auto_sync[0],display_auto_gain};
            delay_meta<=xy_delay_samples;delay_sync<=delay_meta;
            if (frame_latch) begin
                keys_frame<=keys_sync;eg_frame<=eg_sync;preset_frame<=preset_sync;
                voices_frame<=voices_sync;alg_frame<=alg_sync;peak_frame<=peak_sync;clip_frame<=clip_sync[1];
                volume_frame<=volume_sync;octave_frame<=octave_sync;touch_frame<=touch_sync[1];
                visual_frame<=visual_sync[1];delay_frame<=delay_sync;
                spectrum_frame<=spectrum_sync[1];voice_mask_frame<=voice_mask_sync;
                auto_frame<=auto_sync[1];
            end
        end
    end

    reg [7:0] preset_names [0:1279];
    initial $readmemh("src/generated/fm_rom1a_names.mem",preset_names);
    function [23:0] glyph;
        input [7:0] c;
        begin case (c)
            "A":glyph=24'h699F99; "B":glyph=24'hE9E99E; "C":glyph=24'h788887;
            "D":glyph=24'hE9999E; "E":glyph=24'hF88E8F; "F":glyph=24'hF88E88;
            "G":glyph=24'h78B997; "H":glyph=24'h999F99; "I":glyph=24'hF2222F;
            "J":glyph=24'h111196; "K":glyph=24'h9ACCA9; "L":glyph=24'h88888F;
            "M":glyph=24'h9FF999; "N":glyph=24'h9DB999; "O":glyph=24'h699996;
            "P":glyph=24'hE99E88; "Q":glyph=24'h6999B7; "R":glyph=24'hE99EA9;
            "S":glyph=24'hF8861E; "T":glyph=24'hF22222; "U":glyph=24'h999996;
            "V":glyph=24'h999966; "W":glyph=24'h999FF9; "X":glyph=24'h996699;
            "Y":glyph=24'h996222; "Z":glyph=24'hF1248F;
            "0":glyph=24'h699DB6; "1":glyph=24'h262227; "2":glyph=24'h69124F;
            "3":glyph=24'hE1161E; "4":glyph=24'h99F111; "5":glyph=24'hF8E11E;
            "6":glyph=24'h68E996; "7":glyph=24'hF12444; "8":glyph=24'h699699;
            "9":glyph=24'h699711; "-":glyph=24'h000F00; "+":glyph=24'h022F22;
            default:glyph=0;
        endcase end
    endfunction
    // Exact floor(x*15/800) for the active 800-pixel keyboard, using a
    // balanced comparison tree instead of a 32-bit constant divider.
    function [3:0] white_key_index(input [10:0] pixel_x);
        begin
            white_key_index=pixel_x<427 ?
                (pixel_x<214 ? (pixel_x<107 ? (pixel_x<54?0:1):(pixel_x<160?2:3)):
                              (pixel_x<320 ? (pixel_x<267?4:5):(pixel_x<374?6:7))):
                (pixel_x<640 ? (pixel_x<534 ? (pixel_x<480?8:9):(pixel_x<587?10:11)):
                              (pixel_x<747 ? (pixel_x<694?12:13):14));
        end
    endfunction
    function white_key_edge(input [10:0] pixel_x);
        begin case(pixel_x)
            54,107,160,214,267,320,374,427,480,534,587,640,694,747:white_key_edge=1;
            default:white_key_edge=0;
        endcase end
    endfunction
    function [4:0] white_note;
        input integer index;
        begin case(index)
            0:white_note=0;1:white_note=2;2:white_note=4;3:white_note=5;
            4:white_note=7;5:white_note=9;6:white_note=11;7:white_note=12;
            8:white_note=14;9:white_note=16;10:white_note=17;11:white_note=19;
            12:white_note=21;13:white_note=23;default:white_note=24;
        endcase end
    endfunction
    function [3:0] black_boundary;
        input integer index;
        begin case(index)
            0:black_boundary=1;1:black_boundary=2;2:black_boundary=4;
            3:black_boundary=5;4:black_boundary=6;5:black_boundary=8;
            6:black_boundary=9;7:black_boundary=11;8:black_boundary=12;
            default:black_boundary=13;
        endcase end
    endfunction
    function [4:0] black_note;
        input integer index;
        begin case(index)
            0:black_note=1;1:black_note=3;2:black_note=6;3:black_note=8;
            4:black_note=10;5:black_note=13;6:black_note=15;7:black_note=18;
            8:black_note=20;default:black_note=22;
        endcase end
    endfunction
    function text_pixel;
        input [7:0] c;
        input [2:0] cx,cy;
        reg [23:0] bits;
        begin bits=glyph(c);text_pixel=(cx<4 && cy<6) ? bits[(5-cy)*4+3-cx] : 0;end
    endfunction
    localparam [127:0] TITLE="FM SYNTH ACG720 ";
    wire lesson_enabled,lesson_ink;
    wire [23:0] lesson_color;
    lesson_view #(.WIDTH(800)) u_lesson_view(
        .clk(clk),.reset_n(reset_n),.pclk(pclk),.video_reset_n(video_reset_n),.frame_latch(frame_latch),
        .prefetch_x(hcount),.x(x),.y(y),.state(lesson_state),.score_bank(lesson_bank),.score_count(lesson_count),
        .score_write(lesson_write),.score_address(lesson_address),.score_data(lesson_data),
        .midi_event(midi_event_data),.midi_valid(midi_event_valid),
        .background(bg_frame),.accent(wc_frame),.enabled(lesson_enabled),.ink(lesson_ink),.color(lesson_color));
    reg [23:0] rgb;
    reg font_enable;
    reg [7:0] font_character;
    reg [2:0] font_x,font_y;
    wire [2:0] voice_col=(x-16)>>6;
    wire [1:0] voice_row=(y-96)>>6;
    wire [5:0] voice_x=x-16,voice_y=y-96;
    reg [23:0] font_color;
    reg [7:0] character;
    reg [9:0] tx,ty;
    integer k, bx, key_index, note_class, eg_height,base_note,menu_row;
    reg black_key;
    always @* begin
        rgb=bg_frame;character=0;tx=0;ty=0;
        font_enable=0;font_character=0;font_x=0;font_y=0;font_color=24'hFFFFFF;
        bx=0;key_index=0;note_class=0;eg_height=0;black_key=0;menu_row=0;
        base_note=48+$signed(octave_frame)*12;
        if (x>=16 && x<528 && y>=96 && y<352) begin
            rgb=bg_frame;
            if (x[5:0]==16 || y==96 || y==160 || y==224 || y==288 || y==351) rgb=ui_grid;
            // One extra row above and below: a 1-pixel trace loses pixels on the
            // real panel and reads as a broken line.  The XY view already draws
            // 2x2 blocks, which is why only the waveform looked discontinuous.
            if (!spectrum_frame && !visual_frame && wave_valid &&
                y>=10'd96+wave_min-1'b1 && y<=10'd96+wave_max+1'b1) rgb=wc_frame;
            if (!spectrum_frame && visual_frame && xy_pixel) rgb=xc_frame;
            if(spectrum_frame)begin
                rgb=bg_frame;
                if(y<320)begin
                    if(linear_frame&&linear_valid&&linear_level!=0&&y>=320-linear_height)rgb=wc_frame;
                    if(x[5:0]==16 || y==96 || y==170 || y==245 || y==319)rgb=ui_grid;
                    if(!linear_frame && spectrum_valid && spectrum_level!=0 && x[2:0]!=7 &&
                       y>=320-spectrum_height)rgb=wc_frame;
                    if(!linear_frame && spectrum_valid && spectrum_peak!=0 && x[2:0]!=7 &&
                       y==320-spectrum_peak_height)rgb=ui_dim;
                end
            end
        end
        if(spectrum_frame&&visual_frame&&x>=16&&x<528&&y>=96&&y<352)begin
            rgb=bg_frame;
            if(voice_x>=4&&voice_x<60&&voice_y>=4&&voice_y<60)begin
                rgb=voice_mask_frame[{voice_row,voice_col}]?wc_frame:ui_panel;
                if(voice_x==4||voice_x==59||voice_y==4||voice_y==59)rgb=ui_grid;
            end
        end
        if (!spectrum_frame && x>=544 && x<576 && y>=96 && y<352) begin
            rgb=ui_panel;
            if (y>=351-peak_frame) rgb=wc_frame;
        end
        if (clip_frame && x>=544 && x<576 && y>=80 && y<88) rgb=wc_frame;
        if (x<800 && y>=352 && y<480) begin
            key_index=white_key_index(x);
            rgb=keys_frame[base_note+white_note(key_index)] ? wc_frame : 24'hF5F8FB;
            if (white_key_edge(x) || y==479) rgb=bg_frame;
            for(k=0;k<10;k=k+1)begin
                bx=(black_boundary(k)*800)/15;
                if(x>=bx-16&&x<bx+16&&y<432)
                    rgb=keys_frame[base_note+black_note(k)] ? wc_frame : 24'h111820;
            end
        end
        // Menu pages are a flat panel drawn entirely by the character layer;
        // hide the performance-page graphics behind it.  page_frame is latched
        // at the frame boundary, so this switch is tear-free.
        if(page_frame!=0&&!((page_frame==10||page_frame==11||page_frame==13||page_frame==14||page_frame==15)&&y>=352))begin rgb=bg_frame;font_enable=0;end
        if(page_frame==9&&lesson_ink)rgb=lesson_color;
        if (!de) rgb=0;
    end
    // Forward the pixel clock with the SAME phase as the logic that launches
    // RGB/DE/HS/VS, exactly like the vendor GW5AT-138K TFT example
    // (`assign Disp_PCLK = ClkDisp;`).  The panel latches on the opposite
    // clock edge, so a zero-degree forwarded clock puts the panel's sampling
    // edge in the middle of stable data.
    //
    // The previous implementation drove an ODDR with D0=0,D1=1.  In the GW5A
    // primitive Q0 = CLK ? d0_reg : d1_reg, so that produced an INVERTED
    // (180-degree) forwarded clock: the panel's sampling edge landed on the
    // data transition and thin glyph strokes lost pixels on the real screen
    // (simulation cannot show this because it models perfect sampling).
    // PIXEL_CLK_INVERT exists only as a fallback knob; keep it at 0.
    assign lcd_pclk = PIXEL_CLK_INVERT ? ~pclk : pclk;
    // Pipeline the name-ROM lookup separately from the glyph decode.
    // Background RGB, DE and both syncs travel through the same registers.
    reg [23:0] background_pipe,font_color_pipe;
    reg [7:0] character_pipe;
    reg [2:0] font_x_pipe,font_y_pipe;
    reg font_enable_pipe,de_pipe,hs_pipe,vs_pipe;
    wire eg2_ink;wire [2:0] eg2_cls;
    wire [23:0] eg2_color=(eg2_cls==3'd1)?ui_dim:(eg2_cls==3'd2)?wc_frame:
                          (eg2_cls==3'd3)?bg_frame:ui_grid;
    ui_eg_multi #(.PANEL_Y(208),.PANEL_H(80)) u_eg2(.pclk(pclk),.video_reset_n(video_reset_n),.h(hcount),.v(vcount),
        .enable(text_enable&&(page_frame==4'd3)&&eg2_enable),
        .wclk(clk),.we(eg2_we),.waddr(eg2_addr),.wdata(eg2_data),.ink(eg2_ink),.cls(eg2_cls));
    wire algo_ink;wire [1:0] algo_cls;
    wire [23:0] algo_color=(algo_cls==2'd1)?ui_soft:(algo_cls==2'd2)?ui_panel:ui_fg;
    ui_algo_map #(.PANEL_X(272),.PANEL_Y(144)) u_amap(.pclk(pclk),.video_reset_n(video_reset_n),.h(hcount),.v(vcount),
        .enable(text_enable&&(page_frame==4'd1)&&algo_enable),
        .wclk(clk),.we(algo_we),.waddr(algo_addr),.wdata(algo_data),
        .ink(algo_ink),.cls(algo_cls));
    wire pitch_ink;wire [1:0] pitch_cls;
    ui_eg_curve #(.X0(272),.Y0(192),.W(512),.H(208)) u_pitch(
        .pclk(pclk),.video_reset_n(video_reset_n),.h(hcount),.v(vcount),
        .enable(text_enable&&(page_frame==4'd8)),.wclk(clk),.we(eg_we),.waddr(eg_addr),.wdata(eg_data),.ink(pitch_ink),.cls(pitch_cls));
    wire [23:0] pitch_color=pitch_cls==2?wc_frame:pitch_cls==3?ui_grid:bg_frame;
    // Official logo reduced to a 64x24 two-colour static mask, no BSRAM.
    function [127:0] gowin_logo_row(input [4:0] row);
      begin case(row)
        5'd0:gowin_logo_row=128'h00000000000000000000000000000000;
        5'd1:gowin_logo_row=128'h00000000000a00020000000000000000;
        5'd2:gowin_logo_row=128'h00000000000a800a8000000000000000;
        5'd3:gowin_logo_row=128'h00000000000a800a8000000000000000;
        5'd4:gowin_logo_row=128'h00000000002a20222000000000000000;
        5'd5:gowin_logo_row=128'h0000000000a8a8a8a800000000000000;
        5'd6:gowin_logo_row=128'h0000000000a8a8a8a800000000000000;
        5'd7:gowin_logo_row=128'h5400541500a0a0a8a800155400055500;
        5'd8:gowin_logo_row=128'h54015415052a21222140555540555550;
        5'd9:gowin_logo_row=128'h54055415054a854a8541541550155554;
        5'd10:gowin_logo_row=128'h54055415054a955a8545500150000054;
        5'd11:gowin_logo_row=128'h54155415015215521505400054000015;
        5'd12:gowin_logo_row=128'h54145415015455545405400054554005;
        5'd13:gowin_logo_row=128'h54545415005554555405400054554005;
        5'd14:gowin_logo_row=128'h55505415001550155005400054540015;
        5'd15:gowin_logo_row=128'h55405415001540155005400150540015;
        5'd16:gowin_logo_row=128'h55405415000540054001500550540054;
        5'd17:gowin_logo_row=128'h55005415000500010000555540555554;
        5'd18:gowin_logo_row=128'h55005415000000000000155500555540;
        5'd19:gowin_logo_row=128'h00000000000000000000015000000000;
        5'd20:gowin_logo_row=128'h00000000000000000000000000000000;
        5'd21:gowin_logo_row=128'h00000000000000000000000000000000;
        5'd22:gowin_logo_row=128'h11554151011501441515554455155540;
        5'd23:gowin_logo_row=128'h00000000000000000000000000000000;
        default:gowin_logo_row=0;
      endcase end
    endfunction
    wire logo_area=page_frame==0&&x>=688&&x<752&&y>=80&&y<104;
    wire [127:0] logo_row=gowin_logo_row(y-80);
    wire [1:0] logo_code=logo_row[((x-688)&63)*2+:2];
    wire [23:0] logo_color=logo_code==1?24'h005183:logo_code==2?24'h00a0e9:24'hffffff;
    reg logo_area_pipe;reg [23:0] logo_color_pipe;
    always @(posedge pclk)if(!video_reset_n)begin logo_area_pipe<=0;logo_color_pipe<=0;end
    else begin logo_area_pipe<=logo_area;logo_color_pipe<=logo_color;end
    wire [23:0] final_rgb=logo_area_pipe?logo_color_pipe:menu_ink?menu_color:pitch_ink?pitch_color:
        (algo_ink?algo_color:(eg2_ink?eg2_color:background_pipe));
    always @(posedge pclk) begin
        if (!video_reset_n) begin
            lcd_de<=0;lcd_hsync<=0;lcd_vsync<=0;lcd_r<=0;lcd_g<=0;lcd_b<=0;
            background_pipe<=0;font_color_pipe<=0;character_pipe<=0;font_x_pipe<=0;font_y_pipe<=0;
            font_enable_pipe<=0;de_pipe<=0;hs_pipe<=0;vs_pipe<=0;
        end else begin
            background_pipe<=rgb;font_color_pipe<=font_color;character_pipe<=font_character;
            font_x_pipe<=font_x;font_y_pipe<=font_y;font_enable_pipe<=font_enable;
            de_pipe<=de;hs_pipe<=hsync;vs_pipe<=vsync;
            lcd_de<=de_pipe;lcd_hsync<=hs_pipe;lcd_vsync<=vs_pipe;
            lcd_r<=final_rgb[23:19];
            lcd_g<=final_rgb[15:10];
            lcd_b<=final_rgb[7:3];
        end
    end
endmodule


