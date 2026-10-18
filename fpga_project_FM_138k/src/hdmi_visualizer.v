// 640x480 RGB video generated entirely in RTL; no CPU or DDR framebuffer.
// The 512-point waveform is a ping-pong snapshot. Audio writes one bank;
// video switches banks only in vertical blanking, then releases the old bank.
module hdmi_visualizer (
    input wire clk, input wire reset_n,
    input wire sample_tick, input wire signed [15:0] audio_sample,
    input wire [31:0] midi_event_data, input wire midi_event_valid,
    input wire [4:0] active_voice_count, preset_index, algorithm,
    input wire [47:0] operator_envelopes,
    output wire hdmi_clk_p, output wire hdmi_clk_n,
    output wire [2:0] hdmi_data_p, output wire [2:0] hdmi_data_n,
    output wire hdmi_oe, output wire pll_locked
);
    wire pclk, sclk;
    video_pll u_video_pll (.clkin(clk), .pixel_clk(pclk),
        .serial_clk(sclk), .lock(pll_locked));
    reg [2:0] video_reset_sync = 0;
    always @(posedge pclk or negedge reset_n or negedge pll_locked)
        if (!reset_n || !pll_locked) video_reset_sync <= 0;
        else video_reset_sync <= {video_reset_sync[1:0],1'b1};
    wire video_reset_n = video_reset_sync[2];
    assign hdmi_oe = reset_n;

    reg [9:0] hcount, vcount;
    reg [9:0] x, y;
    wire frame_latch = hcount == 0 && vcount == 480;
    always @(posedge pclk or negedge video_reset_n) begin
        if (!video_reset_n) begin hcount<=0; vcount<=0; x<=0; y<=0; end
        else begin
            x <= hcount; y <= vcount;
            if (hcount == 799) begin
                hcount <= 0;
                if (vcount == 524) vcount <= 0;
                else vcount <= vcount + 1'b1;
            end else hcount <= hcount + 1'b1;
        end
    end
    wire de = x < 640 && y < 480;
    wire hsync = !(x >= 656 && x < 752);
    wire vsync = !(y >= 490 && y < 492);

    reg [7:0] wave_memory [0:1023];
    integer init_i;
    initial for (init_i=0;init_i<1024;init_i=init_i+1) wave_memory[init_i]=0;
    reg [8:0] write_address;
    reg write_bank, capture_pending, capture_toggle;
    reg video_ack;
    reg [1:0] ack_sync;
    always @(posedge clk)
        if (reset_n && sample_tick && !capture_pending)
            wave_memory[{write_bank,write_address}] <= audio_sample[15:8];
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            write_address<=0; write_bank<=0; capture_pending<=0;
            capture_toggle<=0; ack_sync<=0;
        end else begin
            ack_sync <= {ack_sync[0],video_ack};
            if (capture_pending) begin
                if (ack_sync[1] == capture_toggle) begin
                    capture_pending<=0; write_bank<=~write_bank; write_address<=0;
                end
            end else if (sample_tick) begin
                if (write_address == 511) begin
                    capture_pending<=1; capture_toggle<=~capture_toggle;
                end else write_address<=write_address+1'b1;
            end
        end
    end
    reg [1:0] capture_sync, bank_sync;
    reg display_bank;
    reg signed [7:0] wave_sample;
    wire [9:0] read_x = hcount - 10'd32;
    always @(posedge pclk) wave_sample <= wave_memory[{display_bank,read_x[8:0]}];
    always @(posedge pclk or negedge video_reset_n) begin
        if (!video_reset_n) begin
            capture_sync<=0; bank_sync<=0; display_bank<=1; video_ack<=0;
        end else begin
            capture_sync<={capture_sync[0],capture_toggle};
            bank_sync<={bank_sync[0],write_bank};
            if (frame_latch && capture_sync[1] != video_ack) begin
                display_bank<=bank_sync[1]; video_ack<=capture_sync[1];
            end
        end
    end

    // Event visual state describes physical key-down, independently of pedal tails.
    reg [24:0] keys_down;
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
            if (midi_event_valid && note>=48 && note<=72) begin
                if (status[7:4]==4'h9) keys_down[note-48]<=velocity!=0;
                else if (status[7:4]==4'h8) keys_down[note-48]<=0;
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
    reg [24:0] keys_meta, keys_sync, keys_frame;
    reg [47:0] eg_meta, eg_sync, eg_frame;
    reg [4:0] preset_meta,preset_sync,preset_frame;
    reg [4:0] voices_meta,voices_sync,voices_frame;
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
        end else begin
            keys_meta<=keys_down;keys_sync<=keys_meta;
            eg_meta<=operator_envelopes;eg_sync<=eg_meta;
            preset_meta<=preset_index;preset_sync<=preset_meta;
            voices_meta<=active_voice_count;voices_sync<=voices_meta;
            alg_meta<=algorithm;alg_sync<=alg_meta;
            peak_meta<=peak;peak_sync<=peak_meta;clip_sync<={clip_sync[0],clip_hold!=0};
            if (frame_latch) begin
                keys_frame<=keys_sync;eg_frame<=eg_sync;preset_frame<=preset_sync;
                voices_frame<=voices_sync;alg_frame<=alg_sync;peak_frame<=peak_sync;clip_frame<=clip_sync[1];
            end
        end
    end

    reg [7:0] preset_names [0:319];
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
            "9":glyph=24'h699711; "-":glyph=24'h000F00;
            default:glyph=0;
        endcase end
    endfunction
    function text_pixel;
        input [7:0] c;
        input [2:0] cx,cy;
        reg [23:0] bits;
        begin bits=glyph(c);text_pixel=(cx<4 && cy<6) ? bits[(5-cy)*4+3-cx] : 0;end
    endfunction
    localparam [127:0] TITLE="FM SYNTH ACG720 ";
    reg [23:0] rgb;
    reg [7:0] character;
    reg [9:0] tx,ty;
    reg signed [10:0] wave_y;
    integer k, bx, key_index, note_class, eg_height;
    reg black_key;
    always @* begin
        rgb=24'h080D18;character=0;tx=0;ty=0;
        wave_y=11'sd190-$signed(wave_sample);
        bx=0;key_index=0;note_class=0;eg_height=0;black_key=0;
        if (y<60) rgb=24'h142439;
        if (x>=24 && x<216 && y>=14 && y<26) begin
            tx=(x-24)>>1;ty=(y-14)>>1;
            character=TITLE[127-(tx/6)*8 -: 8];
            if (text_pixel(character,tx%6,ty)) rgb=24'h5AE8D0;
        end
        if (x>=24 && x<144 && y>=36 && y<48) begin
            tx=(x-24)>>1;ty=(y-36)>>1;
            character=preset_names[preset_frame*10+tx/6];
            if (text_pixel(character,tx%6,ty)) rgb=24'hFFFFFF;
        end
        // Two-digit status: Pxx (preset 1..32), Vxx, Axx (algorithm 1..32).
        if (x>=350 && x<566 && y>=24 && y<36) begin
            tx=(x-350)>>1;ty=(y-24)>>1;
            case (tx/6)
                0:character="P";1:character="0"+(preset_frame+1)/10;
                2:character="0"+(preset_frame+1)%10;4:character="V";
                5:character="0"+voices_frame/10;6:character="0"+voices_frame%10;
                8:character="A";9:character="0"+(alg_frame+1)/10;
                10:character="0"+(alg_frame+1)%10;default:character=" ";
            endcase
            if (text_pixel(character,tx%6,ty)) rgb=24'hFFFFFF;
        end
        if (x>=32 && x<544 && y>=64 && y<316) begin
            rgb=24'h0A1624;
            if (x[5:0]==32 || y==64 || y==127 || y==190 || y==253 || y==315) rgb=24'h20354B;
            if ($signed({1'b0,y})>=wave_y-1 && $signed({1'b0,y})<=wave_y+1) rgb=24'h40EAD0;
        end
        if (x>=576 && x<608 && y>=64 && y<316) begin
            rgb=24'h1B2B3F;
            if (y>=315-peak_frame) rgb=(peak_frame>120) ? 24'hFF8050 : 24'h53D48E;
        end
        if (clip_frame && x>=576 && x<608 && y>=40 && y<52) rgb=24'hFF3040;
        for (k=0;k<6;k=k+1) begin
            bx=32+k*86;eg_height=eg_frame[k*8 +: 8]>>2;
            if (x>=bx && x<bx+62 && y>=324 && y<388) begin
                rgb=24'h1B2B3F;
                if (y>=388-eg_height) rgb=24'h798CFF;
            end
        end
        if (x>=20 && x<620 && y>=408 && y<460) begin
            key_index=(x-20)/24;note_class=key_index%12;
            black_key=note_class==1 || note_class==3 || note_class==6 || note_class==8 || note_class==10;
            rgb=black_key ? 24'h28334A : 24'hCFD9E5;
            if (keys_frame[key_index]) rgb=24'h35DFC1;
            if ((x-20)%24==0 || y==459) rgb=24'h080D18;
        end
        if (!de) rgb=0;
    end
    wire [9:0] red_symbol,green_symbol,blue_symbol;
    tmds_encoder u_r (.clk(pclk),.reset_n(video_reset_n),.data(rgb[23:16]),.de(de),.c0(1'b0),.c1(1'b0),.symbol(red_symbol));
    tmds_encoder u_g (.clk(pclk),.reset_n(video_reset_n),.data(rgb[15:8]),.de(de),.c0(1'b0),.c1(1'b0),.symbol(green_symbol));
    tmds_encoder u_b (.clk(pclk),.reset_n(video_reset_n),.data(rgb[7:0]),.de(de),.c0(hsync),.c1(vsync),.symbol(blue_symbol));
    tmds_lane u_clk (.pixel_clk(pclk),.serial_clk(sclk),.reset_n(video_reset_n),.symbol(10'b1111100000),.out_p(hdmi_clk_p),.out_n(hdmi_clk_n));
    tmds_lane u_red (.pixel_clk(pclk),.serial_clk(sclk),.reset_n(video_reset_n),.symbol(red_symbol),.out_p(hdmi_data_p[2]),.out_n(hdmi_data_n[2]));
    tmds_lane u_green (.pixel_clk(pclk),.serial_clk(sclk),.reset_n(video_reset_n),.symbol(green_symbol),.out_p(hdmi_data_p[1]),.out_n(hdmi_data_n[1]));
    tmds_lane u_blue (.pixel_clk(pclk),.serial_clk(sclk),.reset_n(video_reset_n),.symbol(blue_symbol),.out_p(hdmi_data_p[0]),.out_n(hdmi_data_n[0]));
endmodule
