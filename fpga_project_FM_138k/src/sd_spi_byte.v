// Mode 0 byte shifter, 50 MHz system clock. Slow=200 kHz, fast=5 MHz.
// MMIO: word 0 CS#[0], fast[1], abort[2]; word 1 busy[0], RX[15:8];
// word 2 starts a byte when idle. CS is firmware controlled across bytes.
module sd_spi_byte(
    input wire clk,reset_n,select,write_en,
    input wire [1:0] address,input wire [31:0] write_data,
    output wire [31:0] read_data,
    output reg cs_n,sck,mosi,input wire miso
);
    reg fast,busy,mi_meta,mi_sync;
    reg [6:0] divider;
    reg [3:0] edges;
    reg [7:0] tx,rx,result;
    assign read_data=address==0?{30'd0,fast,cs_n}:{16'd0,result,7'd0,busy};
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            cs_n<=1;sck<=0;mosi<=1;fast<=0;busy<=0;
            mi_meta<=1;mi_sync<=1;divider<=0;edges<=0;tx<=0;rx<=0;result<=255;
        end else begin
            mi_meta<=miso;mi_sync<=mi_meta;
            if(busy)begin
                if(divider!=0)divider<=divider-1'b1;
                else begin
                    divider<=fast?7'd4:7'd124;
                    sck<=!sck;edges<=edges+1'b1;
                    if(!sck)rx<={rx[6:0],mi_sync};
                    else begin
                        tx<={tx[6:0],1'b1};mosi<=edges==15?1'b1:tx[6];
                        if(edges==15)begin busy<=0;result<=rx;end
                    end
                end
            end
            if(select&&write_en)begin
                if(address==0&&(!busy||write_data[2]))begin
                    cs_n<=write_data[0];fast<=write_data[1];
                    if(write_data[2])begin busy<=0;sck<=0;mosi<=1;end
                end else if(address==2&&!busy)begin
                    busy<=1;sck<=0;tx<=write_data[7:0];mosi<=write_data[7];rx<=0;
                    edges<=0;divider<=fast?7'd4:7'd124;
                end
            end
        end
    end
endmodule
