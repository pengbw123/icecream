`timescale 1ns/1ps
// Pixel-accurate checks for the character-cell text layer: glyph decode,
// inverse/blank/underline attributes, palette colours and pipeline alignment.
module tb_char_display;
    reg clk=0, pclk=0;
    always #10 clk=~clk;
    always #15 pclk=~pclk;
    reg reset_n=0, video_reset_n=0;
    reg text_write=0;
    reg [11:0] text_address=0;
    reg [15:0] text_data=0;
    reg palette_write=0;
    reg [3:0] palette_index=0;
    reg [23:0] palette_data=0;
    reg [10:0] h=0;
    reg [9:0] v=0;
    reg enabled=0;
    wire ink;
    wire [23:0] color;

    rtl_char_display dut (
        .clk(clk), .reset_n(reset_n),
        .text_write(text_write), .text_address(text_address), .text_data(text_data),
        .palette_write(palette_write), .palette_index(palette_index),
        .palette_data(palette_data),
        .pclk(pclk), .video_reset_n(video_reset_n), .h(h), .v(v),
        .enabled(enabled), .ink(ink), .color(color)
    );

    integer errors = 0;
    task check_ink(input expected, input [8*32-1:0] name);
        begin
            if (ink !== expected) begin
                $display("FAIL %0s: ink=%0b expected %0b", name, ink, expected);
                errors = errors + 1;
            end else
                $display("ok   %0s", name);
        end
    endtask
    task check_color(input [23:0] expected, input [8*32-1:0] name);
        begin
            if (color !== expected) begin
                $display("FAIL %0s: color=%06h expected %06h", name, color, expected);
                errors = errors + 1;
            end else
                $display("ok   %0s", name);
        end
    endtask

    // Sample one pixel.  The cell/glyph pipeline is two pclk stages deep, so
    // hold the coordinates for four edges before looking at the output.
    task sample(input [10:0] px, input [9:0] py);
        begin
            h = px;
            v = py;
            repeat (4) @(posedge pclk);
        end
    endtask

    task write_palette(input [3:0] index, input [23:0] value);
        begin
            @(posedge clk);
            palette_index = index;
            palette_data = value;
            palette_write = 1;
            @(posedge clk);
            palette_write = 0;
        end
    endtask

    task write_cell(input [11:0] address, input [15:0] value);
        begin
            @(posedge clk);
            text_address = address;
            text_data = value;
            text_write = 1;
            @(posedge clk);
            text_write = 0;
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        reset_n = 1;
        repeat (3) @(posedge clk);
        repeat (5) @(posedge pclk);
        video_reset_n = 1;
        repeat (5) @(posedge pclk);
        enabled = 1;

        write_palette(4'd0, 24'h000000);
        write_palette(4'd1, 24'h112233);
        write_palette(4'd2, 24'h445566);
        write_palette(4'd3, 24'h778899);
        write_palette(4'd4, 24'hAABBCC);
        repeat (6) @(posedge pclk);

        // Cell (col=2,row=3): normal 'A' with palette 1.
        // 'A' row 2 is 0x30 -> pixels x=2,3 inside the cell.
        write_cell(12'h182, {4'd0, 4'd1, 8'h41});
        // Cell (col=3,row=3): inverse 'A' with palette 2.
        write_cell(12'h183, {4'd1, 4'd2, 8'h41});
        // Cell (col=4,row=3): blank fill palette 3.
        write_cell(12'h184, {4'd4, 4'd3, 8'h20});
        // Cell (col=5,row=3): underline palette 4 (space glyph).
        write_cell(12'h185, {4'd2, 4'd4, 8'h20});
        // Cell (col=6,row=3): explicitly empty.
        write_cell(12'h186, 16'd0);
        repeat (3) @(posedge clk);

        // Normal glyph pixels: cell origin is (16, 48); 'A' row 2 is 0x18,
        // so the lit pixels inside the cell are x=3 and x=4.
        sample(11'd19, 10'd50); check_ink(1'b1, "normal glyph on"); check_color(24'h112233, "normal colour");
        sample(11'd16, 10'd50); check_ink(1'b0, "normal glyph off");
        sample(11'd19, 10'd48); check_ink(1'b0, "normal row0 off");

        // Inverse: glyph is dark, the rest of the cell is palette 2.
        sample(11'd27, 10'd50); check_ink(1'b1, "inverse glyph on"); check_color(24'h000000, "inverse glyph dark");
        sample(11'd24, 10'd50); check_ink(1'b1, "inverse cell filled"); check_color(24'h445566, "inverse fill colour");

        // Blank: every pixel is the palette colour.
        sample(11'd32, 10'd48); check_ink(1'b1, "blank fill"); check_color(24'h778899, "blank colour");

        // Underline: only the last two rows of the cell.
        sample(11'd40, 10'd62); check_ink(1'b1, "underline row14"); check_color(24'hAABBCC, "underline colour");
        sample(11'd40, 10'd48); check_ink(1'b0, "underline row0 off");

        // Empty cell draws nothing.
        sample(11'd48, 10'd48); check_ink(1'b0, "empty cell");

        // Layer disable.
        enabled = 0;
        sample(11'd18, 10'd50); check_ink(1'b0, "disabled layer");

        if (errors == 0) $display("PASS character layer glyph/attr/palette/alignment");
        else $display("FAIL %0d character-layer checks", errors);
        $finish;
    end
endmodule
