// Shared RGB/HDMI piano roll. One score read per blanking clock, never a
// framebuffer. 128 events fit inside the 160-clock HDMI horizontal blank.
module lesson_view #(
    parameter integer WIDTH=800,
    parameter GEOMETRY_FILE="src/generated/lesson_geometry_800.mem"
)(
    input wire clk,reset_n,pclk,video_reset_n,frame_latch,
    input wire [10:0] x,input wire [9:0] y,
    input wire [10:0] prefetch_x,
    input wire [31:0] state,
    input wire score_bank,input wire [7:0] score_count,
    input wire score_write,input wire [6:0] score_address,input wire [31:0] score_data,
    input wire [31:0] midi_event,input wire midi_valid,
    input wire [23:0] background,accent,
    output wire enabled,output reg ink,output reg [23:0] color
);
    reg [127:0] human_keys,demo_keys;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin human_keys<=0;demo_keys<=0;end
        else if(midi_valid)begin
            if(midi_event[23:20]==4'h8||midi_event[23:20]==4'h9)begin
                if(midi_event[31])demo_keys[midi_event[14:8]]<=midi_event[23:20]==4'h9&&midi_event[6:0]!=0;
                else human_keys[midi_event[14:8]]<=midi_event[23:20]==4'h9&&midi_event[6:0]!=0;
            end else if(midi_event[23:20]==4'hb&&(midi_event[14:8]==120||midi_event[14:8]==123))begin
                human_keys<=0;demo_keys<=0;
            end
        end
    end
    // Bundled-data request/acknowledge. Source holds the snapshot through
    // acknowledgement and until the next frame request. PLL loss resets both
    // sides; score writes remain in the global domain and survive relocking.
    reg request,ack;
    reg [1:0] request_sync,ack_sync;
    reg [168:0] held;
    reg [168:0] frame;
    always @(posedge clk or negedge video_reset_n)begin
        if(!video_reset_n)begin request_sync<=0;ack<=0;held<=0;end
        else begin
            request_sync<={request_sync[0],request};
            if(request_sync[1]!=ack)begin
                held<={score_bank,score_count,human_keys|demo_keys,state};ack<=request_sync[1];
            end
        end
    end
    always @(posedge pclk or negedge video_reset_n)begin
        if(!video_reset_n)begin request<=0;ack_sync<=0;frame<=0;end
        else begin
            ack_sync<={ack_sync[0],ack};
            if(frame_latch&&ack_sync[1]==request)begin frame<=held;request<=~request;end
        end
    end
    wire [31:0] frame_state=frame[31:0];
    wire [127:0] keys=frame[159:32];
    wire [7:0] count=frame[167:160];
    assign enabled=frame_state[16];
    localparam [10:0] SCAN_START=WIDTH+4;
    wire [10:0] scan_index=x-SCAN_START;
    wire scanning=x>=WIDTH+4&&x<WIDTH+132;
    wire [31:0] entry;
    lesson_score_memory u_score(.wclk(clk),.write(score_write),.write_address(score_address),.write_data(score_data),
        .rclk(pclk),.bank(frame[168]),.address(scan_index[6:0]),.data(entry));
    reg scan_valid;
    reg [6:0] scan_address;
    reg [24:0] row_notes;
    wire [16:0] row_time={1'b0,frame_state[15:0]}+17'd350-{7'd0,y};
    always @(posedge pclk or negedge video_reset_n)begin
        if(!video_reset_n)begin row_notes<=0;scan_valid<=0;scan_address<=0;end
        else begin
            scan_valid<=scanning;scan_address<=scan_index[6:0];
            if(x==WIDTH)row_notes<=0;
            else if(scan_valid&&scan_address<count&&y>=127&&y<351&&
                entry[6:0]>=48&&entry[6:0]<=72&&row_time>={1'b0,entry[31:16]}&&
                row_time<({1'b0,entry[31:16]}+{8'd0,entry[15:7]}))
                row_notes[entry[6:0]-48]<=1;
        end
    end
    // Prefetch with hcount, one clock ahead of raster x. A small synchronous
    // geometry ROM replaces division and 10 cascaded lane/edge multiplexers.
    reg [31:0] geometry[0:1023];
    reg [31:0] geom;
    initial $readmemh(GEOMETRY_FILE,geometry);
    always @(posedge pclk)geom<=geometry[prefetch_x[9:0]];
    wire black=geom[31]&&y<432;
    wire [4:0] lane=(y<432)?geom[30:26]:geom[5:1];
    wire [9:0] left_edge=geom[25:16],right_edge=geom[15:6];
    wire [23:0] grid={1'b0,background[23:17],1'b0,background[15:9],1'b0,background[7:1]}^
                     24'h303030;
    always @*begin
        ink=enabled&&x<WIDTH&&y>=128&&y<480;
        color=background;
        if(y<352)begin
            if(x==left_edge||((frame_state[15:0]+351-y)&31)==0)color=grid;
            if(row_notes[lane]&&x>left_edge+2&&x<right_edge-2)color=accent;
            if(y>=350)color=accent;
        end else begin
            color=keys[48+lane]?accent:(black?24'h111820:24'hF5F8FB);
            if((y<432?x==left_edge:geom[0])||y==479)color=background;
        end
        if(!ink)color=background;
    end
endmodule
