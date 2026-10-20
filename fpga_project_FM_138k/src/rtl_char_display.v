// Character-cell text layer for the menu UI.
//
// One 16-bit cell per 8x16 pixel tile:  {attr[3:0], palette[3:0], char[7:0]}
//   attr[0] = inverse (cell filled with the palette colour, glyph drawn dark)
//   attr[1] = underline (bottom two rows)
//   attr[2] = blank    (fill the whole cell with the palette colour)
//   attr[3] = reserved
//
// Storage is a strict simple-dual-port RAM (write on clk / read on pclk, one
// always block per port, no reset and no initial contents) so Gowin infers
// BSRAM instead of flip-flops.  The old rtl_menu_text failed because it was a
// writable array WITH a $readmemh initial image on two clocks.
//
// Font: one shared 2048x8 pROM (index = char*16 + row).
// Palette: 16 entries of 24 bit, written by the softcore and resynchronised
// into the pixel clock with two flops per bit (theme changes are rare).
module rtl_char_display (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        text_write,
    input  wire [11:0] text_address,
    input  wire [15:0] text_data,
    input  wire        palette_write,
    input  wire [3:0]  palette_index,
    input  wire [23:0] palette_data,

    input  wire        pclk,
    input  wire        video_reset_n,
    input  wire [10:0] h,
    input  wire [9:0]  v,
    input  wire        enabled,
    output wire        ink,
    output wire [23:0] color
);
    // 128 columns x 32 rows of cells.
    reg [15:0] cells [0:4095];
    always @(posedge clk) begin
        if (text_write) cells[text_address] <= text_data;
    end

    reg [7:0] font [0:2047];
    initial $readmemh("src/generated/font8x16.mem", font);

    reg [23:0] palette [0:15];
    always @(posedge clk) begin
        if (!reset_n) begin
            palette[0]  <= 24'h080D18;
            palette[1]  <= 24'hF0F5FA;
            palette[2]  <= 24'h8A8578;
            palette[3]  <= 24'hFFB95A;
            palette[4]  <= 24'h5AE8D0;
            palette[5]  <= 24'h1B2B3F;
            palette[6]  <= 24'h284763;
            palette[7]  <= 24'h26786F;
            palette[8]  <= 24'h35DFC1;
            palette[9]  <= 24'hFF8050;
            palette[10] <= 24'h733946;
            palette[11] <= 24'h0A1624;
            palette[12] <= 24'h142439;
            palette[13] <= 24'h101E30;
            palette[14] <= 24'hCFD9E5;
            palette[15] <= 24'h000000;
        end else if (palette_write) begin
            palette[palette_index] <= palette_data;
        end
    end

    // ------------------------------------------------------------------
    // Pixel-clock side.  Keep the BSRAM/pROM read registers in their own
    // reset-free always blocks: a reset on a memory output register stops
    // Gowin from inferring block memory.  Only the small pipeline registers
    // are reset; valid_q2 gates the output so power-up garbage never shows.
    //
    // Two register stages then a combinational pixel pick, matching the
    // existing background pipeline: the overlay is aligned with
    // background_pipe (hcount - 2), exactly like the old text path.
    // ------------------------------------------------------------------
    wire [11:0] read_address = {v[8:4], h[9:3]};
    reg [15:0] cell_q;
    reg [7:0]  glyph_q;
    // Keep the palette resynchronisers as flip-flops.  Left as plain arrays,
    // Gowin packs them into DPB RAM with WRITE_MODE=2'b10 and PnR aborts with
    // PA2122 (the same trap that killed the first rtl_menu_text attempt).
    reg [23:0] palette_meta [0:15] /* synthesis syn_ramstyle = "registers" */;
    reg [23:0] palette_sync [0:15] /* synthesis syn_ramstyle = "registers" */;
    reg [3:0]  v_low_q, v_low_q2;
    reg [2:0]  col_q, col_q2;
    reg        valid_q, valid_q2;
    reg [15:0] cell_q2;
    integer p;

    always @(posedge pclk) begin
        cell_q <= cells[read_address];
    end
    always @(posedge pclk) begin
        for (p = 0; p < 16; p = p + 1) begin
            palette_meta[p] <= palette[p];
            palette_sync[p] <= palette_meta[p];
        end
    end
    always @(posedge pclk) begin
        if (!video_reset_n) begin
            v_low_q <= 4'd0; col_q <= 3'd0; valid_q <= 1'b0;
            v_low_q2 <= 4'd0; col_q2 <= 3'd0; valid_q2 <= 1'b0;
            cell_q2 <= 16'd0;
        end else begin
            v_low_q <= v[3:0];
            col_q   <= h[2:0];
            valid_q <= enabled;
            cell_q2  <= cell_q;
            v_low_q2 <= v_low_q;
            col_q2   <= col_q;
            valid_q2 <= valid_q;
        end
    end
    always @(posedge pclk) begin
        glyph_q <= font[{cell_q[6:0], v_low_q}];
    end

    wire [3:0]  attr = cell_q2[15:12];
    wire [3:0]  pal_index = cell_q2[11:8];
    wire        glyph_pixel = glyph_q[7 - col_q2];
    wire        underline = (v_low_q2 >= 4'd14);
    wire        inverse = attr[0];
    wire        blank = attr[2];
    wire [23:0] pal_color = palette_sync[pal_index];
    wire [23:0] dark_color = palette_sync[0];
    wire        glyph_ink = glyph_pixel | (attr[1] & underline);

    assign ink = valid_q2 & (blank | inverse | glyph_ink);
    assign color = blank ? pal_color : inverse ? (glyph_ink ? dark_color : pal_color)
                                               : pal_color;
endmodule
