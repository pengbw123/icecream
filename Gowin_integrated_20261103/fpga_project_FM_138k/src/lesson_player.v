// Monophonic ROM lesson. Audio and timeline never depend on UI polling.
// Output bit31 tags the demo owner; all MIDI channels remain available to humans.
module lesson_player #(
    parameter integer CLOCKS_PER_MS=50000
)(
    input wire clk,reset_n,
    input wire control_write,input wire [31:0] control_data,
    input wire score_bank,input wire [7:0] score_count,input wire [15:0] score_end,
    input wire score_write,input wire [6:0] score_address,input wire [31:0] score_data,
    input wire [31:0] human_event,input wire human_valid,
    output reg [31:0] midi_data,output wire midi_valid,input wire midi_ready,
    output wire [31:0] status,
    output wire [31:0] view_state
);
    reg enabled,running,demo,restarting,done;
    reg [7:0] speed;
    reg [15:0] ms_div;
    reg [10:0] phase;
    reg [15:0] position;
    reg [7:0] index,read_index;
    reg pending,active;
    reg [6:0] active_note;
    reg [15:0] off_at;
    wire [31:0] score;
    lesson_score_memory u_score(.wclk(clk),.write(score_write),.write_address(score_address),.write_data(score_data),
        .rclk(clk),.bank(score_bank),.address(index[6:0]),.data(score));
    always @(posedge clk)read_index<=index;
    wire score_ready=read_index==index;
    wire [15:0] onset=score[31:16];
    wire [8:0] gate=score[15:7];
    wire [6:0] note=score[6:0];
    wire waiting=enabled&&running&&!demo&&!done&&index<score_count&&score_ready&&position>=onset;
    wire allowed=enabled&&running&&demo&&!restarting&&!done;
    wire pending_on=midi_data[23:20]==4'h9;
    assign midi_valid=pending&&(!pending_on||allowed);
    // Low flags: enabled, running, demo, waiting, done, cleanup. Next note in [14:8].
    assign status={index,9'd0,note,2'd0,(restarting||active||pending),done,waiting,demo,running,enabled};
    assign view_state={index,3'd0,done,waiting,demo,running,enabled,position};
    wire hit=human_valid&&!human_event[31]&&human_event[23:20]==4'h9&&
             human_event[6:0]!=0&&human_event[14:8]==note;
    wire [11:0] next_phase={1'b0,phase}+{4'd0,speed};
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            enabled<=0;running<=0;demo<=0;restarting<=0;done<=0;speed<=100;
            ms_div<=0;phase<=0;position<=0;index<=0;
            pending<=0;active<=0;active_note<=0;off_at<=0;midi_data<=0;
        end else begin
            if(ms_div==CLOCKS_PER_MS-1)ms_div<=0;else ms_div<=ms_div+1'b1;
            if(pending&&midi_valid&&midi_ready)begin
                pending<=0;
                if(pending_on)begin active<=1;active_note<=midi_data[14:8];index<=index+1'b1;end
                else active<=0;
            end
            if(pending&&pending_on&&!allowed)pending<=0;
            // Drain a demo Note Off on pause, page exit, mode change or restart.
            // It remains valid until the synth accepts it, even with enabled=0.
            if(!pending)begin
                if(active&&(!allowed||position>=off_at))begin
                    midi_data<={8'h80,8'h80,1'b0,active_note,8'd0};pending<=1;
                end else if(restarting)begin
                    position<=0;index<=0;phase<=0;done<=0;restarting<=0;
                end else if(enabled&&running&&!done)begin
                    if(index<score_count&&score_ready&&position>=onset)begin
                        if(demo&&!active)begin
                            midi_data<={8'h80,8'h90,1'b0,note,8'd96};pending<=1;
                            off_at<=onset+{7'd0,gate};
                        end else if(!demo&&hit)index<=index+1'b1;
                    end
                    if(index==score_count&&position>=score_end&&!active)begin
                        done<=1;running<=0;
                    end
                end
            end
            if(ms_div==CLOCKS_PER_MS-1&&enabled&&running&&!done&&!restarting&&!waiting&&!pending)begin
                // Freeze at a demo onset during backpressure as well.
                if(score_ready&&!(demo&&index<score_count&&position>=onset))begin
                    if(next_phase>=1600)begin phase<=next_phase[10:0]-11'd1600;if(position!=16'hffff)position<=position+1'b1;end
                    else phase<=next_phase[10:0];
                end
            end
            if(control_write)begin
                enabled<=control_data[0];running<=control_data[1];demo<=control_data[2];
                if(control_data[15:8]>=50&&control_data[15:8]<=150)speed<=control_data[15:8];
                if(control_data[3]||control_data[2]!=demo||(!enabled&&control_data[0]))restarting<=1;
            end
        end
    end
endmodule
