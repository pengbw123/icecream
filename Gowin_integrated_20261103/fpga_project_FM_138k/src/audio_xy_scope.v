// Capture X=s[n], Y=s[n-delay], then fit and rasterize a complete snapshot.
// Pixel banks transfer ownership only in VBlank. No CPU drawing.
module audio_xy_scope (
    input wire clk,reset_n,sample_tick,
    input wire signed [15:0] audio_sample,
    input wire [6:0] delay_samples,
    input wire auto_gain,
    input wire pixel_clk,video_reset_n,frame_latch,
    input wire [14:0] pixel_address,
    output wire pixel_on
);
    reg pixels[0:65535];
    reg signed [15:0] history[0:127];
    reg [6:0] history_pointer,delay_latched;
    reg [7:0] history_count;
    wire [6:0] delay_safe=delay_latched==0?7'd1:delay_latched;
    wire [6:0] history_read_address=history_pointer-delay_safe;
    reg signed [15:0] delayed_sample;
    always @(posedge clk)delayed_sample<=history[history_read_address];
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin history_pointer<=0;history_count<=0;end
        else if(sample_tick)begin
            history[history_pointer]<=audio_sample;history_pointer<=history_pointer+1'b1;
            if(history_count<128)history_count<=history_count+1'b1;
        end
    end
    localparam CLEAR=0,CAPTURE=1,RANGE=2,READ_POINT=3,SET_POINT=4,DRAW=5,WAIT_ACK=6,ARM=7;
    reg [2:0] state;
    reg [14:0] clear_address;
    reg [8:0] index;
    reg [8:0] read_index;
    reg [31:0] pairs[0:511];
    reg [31:0] pair_read;
    reg [15:0] peak;
    reg [3:0] capture_gain;
    reg auto_latched,write_bank,publish_toggle,video_ack;
    reg [1:0] ack_sync;
    wire [15:0] abs_x=audio_sample[15]?(~audio_sample+16'd1):audio_sample;
    wire [15:0] abs_y=delayed_sample[15]?(~delayed_sample+16'd1):delayed_sample;
    wire [15:0] pair_peak=abs_x>abs_y?abs_x:abs_y;
    always @(posedge clk)begin
        if(reset_n && state==CAPTURE && sample_tick && history_count>=delay_safe)
            pairs[index]<={audio_sample,delayed_sample};
        pair_read<=pairs[read_index];
    end
    function [3:0] fit_shift(input [15:0] p,input enable);
        integer n;begin fit_shift=0;
            if(enable)for(n=1;n<=8;n=n+1)if(p<=(16'd32768>>n))fit_shift=n;
        end
    endfunction
    reg signed [31:0] sx,sy;
    reg [7:0] point_x;
    reg [6:0] point_y;
    always @*begin
        sx=$signed(pair_read[31:16]);sx=sx<<<capture_gain;sx=sx-(sx>>>3);
        sy=$signed(pair_read[15:0]);sy=sy<<<capture_gain;sy=sy-(sy>>>3);
        point_x=128+(sx>>>8);point_y=64-(sy>>>9);
    end
    reg [7:0] draw_x,target_x,dx;
    reg [6:0] draw_y,target_y,dy;
    reg step_x_positive,step_y_positive;
    reg signed [10:0] error;
    wire signed [11:0] twice_error=$signed(error)*2;
    wire move_x=twice_error>-$signed({1'b0,dy});
    wire move_y=twice_error<$signed({1'b0,dx});
    wire signed [10:0] next_error=error-(move_x?$signed({4'd0,dy}):11'sd0)
        +(move_y?$signed({3'd0,dx}):11'sd0);
    wire [7:0] point_dx=point_x>draw_x?point_x-draw_x:draw_x-point_x;
    wire [6:0] point_dy=point_y>draw_y?point_y-draw_y:draw_y-point_y;
    wire drawing=state==DRAW;
    always @(posedge clk)begin
        if(reset_n && state==CLEAR)pixels[{write_bank,clear_address}]<=0;
        else if(reset_n && drawing)pixels[{write_bank,draw_y,draw_x}]<=1;
    end
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=CLEAR;clear_address<=0;index<=0;read_index<=0;peak<=0;capture_gain<=0;auto_latched<=0;
            delay_latched<=24;write_bank<=0;publish_toggle<=0;ack_sync<=0;
            draw_x<=128;draw_y<=64;target_x<=128;target_y<=64;
            dx<=0;dy<=0;step_x_positive<=0;step_y_positive<=0;error<=0;
        end else begin
            ack_sync<={ack_sync[0],video_ack};
            case(state)
                CLEAR:if(clear_address==32767)begin
                    clear_address<=0;index<=0;peak<=0;state<=ARM;
                    delay_latched<=delay_samples==0?7'd1:delay_samples;auto_latched<=auto_gain;
                end else clear_address<=clear_address+1'b1;
                ARM:state<=CAPTURE; // settle the synchronous read after a delay change
                CAPTURE:if(sample_tick && history_count>=delay_safe)begin
                    if(pair_peak>peak)peak<=pair_peak;
                    if(index==511)begin index<=0;state<=RANGE;end
                    else index<=index+1'b1;
                end
                RANGE:begin capture_gain<=fit_shift(peak,auto_latched);read_index<=0;state<=READ_POINT;end
                READ_POINT:state<=SET_POINT;
                SET_POINT:begin
                    target_x<=point_x;target_y<=point_y;state<=DRAW;
                    step_x_positive<=point_x>draw_x;step_y_positive<=point_y>draw_y;
                    if(index==0)begin draw_x<=point_x;draw_y<=point_y;dx<=0;dy<=0;error<=0;end
                    else begin dx<=point_dx;dy<=point_dy;error<=$signed({3'd0,point_dx})-$signed({4'd0,point_dy});end
                end
                DRAW:if(draw_x==target_x && draw_y==target_y)begin
                    if(index==511)begin publish_toggle<=~publish_toggle;state<=WAIT_ACK;end
                    else begin index<=index+1'b1;read_index<=index+1'b1;state<=READ_POINT;end
                end else begin
                    error<=next_error;
                    if(move_x)draw_x<=step_x_positive?draw_x+1'b1:draw_x-1'b1;
                    if(move_y)draw_y<=step_y_positive?draw_y+1'b1:draw_y-1'b1;
                end
                WAIT_ACK:if(ack_sync[1]==publish_toggle)begin
                    write_bank<=~write_bank;clear_address<=0;state<=CLEAR;
                end
                default:state<=CLEAR;
            endcase
        end
    end
    reg [1:0] publish_sync,bank_sync;
    reg display_bank,display_valid,pixel_raw;
    always @(posedge pixel_clk)pixel_raw<=pixels[{display_bank,pixel_address}];
    assign pixel_on=display_valid?pixel_raw:1'b0;
    always @(posedge pixel_clk or negedge video_reset_n)begin
        if(!video_reset_n)begin
            publish_sync<=0;bank_sync<=0;display_bank<=1;display_valid<=0;video_ack<=0;
        end else begin
            publish_sync<={publish_sync[0],publish_toggle};bank_sync<={bank_sync[0],write_bank};
            if(frame_latch && publish_sync[1]!=video_ack)begin
                display_bank<=bank_sync[1];display_valid<=1;video_ack<=publish_sync[1];
            end
        end
    end
endmodule
