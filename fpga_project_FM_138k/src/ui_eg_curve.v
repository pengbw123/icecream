// Smooth envelope preview panel for the menu (EG page).
//
// The firmware pre-computes 192 height samples (9-bit, 0 = bottom, 255 = top)
// and writes them through the UI register pair 18/19.  The video side reads
// one sample per pixel column and classifies each pixel as fill / edge / grid,
// so the panel costs one small BSRAM and a few comparators instead of a full
// framebuffer.  Output timing matches rtl_char_display (two pixel-clock stages,
// aligned with the background pipeline).
module ui_eg_curve (
    input  wire        pclk,
    input  wire        video_reset_n,
    input  wire [10:0] h,
    input  wire [9:0]  v,
    input  wire        enable,
    // 50 MHz write port (firmware): one address/data pair per sample.
    input  wire        wclk,
    input  wire        we,
    input  wire [7:0]  waddr,
    input  wire [8:0]  wdata,
    output wire        ink,
    output wire [1:0]  cls
);
    localparam integer X0 = 576;   // panel left edge on screen
    localparam integer Y0 = 96;    // panel top edge
    localparam integer W  = 192;   // one sample per pixel column
    localparam integer H  = 256;   // one sample step per pixel row

    reg [8:0] level_mem [0:191] /* synthesis syn_ramstyle = "block_ram" */;

    // Independent write port: the softcore writes these through UI[18]/UI[19].
    always @(posedge wclk) begin
        if (we && waddr < W) level_mem[waddr] <= wdata;
    end

    wire in_range = (h >= X0[10:0]) && (h < (X0 + W));
    wire in_v     = (v >= Y0[9:0]) && (v < (Y0 + H));
    wire [7:0]  hx = h[7:0] - X0[7:0];
    wire [9:0]  vy = v - Y0[9:0];

    reg [7:0]  raddr;
    reg [7:0]  hx_q;
    reg [9:0]  vy_q, vy_q2;
    reg        in_q, in_q2;

    // Keep the memory output register in a reset-free block so Gowin infers
    // block memory (same rule as rtl_char_display).
    reg [8:0] level_q;
    always @(posedge pclk) begin
        level_q <= level_mem[raddr];
    end

    always @(posedge pclk) begin
        if (!video_reset_n) begin
            raddr <= 8'd0; hx_q <= 8'd0; vy_q <= 10'd0; vy_q2 <= 10'd0;
            in_q <= 1'b0; in_q2 <= 1'b0;
        end else begin
            raddr <= in_range ? hx : 8'd0;
            hx_q  <= raddr;
            vy_q  <= vy;
            vy_q2 <= vy_q;
            in_q  <= enable && in_range && in_v;
            in_q2 <= in_q;
        end
    end

    // level 0 = bottom row, 255 = top row.
    wire [9:0] top_y = 10'd255 - {1'b0, level_q};
    wire is_filled = (vy_q2 >= top_y);
    wire is_edge = (vy_q2 + 10'd1 >= top_y) && (vy_q2 <= top_y + 10'd1);
    wire is_grid = (hx_q[5:0] == 6'd0) || (hx_q == 8'd0) || (hx_q == W[7:0] - 8'd1) ||
                  (vy_q2[6:0] == 7'd0) || (vy_q2 == 10'd0) || (vy_q2 == H[9:0] - 10'd1);

    assign cls = !in_q2 ? 2'd0 : is_edge ? 2'd2 : is_filled ? 2'd1 : is_grid ? 2'd3 : 2'd0;
    assign ink = (cls != 2'd0);
endmodule


