// Interactive V2: causal player history, left-hand harmony and four-head policy.
// 0x3f3 shadow: split[14:8], bit1 adaptive expression, bit0 follow activity.
// 0x3f0 commits all shadows: bit3 left-hand harmony, bit2 loop, legacy bits same.
module ai_bass_accompaniment #(parameter integer CLOCKS_PER_US=50)(
    input wire clk,reset_n,cfg_write,input wire [9:0] cfg_address,input wire [15:0] cfg_value,
    input wire suspend,input wire [31:0] observe_data,input wire observe_valid,
    output reg [31:0] out_data,output reg out_valid,input wire out_ready,output wire [31:0] status
);
    reg [15:0] config_word,settings_shadow,settings;
    reg [31:0] period_shadow,step_us;
    reg panic_latched;
    wire enabled=config_word[0]&&!suspend&&!panic_latched;
    wire follow_harmony=config_word[3],adaptive=settings[1],follow_activity=settings[0];
    wire [6:0] split=settings[14:8];
    wire human=observe_valid&&observe_data[31:28]==0&&observe_data[19:16]!=9;
    wire note_on=human&&observe_data[23:20]==9&&observe_data[6:0]!=0;
    wire note_off=human&&(observe_data[23:20]==8||(observe_data[23:20]==9&&observe_data[6:0]==0));
    wire pedal_event=human&&observe_data[23:20]==11&&observe_data[14:8]==64;
    wire panic=human&&observe_data[23:20]==11&&(observe_data[14:8]==120||observe_data[14:8]==123);
    wire [6:0] note=observe_data[14:8];
    function [3:0] pc(input [6:0] n);
        reg [6:0] v;begin v=n;if(v>=96)v=v-96;if(v>=48)v=v-48;if(v>=24)v=v-24;if(v>=12)v=v-12;pc=v[3:0];end
    endfunction
    wire [3:0] note_pc=pc(note);
    reg [127:0] physical,held;
    reg pedal,armed,seen_lead;
    reg [6:0] idle_age;
    wire play_active=enabled&&(!follow_activity||armed);
    wire lead_on=note_on&&(!follow_harmony||note>=split);
    reg [7:0] us_div;
    wire us_tick=us_div==CLOCKS_PER_US-1;
    reg [31:0] remaining,age_us;
    wire sub_tick=us_tick&&age_us==0;
    reg [3:0] phase;reg [1:0] chord_slot;
    wire [4:0] root_sum={1'b0,config_word[7:4]}+(!config_word[2] ? 0:chord_slot==1 ? 9:chord_slot==2 ? 5:chord_slot==3 ? 7:0);
    wire [3:0] manual_root=root_sum>=12 ? root_sum-12:root_sum;
    wire manual_minor=config_word[2] ? (chord_slot==1):config_word[8];
    wire [3:0] lh_root;wire lh_minor,lh_present,lh_ready;
    ai_harmony_tracker u_harmony(.clk(clk),.reset_n(reset_n),.enable(enabled&&follow_harmony),
        .held(held),.split(split),.changed(note_on||note_off||pedal_event),
        .new_left_note(note_on&&note<split),
        .fallback_root(config_word[7:4]),.fallback_minor(config_word[8]),
        .root(lh_root),.minor(lh_minor),.present(lh_present),.ready(lh_ready));
    wire step_tick=play_active&&remaining==0&&(!follow_harmony||lh_ready);
    wire [3:0] root=follow_harmony ? lh_root:manual_root;
    wire minor=follow_harmony ? lh_minor:manual_minor;
    reg [6:0] hist[0:11],history[0:14],onsets,last_velocity,silence;
    reg [6:0] rec_note[0:7],rec_age[0:7],rec_duration[0:7],rec_ioi[0:7],rec_velocity[0:7];
    reg [7:0] rec_gate;
    reg [6:0] onset_age;
    reg [7:0] snapshot[0:95];
    reg [2:0] build_state;reg [6:0] build_index,scan_index;reg [3:0] lead_count;
    reg [3:0] scan_pc,snapshot_root,snapshot_phase,previous_root;
    reg snapshot_minor,previous_minor,snapshot_changed,snapshot_dense,snapshot_left,scan_follow;
    reg [127:0] held_scan;
    reg [6:0] scan_split;
    reg infer_start;
    wire infer_busy,infer_done;wire [2:0] infer_action,degree;
    wire [1:0] articulation,gate_class,dynamic_class;wire [15:0] infer_cycles;
    ai_bass_inference u_policy(.clk(clk),.reset_n(reset_n),
        .feature_write(build_state==3),.feature_index(build_index),.feature_value(snapshot[build_index]),
        .start(infer_start),.busy(infer_busy),.done(infer_done),.action(infer_action),
        .articulation(articulation),.degree(degree),.gate_class(gate_class),.dynamic_class(dynamic_class),
        .cycles(infer_cycles),.score_index(5'd0),.score());
    reg active,off_pending,on_pending;
    reg [6:0] active_note,wanted_note,wanted_velocity,pending_gate,gate_left;
    reg [3:0] steps_since_attack;
    reg [15:0] misses;reg [31:0] decisions;
    wire beat_anchor=snapshot_phase[1:0]==0;
    wire recent_onset=snapshot[40]!=0;
    wire allow_attack=config_word[1] ? beat_anchor:snapshot_dense ? !snapshot_phase[0]:
                      (beat_anchor||(snapshot[46]!=0&&snapshot_phase[0]));
    // Explicit rhythm contract: quarter-note anchors; dense playing may answer
    // on eighths. The trained heads choose degree, articulation, gate/dynamics.
    wire anchor=beat_anchor&&(steps_since_attack>=4||snapshot_phase==0);
    wire answer=recent_onset&&(snapshot_dense ? !snapshot_phase[0]:beat_anchor);
    wire attack=snapshot_changed||anchor||answer||(articulation==2&&allow_attack);
    wire [2:0] chosen_degree=(snapshot_changed||snapshot_phase==0) ? 0:
        (degree==5&&snapshot_phase[1:0]!=3) ? 2:degree;
    function [6:0] bass_note(input [2:0] d,input [3:0] r,input m);
        begin case(d)1:bass_note=36+r+(m ? 3:4);2:bass_note=43+r;3:bass_note=48+r;
            4:bass_note=31+r;5:bass_note=35+r;default:bass_note=36+r;endcase end
    endfunction
    reg [6:0] learned_gate,chosen_gate,learned_velocity;
    reg [8:0] velocity_mix;reg [15:0] velocity_product;reg [6:0] chosen_velocity;
    always @*begin
        case(gate_class)0:learned_gate=4;1:learned_gate=8;2:learned_gate=24;default:learned_gate=64;endcase
        case(dynamic_class)0:learned_velocity=40;1:learned_velocity=64;2:learned_velocity=88;default:learned_velocity=112;endcase
        chosen_gate=learned_gate;
        if(adaptive)begin
            if(snapshot_dense)begin if(chosen_gate>8)chosen_gate=8;end
            else if(snapshot[45]!=0||(snapshot_left&&snapshot[48]==0))begin if(chosen_gate<24)chosen_gate=24;end
            else if(chosen_gate>4)chosen_gate=4;
        end
        velocity_mix=({2'b0,snapshot[44][6:0]}<<1)+snapshot[44][6:0]+learned_velocity;
        velocity_product=(velocity_mix>>2)*(config_word[15:9]==0 ? 7'd70:config_word[15:9]);
        chosen_velocity=!adaptive ? (config_word[15:9]==0 ? 7'd70:config_word[15:9]):
            velocity_product>=16'd8128 ? 7'd127:velocity_product<64 ? 7'd1:velocity_product[12:6];
    end
    // V2 telemetry: version[15:13], pedal12, dense11, LH10, playing9,
    // minor8, actual root[7:4], legacy panic/busy/event/enabled[3:0].
    // Register before the soft-core MMIO decoder, keeping telemetry off the
    // real-time control critical paths.
    reg [31:0] status_q;
    always @(posedge clk)
        if(!reset_n)status_q<=0;
        else status_q<={misses,3'd2,pedal,snapshot_dense,follow_harmony,play_active,minor,root,panic_latched,
            infer_busy||(build_state!=0)||infer_start,active||out_valid||off_pending||on_pending,enabled};
    assign status=status_q;
    integer i,rot,total;
    always @(posedge clk)begin
        if(!reset_n)begin
            config_word<=0;settings_shadow<=16'h3c00;settings<=16'h3c00;period_shadow<=125000;step_us<=125000;
            panic_latched<=0;physical<=0;held<=0;pedal<=0;armed<=0;seen_lead<=0;idle_age<=0;
            us_div<=0;remaining<=0;age_us<=0;phase<=0;chord_slot<=0;
            onsets<=0;last_velocity<=70;silence<=15;rec_gate<=0;onset_age<=127;
            build_state<=0;build_index<=0;scan_index<=0;lead_count<=0;scan_pc<=0;held_scan<=0;scan_split<=60;
            snapshot_root<=0;snapshot_phase<=0;previous_root<=15;snapshot_minor<=0;previous_minor<=0;
            snapshot_changed<=0;snapshot_dense<=0;snapshot_left<=0;scan_follow<=0;infer_start<=0;
            out_data<=0;out_valid<=0;active<=0;off_pending<=0;on_pending<=0;active_note<=0;wanted_note<=0;wanted_velocity<=70;
            pending_gate<=8;gate_left<=0;steps_since_attack<=15;misses<=0;decisions<=0;
            for(i=0;i<12;i=i+1)hist[i]<=0;
            for(i=0;i<15;i=i+1)history[i]<=0;
            for(i=0;i<8;i=i+1)begin rec_note[i]<=0;rec_age[i]<=0;rec_duration[i]<=0;rec_ioi[i]<=0;rec_velocity[i]<=0;end
        end else begin
            infer_start<=0;
            if(cfg_write)case(cfg_address)
                10'h3f1:period_shadow[15:0]<=cfg_value;
                10'h3f2:period_shadow[31:16]<=cfg_value;
                10'h3f3:settings_shadow<={(cfg_value[14:8]<36 ? 7'd36:cfg_value[14:8]>84 ? 7'd84:cfg_value[14:8]),cfg_value[7:0]};
                10'h3f0:begin
                    config_word<={cfg_value[15:8],(cfg_value[7:4]>11 ? 4'd11:cfg_value[7:4]),cfg_value[3:0]};
                    step_us<=period_shadow<10000 ? 10000:period_shadow>1000000 ? 1000000:period_shadow;settings<=settings_shadow;
                end
            endcase
            if(!config_word[0])panic_latched<=0;else if(panic)panic_latched<=1;
            if(us_tick)begin
                us_div<=0;
                if(remaining!=0)remaining<=remaining-1'b1;
                if(age_us==0)age_us<=(step_us>>3)-1'b1;else age_us<=age_us-1'b1;
            end else us_div<=us_div+1'b1;
            if(sub_tick)begin
                if(onset_age!=127)onset_age<=onset_age+1'b1;
                for(i=0;i<8;i=i+1)if(rec_age[i]!=127)rec_age[i]<=rec_age[i]+1'b1;
                if(held!=0)idle_age<=0;else if(idle_age!=127)idle_age<=idle_age+1'b1;
                if(active&&gate_left!=0)begin gate_left<=gate_left-1'b1;if(gate_left==1)off_pending<=1;end
            end
            if(follow_activity&&idle_age>=32&&held==0)armed<=0;
            if(out_valid&&out_ready)begin
                out_valid<=0;
                if(out_data[23:20]==9)begin active<=1;active_note<=out_data[14:8];gate_left<=pending_gate;steps_since_attack<=0;end
                else if(out_data[23:20]==8)active<=0;
            end
            if(!out_valid)begin
                if(off_pending)begin
                    if(active)begin out_data<=32'h40800000|({25'd0,active_note}<<8);out_valid<=1;end
                    off_pending<=0;
                end else if(on_pending&&play_active)begin
                    out_data<=32'h40900000|({25'd0,wanted_note}<<8)|{25'd0,wanted_velocity};out_valid<=1;on_pending<=0;
                end
            end
            if(build_state==1)begin
                if(held_scan[scan_index])begin
                    rot=scan_pc>=snapshot_root ? scan_pc-snapshot_root:scan_pc+12-snapshot_root;
                    snapshot[28+rot]<=127;
                    if((!scan_follow||scan_index>=scan_split)&&lead_count<8)lead_count<=lead_count+1'b1;
                end
                scan_pc<=scan_pc==11 ? 0:scan_pc+1'b1;
                if(scan_index==127)build_state<=2;else scan_index<=scan_index+1'b1;
            end else if(build_state==2)begin
                snapshot[45]<=lead_count>=8 ? 127:lead_count*16;build_index<=0;build_state<=3;
            end else if(build_state==3)begin
                if(build_index==95)begin build_state<=0;infer_start<=1;end else build_index<=build_index+1'b1;
            end
            if(!play_active)begin
                remaining<=0;phase<=0;chord_slot<=0;on_pending<=0;
                if(active&&!off_pending&&!(out_valid&&out_data[23:20]==8))off_pending<=1;
                if(out_valid&&out_data[23:20]==9&&!out_ready)out_valid<=0;
                previous_root<=15;previous_minor<=0;steps_since_attack<=15;
            end
            if(!enabled)begin
                physical<=0;held<=0;pedal<=0;armed<=0;idle_age<=0;onsets<=0;silence<=15;last_velocity<=70;
                rec_gate<=0;onset_age<=127;seen_lead<=0;
                for(i=0;i<12;i=i+1)hist[i]<=0;
                for(i=0;i<15;i=i+1)history[i]<=0;
                for(i=0;i<8;i=i+1)begin rec_note[i]<=0;rec_age[i]<=0;rec_duration[i]<=0;rec_ioi[i]<=0;rec_velocity[i]<=0;end
            end else begin
                if(step_tick)begin
                    remaining<=step_us-1'b1;
                    if(phase==15)chord_slot<=chord_slot+1'b1;phase<=phase+1'b1;
                    if(steps_since_attack!=15)steps_since_attack<=steps_since_attack+1'b1;
                    if(!infer_busy&&build_state==0&&!infer_start&&!on_pending&&!off_pending&&!out_valid)begin
                        for(i=0;i<96;i=i+1)snapshot[i]<=0;
                        for(i=0;i<16;i=i+1)snapshot[i]<=phase==i ? 127:0;
                        for(i=0;i<12;i=i+1)begin rot=i+root;if(rot>=12)rot=rot-12;snapshot[16+i]<=hist[rot];end
                        // Training and runtime both represent the GIVEN triad,
                        // plus currently sounding performer pitch classes.
                        snapshot[28]<=127;snapshot[28+(minor ? 3:4)]<=127;snapshot[35]<=127;
                        snapshot[40]<=onsets>=6 ? 127:onsets*24;
                        for(i=0;i<3;i=i+1)snapshot[41+i]<=history[i]>=6 ? 127:history[i]*24;
                        for(i=0;i<12;i=i+1)snapshot[80+i]<=history[i+3]>=6 ? 127:history[i+3]*24;
                        snapshot[44]<=last_velocity;snapshot[46]<=onsets!=0 ? 0:silence>=15 ? 127:(silence+1)*8;
                        snapshot[47]<=minor ? 127:0;
                        for(i=0;i<8;i=i+1)begin
                            snapshot[48+i]<=rec_note[i];snapshot[56+i]<=rec_gate[i] ? rec_age[i]:rec_duration[i];
                            snapshot[64+i]<=rec_ioi[i];snapshot[72+i]<=rec_velocity[i];
                        end
                        snapshot[92]<=root!=previous_root||minor!=previous_minor ? 127:0;
                        snapshot[93]<=config_word[1] ? 127:0;snapshot[94]<=root*11;snapshot[95]<=pedal ? 127:0;
                        snapshot_root<=root;snapshot_minor<=minor;snapshot_phase<=phase;
                        snapshot_changed<=root!=previous_root||minor!=previous_minor;
                        previous_root<=root;previous_minor<=minor;snapshot_left<=follow_harmony&&lh_present;
                        total=onsets+history[0]+history[1]+history[2];snapshot_dense<=total>=3;
                        held_scan<=held;scan_index<=0;scan_pc<=0;scan_split<=split;scan_follow<=follow_harmony;lead_count<=0;build_state<=1;
                    end else if(misses!=65535)misses<=misses+1'b1;
                    for(i=14;i>0;i=i-1)history[i]<=history[i-1];history[0]<=onsets;onsets<=0;
                    silence<=onsets!=0 ? 0:silence==15 ? 15:silence+1'b1;
                    for(i=0;i<12;i=i+1)hist[i]<=hist[i]>>1;
                end
                if(note_on)begin
                    physical[note]<=1;held[note]<=1;armed<=1;idle_age<=0;last_velocity<=observe_data[6:0];
                    if(lead_on)begin
                        onsets<=step_tick ? 1:onsets>=15 ? 15:onsets+1'b1;
                        hist[note_pc]<=((step_tick ? (hist[note_pc]>>1):hist[note_pc])>79) ? 127:
                            (step_tick ? (hist[note_pc]>>1):hist[note_pc])+48;
                        for(i=7;i>0;i=i-1)begin
                            rec_note[i]<=rec_note[i-1];rec_age[i]<=rec_age[i-1];rec_ioi[i]<=rec_ioi[i-1];rec_velocity[i]<=rec_velocity[i-1];
                            rec_gate[i]<=rec_gate[i-1]&&rec_note[i-1]!=note;
                            rec_duration[i]<=rec_note[i-1]==note ? rec_age[i-1]:rec_duration[i-1];
                        end
                        rec_note[0]<=note;rec_age[0]<=0;rec_duration[0]<=0;rec_ioi[0]<=seen_lead ? onset_age:0;seen_lead<=1;
                        rec_velocity[0]<=observe_data[6:0];rec_gate[0]<=1;onset_age<=0;
                    end
                end else if(note_off)begin
                    physical[note]<=0;if(!pedal)held[note]<=0;
                    if(!pedal)for(i=0;i<8;i=i+1)if(rec_gate[i]&&rec_note[i]==note)begin rec_gate[i]<=0;rec_duration[i]<=rec_age[i];end
                end
                if(pedal_event)begin
                    pedal<=observe_data[6];
                    if(!observe_data[6])begin
                        held<=physical;
                        for(i=0;i<8;i=i+1)if(rec_gate[i]&&!physical[rec_note[i]])begin rec_gate[i]<=0;rec_duration[i]<=rec_age[i];end
                    end
                end
                if(infer_done&&play_active)begin
                    decisions<=decisions+1'b1;
                    if(attack)begin
                        if(active)off_pending<=1;
                        wanted_note<=bass_note(chosen_degree,snapshot_root,snapshot_minor);
                        wanted_velocity<=chosen_velocity;pending_gate<=chosen_gate;on_pending<=1;
                    end else if(articulation==0&&active)off_pending<=1;
                end
            end
        end
    end
endmodule

// Serial triad recognizer, no parallel 128-key population/mux chain.
module ai_harmony_tracker(
    input wire clk,reset_n,enable,input wire [127:0] held,input wire [6:0] split,
    input wire changed,new_left_note,input wire [3:0] fallback_root,input wire fallback_minor,
    output reg [3:0] root,output reg minor,present,output wire ready
);
    reg [1:0] state;reg dirty,any_key,known,old_minor,single_request,scan_single;
    reg [127:0] keys;reg [6:0] index,old_split;
    reg [3:0] pitch,lowest,count,old_fallback,picked_root;
    reg [11:0] mask;
    reg [4:0] candidate;reg [3:0] best;reg picked_minor;
    wire [3:0] r=candidate>=12 ? candidate-12:candidate[3:0];
    wire [4:0] third_sum={1'b0,r}+(candidate>=12 ? 3:4),fifth_sum={1'b0,r}+7;
    wire [3:0] third=third_sum>=12 ? third_sum-12:third_sum,fifth=fifth_sum>=12 ? fifth_sum-12:fifth_sum;
    wire match=mask[r]&&mask[third]&&mask[fifth];
    wire [3:0] rank=1+(r==lowest ? 4:0)+(r==root ? 2:0);
    assign ready=state==0&&!dirty&&!changed&&old_split==split&&old_fallback==fallback_root&&old_minor==fallback_minor;
    always @(posedge clk)begin
        if(!reset_n)begin
            state<=0;dirty<=1;any_key<=0;known<=0;old_minor<=0;single_request<=0;scan_single<=0;keys<=0;index<=0;old_split<=60;pitch<=0;lowest<=0;count<=0;
            old_fallback<=0;picked_root<=0;mask<=0;candidate<=0;best<=0;picked_minor<=0;root<=0;minor<=0;present<=0;
        end else if(!enable)begin
            state<=0;dirty<=1;known<=0;single_request<=0;scan_single<=0;root<=fallback_root;minor<=fallback_minor;present<=0;
            old_fallback<=fallback_root;old_split<=split;old_minor<=fallback_minor;
        end else begin
            if(new_left_note)single_request<=1;
            if(changed||old_split!=split||old_fallback!=fallback_root||old_minor!=fallback_minor)dirty<=1;
            if(old_fallback!=fallback_root||old_minor!=fallback_minor)begin root<=fallback_root;minor<=fallback_minor;known<=0;old_fallback<=fallback_root;old_minor<=fallback_minor;end
            case(state)
                0:if(dirty)begin
                    keys<=held;index<=0;pitch<=0;mask<=0;count<=0;any_key<=0;state<=1;old_split<=split;
                    scan_single<=single_request;single_request<=new_left_note;
                    dirty<=changed||old_split!=split||old_fallback!=fallback_root||old_minor!=fallback_minor;
                end
                1:begin
                    if(keys[index]&&index<split)begin
                        if(!any_key)lowest<=pitch;any_key<=1;mask[pitch]<=1;
                        if(!mask[pitch])count<=count+1'b1;
                    end
                    pitch<=pitch==11 ? 0:pitch+1'b1;
                    if(index==127)state<=2;else index<=index+1'b1;
                end
                2:begin
                    present<=any_key;candidate<=0;best<=0;state<=3;
                    // Releasing a triad must retain its harmony, not reinterpret
                    // the last remaining key as a fresh bass-note chord.
                    if((count==1&&scan_single)||(!known&&any_key))begin
                        root<=lowest;if(!known||root!=lowest)minor<=fallback_minor;known<=1;
                    end
                end
                3:begin
                    if(match&&rank>best)begin best<=rank;picked_root<=r;picked_minor<=candidate>=12;end
                    if(candidate==23)begin
                        if(match&&rank>best)begin root<=r;minor<=candidate>=12;known<=1;end
                        else if(best!=0)begin root<=picked_root;minor<=picked_minor;known<=1;end
                        state<=0;
                    end else candidate<=candidate+1'b1;
                end
            endcase
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
            out_valid<=choose_ai ? ai_valid:live_valid;
            if(choose_ai)begin out_data<=ai_data;out_brightness<=ai_data[6:0];last_live<=0;end
            else if(live_valid)begin out_data<=live_data;out_brightness<=live_brightness;last_live<=1;end
        end
    end
endmodule
