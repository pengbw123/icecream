// Coherent system->HDMI telemetry. Request at vertical blank; source holds
// the entire packet until the NEXT request. No independently sampled digits.
module gesture_video_snapshot #(parameter integer WIDTH=64)(
    input wire clk,pixel_clk,reset_n,frame_latch,
    input wire [WIDTH-1:0] source_data,output reg [WIDTH-1:0] video_data
);
    reg request,ack;
    reg [1:0] req_sync,ack_sync;
    reg [WIDTH-1:0] held;
    reg [2:0] main_reset,video_reset;
    always @(posedge clk or negedge reset_n)
        if(!reset_n)main_reset<=0;else main_reset<={main_reset[1:0],1'b1};
    always @(posedge pixel_clk or negedge reset_n)
        if(!reset_n)video_reset<=0;else video_reset<={video_reset[1:0],1'b1};
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin req_sync<=0;ack<=0;held<=0;end
        else if(!main_reset[2])begin req_sync<=0;ack<=0;held<=0;end
        else begin
            req_sync<={req_sync[0],request};
            if(req_sync[1]!=ack)begin held<=source_data;ack<=req_sync[1];end
        end
    end
    reg received;
    always @(posedge pixel_clk or negedge reset_n)begin
        if(!reset_n)begin request<=0;ack_sync<=0;received<=0;video_data<=0;end
        else if(!video_reset[2])begin request<=0;ack_sync<=0;received<=0;video_data<=0;end
        else begin
            ack_sync<={ack_sync[0],ack};
            if(frame_latch&&request==ack_sync[1])begin
                if(ack_sync[1]!=received)begin video_data<=held;received<=ack_sync[1];end
                request<=!request;
            end
        end
    end
endmodule
