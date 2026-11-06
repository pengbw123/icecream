// CPU writes character cells only; both font rasterization and timing are RTL.
// 80 columns x 21 rows, 8x16 cells in the left 640x336 editing panel.
module rtl_menu_text(
    input wire clk,text_write,input wire [10:0] text_address,input wire [15:0] text_data,
    input wire pclk,reset_n,input wire [10:0] h,input wire [9:0] v,input wire enabled,
    output wire ink,output wire [23:0] color
);
    reg [15:0] cells[0:2047];
    reg [7:0] font[0:2047];
    initial begin $readmemh("src/generated/menu_blank.mem",cells);
        $readmemh("src/generated/font8x16.mem",font);end
    always @(posedge clk)if(text_write)cells[text_address]<=text_data;
    wire [9:0] rel_y=v-10'd64;
    wire [10:0] cell_address={rel_y[8:4],6'd0}+{rel_y[8:4],4'd0}+h[9:3];
    reg [15:0] char_cell;reg [3:0] row;reg [2:0] col1,col2;
    reg valid1,valid2;reg [7:0] glyph_row;reg [3:0] palette;
    // Keep the registered read in its own process: Gowin otherwise expands
    // this dual-clock character store into thousands of RAMREG flip-flops.
    always @(posedge pclk)char_cell<=cells[cell_address];
    always @(posedge pclk)begin
        row<=rel_y[3:0];col1<=h[2:0];
        valid1<=reset_n&&enabled&&h<640&&v>=64&&v<400;
        glyph_row<=font[{char_cell[6:0],row}];col2<=col1;valid2<=valid1;palette<=char_cell[11:8];
    end
    assign ink=valid2&&glyph_row[7-col2];
    assign color=palette==1?24'hFFB95A:palette==2?24'h5AE8D0:palette==3?24'hF06A83:24'hDCE5F1;
endmodule
