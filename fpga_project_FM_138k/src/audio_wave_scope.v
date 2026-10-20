// Complete snapshot -> range selection -> connected vertical column spans.
module audio_wave_scope(
    input wire clk,reset_n,sample_tick,auto_gain,
    input wire signed [15:0] audio_sample,
    input wire pixel_clk,video_reset_n,frame_latch,
    input wire [8:0] pixel_address,
    output wire [7:0] y_min,y_max,output wire valid
);
    localparam CAPTURE=0,RANGE=1,READ_POINT=2,CONVERT=3,STORE=4,WAIT_ACK=5;
    reg [2:0] state;
    reg signed [15:0] samples[0:511];
    reg [15:0] spans[0:1023];
    reg [8:0] index;
    reg [8:0] read_index;
    reg [15:0] peak;
    reg [3:0] shift;
    reg auto_latched,write_bank,publish_toggle,video_ack;
    reg [1:0] ack_sync;
    wire [15:0] magnitude=audio_sample[15]?(~audio_sample+16'd1):audio_sample;
    reg signed [15:0] sample_read;
    always @(posedge clk)begin
        if(reset_n && state==CAPTURE && sample_tick)samples[index]<=audio_sample;
        sample_read<=samples[read_index];
    end
    function [3:0] fit_shift(input [15:0] p,input enable);
        integer n;begin fit_shift=0;
            if(enable)for(n=1;n<=8;n=n+1)if(p<=(16'd32768>>n))fit_shift=n;
        end
    endfunction
    // 1/8 headroom also applies with AUTO off, so full scale fits the plot.
    reg signed [31:0] scaled;
    reg [7:0] point_y,previous_y,span_lo,span_hi;
    always @*begin
        scaled=$signed(sample_read);scaled=scaled<<<shift;
        scaled=scaled-(scaled>>>3);point_y=128-(scaled>>>8);
    end
    always @(posedge clk)if(reset_n && state==STORE)
        spans[{write_bank,index}]<={span_lo,span_hi};
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=CAPTURE;index<=0;read_index<=0;peak<=0;shift<=0;auto_latched<=0;
            write_bank<=0;publish_toggle<=0;ack_sync<=0;
            previous_y<=128;span_lo<=128;span_hi<=128;
        end else begin
            ack_sync<={ack_sync[0],video_ack};
            case(state)
                CAPTURE:if(sample_tick)begin
                    if(index==0)begin peak<=magnitude;auto_latched<=auto_gain;end
                    else if(magnitude>peak)peak<=magnitude;
                    if(index==511)begin state<=RANGE;index<=0;end
                    else index<=index+1'b1;
                end
                RANGE:begin shift<=fit_shift(peak,auto_latched);read_index<=0;state<=READ_POINT;end
                READ_POINT:state<=CONVERT;
                CONVERT:begin
                    span_lo<=(index==0 || point_y<previous_y)?point_y:previous_y;
                    span_hi<=(index==0 || point_y>previous_y)?point_y:previous_y;
                    previous_y<=point_y;state<=STORE;
                end
                STORE:if(index==511)begin publish_toggle<=~publish_toggle;state<=WAIT_ACK;end
                    else begin index<=index+1'b1;read_index<=index+1'b1;state<=READ_POINT;end
                WAIT_ACK:if(ack_sync[1]==publish_toggle)begin
                    write_bank<=~write_bank;index<=0;peak<=0;state<=CAPTURE;
                end
                default:state<=CAPTURE;
            endcase
        end
    end
    reg [1:0] publish_sync,bank_sync;
    reg display_bank,display_valid;
    reg [15:0] span_read;
    always @(posedge pixel_clk)span_read<=spans[{display_bank,pixel_address}];
    assign y_min=span_read[15:8];assign y_max=span_read[7:0];assign valid=display_valid;
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
