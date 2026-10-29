// System-clock plain-background compensation. Four 2x2 corner minima define
// a bilinear darkness plane. All arithmetic matches model.py mode="plane".
// Complete raw frames arrive via mailbox; no camera-domain frame buffering.
module gesture_normalize(
    input wire clk,reset_n,enable,input_write,
    input wire [7:0] input_index,input wire [6:0] input_value,
    input wire input_start,
    output reg feature_write,output reg [7:0] feature_index,
    output reg [6:0] feature_value,output reg start,
    output reg [14:0] feature_energy
);
    reg [6:0] samples[0:255] /* synthesis syn_ramstyle="distributed_ram" */;
    reg mask[0:255] /* synthesis syn_ramstyle="distributed_ram" */;
    reg [6:0] tl,tr,bl,br,q;
    reg [7:0] index;
    reg [3:0] state;
    localparam IDLE=0,READ=1,VERT=2,HORIZ=3,THRESH=4,CHECK=5,REPLAY=6,START=7;
    reg [10:0] left,right,plane;
    reg [8:0] area,edges;
    reg [6:0] border;
    reg [15:0] previous_row;
    reg previous;
    wire [4:0] dx=5'd16-{1'b0,index[3:0]},dy=5'd16-{1'b0,index[7:4]};
    wire foreground={1'b0,q}>=(plane>>4)+8'd12;
    wire at_border=index[3:0]==0||index[3:0]==15||index[7:4]==0||index[7:4]==15;
    wire horizontal_edge=index[3:0]!=0&&(foreground!=previous);
    wire vertical_edge=index[7:4]!=0&&(foreground!=previous_row[index[3:0]]);
    always @(posedge clk)begin
        if(input_write&&enable&&state==IDLE)samples[input_index]<=input_value;
        q<=samples[index];
        if(!reset_n||!enable)begin
            state<=IDLE;index<=0;feature_write<=0;feature_index<=0;
            feature_value<=0;start<=0;feature_energy<=0;
            tl<=127;tr<=127;bl<=127;br<=127;
            left<=0;right<=0;plane<=0;area<=0;edges<=0;border<=0;
            previous_row<=0;previous<=0;
        end else begin
            feature_write<=0;start<=0;
            if(input_write&&state==IDLE)begin
                if(input_index==0)begin tl<=input_value;tr<=127;bl<=127;br<=127;end
                else begin
                    if(input_index[7:4]<2&&input_index[3:0]<2&&input_value<tl)tl<=input_value;
                    if(input_index[7:4]<2&&input_index[3:0]>=14&&input_value<tr)tr<=input_value;
                    if(input_index[7:4]>=14&&input_index[3:0]<2&&input_value<bl)bl<=input_value;
                    if(input_index[7:4]>=14&&input_index[3:0]>=14&&input_value<br)br<=input_value;
                end
            end
            case(state)
                IDLE: if(input_start)begin
                    index<=0;area<=0;edges<=0;border<=0;previous_row<=0;previous<=0;state<=READ;
                end
                READ: state<=VERT;
                VERT: begin
                    left<=tl*dy+bl*{1'b0,index[7:4]};
                    right<=tr*dy+br*{1'b0,index[7:4]};state<=HORIZ;
                end
                HORIZ: begin plane<=(left>>4)*dx+(right>>4)*{1'b0,index[3:0]};state<=THRESH;end
                THRESH: begin
                    mask[index]<=foreground;
                    area<=area+foreground;border<=border+(foreground&&at_border);
                    edges<=edges+horizontal_edge+vertical_edge;
                    previous<=foreground;previous_row[index[3:0]]<=foreground;
                    if(index==255)state<=CHECK;
                    else begin index<=index+1'b1;state<=READ;end
                end
                CHECK: begin
                    // Shape rejection is conservative engineering filtering,
                    // not a trained unknown class. Keep features for raw scores.
                    feature_energy<=(area>=7&&area<=192&&border<=24&&edges<=96)?
                        ({area,7'b0}-{6'b0,area}):15'd0;
                    index<=0;state<=REPLAY;
                end
                REPLAY: begin
                    feature_write<=1;feature_index<=index;feature_value<=mask[index]?7'd127:7'd0;
                    if(index==255)state<=START;else index<=index+1'b1;
                end
                START: begin start<=1;state<=IDLE;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
