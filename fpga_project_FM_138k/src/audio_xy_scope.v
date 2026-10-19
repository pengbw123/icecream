// Mono delay-coordinate (X=s[n], Y=s[n-delay]) oscilloscope, not stereo
// correlation and not an FFT. Capture and draw in the audio clock domain;
// video owns the published bank until it acknowledges a new one in VBlank.
module audio_xy_scope (
    input wire clk,reset_n,sample_tick,
    input wire signed [15:0] audio_sample,
    input wire [6:0] delay_samples,
    input wire pixel_clk,video_reset_n,frame_latch,
    input wire [14:0] pixel_address,
    output reg pixel_on
);
    reg pixels[0:65535]; // two banks of 256 x 128, 1 bit per pixel
    reg signed [15:0] history[0:127];
    reg [6:0] history_pointer;
    reg [7:0] history_count;
    wire [6:0] delay_safe=delay_samples==0?7'd1:delay_samples;
    wire [6:0] history_read_address=history_pointer-delay_safe;
    reg signed [15:0] delayed_sample;
    // Synchronous history read: index is stable for the 1024-clock sample gap.
    always @(posedge clk) delayed_sample<=history[history_read_address];
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n)begin history_pointer<=0;history_count<=0;end
        else if(sample_tick)begin
            history[history_pointer]<=audio_sample;
            history_pointer<=history_pointer+1'b1;
            if(history_count<128)history_count<=history_count+1'b1;
        end
    end
    localparam [1:0] CLEAR=0,CAPTURE=1,WAIT_ACK=2;
    reg [1:0] state;
    reg [14:0] clear_address;
    reg [8:0] captured;
    reg write_bank,publish_toggle;
    reg [1:0] ack_sync;
    reg video_ack;
    reg [7:0] draw_x,target_x;
    reg [6:0] draw_y,target_y;
    reg drawing,have_point;
    // Walk both coordinates toward the next sampled point. This rasterizes
    // a continuous staircase segment using only add/compare (no multiplier).
    wire [7:0] next_x=draw_x<target_x?draw_x+1'b1:draw_x>target_x?draw_x-1'b1:draw_x;
    wire [6:0] next_y=draw_y<target_y?draw_y+1'b1:draw_y>target_y?draw_y-1'b1:draw_y;
    wire [7:0] sample_x=audio_sample[15:8]^8'h80;
    wire [6:0] sample_y=~(delayed_sample[15:9]^7'h40);
    // Same port performs bank clearing and point writes. No per-pixel reset
    // loop, so this infers block RAM rather than a bank of flip-flops.
    always @(posedge clk)begin
        if(reset_n && state==CLEAR)pixels[{write_bank,clear_address}]<=0;
        else if(reset_n && drawing)pixels[{write_bank,draw_y,draw_x}]<=1;
    end
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=CLEAR;clear_address<=0;captured<=0;write_bank<=0;
            publish_toggle<=0;ack_sync<=0;drawing<=0;have_point<=0;
            draw_x<=0;draw_y<=0;target_x<=0;target_y<=0;
        end else begin
            ack_sync<={ack_sync[0],video_ack};
            case(state)
                CLEAR:if(clear_address==32767)begin
                    clear_address<=0;captured<=0;have_point<=0;state<=CAPTURE;
                end else clear_address<=clear_address+1'b1;
                CAPTURE:begin
                    if(drawing)begin
                        if(draw_x==target_x && draw_y==target_y)begin
                            drawing<=0;
                            if(captured==0)begin
                                publish_toggle<=~publish_toggle;state<=WAIT_ACK;
                            end
                        end else begin draw_x<=next_x;draw_y<=next_y;end
                    end
                    // Worst-case segment is 256 clocks, safely below 1024.
                    if(sample_tick && !drawing && history_count>=delay_safe)begin
                        target_x<=sample_x;target_y<=sample_y;drawing<=1;
                        if(!have_point)begin draw_x<=sample_x;draw_y<=sample_y;have_point<=1;end
                        captured<=captured+1'b1;
                    end
                end
                WAIT_ACK:if(ack_sync[1]==publish_toggle)begin
                    write_bank<=~write_bank;clear_address<=0;state<=CLEAR;
                end
                default:state<=CLEAR;
            endcase
        end
    end
    reg [1:0] publish_sync,bank_sync;
    reg display_bank,display_valid;
    reg pixel_raw;
    always @(posedge pixel_clk)pixel_raw<=pixels[{display_bank,pixel_address}];
    // pixel_raw is a synchronous RAM output; gate initial undefined memory.
    always @* pixel_on=display_valid?pixel_raw:1'b0;
    always @(posedge pixel_clk or negedge video_reset_n)begin
        if(!video_reset_n)begin
            publish_sync<=0;bank_sync<=0;display_bank<=1;display_valid<=0;video_ack<=0;
        end else begin
            publish_sync<={publish_sync[0],publish_toggle};
            bank_sync<={bank_sync[0],write_bank};
            if(frame_latch && publish_sync[1]!=video_ack)begin
                display_bank<=bank_sync[1];display_valid<=1;video_ack<=publish_sync[1];
            end
        end
    end
endmodule
