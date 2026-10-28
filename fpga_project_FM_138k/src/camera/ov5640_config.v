// Ch45 TFT-verified 800x480 RGB565 table, ID/readback and bounded recovery.
// The dedicated 24.242 MHz XCLK runs throughout reset and configuration.
module ov5640_config #(parameter integer QUARTER_CLOCKS=31,
    parameter integer RESET_CLOCKS=50000,BOOT_CLOCKS=1000000,
    parameter integer SOFT_RESET_CLOCKS=250000,RETRY_CLOCKS=50000000,
    parameter integer WATCHDOG_CLOCKS=100000000,
    parameter integer STARTUP_WATCHDOG_CLOCKS=WATCHDOG_CLOCKS*5)(
    input wire clk,reset_n,frame_toggle,
    output reg camera_reset_n,inout wire scl,sda,
    output reg ready,output reg [2:0] fault,output reg [15:0] chip_id
);
    reg [23:0] table_mem[0:251] /* synthesis syn_ramstyle="block_ram" */;
    initial $readmemh("src/generated/ov5640_tft_800x480.mem",table_mem);
    reg [7:0] index;reg [23:0] entry;
    always @(posedge clk)entry<=table_mem[index];
    reg start,read_request;reg [15:0] address;reg [7:0] write_data;
    wire done,failed;wire [7:0] read_data;
    camera_sccb #(.QUARTER_CLOCKS(QUARTER_CLOCKS)) u_bus(
        .clk(clk),.reset_n(reset_n),.start(start),.read_request(read_request),
        .address(address),.write_data(write_data),.scl(scl),.sda(sda),
        .done(done),.failed(failed),.read_data(read_data));
    reg [3:0] state;reg [31:0] wait_count,watchdog;
    // Startup includes sensor settling and the capture receiver's warmup.
    // Do not repeatedly reset a slow first stream with the running timeout.
    reg stream_seen;
    reg [3:0] check_index;
    reg [1:0] frame_sync;reg frame_prev;
    always @(posedge clk or negedge reset_n)
        if(!reset_n)begin frame_sync<=0;frame_prev<=0;end
        else begin frame_sync<={frame_sync[0],frame_toggle};frame_prev<=frame_sync[1];end
    function [23:0] check_register(input [3:0] n);
        case(n)
            0:check_register=24'h380803;1:check_register=24'h380920;
            2:check_register=24'h380a01;3:check_register=24'h380be0;
            4:check_register=24'h430061;5:check_register=24'h501f01;
            6:check_register=24'h300802;7:check_register=24'h474020;
            8:check_register=24'h500183;9:check_register=24'h460c20;
            10:check_register=24'h382404;11:check_register=24'h303521;
            default:check_register=24'h303669;
        endcase
    endfunction
    wire [23:0] check_word=check_register(check_index);
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            camera_reset_n<=0;ready<=0;fault<=0;chip_id<=0;
            index<=0;start<=0;read_request<=0;address<=0;write_data<=0;
            state<=0;wait_count<=RESET_CLOCKS-1;check_index<=0;watchdog<=0;stream_seen<=0;
        end else begin
            start<=0;
            case(state)
                0:if(wait_count!=0)wait_count<=wait_count-1'b1;
                  else begin camera_reset_n<=1;wait_count<=BOOT_CLOCKS-1;state<=1;end
                1:if(wait_count!=0)wait_count<=wait_count-1'b1;
                  else begin address<=16'h300a;read_request<=1;start<=1;state<=2;end
                2:if(done)begin
                    if(failed)begin fault<=1;state<=14;end
                    else begin chip_id[15:8]<=read_data;address<=16'h300b;start<=1;state<=3;end
                end
                3:if(done)begin
                    chip_id[7:0]<=read_data;
                    if(failed)begin fault<=1;state<=14;end
                    else if(chip_id[15:8]!=8'h56||read_data!=8'h40)begin fault<=2;state<=14;end
                    else begin index<=0;state<=4;end
                end
                4:state<=5; // synchronous table ROM settles after index change
                5:begin address<=entry[23:8];write_data<=entry[7:0];read_request<=0;start<=1;state<=6;end
                6:if(done)begin
                    if(failed)begin fault<=1;state<=14;end
                    else if(index==251)begin check_index<=0;state<=8;end
                    else begin
                        index<=index+1'b1;
                        if(index==1)begin wait_count<=SOFT_RESET_CLOCKS-1;state<=7;end
                        else state<=4;
                    end
                end
                7:if(wait_count!=0)wait_count<=wait_count-1'b1;else state<=4;
                8:begin address<=check_word[23:8];read_request<=1;start<=1;state<=9;end
                9:if(done)begin
                    if(failed)begin fault<=1;state<=14;end
                    else if(check_index==6 ? ((read_data&8'hc0)!=0) : (read_data!=check_word[7:0]))begin fault<=3;state<=14;end
                    else if(check_index==12)begin ready<=1;fault<=0;watchdog<=0;stream_seen<=0;state<=10;end
                    else begin check_index<=check_index+1'b1;state<=8;end
                end
                10:if(frame_sync[1]!=frame_prev)begin watchdog<=0;stream_seen<=1;end
                   else if((stream_seen&&watchdog==WATCHDOG_CLOCKS-1)||
                           (!stream_seen&&watchdog==STARTUP_WATCHDOG_CLOCKS-1))begin fault<=4;ready<=0;state<=14;end
                   else watchdog<=watchdog+1'b1;
                14:begin camera_reset_n<=0;ready<=0;wait_count<=RETRY_CLOCKS-1;state<=15;end
                15:if(wait_count!=0)wait_count<=wait_count-1'b1;
                   else begin wait_count<=RESET_CLOCKS-1;state<=0;end
                default:state<=14;
            endcase
        end
    end
endmodule
