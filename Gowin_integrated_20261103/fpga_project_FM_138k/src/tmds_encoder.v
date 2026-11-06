// DVI/HDMI video-only TMDS encoding, one 10-bit symbol per pixel.
module tmds_encoder (
    input wire clk, input wire reset_n,
    input wire [7:0] data,
    input wire de, input wire c0, input wire c1,
    output reg [9:0] symbol
);
    reg [8:0] qm;
    reg signed [5:0] disparity;
    reg signed [5:0] balance;
    integer ones, qm_ones, i;
    always @* begin
        ones = 0;
        for (i=0; i<8; i=i+1) ones = ones + data[i];
        qm[8] = !((ones > 4) || ((ones == 4) && !data[0]));
        qm[0] = data[0];
        for (i=1; i<8; i=i+1)
            qm[i] = qm[8] ? (qm[i-1] ^ data[i]) : ~(qm[i-1] ^ data[i]);
        qm_ones = 0;
        for (i=0; i<8; i=i+1) qm_ones = qm_ones + qm[i];
        balance = qm_ones * 2 - 8;
    end
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            symbol <= 10'b1101010100;
            disparity <= 0;
        end else if (!de) begin
            disparity <= 0;
            case ({c1,c0})
                2'b00: symbol <= 10'b1101010100;
                2'b01: symbol <= 10'b0010101011;
                2'b10: symbol <= 10'b0101010100;
                2'b11: symbol <= 10'b1010101011;
            endcase
        end else if (disparity == 0 || balance == 0) begin
            symbol <= {~qm[8],qm[8],(qm[8] ? qm[7:0] : ~qm[7:0])};
            disparity <= disparity + (qm[8] ? balance : -balance);
        end else if ((disparity > 0 && balance > 0) ||
                     (disparity < 0 && balance < 0)) begin
            symbol <= {1'b1,qm[8],~qm[7:0]};
            disparity <= disparity - balance + (qm[8] ? 6'sd2 : 6'sd0);
        end else begin
            symbol <= {1'b0,qm[8],qm[7:0]};
            disparity <= disparity + balance - (qm[8] ? 6'sd0 : 6'sd2);
        end
    end
endmodule

module tmds_lane (
    input wire pixel_clk, input wire serial_clk, input wire reset_n,
    input wire [9:0] symbol,
    output wire out_p, output wire out_n
);
    // Match the ACG720 ch29 reference: two complementary LVCMOS33 ODDRs.
    // OSER10 consumes the adjacent I/O resource and cannot drive both pins
    // independently on these pairs. A five-cycle shifter avoids that conflict.
    reg [2:0] phase;
    reg [9:0] shift;
    always @(posedge serial_clk or negedge reset_n) begin
        if (!reset_n) begin phase<=0;shift<=0;end
        else if (phase==4) begin phase<=0;shift<=symbol;end
        else begin phase<=phase+1'b1;shift<={2'b0,shift[9:2]};end
    end
    ODDR u_pos (.Q0(out_p),.Q1(),.D0(shift[0]),.D1(shift[1]),.TX(1'b0),.CLK(serial_clk));
    ODDR u_neg (.Q0(out_n),.Q1(),.D0(~shift[0]),.D1(~shift[1]),.TX(1'b0),.CLK(serial_clk));
endmodule
