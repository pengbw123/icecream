// ST7735 160x80 FM status display for the one-PMOD LCD board.
// The LCD GRAM is the framebuffer; FPGA memory holds only 32 preset names.
module fm_status_lcd (
    input  wire clk, input wire reset_n, input wire sample_tick,
    input  wire signed [15:0] audio_sample,
    input  wire [4:0] active_voice_count, input wire [6:0] preset_index,
    input  wire [4:0] algorithm, input wire [47:0] algorithm_flags,
    input  wire [47:0] operator_envelope_levels,
    input  wire [7:0] peak_level, input wire clip_active,
    output wire lcd_resetn, output wire lcd_clk, output wire lcd_cs,
    output wire lcd_dc, output wire lcd_data
);
    localparam ST_RESET=3'd0, ST_POST_RESET=3'd1, ST_WAKE=3'd2,
               ST_WAKE_WAIT=3'd3, ST_INIT=3'd4, ST_PREFETCH=3'd5,
               ST_PIXEL_HI=3'd6, ST_PIXEL_LO=3'd7;

    reg [11:0] init_memory [0:87];
    reg [7:0] preset_name_memory [0:1279];
    initial begin
        $readmemh("src/generated/st7735_160x80_init.mem", init_memory);
        $readmemh("src/generated/fm_rom1a_names.mem", preset_name_memory);
    end
    reg [10:0] name_address;
    reg [7:0] name_character;
    always @(posedge clk) name_character <= preset_name_memory[name_address];

    // Four by six uppercase font. Each hex nibble is one row, top to bottom.
    function [23:0] glyph_bitmap;
        input [7:0] character;
        begin
            case (character)
                "A":glyph_bitmap=24'h699F99; "B":glyph_bitmap=24'hE9E99E;
                "C":glyph_bitmap=24'h788887; "D":glyph_bitmap=24'hE9999E;
                "E":glyph_bitmap=24'hF88E8F; "F":glyph_bitmap=24'hF88E88;
                "G":glyph_bitmap=24'h78B997; "H":glyph_bitmap=24'h999F99;
                "I":glyph_bitmap=24'hF2222F; "J":glyph_bitmap=24'h111196;
                "K":glyph_bitmap=24'h9ACCA9; "L":glyph_bitmap=24'h88888F;
                "M":glyph_bitmap=24'h9FF999; "N":glyph_bitmap=24'h9DB999;
                "O":glyph_bitmap=24'h699996; "P":glyph_bitmap=24'hE99E88;
                "Q":glyph_bitmap=24'h6999B7; "R":glyph_bitmap=24'hE99EA9;
                "S":glyph_bitmap=24'hF8861E; "T":glyph_bitmap=24'hF22222;
                "U":glyph_bitmap=24'h999996; "V":glyph_bitmap=24'h999966;
                "W":glyph_bitmap=24'h999FF9; "X":glyph_bitmap=24'h996699;
                "Y":glyph_bitmap=24'h996222; "Z":glyph_bitmap=24'hF1248F;
                "0":glyph_bitmap=24'h699DB6; "1":glyph_bitmap=24'h262227;
                "2":glyph_bitmap=24'h691248; "3":glyph_bitmap=24'hE1161E;
                "4":glyph_bitmap=24'h99F111; "5":glyph_bitmap=24'hF8E11E;
                "6":glyph_bitmap=24'h68E996; "7":glyph_bitmap=24'hF12444;
                "8":glyph_bitmap=24'h699699; "9":glyph_bitmap=24'h699711;
                ".":glyph_bitmap=24'h000006; "-":glyph_bitmap=24'h000F00;
                default:glyph_bitmap=24'h000000;
            endcase
        end
    endfunction

    reg [2:0] state;
    reg [31:0] delay_counter;
    reg [6:0] init_index;
    reg [7:0] pixel_x;
    reg [6:0] pixel_y;
    reg [15:0] pixel_color;
    reg spi_busy, spi_clock, spi_cs, spi_dc, spi_done, tx_start;
    reg [7:0] spi_shift, tx_data;
    reg [2:0] spi_bit;
    reg tx_dc, lcd_reset_reg;
    assign lcd_resetn=lcd_reset_reg; assign lcd_clk=spi_clock;
    assign lcd_cs=spi_cs; assign lcd_dc=spi_dc; assign lcd_data=spi_shift[7];

    wire [23:0] current_glyph=glyph_bitmap(name_character);
    wire [4:0] name_bit_index=((pixel_y-1'b1)<<2)+(3-pixel_x[1:0]);
    wire name_pixel=(pixel_y>=1 && pixel_y<=6 && pixel_x<40)
        ? current_glyph[name_bit_index] : 1'b0;
    wire [15:0] peak_width_sum={peak_level,7'd0}+{peak_level,5'd0}-
                               {peak_level,2'd0};
    wire [7:0] peak_width=peak_width_sum[15:8];
    wire peak_background=(pixel_y>=71 && pixel_y<=77 &&
                          pixel_x>=2 && pixel_x<=157);
    wire peak_fill=peak_background && ((pixel_x-2)<peak_width);
    wire clip_pixel=clip_active && pixel_x>=151 && pixel_y<=7;

    // Bus-oriented algorithm diagram. It is derived directly from the same
    // six routing flag bytes consumed by the synthesizer, so every preset is
    // represented without a bank of pre-rendered bitmaps.
    reg algorithm_pixel, feedback_pixel, carrier_pixel;
    reg [7:0] graph_flags;
    integer graph_operator, graph_x;
    always @* begin
        algorithm_pixel=0; feedback_pixel=0; carrier_pixel=0; graph_flags=0;
        if (pixel_x<80 && (pixel_y==17 || pixel_y==47)) algorithm_pixel=1;
        if (pixel_x<80 && pixel_y==61) carrier_pixel=1;
        for (graph_operator=0;graph_operator<6;graph_operator=graph_operator+1) begin
            graph_x=3+graph_operator*12;
            graph_flags=algorithm_flags[graph_operator*8 +: 8];
            if (pixel_x>=graph_x && pixel_x<graph_x+8 && pixel_y>=28 &&
                pixel_y<=37 && (pixel_y==28 || pixel_y==37 ||
                pixel_x==graph_x || pixel_x==graph_x+7)) algorithm_pixel=1;
            if (graph_flags[4] && pixel_x==graph_x+2 && pixel_y>=17 && pixel_y<=28) algorithm_pixel=1;
            if (graph_flags[0] && pixel_x==graph_x+5 && pixel_y>=17 && pixel_y<=28) algorithm_pixel=1;
            if (graph_flags[5] && pixel_x==graph_x+2 && pixel_y>=37 && pixel_y<=47) algorithm_pixel=1;
            if (graph_flags[1] && pixel_x==graph_x+5 && pixel_y>=37 && pixel_y<=47) algorithm_pixel=1;
            if (graph_flags[1:0]==0 && pixel_x==graph_x+4 && pixel_y>=37 && pixel_y<=61) carrier_pixel=1;
            if ((graph_flags[7] || graph_flags[6]) && pixel_x>=graph_x+1 &&
                pixel_x<=graph_x+6 && (pixel_y==25 || pixel_y==40)) feedback_pixel=1;
        end
    end

    reg [7:0] selected_envelope;
    reg envelope_column, envelope_fill;
    reg [6:0] envelope_base_x, envelope_height;
    integer envelope_operator;
    always @* begin
        selected_envelope=0; envelope_column=0; envelope_fill=0;
        envelope_base_x=0; envelope_height=0;
        for (envelope_operator=0;envelope_operator<6;envelope_operator=envelope_operator+1) begin
            envelope_base_x=88+envelope_operator*11;
            if (pixel_x>=envelope_base_x && pixel_x<envelope_base_x+7) begin
                selected_envelope=operator_envelope_levels[envelope_operator*8 +: 8];
                envelope_height=(selected_envelope>>2)-(selected_envelope>>4);
                if (pixel_y>=15 && pixel_y<=62) begin
                    envelope_column=(pixel_x==envelope_base_x ||
                        pixel_x==envelope_base_x+6 || pixel_y==62);
                    envelope_fill=(pixel_x>envelope_base_x &&
                        pixel_x<envelope_base_x+6 && pixel_y>=62-envelope_height);
                end
            end
        end
    end

    wire voice_meter=(pixel_y>=9 && pixel_y<=11 &&
                      pixel_x<active_voice_count*5);
    wire algorithm_number=(pixel_y>=2 && pixel_y<=6 && pixel_x>=48 &&
                           pixel_x<78 && algorithm[(pixel_x-48)/6]);
    always @* begin
        if (clip_pixel) pixel_color=16'hf800;
        else if (name_pixel) pixel_color=16'hffff;
        else if (algorithm_number) pixel_color=16'hffe0;
        else if (voice_meter) pixel_color=16'h07e0;
        else if (feedback_pixel) pixel_color=16'hf81f;
        else if (carrier_pixel) pixel_color=16'h07ff;
        else if (algorithm_pixel) pixel_color=16'h7bef;
        else if (envelope_fill) pixel_color=16'h05ff;
        else if (envelope_column) pixel_color=16'h3186;
        else if (peak_fill && pixel_x>=122) pixel_color=16'hf800;
        else if (peak_fill && pixel_x>=96) pixel_color=16'hffe0;
        else if (peak_fill) pixel_color=16'h07e0;
        else if (peak_background) pixel_color=16'h2104;
        else pixel_color=16'h0008;
    end

    // SPI mode 0, SCK=25 MHz.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            spi_busy<=0; spi_clock<=0; spi_cs<=1; spi_dc<=1;
            spi_shift<=8'hff; spi_bit<=0; spi_done<=0;
        end else begin
            spi_done<=0;
            if (!spi_busy) begin
                spi_clock<=0;
                if (tx_start) begin
                    spi_busy<=1; spi_cs<=0; spi_dc<=tx_dc;
                    spi_shift<=tx_data; spi_bit<=0;
                end
            end else if (!spi_clock) spi_clock<=1;
            else begin
                spi_clock<=0;
                if (spi_bit==7) begin spi_busy<=0; spi_cs<=1; spi_done<=1; end
                else begin spi_shift<={spi_shift[6:0],1'b0}; spi_bit<=spi_bit+1'b1; end
            end
        end
    end

    wire [7:0] next_pixel_x=(pixel_x==159)?0:pixel_x+1'b1;
    wire [6:0] next_pixel_y=(pixel_x==159)?((pixel_y==79)?0:pixel_y+1'b1):pixel_y;
    wire [10:0] next_name_address=preset_index*10+(next_pixel_x>>2);
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state<=ST_RESET; delay_counter<=0; init_index<=0; pixel_x<=0;
            pixel_y<=0; name_address<=0; lcd_reset_reg<=0; tx_start<=0;
            tx_data<=0; tx_dc<=1;
        end else begin
            tx_start<=0;
            case (state)
                ST_RESET: if (delay_counter==32'd4_999_999) begin
                    delay_counter<=0; lcd_reset_reg<=1; state<=ST_POST_RESET;
                end else delay_counter<=delay_counter+1'b1;
                ST_POST_RESET: if (delay_counter==32'd9_999_999) begin
                    delay_counter<=0; state<=ST_WAKE;
                end else delay_counter<=delay_counter+1'b1;
                ST_WAKE: if (!spi_busy && !tx_start) begin
                    tx_data<=8'h11; tx_dc<=0; tx_start<=1; state<=ST_WAKE_WAIT;
                end
                ST_WAKE_WAIT: begin
                    if (spi_done) delay_counter<=0;
                    else if (!spi_busy && !tx_start) begin
                        if (delay_counter==32'd5_999_999) begin
                            delay_counter<=0; init_index<=1; state<=ST_INIT;
                        end else delay_counter<=delay_counter+1'b1;
                    end
                end
                ST_INIT: if (!spi_busy && !tx_start) begin
                    tx_data<=init_memory[init_index][7:0];
                    tx_dc<=init_memory[init_index][8]; tx_start<=1;
                    if (init_index==87) begin
                        pixel_x<=0; pixel_y<=0; name_address<=preset_index*10;
                        state<=ST_PREFETCH;
                    end else init_index<=init_index+1'b1;
                end
                ST_PREFETCH: if (!spi_busy && !tx_start) state<=ST_PIXEL_HI;
                ST_PIXEL_HI: if (!spi_busy && !tx_start) begin
                    tx_data<=pixel_color[15:8]; tx_dc<=1; tx_start<=1;
                    state<=ST_PIXEL_LO;
                end
                ST_PIXEL_LO: if (!spi_busy && !tx_start) begin
                    tx_data<=pixel_color[7:0]; tx_dc<=1; tx_start<=1;
                    pixel_x<=next_pixel_x; pixel_y<=next_pixel_y;
                    name_address<=next_name_address; state<=ST_PREFETCH;
                end
                default: state<=ST_RESET;
            endcase
        end
    end
    wire unused_status_inputs=sample_tick^audio_sample[0];
endmodule
