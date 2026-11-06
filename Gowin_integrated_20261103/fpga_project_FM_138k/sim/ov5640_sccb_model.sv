`timescale 1ns/1ps
// Pin-level sensor register model; no hierarchical drive of the controller.
module ov5640_sccb_model(input wire scl,input wire sensor_reset_n,present,
    input wire wrong_id,corrupt_readback,nack_first,stretch_first,
    inout wire sda,output reg stretch_low=0);
    reg drive_low=0;assign sda=drive_low?1'b0:1'bz;
    reg [7:0] registers[0:65535];reg [7:0] rx,tx;
    reg [15:0] register_address;
    integer mode=0,bits=0,byte_index=0,tx_bits=0;
    integer writes=0,reads=0,starts=0;
    reg read_after_ack=0,injected=0,stretched=0;
    always @(negedge sensor_reset_n)begin mode=0;drive_low=0;stretch_low=0;end
    always @(negedge sda)if(scl===1'b1&&sensor_reset_n)begin
        mode=1;bits=0;byte_index=0;rx=0;read_after_ack=0;starts=starts+1;
    end
    always @(posedge sda)if(scl===1'b1)mode=0;
    always @(posedge scl)begin
        if(mode==1)begin rx={rx[6:0],sda};bits=bits+1;if(bits==8)mode=2;end
        else if(mode==3)mode=6;
        else if(mode==4)begin tx_bits=tx_bits+1;if(tx_bits==8)mode=5;end
        else if(mode==7)begin if(sda!==1'b1)$fatal(1,"Read did not terminate with master NACK");mode=8;end
    end
    always @(negedge scl)begin
        case(mode)
            2:begin
                drive_low=present;
                if(nack_first&&!injected&&byte_index==0)begin injected=1;drive_low=0;end
                if(byte_index==0)begin
                    if(rx==8'h79)begin
                        read_after_ack=1;reads=reads+1;
                        tx=register_address==16'h300a ? (wrong_id ? 8'hff:8'h56):
                           register_address==16'h300b ? 8'h40:
                           corrupt_readback&&register_address==16'h3809 ? 8'hff:registers[register_address];
                    end else if(rx!==8'h78)$fatal(1,"Wrong SCCB address %h",rx);
                end else if(byte_index==1)register_address[15:8]=rx;
                else if(byte_index==2)register_address[7:0]=rx;
                else if(byte_index==3)begin registers[register_address]=rx;writes=writes+1;end
                byte_index=byte_index+1;mode=3;
                if(stretch_first&&!stretched&&present&&byte_index==2)begin
                    stretched=1;stretch_low=1;
                    fork begin #3000;stretch_low=0;end join_none
                end
            end
            6:begin
                drive_low=0;
                if(read_after_ack&&present)begin mode=4;tx_bits=0;drive_low=~tx[7];end
                else begin mode=1;bits=0;rx=0;end
            end
            4:drive_low=~tx[7-tx_bits];
            5:begin drive_low=0;mode=7;end
            8:begin drive_low=0;mode=0;end
        endcase
    end
endmodule
