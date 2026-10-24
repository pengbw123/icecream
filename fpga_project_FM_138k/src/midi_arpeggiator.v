// MIDI-domain arpeggiator. One ready/valid output owns all generated notes.
// Configuration is sampled at step boundaries; no audio-rate arithmetic.
module midi_arpeggiator #(
    parameter integer CLOCKS_PER_US=50
)(
    input wire clk,reset_n,
    // cfg: enable, hold, fixed velocity, order[5:3], octaves-1[7:6],
    // velocity[14:8], stop toggle[15]. Timing words are microseconds.
    input wire [159:0] config_data,input wire suspend,
    input wire sync_step,sync_restart,input wire external_sync,
    input wire [31:0] in_data,input wire [6:0] in_brightness,
    input wire in_valid,output wire in_ready,
    output reg [31:0] out_data,output reg [6:0] out_brightness,
    output reg out_valid,input wire out_ready,
    output wire [31:0] status,output wire [127:0] chord_notes
);
    localparam IDLE=0,CLEAN_PEDAL=1,CLEAN_ALL=2,PRUNE=3,COUNT=4,
               CHOOSE=5,RANDOMIZE=6,FIND=7;
    reg [3:0] state;
    wire [31:0] cfg=config_data[31:0];
    wire wanted=cfg[0]&&!suspend;
    reg enabled,stop_seen,hold_seen,pedal,running,active,external_pending;
    reg [127:0] physical,chord;
    // Synth allocator also merges channels by pitch. Duplicate Note Ons
    // update velocity; a Note Off removes that pitch from the input set.
    reg [6:0] velocity[0:127];
    reg [6:0] ordered[0:127];
    reg [7:0] count,prune_read,prune_write;
    reg [8:0] scan,sequence_pos,target;
    reg [9:0] total;
    reg [2:0] mode;
    reg [1:0] octaves;
    reg descending,odd;
    reg [8:0] random_bits;
    reg [6:0] active_note;
    reg [31:0] step_left,gate_left,step_length,gate_length;
    reg [5:0] us_div;
    wire us_tick=us_div==CLOCKS_PER_US-1;
    wire note_on=in_data[23:20]==4'h9&&in_data[6:0]!=0;
    wire note_off=in_data[23:20]==4'h8||(in_data[23:20]==4'h9&&in_data[6:0]==0);
    wire cc=in_data[23:20]==4'hb;
    wire [6:0] note=in_data[14:8];
    wire change=enabled!=wanted||stop_seen!=cfg[15]||sync_restart;
    wire gate_due=active&&gate_left==0;
    wire step_due=running&&(external_sync?external_pending:step_left==0);
    assign in_ready=state==IDLE&&!out_valid&&!change&&
        !(enabled&&((active&&(!running||gate_due||chord==0||step_due))||
            (step_due&&chord!=0)||hold_seen!=cfg[1]||(!running&&chord!=0)));
    assign chord_notes=chord;
    assign status={count,active_note,1'b0,sequence_pos[7:0],3'd0,pedal,active,running,enabled,cfg[0]};
    wire [6:0] base_note=mode==3?ordered[scan[6:0]]:scan[6:0];
    wire [8:0] expanded={2'd0,base_note}+({7'd0,scan[8:7]}*9'd12);
    wire candidate=scan[8:7]<=octaves&&expanded<128&&chord[base_note]&&
        (mode!=3||{1'b0,scan[6:0]}<count);
    wire [31:0] requested_step=odd?config_data[95:64]:config_data[63:32];
    wire [31:0] requested_gate=odd?config_data[159:128]:config_data[127:96];
    task send;
        input [31:0] word;input [6:0] brightness;
        begin out_data<=word;out_brightness<=brightness;out_valid<=1;end
    endtask
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=IDLE;enabled<=0;stop_seen<=0;hold_seen<=0;pedal<=0;
            running<=0;active<=0;physical<=0;chord<=0;count<=0;external_pending<=0;
            prune_read<=0;prune_write<=0;scan<=0;sequence_pos<=0;target<=0;
            total<=0;mode<=0;octaves<=0;descending<=0;odd<=0;random_bits<=9'h1ab;
            active_note<=0;step_left<=0;gate_left<=0;step_length<=1;gate_length<=1;
            us_div<=0;out_data<=0;out_brightness<=0;out_valid<=0;
        end else begin
            if(sync_step&&enabled)external_pending<=1;
            if(us_tick)us_div<=0;else us_div<=us_div+1'b1;
            if(us_tick&&running&&!out_valid)begin
                if(step_left!=0)step_left<=step_left-1'b1;
                if(gate_left!=0)gate_left<=gate_left-1'b1;
            end
            if(out_valid&&out_ready)begin
                out_valid<=0;
                if(out_data[30]&&out_data[23:20]==4'h9)begin
                    active<=1;active_note<=out_data[14:8];
                    step_left<=step_length;gate_left<=gate_length;odd<=!odd;
                end
                if(out_data[30]&&out_data[23:20]==4'h8)active<=0;
            end
            // A stalled event is immutable. Cleanup follows its acceptance.
            if(!out_valid)begin
                if(change&&state!=CLEAN_PEDAL&&state!=CLEAN_ALL)begin
                    state<=CLEAN_PEDAL;running<=0;
                end else case(state)
                    CLEAN_PEDAL:begin send(32'h00b04000,0);state<=CLEAN_ALL;end
                    CLEAN_ALL:begin
                        send(32'h00b07b00,0);enabled<=wanted;stop_seen<=cfg[15];hold_seen<=cfg[1];
                        physical<=0;chord<=0;count<=0;pedal<=0;running<=0;active<=0;external_pending<=0;
                        sequence_pos<=0;descending<=0;odd<=0;state<=IDLE;
                    end
                    IDLE:begin
                        if(enabled&&chord==0)begin running<=0;sequence_pos<=0;descending<=0;odd<=0;end
                        if(enabled&&hold_seen!=cfg[1])begin
                            hold_seen<=cfg[1];
                            if(!cfg[1]&&!pedal)begin prune_read<=0;prune_write<=0;state<=PRUNE;end
                        end else if(enabled&&active&&(!running||gate_due||chord==0||step_due))begin
                            send(32'h40800000|({25'd0,active_note}<<8),0);
                        end else if(enabled&&chord!=0&&(!running||step_due))begin
                            running<=1;scan<=0;total<=0;state<=COUNT;external_pending<=0;
                            mode<=cfg[5:3]>4?0:cfg[5:3];octaves<=cfg[7:6];
                            step_length<=requested_step<2?2:requested_step;
                            gate_length<=requested_gate==0?1:
                                requested_gate>=requested_step?(requested_step<2?1:requested_step-1):requested_gate;
                        end else if(in_valid&&in_ready)begin
                            if(!enabled||in_data[31])send(in_data,in_brightness);
                            else if(note_on)begin
                                physical[note]<=1;velocity[note]<=in_data[6:0];
                                if(chord==0)begin running<=1;step_left<=0;external_pending<=1;end
                                if(physical==0&&(cfg[1]||pedal))begin
                                    chord<=128'd1<<note;ordered[0]<=note;count<=1;
                                end else if(!chord[note])begin
                                    chord[note]<=1;ordered[count[6:0]]<=note;count<=count+1'b1;
                                end
                            end else if(note_off)begin
                                physical[note]<=0;
                                if(!cfg[1]&&!pedal)begin
                                    prune_read<=0;prune_write<=0;state<=PRUNE;
                                end
                            end else if(cc&&note==64)begin
                                pedal<=in_data[6];
                                if(!in_data[6]&&!cfg[1])begin prune_read<=0;prune_write<=0;state<=PRUNE;end
                            end else if(cc&&(note==120||note==123))begin
                                physical<=0;chord<=0;count<=0;running<=0;active<=0;
                                sequence_pos<=0;descending<=0;odd<=0;send(in_data,in_brightness);
                            end else if(cc&&note==22)send(in_data&32'hffffff80,in_brightness);
                            else send(in_data,in_brightness);
                        end
                    end
                    PRUNE:begin
                        if(prune_read<count)begin
                            if(physical[ordered[prune_read[6:0]]])begin
                                ordered[prune_write[6:0]]<=ordered[prune_read[6:0]];
                                prune_write<=prune_write+1'b1;
                            end
                            prune_read<=prune_read+1'b1;
                        end else begin chord<=physical;count<=prune_write;state<=IDLE;end
                    end
                    COUNT:begin
                        if(candidate)total<=total+1'b1;
                        if(scan==511)state<=CHOOSE;else scan<=scan+1'b1;
                    end
                    CHOOSE:begin
                        scan<=0;
                        if(total==0)begin running<=0;state<=IDLE;end
                        else if(mode==4)begin
                            target<=random_bits;
                            random_bits<={random_bits[7:0],random_bits[8]^random_bits[4]};state<=RANDOMIZE;
                        end else begin
                            if(sequence_pos>=total)sequence_pos<=0;
                            target<=mode==1?(total-1-(sequence_pos>=total?0:sequence_pos)):
                                (sequence_pos>=total?0:sequence_pos);state<=FIND;
                        end
                    end
                    RANDOMIZE:begin
                        if(target>=total)target<=target-total;else state<=FIND;
                    end
                    FIND:begin
                        if(candidate&&target==0)begin
                            send(32'h40900000|({23'd0,expanded}<<8)|
                                {25'd0,(cfg[2]?(cfg[14:8]==0?7'd1:cfg[14:8]):velocity[base_note])},
                                cfg[2]?(cfg[14:8]==0?7'd1:cfg[14:8]):velocity[base_note]);
                            if(mode==2)begin
                                if(total==1)sequence_pos<=1;
                                else if(descending)begin
                                    if(sequence_pos==0)begin sequence_pos<=1;descending<=0;end
                                    else sequence_pos<=sequence_pos-1'b1;
                                end else if(sequence_pos>=total-1)begin
                                    sequence_pos<=total-2;descending<=1;
                                end else sequence_pos<=sequence_pos+1'b1;
                            end else sequence_pos<=sequence_pos+1'b1;
                            state<=IDLE;
                        end else begin
                            if(candidate)target<=target-1'b1;
                            if(scan==511)state<=IDLE;else scan<=scan+1'b1;
                        end
                    end
                    default:state<=IDLE;
                endcase
            end
        end
    end
endmodule
