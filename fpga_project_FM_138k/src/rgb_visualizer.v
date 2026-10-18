// 800x480 TFT V3.0 RGB565 raster generated entirely in RTL; no framebuffer.
// The 512-point waveform is a ping-pong snapshot. Audio writes one bank;
// video switches banks only in vertical blanking, then releases the old bank.
module rgb_visualizer (
    input wire clk, input wire reset_n,
    input wire sample_tick, input wire signed [15:0] audio_sample,
    input wire [31:0] midi_event_data, input wire midi_event_valid,
    input wire [4:0] active_voice_count, preset_index, algorithm,
    input wire [47:0] operator_envelopes,
    input wire touch_present,
    input wire signed [3:0] keyboard_octave,
    input wire [6:0] master_volume,
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
    assign lcd_bl = video_reset_n;

    reg [10:0] hcount, x;
    reg [9:0] vcount, y;
    wire frame_latch = hcount == 0 && vcount == 480;
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
            volume_meta<=96;volume_sync<=96;volume_frame<=96;
            octave_meta<=0;octave_sync<=0;octave_frame<=0;touch_sync<=0;touch_frame<=0;
        end else begin
            keys_meta<=keys_down;keys_sync<=keys_meta;
            eg_meta<=operator_envelopes;eg_sync<=eg_meta;
            preset_meta<=preset_index;preset_sync<=preset_meta;
            voices_meta<=active_voice_count;voices_sync<=voices_meta;
            alg_meta<=algorithm;alg_sync<=alg_meta;
            peak_meta<=peak;peak_sync<=peak_meta;clip_sync<={clip_sync[0],clip_hold!=0};
            volume_meta<=master_volume;volume_sync<=volume_meta;
            octave_meta<=keyboard_octave;octave_sync<=octave_meta;
            touch_sync<={touch_sync[0],touch_present};
            if (frame_latch) begin
                keys_frame<=keys_sync;eg_frame<=eg_sync;preset_frame<=preset_sync;
                voices_frame<=voices_sync;alg_frame<=alg_sync;peak_frame<=peak_sync;clip_frame<=clip_sync[1];
                volume_frame<=volume_sync;octave_frame<=octave_sync;touch_frame<=touch_sync[1];
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
            "9":glyph=24'h699711; "-":glyph=24'h000F00; "+":glyph=24'h022F22;
            default:glyph=0;
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
    reg [23:0] rgb;
    reg font_enable;
    reg [7:0] font_character;
    reg [2:0] font_x,font_y;
    reg [23:0] font_color;
    reg [7:0] character;
    reg [9:0] tx,ty;
    reg signed [10:0] wave_y;
    integer k, bx, key_index, note_class, eg_height,base_note,menu_row;
    reg black_key;
    always @* begin
        rgb=24'h080D18;character=0;tx=0;ty=0;
        font_enable=0;font_character=0;font_x=0;font_y=0;font_color=24'hFFFFFF;
        wave_y=11'sd190-$signed(wave_sample);
        bx=0;key_index=0;note_class=0;eg_height=0;black_key=0;menu_row=0;
        base_note=48+$signed(octave_frame)*12;
        if (y<60) rgb=24'h142439;
        if (x>=24 && x<216 && y>=14 && y<26) begin
            tx=(x-24)>>1;ty=(y-14)>>1;
            character=TITLE[127-(tx/6)*8 -: 8];
            font_enable=1;font_character=character;font_x=tx%6;font_y=ty;
            font_color=24'h5AE8D0;
        end
        if (x>=24 && x<144 && y>=36 && y<48) begin
            tx=(x-24)>>1;ty=(y-36)>>1;
            character=preset_names[preset_frame*10+tx/6];
            font_enable=1;font_character=character;font_x=tx%6;font_y=ty;
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
            font_enable=1;font_character=character;font_x=tx%6;font_y=ty;
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
            key_index=(x-20)/40;
            rgb=keys_frame[base_note+white_note(key_index)] ? 24'h35DFC1 : 24'hCFD9E5;
            if ((x-20)%40==0 || y==459) rgb=24'h080D18;
            for(k=0;k<10;k=k+1)begin
                bx=20+black_boundary(k)*40;
                if(x>=bx-11&&x<bx+11&&y<439)
                    rgb=keys_frame[base_note+black_note(k)] ? 24'h1B9B99 : 24'h182137;
            end
        end
        // Menu buttons have fixed hit boxes shared with ui_firmware/main.c.
        if(x>=640&&x<800&&y>=64)rgb=24'h101E30;
        for(k=0;k<3;k=k+1)begin
            menu_row=80+k*56;
            if(y>=menu_row&&y<menu_row+40&&((x>=648&&x<714)||(x>=726&&x<792)))begin
                rgb=24'h284763;tx=(x<720)?(x-672)/3:(x-750)/3;ty=(y-menu_row-11)/3;
                if(y>=menu_row+11&&y<menu_row+29&&
                   ((x>=672&&x<684)||(x>=750&&x<762))&&
                   text_pixel(x<720?"-":"+",tx[2:0],ty[2:0]))rgb=24'hFFFFFF;
            end
        end
        if(x>=648&&x<792&&y>=248&&y<288)rgb=24'h733946;
        if(x>=648&&x<792&&y>=304&&y<324)rgb=touch_frame?24'h174D48:24'h733946;
        if(x>=648&&x<792)begin
            character=0;tx=(x-648)/6;ty=0;
            if(y>=68&&y<74)begin
                ty=y-68;case(tx)0:character="P";1:character="R";2:character="E";
                    3:character="S";4:character="E";5:character="T";default:character=0;endcase
            end else if(y>=124&&y<130)begin
                ty=y-124;case(tx)0:character="V";1:character="O";2:character="L";
                    3:character="U";4:character="M";5:character="E";
                    8:character="0"+volume_frame/100;9:character="0"+(volume_frame/10)%10;
                    10:character="0"+volume_frame%10;default:character=0;endcase
            end else if(y>=180&&y<186)begin
                ty=y-180;case(tx)0:character="O";1:character="C";2:character="T";
                    3:character="A";4:character="V";5:character="E";
                    8:character=octave_frame<0?"-":"+";
                    9:character="0"+(octave_frame<0?-octave_frame:octave_frame);
                    default:character=0;endcase
            end else if(y>=264&&y<270)begin
                ty=y-264;case(tx)7:character="P";8:character="A";9:character="N";
                    10:character="I";11:character="C";default:character=0;endcase
            end else if(y>=312&&y<318)begin
                ty=y-312;case(tx)1:character="T";2:character="O";3:character="U";
                    4:character="C";5:character="H";7:character=touch_frame?"O":"E";
                    8:character=touch_frame?"K":"R";9:character=touch_frame?0:"R";
                    default:character=0;endcase
            end
            font_enable=character!=0;font_character=character;font_x=(x-648)%6;font_y=ty[2:0];
            font_color=24'hF0F5FA;
        end
        if (!de) rgb=0;
    end
    // Forward the pixel clock with its active edge centered in stable data.
    ODDR u_pixel_clock (.Q0(lcd_pclk),.Q1(),.D0(1'b0),.D1(1'b1),.TX(1'b0),.CLK(pclk));
    // Pipeline the name-ROM lookup separately from the glyph decode.
    // Background RGB, DE and both syncs travel through the same registers.
    reg [23:0] background_pipe,font_color_pipe;
    reg [7:0] character_pipe;
    reg [2:0] font_x_pipe,font_y_pipe;
    reg font_enable_pipe,de_pipe,hs_pipe,vs_pipe;
    wire [23:0] final_rgb=(font_enable_pipe&&text_pixel(character_pipe,font_x_pipe,font_y_pipe))
        ? font_color_pipe : background_pipe;
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
            lcd_r<=final_rgb[23:19];lcd_g<=final_rgb[15:10];lcd_b<=final_rgb[7:3];
        end
    end
endmodule
