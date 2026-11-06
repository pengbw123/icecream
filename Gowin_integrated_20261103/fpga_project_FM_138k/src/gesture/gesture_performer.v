// Standalone performance adapter. Stable gesture actions: 2=palm/normal,
// 3=fist/chop, 4=V/arpeggio. No composer commands or generated melody.
// Reuses the downstream arpeggiator; retains held keys across enable changes.
module gesture_performer (
    input wire clk,reset_n,enable,track_enable,
    input wire action_valid,input wire [3:0] action,output wire action_ready,
    input wire arp_enabled,
    input wire [31:0] in_data,input wire [6:0] in_brightness,
    input wire in_valid,output wire in_ready,
    output reg [31:0] out_data,output reg [6:0] out_brightness,
    output reg out_valid,input wire out_ready,
    output reg [1:0] mode,output wire busy,output wire cancel,output reg restart_arp
);
    localparam RUN=0,PEDAL_OFF=1,LIVE_OFF=2,SET_MODE=3,WAIT_ARP=4,
               PEDAL_RESTORE=5,REPLAY=6,REPLAY_OFF=7;
    reg [2:0] state;
    reg [1:0] requested;
    reg [127:0] physical,held;
    // Deliberately registers, not a new frame/audio buffer. Only read set bits.
    reg [6:0] velocity[0:127];
    reg [3:0] channel[0:127];
    reg pedal;
    reg [7:0] scan;
    wire [1:0] wanted=enable?requested:2'd0;
    wire transition=(mode==2)!=(wanted==2);
    wire manual=!in_data[31]&&!in_data[30];
    wire on_event=in_data[23:20]==9&&in_data[6:0]!=0;
    wire off_event=in_data[23:20]==8||(in_data[23:20]==9&&in_data[6:0]==0);
    wire cc=in_data[23:20]==11;
    wire [6:0] note=in_data[14:8];
    assign busy=state!=RUN||transition;
    assign action_ready=1'b1;
    assign in_ready=state==RUN&&!transition&&!out_valid;
    assign cancel=in_valid&&in_ready&&cc&&(note==120||note==123);
    task send;
        input [31:0] data;input [6:0] brightness;
        begin out_data<=data;out_brightness<=brightness;out_valid<=1;end
    endtask
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=RUN;requested<=0;mode<=0;physical<=0;held<=0;
            pedal<=0;scan<=0;out_valid<=0;out_data<=0;out_brightness<=0;restart_arp<=0;
        end else begin
            restart_arp<=0;
            if(!enable)requested<=0;
            else if(action_valid)case(action)
                2:requested<=0;3:requested<=1;4:requested<=2;default:;
            endcase
            if(out_valid&&out_ready)out_valid<=0;
            // Never rewrite a stalled event, including when control is disabled.
            if(!out_valid)case(state)
                RUN:begin
                    if(transition)state<=PEDAL_OFF;
                    else begin
                        mode<=wanted;
                        if(in_valid&&in_ready)begin
                            send(in_data,in_brightness);
                            if(manual)begin
                                if(on_event)begin
                                    physical[note]<=1;held[note]<=1;
                                    velocity[note]<=in_data[6:0];channel[note]<=in_data[19:16];
                                end else if(off_event)begin
                                    physical[note]<=0;if(!pedal)held[note]<=0;
                                end else if(cc&&note==64)begin
                                    pedal<=in_data[6];if(!in_data[6])held<=physical;
                                end
                            end
                            if(cc&&(note==120||note==123))begin
                                physical<=0;held<=0;pedal<=0;requested<=0;
                            end
                        end
                    end
                end
                // Scoped LIVE cleanup; downstream ARP cleans its own BACKING
                // notes when enable changes. No global all-parts panic.
                PEDAL_OFF:begin send(32'h88b04000,0);state<=LIVE_OFF;end
                LIVE_OFF:begin send(32'h88b07b00,0);state<=SET_MODE;end
                SET_MODE:begin mode<=wanted;restart_arp<=1;state<=WAIT_ARP;end
                WAIT_ARP:if(arp_enabled)begin scan<=0;state<=PEDAL_RESTORE;end
                PEDAL_RESTORE:begin
                    if(pedal)send(32'h00b0407f,127);
                    state<=REPLAY;
                end
                REPLAY:begin
                    if(scan==128)state<=RUN;
                    else if(held[scan[6:0]])begin
                        send({8'd0,4'h9,channel[scan[6:0]],1'b0,scan[6:0],1'b0,velocity[scan[6:0]]},velocity[scan[6:0]]);
                        if(!physical[scan[6:0]])state<=REPLAY_OFF;
                        else scan<=scan+1'b1;
                    end else scan<=scan+1'b1;
                end
                REPLAY_OFF:begin
                    send({8'd0,4'h8,channel[scan[6:0]],1'b0,scan[6:0],8'd0},0);
                    scan<=scan+1'b1;state<=REPLAY;
                end
                default:state<=RUN;
            endcase
            if(!track_enable)begin physical<=0;held<=0;pedal<=0;end
        end
    end
endmodule
