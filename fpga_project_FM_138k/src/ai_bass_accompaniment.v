// Causal MIDI observer + trained bass policy + bounded MIDI output scheduler.
// The observer never backpressures LIVE. Generated events use BACKING bit30.
module ai_bass_accompaniment #(
    parameter integer CLOCKS_PER_US=50
)(
    input wire clk,reset_n,
    input wire cfg_write,input wire [9:0] cfg_address,input wire [15:0] cfg_value,
    input wire suspend,
    input wire [31:0] observe_data,input wire observe_valid,
    output reg [31:0] out_data,output reg out_valid,input wire out_ready,
    output wire [31:0] status
);
    reg [15:0] config_word=0;
    reg [31:0] period_shadow=125000,step_us=125000;
    reg panic_latched=0;
    wire enabled=config_word[0]&&!suspend&&!panic_latched;
    reg was_enabled;
    reg [7:0] us_div;
    reg [31:0] remaining;
    reg [3:0] phase;
    reg [1:0] chord_slot;
    wire [4:0] root_sum={1'b0,config_word[7:4]}+
        (!config_word[2]?0:chord_slot==1?9:chord_slot==2?5:chord_slot==3?7:0);
    wire [3:0] root=root_sum>=12?root_sum-12:root_sum;
    wire minor=config_word[2]?(chord_slot==1):config_word[8];
    reg [6:0] hist[0:11];
    reg [127:0] held;
    reg [7:0] held_count,onsets,history[0:2];
    reg [6:0] velocity;
    reg [3:0] last_pc,silence,previous_root;
    reg previous_minor,snapshot_changed;
    reg [2:0] previous_action;
    function [3:0] pitch_class(input [6:0] pitch);
        reg [6:0] p;
        begin p=pitch;if(p>=96)p=p-96;if(p>=48)p=p-48;
            if(p>=24)p=p-24;if(p>=12)p=p-12;pitch_class=p[3:0];end
    endfunction
    wire [3:0] note_pc=pitch_class(observe_data[14:8]);
    wire human_event=observe_valid&&observe_data[31:28]==0&&observe_data[19:16]!=9;
    wire note_on=human_event&&observe_data[23:20]==9&&observe_data[6:0]!=0;
    wire note_off=human_event&&(observe_data[23:20]==8||
                   (observe_data[23:20]==9&&observe_data[6:0]==0));
    wire panic=human_event&&observe_data[23:20]==11&&
               (observe_data[14:8]==120||observe_data[14:8]==123);
    wire step_tick=enabled&&((!was_enabled)||((us_div==CLOCKS_PER_US-1)&&remaining==0));
    reg [7:0] snapshot[0:47];
    reg [5:0] load_index;
    reg loading,infer_start;
    wire infer_busy,infer_done;wire [2:0] infer_action;wire [15:0] infer_cycles;
    reg [3:0] snapshot_root,snapshot_phase;reg snapshot_minor,snapshot_sparse;
    ai_bass_inference u_policy(.clk(clk),.reset_n(reset_n),
        .feature_write(loading),.feature_index(load_index),.feature_value(snapshot[load_index]),
        .start(infer_start),.busy(infer_busy),.done(infer_done),.action(infer_action),
        .cycles(infer_cycles),.score_index(3'd0),.score());
    reg active,off_pending,on_pending;
    reg [6:0] active_note,wanted_note;
    reg [15:0] misses;
    reg [31:0] decisions;
    wire [2:0] density_action=(snapshot_sparse&&snapshot_phase[1:0]!=0&&infer_action>=2)?3'd1:infer_action;
    wire [3:0] active_pc=pitch_class(active_note);
    wire [3:0] relative_pc=active_pc>=snapshot_root?active_pc-snapshot_root:active_pc+12-snapshot_root;
    // A HOLD across a harmony change must not leave an unrelated old pitch.
    wire [2:0] decision=(density_action==1&&snapshot_changed&&active&&relative_pc!=0&&
        relative_pc!=(snapshot_minor?3:4)&&relative_pc!=7)?3'd2:density_action;
    function [6:0] bass_note(input [2:0] a,input [3:0] r,input m);
        begin case(a)
            3:bass_note=36+r+(m?3:4);
            4:bass_note=43+r;
            5:bass_note=48+r;
            6:bass_note=31+r;
            7:bass_note=35+r;
            default:bass_note=36+r;
        endcase end
    endfunction
    assign status={misses,infer_cycles[11:0],panic_latched,
                   infer_busy||loading||infer_start,active||out_valid||off_pending||on_pending,enabled};
    integer i,rot;integer total_onsets;
    always @(posedge clk)begin
        if(!reset_n)begin
            config_word<=0;period_shadow<=125000;step_us<=125000;
            panic_latched<=0;was_enabled<=0;us_div<=0;remaining<=0;
            phase<=0;chord_slot<=0;held<=0;held_count<=0;onsets<=0;velocity<=0;
            last_pc<=0;silence<=15;previous_root<=15;previous_action<=0;
            previous_minor<=0;snapshot_changed<=0;
            loading<=0;load_index<=0;infer_start<=0;active<=0;off_pending<=0;on_pending<=0;
            out_valid<=0;out_data<=0;misses<=0;decisions<=0;
            snapshot_root<=0;snapshot_phase<=0;snapshot_minor<=0;snapshot_sparse<=0;
            active_note<=0;wanted_note<=0;
            for(i=0;i<12;i=i+1)hist[i]<=0;
            for(i=0;i<3;i=i+1)history[i]<=0;
        end else begin
            was_enabled<=enabled;infer_start<=0;
            if(cfg_write)case(cfg_address)
                10'h3f1:period_shadow[15:0]<=cfg_value;
                10'h3f2:period_shadow[31:16]<=cfg_value;
                10'h3f0:begin
                    config_word<={cfg_value[15:8],(cfg_value[7:4]>11?4'd11:cfg_value[7:4]),cfg_value[3:0]};
                    step_us<=period_shadow<10000?10000:period_shadow>1000000?1000000:period_shadow;
                end
            endcase
            if(!config_word[0])panic_latched<=0;
            else if(panic)panic_latched<=1;
            if(loading)begin
                if(load_index==47)begin loading<=0;infer_start<=1;end
                else load_index<=load_index+1'b1;
            end
            if(out_valid&&out_ready)begin
                out_valid<=0;
                if(out_data[23:20]==9)begin active<=1;active_note<=out_data[14:8];end
                else if(out_data[23:20]==8)active<=0;
            end
            if(!out_valid)begin
                if(off_pending)begin
                    out_data<=32'h40800000|({25'd0,active_note}<<8);out_valid<=1;off_pending<=0;
                end else if(on_pending&&enabled)begin
                    out_data<=32'h40900000|({25'd0,wanted_note}<<8)|
                              {25'd0,(config_word[15:9]==0?7'd70:config_word[15:9])};
                    out_valid<=1;on_pending<=0;
                end
            end
            if(!enabled)begin
                remaining<=0;us_div<=0;phase<=0;chord_slot<=0;
                on_pending<=0;
                if(active&&!off_pending&&!(out_valid&&out_data[23:20]==8))off_pending<=1;
                if(out_valid&&out_data[23:20]==9&&!out_ready)out_valid<=0;
                held<=0;held_count<=0;onsets<=0;velocity<=0;last_pc<=0;
                silence<=15;previous_root<=15;previous_action<=0;
                previous_minor<=0;
                for(i=0;i<12;i=i+1)hist[i]<=0;
                for(i=0;i<3;i=i+1)history[i]<=0;
            end else begin
                if(us_div==CLOCKS_PER_US-1)begin
                    us_div<=0;if(remaining!=0)remaining<=remaining-1'b1;
                end else us_div<=us_div+1'b1;
                if(step_tick)begin
                    remaining<=step_us-1'b1;us_div<=0;
                    if(phase==15)chord_slot<=chord_slot+1'b1;
                    phase<=phase+1'b1;
                    if(!infer_busy&&!loading&&!infer_start&&!on_pending&&!off_pending&&!out_valid)begin
                        for(i=0;i<16;i=i+1)snapshot[i]<=(phase==i)?127:0;
                        for(i=0;i<12;i=i+1)begin
                            rot=i+root;if(rot>=12)rot=rot-12;
                            snapshot[16+i]<=hist[rot];
                        end
                        snapshot[28]<=onsets>=6?127:onsets*24;
                        for(i=0;i<3;i=i+1)snapshot[29+i]<=history[i]>=6?127:history[i]*24;
                        snapshot[32]<=held_count>=8?127:held_count*16;
                        snapshot[33]<=velocity;
                        total_onsets=onsets+history[0]+history[1]+history[2];
                        snapshot[34]<=total_onsets>=11?127:total_onsets*12;
                        snapshot[35]<=minor?127:0;
                        for(i=0;i<8;i=i+1)snapshot[36+i]<=previous_action==i?127:0;
                        snapshot[44]<=config_word[1]?0:127;
                        snapshot[45]<=root!=previous_root?127:0;
                        snapshot[46]<=onsets!=0?0:silence>=15?127:(silence+1)*8;
                        snapshot[47]<=(last_pc>=root?last_pc-root:last_pc+12-root)*11;
                        snapshot_root<=root;snapshot_minor<=minor;snapshot_phase<=phase;snapshot_sparse<=config_word[1];
                        snapshot_changed<=root!=previous_root||minor!=previous_minor;previous_minor<=minor;
                        load_index<=0;loading<=1;previous_root<=root;
                    end else if(misses!=65535)misses<=misses+1'b1;
                    history[2]<=history[1];history[1]<=history[0];history[0]<=onsets;onsets<=0;
                    silence<=onsets!=0?0:silence==15?15:silence+1'b1;
                    for(i=0;i<12;i=i+1)hist[i]<=hist[i]>>1;
                end
                if(note_on)begin
                    if(!held[observe_data[14:8]])begin
                        held[observe_data[14:8]]<=1;held_count<=held_count+1'b1;
                    end
                    onsets<=step_tick?1:onsets>=15?15:onsets+1'b1;
                    if((step_tick?(hist[note_pc]>>1):hist[note_pc])>79)hist[note_pc]<=127;
                    else hist[note_pc]<=(step_tick?(hist[note_pc]>>1):hist[note_pc])+48;
                    last_pc<=note_pc;velocity<=observe_data[6:0];
                end else if(note_off&&held[observe_data[14:8]])begin
                    held[observe_data[14:8]]<=0;held_count<=held_count-1'b1;
                end
                if(infer_done)begin
                    previous_action<=decision;decisions<=decisions+1'b1;
                    if(decision==0)begin if(active)off_pending<=1;end
                    else if(decision>=2)begin
                        if(active)off_pending<=1;
                        wanted_note<=bass_note(decision,snapshot_root,snapshot_minor);on_pending<=1;
                    end
                end
            end
        end
    end
endmodule

// One held output slot and fair arbitration. LIVE preserves its brightness
// metadata and waits for at most one competing event, never for inference.
module ai_midi_merge(
    input wire clk,reset_n,
    input wire [31:0] live_data,input wire [6:0] live_brightness,
    input wire live_valid,output wire live_ready,
    input wire [31:0] ai_data,input wire ai_valid,output wire ai_ready,
    output reg [31:0] out_data,output reg [6:0] out_brightness,
    output reg out_valid,input wire out_ready
);
    reg last_live;
    wire available=!out_valid||out_ready;
    wire choose_ai=ai_valid&&(!live_valid||last_live);
    assign live_ready=available&&!choose_ai;
    assign ai_ready=available&&choose_ai;
    always @(posedge clk)begin
        if(!reset_n)begin last_live<=0;out_valid<=0;out_data<=0;out_brightness<=0;end
        else if(available)begin
            out_valid<=choose_ai?ai_valid:live_valid;
            if(choose_ai)begin out_data<=ai_data;out_brightness<=ai_data[6:0];last_live<=0;end
            else if(live_valid)begin out_data<=live_data;out_brightness<=live_brightness;last_live<=1;end
        end
    end
endmodule
