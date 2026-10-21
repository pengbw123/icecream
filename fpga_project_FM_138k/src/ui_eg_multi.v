// Six small operator-envelope panels for the EG page (3 columns x 2 rows).
// Firmware rasterises six 128-sample curves into a 768-byte RAM; the video
// side draws frame, grid, fill and top edge per panel.
module ui_eg_multi (
    input  wire        pclk,
    input  wire        video_reset_n,
    input  wire [10:0] h,
    input  wire [9:0]  v,
    input  wire        enable,
    input  wire        wclk,
    input  wire        we,
    input  wire [9:0]  waddr,
    input  wire [7:0]  wdata,
    output wire        ink,
    output wire [2:0]  cls
);
    reg [7:0] mem [0:1023];

    // pixel-clock read pipeline
    reg [10:0] h1; reg [9:0] v1;
    reg       en1;
    reg [9:0] raddr;
    reg [7:0] q1;
    reg [7:0] q2;
    reg [10:0] h2; reg [9:0] v2;
    reg       en2;

    wire [9:0] col = (h >= 10'd528) ? 10'd2 : (h >= 10'd272) ? 10'd1 : 10'd0;
    wire [9:0] row = (v >= 10'd288) ? 10'd1 : 10'd0;
    wire [9:0] x0 = 10'd16 + col * 10'd256;
    wire [9:0] y0 = 10'd176 + row * 10'd112;
    wire [9:0] dx = h - x0;
    wire [9:0] dy = v - y0;
    wire       in_panel = (h >= x0) && (h < x0 + 10'd240) &&
                        (v >= y0) && (v < y0 + 10'd104);
    wire [9:0] panel = row * 10'd3 + col;
    wire [15:0] dxw0 = {6'd0, dx};
    wire [15:0] lxw0 = (dxw0 * 16'd17) >> 5;
    wire [9:0] lx = lxw0[9:0];
    wire [9:0] lx_c = (lx > 10'd127) ? 10'd127 : lx;
    wire [9:0] addr = panel * 10'd128 + lx_c;

    always @(posedge pclk or negedge video_reset_n) begin
        if (!video_reset_n) begin
            h1 <= 0; v1 <= 0; en1 <= 0; raddr <= 0;
        end else begin
            h1 <= h; v1 <= v;
            en1 <= enable && in_panel;
            raddr <= addr;
        end
    end
    always @(posedge pclk or negedge video_reset_n) begin
        if (!video_reset_n) begin q1 <= 0; h2 <= 0; v2 <= 0; en2 <= 0; end
        else begin q1 <= mem[raddr]; h2 <= h1; v2 <= v1; en2 <= en1; end
    end
    always @(posedge pclk or negedge video_reset_n) begin
        if (!video_reset_n) q2 <= 0;
        else q2 <= q1;
    end

    // geometry for the registered pixel
    wire [9:0] col2 = (h2 >= 10'd528) ? 10'd2 : (h2 >= 10'd272) ? 10'd1 : 10'd0;
    wire [9:0] row2 = (v2 >= 10'd288) ? 10'd1 : 10'd0;
    wire [9:0] x02 = 10'd16 + col2 * 10'd256;
    wire [9:0] y02 = 10'd176 + row2 * 10'd112;
    wire [9:0] dx2 = h2 - x02;
    wire [9:0] dy2 = v2 - y02;
    wire [15:0] dxw = {6'd0, dx2};
    wire [15:0] lx2w = (dxw * 16'd17) >> 5;
    wire [9:0] lx2 = lx2w[9:0];
    wire [9:0] lx2_c = (lx2 > 10'd127) ? 10'd127 : lx2;
    wire [15:0] hspan = 16'd255 - {8'd0, q2};
    wire [15:0] topw = {6'd0, y02} + 16'd6 + ((hspan * 16'd11) >> 5);
    wire [9:0] top = topw[9:0];
    wire       frame = (dy2 == 0) || (dy2 == 1) || (dy2 == 10'd103) ||
                       (dx2 == 0) || (dx2 == 1) || (dx2 == 10'd238) || (dx2 == 10'd239);
    wire       curve = (v2 == top) || (v2 == top + 1);
    wire       fill  = (v2 > top + 1) && (v2 <= y02 + 10'd101);
    wire       gridv = (lx2_c[4:0] == 5'd0);
    wire [9:0] gy = dy2 - 10'd6;
    wire       gridh = (gy == 10'd0) || (gy == 10'd22) || (gy == 10'd44) ||
                       (gy == 10'd66) || (gy == 10'd88);

    assign cls = frame ? 3'd1 : curve ? 3'd2 : gridv || gridh ? 3'd4 : fill ? 3'd3 : 3'd0;
    assign ink = en2 && (cls != 3'd0);

    always @(posedge wclk) begin
        if (we) mem[waddr] <= wdata;
    end
endmodule
