// 128 decoded score entries: {start in 16ms units[15:0], gate[8:0], note[6:0]}.
// Factory and upload banks are separate, so reset always restores a valid ROM.
// Uploaded entries are written only while the transport is disabled; commit
// changes bank/count/end atomically. All display copies receive the same write.
module lesson_score_memory(
    input wire wclk,write,input wire [6:0] write_address,input wire [31:0] write_data,
    input wire rclk,bank,input wire [6:0] address,output reg [31:0] data
);
    reg [31:0] factory[0:127];
    reg [31:0] uploaded[0:127];
    initial $readmemh("src/generated/lesson_score.mem",factory);
    always @(posedge wclk)if(write)uploaded[write_address]<=write_data;
    always @(posedge rclk)data<=bank?uploaded[address]:factory[address];
endmodule
