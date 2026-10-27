// Open-drain SCCB/I2C: OV5640 7-bit address 0x3c, 16-bit register address.
// A read uses a repeated START and terminates its single byte with NACK.
module camera_sccb #(parameter integer QUARTER_CLOCKS=125,
    parameter integer TIMEOUT_QUARTERS=4000)(
    input wire clk,reset_n,start,read_request,
    input wire [15:0] address,input wire [7:0] write_data,
    inout wire scl,sda,output reg done,failed,output reg [7:0] read_data
);
    reg scl_low,sda_low;
    assign scl=scl_low?1'b0:1'bz;
    assign sda=sda_low?1'b0:1'bz;
    reg [1:0] scl_sync,sda_sync;
    always @(posedge clk or negedge reset_n)
        if(!reset_n)begin scl_sync<=3;sda_sync<=3;end
        else begin scl_sync<={scl_sync[0],scl};sda_sync<={sda_sync[0],sda};end
    reg [15:0] divider,timeout_count;
    reg [3:0] state,bit_index;
    reg [1:0] phase,byte_index;
    reg reading;reg [31:0] payload;reg [7:0] received;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            scl_low<=0;sda_low<=0;done<=0;failed<=0;read_data<=0;
            divider<=0;timeout_count<=0;state<=0;bit_index<=0;
            phase<=0;byte_index<=0;reading<=0;payload<=0;received<=0;
        end else begin
            done<=0;
            if(state==0)begin
                divider<=0;
                if(start)begin
                    payload<={8'h78,address,write_data};reading<=read_request;
                    failed<=0;timeout_count<=0;state<=1;
                end
            end else if(divider==QUARTER_CLOCKS-1)begin
                divider<=0;
                if(timeout_count==TIMEOUT_QUARTERS-1)begin
                    scl_low<=0;sda_low<=0;failed<=1;done<=1;state<=0;
                end else begin
                    timeout_count<=timeout_count+1'b1;
                    case(state)
                        1:if(scl_sync[1]&&sda_sync[1])begin sda_low<=1;timeout_count<=0;state<=2;end
                        2:begin scl_low<=1;bit_index<=0;byte_index<=0;phase<=0;state<=3;end
                        3:case(phase)
                            0:begin scl_low<=1;sda_low<=bit_index<8?~payload[31]:1'b0;phase<=1;end
                            1:begin scl_low<=0;phase<=2;end
                            2:if(scl_sync[1])begin
                                timeout_count<=0;if(bit_index==8&&sda_sync[1])failed<=1;phase<=3;
                            end
                            3:begin
                                scl_low<=1;phase<=0;
                                if(bit_index==8)begin
                                    bit_index<=0;
                                    if(failed)state<=4;
                                    else if(reading&&byte_index==2)state<=10;
                                    else if(byte_index==3)begin
                                        if(reading)begin state<=8;received<=0;end else state<=4;
                                    end else byte_index<=byte_index+1'b1;
                                end else begin payload<={payload[30:0],1'b0};bit_index<=bit_index+1'b1;end
                            end
                        endcase
                        4:begin scl_low<=1;sda_low<=1;state<=5;end
                        5:begin scl_low<=0;state<=6;end
                        6:if(scl_sync[1])begin sda_low<=0;state<=7;end
                        7:begin done<=1;state<=0;end
                        8:case(phase)
                            0:begin scl_low<=1;sda_low<=0;phase<=1;end
                            1:begin scl_low<=0;phase<=2;end
                            2:if(scl_sync[1])begin
                                timeout_count<=0;if(bit_index<8)received<={received[6:0],sda_sync[1]};phase<=3;
                            end
                            3:begin
                                scl_low<=1;phase<=0;
                                if(bit_index==8)begin read_data<=received;state<=4;end
                                else bit_index<=bit_index+1'b1;
                            end
                        endcase
                        10:begin scl_low<=1;sda_low<=0;state<=11;end
                        11:begin scl_low<=0;state<=12;end
                        12:if(scl_sync[1])begin sda_low<=1;timeout_count<=0;state<=13;end
                        13:begin scl_low<=1;payload<=32'h79000000;byte_index<=3;bit_index<=0;phase<=0;state<=3;end
                        default:state<=0;
                    endcase
                end
            end else divider<=divider+1'b1;
        end
    end
endmodule
