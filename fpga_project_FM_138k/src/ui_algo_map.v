// Ordered rectangle list, inclusive coordinates, later entries paint on top.
// Byte format at index*8: x0[8:0],x1[8:0],y0[7:0],y1[7:0],class[1:0].
// Count is at 0x7ff8/9. Firmware disables and drains the video pipeline
// before modifying this bundled-data list; it enables after the count write.
module ui_algo_map #(parameter integer PANEL_X=144, PANEL_Y=160)(
    input wire pclk,input wire video_reset_n,
    input wire [10:0] h,input wire [9:0] v,input wire enable,
    input wire wclk,input wire we,input wire [14:0] waddr,
    input wire [7:0] wdata,output wire ink,output wire [1:0] cls
);
    reg [35:0] rectangles[0:255] /* synthesis syn_ramstyle = "registers" */;
    reg [8:0] count=0;
    always @(posedge wclk) if(we)begin
        if(waddr==15'h7ff8)count[7:0]<=wdata;
        else if(waddr==15'h7ff9)count[8]<=wdata[0];
        else if(waddr<2048)case(waddr[2:0])
            0:rectangles[waddr[10:3]][7:0]<=wdata;
            1:rectangles[waddr[10:3]][15:8]<=wdata;
            2:rectangles[waddr[10:3]][23:16]<=wdata;
            3:rectangles[waddr[10:3]][31:24]<=wdata;
            4:rectangles[waddr[10:3]][35:32]<=wdata[3:0];
        endcase
    end
    reg en_meta=0,en_sync=0;
    always @(posedge pclk)begin
        if(!video_reset_n)begin en_meta<=0;en_sync<=0;end
        else begin en_meta<=enable;en_sync<=en_meta;end
    end
    wire inside_panel=(h>=PANEL_X)&&(h<PANEL_X+512)&&(v>=PANEL_Y)&&(v<PANEL_Y+256);
    wire [8:0] x=h-PANEL_X;
    wire [7:0] y=v-PANEL_Y;
    reg [1:0] hit[0:255];
    reg [1:0] groups[0:15];
    reg valid1=0,valid2=0;
    always @(posedge pclk)begin
        valid1<=video_reset_n&&en_sync&&inside_panel;
        valid2<=valid1&&video_reset_n&&en_sync;
    end
    genvar g,k;
    generate for(g=0;g<16;g=g+1)begin:group_gen
        for(k=0;k<16;k=k+1)begin:rect_gen
            localparam integer N=g*16+k;
            wire [35:0] r=rectangles[N];
            always @(posedge pclk)begin
                if(!en_sync||N>=count)hit[N]<=0;
                else hit[N]<=(x>=r[8:0] && x<=r[17:9] &&
                         y>=r[25:18] && y<=r[33:26])?r[35:34]:2'd0;
            end
        end
        integer j;reg [1:0] chosen;
        always @* begin
            chosen=0;
            for(j=0;j<16;j=j+1)if(hit[g*16+j]!=0)chosen=hit[g*16+j];
        end
        always @(posedge pclk)groups[g]<=chosen;
    end endgenerate
    integer i;reg [1:0] chosen_group;
    always @* begin
        chosen_group=0;
        for(i=0;i<16;i=i+1)if(groups[i]!=0)chosen_group=groups[i];
    end
    // Two pixel clocks, matching the existing character/graph layers.
    assign cls=valid2?chosen_group:2'd0;
    assign ink=|cls;
endmodule
