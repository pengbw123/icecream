// Two independent dual-clock RAM banks. The producer holds a complete bank
// until the consumer switches at vertical blank and acknowledges ownership.
// When congested, discard a whole incoming frame, never overwrite the display.
module camera_framebuffer #(parameter integer PIXELS=19200)(
    input wire pclk,pixel_clk,reset_n,
    input wire frame_start,frame_good,pixel_write,
    input wire [14:0] pixel_address,input wire [7:0] pixel_data,
    input wire frame_latch,input wire [14:0] read_address,
    output wire [7:0] read_data,output reg valid,present_pulse,
    output reg drop_toggle
);
    reg [7:0] bank0[0:PIXELS-1] /* synthesis syn_ramstyle="block_ram" */;
    reg [7:0] bank1[0:PIXELS-1] /* synthesis syn_ramstyle="block_ram" */;
    reg [2:0] cam_reset_sync,video_reset_sync;
    always @(posedge pclk or negedge reset_n)
        if(!reset_n)cam_reset_sync<=0;else cam_reset_sync<={cam_reset_sync[1:0],1'b1};
    always @(posedge pixel_clk or negedge reset_n)
        if(!reset_n)video_reset_sync<=0;else video_reset_sync<={video_reset_sync[1:0],1'b1};
    wire cam_reset_n=cam_reset_sync[2],video_reset_n=video_reset_sync[2];
    reg request_toggle,ack_toggle,write_bank,read_bank;
    reg [1:0] ack_sync,request_sync;
    reg started,capturing;
    wire free_bank=request_toggle==ack_sync[1];
    wire first_pixel=!started&&pixel_address==0;
    wire write_allowed=cam_reset_n&&pixel_write&&pixel_address<PIXELS&&
        (capturing||(first_pixel&&free_bank));
    always @(posedge pclk)begin
        if(write_allowed&&!write_bank)bank0[pixel_address]<=pixel_data;
        if(write_allowed&&write_bank)bank1[pixel_address]<=pixel_data;
    end
    always @(posedge pclk or negedge cam_reset_n)begin
        if(!cam_reset_n)begin
            request_toggle<=0;write_bank<=1;ack_sync<=0;started<=0;capturing<=0;drop_toggle<=0;
        end else begin
            ack_sync<={ack_sync[0],ack_toggle};
            if(pixel_write&&!started)begin started<=1;capturing<=first_pixel&&free_bank;end
            if(frame_start)begin started<=0;capturing<=0;end
            if(frame_good)begin
                if(capturing)begin request_toggle<=!request_toggle;write_bank<=!write_bank;end
                else drop_toggle<=!drop_toggle;
            end
        end
    end
    reg [7:0] q0,q1;
    always @(posedge pixel_clk)begin q0<=bank0[read_address];q1<=bank1[read_address];end
    assign read_data=read_bank?q1:q0;
    always @(posedge pixel_clk or negedge video_reset_n)begin
        if(!video_reset_n)begin request_sync<=0;ack_toggle<=0;read_bank<=0;valid<=0;present_pulse<=0;end
        else begin
            request_sync<={request_sync[0],request_toggle};present_pulse<=0;
            if(frame_latch&&request_sync[1]!=ack_toggle)begin
                read_bank<=request_sync[1];ack_toggle<=request_sync[1];valid<=1;present_pulse<=1;
            end
        end
    end
endmodule
