// 2bpp bitmap canvas for the ALGORITHM routing diagram.
//
// The firmware draws 512x256 pixels into a 32 KiB buffer (4 pixels per byte,
// colour classes 0=transparent, 1=line/border, 2=box fill, 3=highlight) and
// uploads it through UI[20]/UI[21]; UI[22] enables the layer.  The video side
// only does a byte lookup per four pixels, so the diagram costs BSRAM but very
// little logic and no per-pixel line math.
module ui_algo_map #(
    parameter integer PANEL_X=144,
    parameter integer PANEL_Y=160
) (
    input  wire        pclk,
    input  wire        video_reset_n,
    input  wire [10:0] h,
    input  wire [9:0]  v,
    input  wire        enable,
    input  wire        wclk,
    input  wire        we,
    input  wire [14:0] waddr,
    input  wire [7:0]  wdata,
    output wire        ink,
    output wire [1:0]  cls
);
    localparam [9:0] X0 = PANEL_X;
    localparam [8:0] Y0 = PANEL_Y;
    localparam integer MAP_W = 512;
    localparam integer MAP_H = 256;

    reg [7:0] map_mem [0:32767] /* synthesis syn_ramstyle = "block_ram" */;

    always @(posedge wclk) begin
        if (we) map_mem[waddr] <= wdata;
    end

    wire in_x = (h >= {1'b0, X0}) && (h < (X0 + MAP_W));
    wire in_y = (v >= {1'b0, Y0}) && (v < (Y0 + MAP_H));
    wire [9:0] hx = h[9:0] - X0;
    wire [8:0] vy = v[8:0] - Y0;
    wire [16:0] pix = ({8'd0, vy} << 9) | {7'd0, hx};
    wire [14:0] raddr = pix[16:2];

    // Two pixel-clock stages so the bitmap lines up with the character layer
    // (which also presents its result at hcount-2).
    reg [14:0] raddr1;
    reg [9:0]  hx1, hx2;
    reg [8:0]  vy1, vy2;
    reg        in1, in2;
    reg [7:0]  byte2;

    always @(posedge pclk) begin
        byte2 <= map_mem[raddr1];
    end

    always @(posedge pclk) begin
        if (!video_reset_n) begin
            raddr1 <= 15'd0; hx1 <= 10'd0; hx2 <= 10'd0;
            vy1 <= 9'd0; vy2 <= 9'd0; in1 <= 1'b0; in2 <= 1'b0;
        end else begin
            raddr1 <= raddr;
            hx1 <= hx; vy1 <= vy;
            in1 <= enable && in_x && in_y;
            hx2 <= hx1; vy2 <= vy1; in2 <= in1;
        end
    end

    wire [1:0] pix_sel = hx2[1:0];
    wire [1:0] pix_val = byte2[pix_sel*2 + 1 -: 2];
    assign cls = !in2 ? 2'd0 : pix_val;
    assign ink = (cls != 2'd0);
endmodule
