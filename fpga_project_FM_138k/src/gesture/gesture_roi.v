// Tap the validated 160x120 RGB332 camera stream, same clock domain.
// Center 96x96 ROI: x=32..127,y=12..107. Sample cell centers at stride 6.
// The camera's frame_good and frame_start can coincide (end/start boundary).
// No frame RAM; if inference is busy, discard a WHOLE acquisition frame.
module gesture_roi #(parameter integer SILHOUETTE=1)(
    input wire clk,reset_n,enable,frame_start,frame_good,frame_bad,
    input wire pixel_write,input wire [14:0] pixel_address,
    input wire [7:0] pixel_data,input wire inference_busy,
    output reg feature_write,output reg [7:0] feature_index,
    output reg [6:0] feature_value,output reg inference_start,
    output reg [14:0] feature_energy
);
    reg collecting;
    reg [8:0] count;
    reg [14:0] target,energy;
    // r3/g3 -> 0..126, b2 -> 0..126. Explicitly wide intermediate sums.
    wire [7:0] red={5'd0,pixel_data[7:5]}*8'd18;
    wire [7:0] green={5'd0,pixel_data[4:2]}*8'd18;
    wire [7:0] blue={6'd0,pixel_data[1:0]}*8'd42;
    wire [9:0] luma={2'b0,red}+{1'b0,green,1'b0}+{2'b0,blue};
    wire [6:0] darkness=7'd127-luma[8:2];
    wire [6:0] value=SILHOUETTE?(darkness>=12?7'd127:7'd0):darkness;
    wire publish=enable&&collecting&&frame_good&&!frame_bad&&count==256&&!inference_busy;
    always @(posedge clk) begin
        if(!reset_n||!enable) begin
            collecting<=0;count<=0;target<=2435;energy<=0;
            feature_write<=0;feature_index<=0;feature_value<=0;
            inference_start<=0;feature_energy<=0;
        end else begin
            feature_write<=0;inference_start<=0;
            if(publish) begin inference_start<=1;feature_energy<=energy;end
            if(frame_start) begin
                collecting<=!inference_busy&&!publish;count<=0;target<=2435;energy<=0;
            end else if(frame_bad) collecting<=0;
            else if(collecting&&!inference_busy&&pixel_write&&count<256) begin
                if(pixel_address==target) begin
                    feature_write<=1;feature_index<=count[7:0];feature_value<=value;
                    count<=count+1'b1;energy<=energy+value;
                    target<=target+(count[3:0]==15?15'd870:15'd6);
                end else if(pixel_address>target) collecting<=0; // missing sample => no inference
            end
        end
    end
endmodule
