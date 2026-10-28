// Interactive lead composer. Transport and inference stay entirely in RTL.
// Aux 3c0 session/commit, 3c1/2 period shadow, 3c3 key/minor/form,
// 3c4 density/direction, 3c5 one-shot action, 3c6 variation/output strength.
module ai_melody_composer #(parameter integer CLOCKS_PER_US=50, GESTURE_ENABLED=0)(
    input wire clk,reset_n,cfg_write,input wire [9:0] cfg_address,input wire [15:0] cfg_value,
    input wire suspend,input wire [31:0] observe_data,input wire observe_valid,
    output wire consume_input,output reg [31:0] out_data,output reg out_valid,input wire out_ready,
    output reg [31:0] status,detail,
    input wire gesture_valid,input wire [3:0] gesture_action,
    output wire gesture_ready,gesture_allowed,gesture_cancel
);
    reg session,running,theme_recording,learning,panic_latched,start_wait;
    reg [31:0] period_shadow,step_us,remaining;
    reg [7:0] us_div;
    wire us_tick=us_div==CLOCKS_PER_US-1;
    wire step_tick=((running&&!start_wait)||record_mode!=0)&&remaining==0;
    reg [3:0] key;reg minor;reg [1:0] form;
    reg [6:0] density,direction,variation,strength;
    reg [6:0] seed[0:7];reg [3:0] seed_count;reg [3:0] seed_key;
    reg [2:0] motif_cursor;
    reg [6:0] pad_note[0:7];reg [3:0] pad_channel[0:7];reg [7:0] pad_valid;
    reg [2:0] learn_index;
    wire human=observe_data[31:28]==0;
    wire note_event=human&&(observe_data[23:20]==9||observe_data[23:20]==8);
    wire note_on=human&&observe_data[23:20]==9&&observe_data[6:0]!=0;
    wire panic=observe_valid&&human&&observe_data[23:20]==11&&(observe_data[14:8]==120||observe_data[14:8]==123);
    reg pad_match;reg [2:0] pad_index;integer p;
    always @*begin
        pad_match=0;pad_index=0;
        for(integer j=0;j<8;j=j+1)if(pad_valid[j]&&observe_data[14:8]==pad_note[j]&&observe_data[19:16]==pad_channel[j])begin pad_match=1;pad_index=j;end
    end
    // Only onset packets are swallowed. Unmatched NoteOff safely reaches LIVE,
    // including a key already held before entering this mode.
    assign consume_input=session&&note_on&&(learning||pad_match||observe_data[19:16]==9);
    wire pad_on=observe_valid&&note_on&&(pad_match||observe_data[19:16]==9);
    reg [3:0] pad_action;
    always @*case(pad_index)
        0:pad_action=1;1:pad_action=4;2:pad_action=5;3:pad_action=6;
        4:pad_action=7;5:pad_action=8;6:pad_action=10;default:pad_action=11;
    endcase
    wire manual_cfg=cfg_write&&(cfg_address==10'h3c5||cfg_address==10'h3c0);
    wire manual_pad=session&&pad_on&&pad_match&&!learning&&record_mode==0;
    assign gesture_allowed=GESTURE_ENABLED&&session&&!suspend&&!panic_latched&&
        !panic&&!learning&&!theme_recording&&record_mode==0;
    assign gesture_cancel=GESTURE_ENABLED&&(manual_cfg||manual_pad||panic);
    // Drop obsolete pending gestures when a manual command wins. Only 2/3/4
    // are exposed; a palm held while already playing must not restart a phrase.
    assign gesture_ready=GESTURE_ENABLED&&(gesture_cancel||gesture_allowed&&!cfg_write);
    wire external_action=GESTURE_ENABLED&&gesture_valid&&gesture_ready&&!gesture_cancel;
    wire [3:0] decoded_action=(cfg_write&&cfg_address==10'h3c5) ? cfg_value[3:0] :
        manual_pad ? pad_action : external_action ?
        (gesture_action==2 ? (running?4'd0:4'd2) : gesture_action==3 ? 4'd3 :
        gesture_action==4&&running ? 4'd4 : 4'd0) : 4'd0;
    // Terminate the eight-pad associative match/priority chain before it
    // fans out to phrase/transport registers. One clock (20ns) only.
    reg [3:0] action_q;
    always @(posedge clk)begin
        if(!reset_n)action_q<=0;
        else action_q<=decoded_action;
    end
    wire [3:0] action=action_q;
    reg [1:0] record_mode;reg [5:0] record_step;reg record_resume;
    reg [31:0] rhythm_mask;reg rhythm_valid;
    reg [5:0] step_index;
    reg locked,lock_pending,repeat_pending,replaying,completed,write_bank,completed_bank,play_bank;
    reg contrast_pending,contrast_active,ending;
    reg [3:0] end_count;
    reg [15:0] phrase[0:127] /* synthesis syn_ramstyle="block_ram" */;
    reg [6:0] history_pitch[0:31];reg [1:0] history_action[0:15];
    reg [6:0] last_note,last_velocity;reg [2:0] same_count;
    reg [15:0] rng,misses;
    reg [4:0] variation_steps;
    reg [15:0] snap_rng;
    reg [7:0] epoch;
    reg [2:0] work;
    reg [6:0] feature_index;
    reg infer_start;
    wire infer_busy,infer_done;wire [1:0] articulation,gate_class,dynamic_class;
    wire [4:0] interval_class,interval_alt;wire [15:0] infer_cycles;
    reg [7:0] snap_epoch;
    reg snap_minor,snap_contrast,snap_ending,snap_replay,snap_write_bank;
    reg [5:0] snap_step;reg [3:0] snap_key,snap_count,snap_seed_key;
    reg [1:0] snap_form;reg [6:0] snap_density,snap_direction,snap_variation,snap_strength,snap_last,snap_velocity,snap_seed;
    reg [2:0] snap_same;
    reg [15:0] replay_word;
    reg [7:0] feature_value;
    integer fv,idx,delta,candidate,gate_value,vel_value;
    always @*begin
        fv=0;idx=0;
        if(feature_index<16)fv=snap_step[3:0]==feature_index ? 127 : 0;
        else if(feature_index<20)fv=snap_step[5:4]==feature_index-16 ? 127 : 0;
        else if(feature_index<36)fv=history_pitch[feature_index-20];
        else if(feature_index<52)fv=history_action[feature_index-36]==2 ? 127 : 0;
        else if(feature_index<68)fv=history_action[feature_index-52]*63;
        else if(feature_index<76)begin
            idx=feature_index-68;
            if(idx<snap_count)begin fv=seed[idx]+snap_key-snap_seed_key;if(fv<48)fv=48;if(fv>84)fv=84;end
        end else if(feature_index<84)fv=rhythm_mask[(snap_step+feature_index-76)&31] ? 127 : 0;
        else if(feature_index<96)fv=snap_key==feature_index-84 ? 127 : 0;
        else case(feature_index)
            96:fv=snap_minor ? 127 : 0;
            97,98,99:fv=snap_form==feature_index-97 ? 127 : 0;
            100:fv=snap_density;101:fv=snap_direction;102:fv=snap_variation;
            103:fv=snap_count>=8 ? 127 : snap_count*16;
            104:fv=snap_last;105:fv=snap_same>=4 ? 127 : snap_same*32;
            122:fv=snap_step>=60 ? 127 : 0;123:fv=snap_contrast ? 127 : 0;
            124:fv=rhythm_valid ? 127 : 0;125:fv=snap_velocity;126:fv=snap_step*2;127:fv=127;
            default:fv=history_pitch[feature_index-90];
        endcase
        feature_value=fv[7:0];
    end
    ai_melody_inference u_policy(.clk(clk),.reset_n(reset_n),.feature_write(work==1),.feature_index(feature_index),.feature_value(feature_value),
        .start(infer_start),.busy(infer_busy),.done(infer_done),.articulation(articulation),.gate_class(gate_class),.dynamic_class(dynamic_class),
        .interval_class(interval_class),.interval_alt(interval_alt),.cycles(infer_cycles),.score_index(6'd0),.score());
    reg active,off_pending,on_pending;reg [6:0] active_note,wanted_note,wanted_velocity;
    reg [3:0] gate_left,pending_gate;
    reg [1:0] decision_action,decision_gate;
    reg [6:0] decision_velocity,raw_note,final_note;
    reg signed [6:0] interval_delta;
    reg [3:0] raw_pc;
    reg decision_cadence;
    reg [15:0] decision_word;
    wire motif_anchor=snap_step[1:0]==0&&(snap_step<32||snap_step>=48)&&!snap_contrast;
    wire required_attack=snap_density<43 ? snap_step[2:0]==0 : snap_density<85 ? snap_step[1:0]==0 : !snap_step[0];
    wire allowed_attack=snap_density<43 ? snap_step[1:0]==0 : snap_density<85 ? !snap_step[0] : 1'b1;
    wire attack=rhythm_valid ? rhythm_mask[snap_step[4:0]] : (motif_anchor||required_attack||(articulation==2&&allowed_attack));
    function [3:0] pitch_class(input [6:0] n);
        reg [6:0] v;begin v=n;if(v>=96)v=v-96;if(v>=48)v=v-48;if(v>=24)v=v-24;if(v>=12)v=v-12;pitch_class=v[3:0];end
    endfunction
    function signed [3:0] adjustment(input [3:0] pc,input m,input pent,input [6:0] n);
        begin
            adjustment=0;
            if(!pent)begin
                if(m)case(pc)1,4,6,9,11:adjustment=-1;default:adjustment=0;endcase
                else case(pc)1,3,6,8,10:adjustment=-1;default:adjustment=0;endcase
            end else if(m)case(pc)1:adjustment=-1;2:adjustment=1;4,6,8,11:adjustment=-1;9:adjustment=1;default:adjustment=0;endcase
            else case(pc)1,3,5,8,10:adjustment=-1;6:adjustment=1;11:adjustment=1;default:adjustment=0;endcase
            if(n==48&&adjustment<0)begin
                adjustment=1;
                if(pent&&((m&&(pc==1||pc==8))||(!m&&(pc==5||pc==10))))adjustment=2;
            end
            if(n==84&&adjustment>0)adjustment=-2;
        end
    endfunction
    always @*begin
        delta=((snap_rng[6:0]<snap_variation&&snap_variation>=32)||snap_same>=2) ? interval_alt : interval_class;
        delta=delta-12;
        if(snap_contrast)begin if(delta>=0)delta=delta+3;else delta=delta-3;end
        if(snap_direction>=85)begin if(delta<0)delta=-delta;if(delta==0)delta=1;end
        else if(snap_direction<=42)begin if(delta>0)delta=-delta;if(delta==0)delta=-1;end
        candidate=$signed({1'b0,snap_last})+$signed(interval_delta);
        // Keep the unsigned theme arithmetic outside this signed expression;
        // a mixed-sign ternary would zero-extend negative 7-bit intervals.
        if(motif_anchor)candidate=snap_seed+snap_key-snap_seed_key;
        // Gesture contour also moves theme anchors, but never alters held audio.
        if(motif_anchor&&snap_step!=0)begin if(snap_direction>=85)candidate=candidate+5;else if(snap_direction<=42)candidate=candidate-5;end
        if(candidate<48)candidate=48;if(candidate>84)candidate=84;
        gate_value=1<<gate_class;
        if(snap_form==0&&gate_value<4)gate_value=4;
        if(snap_form==1)gate_value=1;
        if(snap_density>=85&&gate_value>2)gate_value=2;
        case(dynamic_class)0:vel_value=48;1:vel_value=72;2:vel_value=96;default:vel_value=120;endcase
        vel_value=(vel_value*snap_strength)>>7;if(vel_value<1)vel_value=1;if(vel_value>127)vel_value=127;
        decision_word={decision_gate,decision_velocity,(decision_action==2 ? final_note : decision_action==1 ? 7'd1 : 7'd0)};
    end
    integer i;
    always @(posedge clk)begin
        if(!reset_n)begin
            session<=0;running<=0;theme_recording<=0;learning<=0;panic_latched<=0;start_wait<=0;
            period_shadow<=125000;step_us<=125000;remaining<=0;us_div<=0;
            key<=0;minor<=0;form<=0;density<=64;direction<=64;variation<=64;strength<=100;
            seed_count<=4;seed_key<=0;seed[0]<=60;seed[1]<=64;seed[2]<=67;seed[3]<=64;
            for(i=4;i<8;i=i+1)seed[i]<=60;
            motif_cursor<=0;pad_valid<=255;learn_index<=0;
            pad_note[0]<=36;pad_note[1]<=38;pad_note[2]<=42;pad_note[3]<=46;
            pad_note[4]<=49;pad_note[5]<=51;pad_note[6]<=45;pad_note[7]<=41;
            for(i=0;i<8;i=i+1)pad_channel[i]<=9;
            record_mode<=0;record_step<=0;record_resume<=0;rhythm_mask<=0;rhythm_valid<=0;
            step_index<=0;locked<=0;lock_pending<=0;repeat_pending<=0;replaying<=0;completed<=0;
            write_bank<=0;completed_bank<=0;play_bank<=0;contrast_pending<=0;contrast_active<=0;ending<=0;end_count<=0;
            for(i=0;i<32;i=i+1)history_pitch[i]<=0;
            for(i=0;i<16;i=i+1)history_action[i]<=0;
            last_note<=60;last_velocity<=96;same_count<=0;rng<=16'h7201;misses<=0;epoch<=0;variation_steps<=0;snap_rng<=16'h7201;
            work<=0;feature_index<=0;infer_start<=0;snap_epoch<=0;snap_step<=0;snap_key<=0;snap_minor<=0;snap_form<=0;
            snap_count<=4;snap_seed_key<=0;snap_density<=64;snap_direction<=64;snap_variation<=64;snap_strength<=100;
            snap_last<=60;snap_velocity<=96;snap_seed<=60;snap_same<=0;snap_contrast<=0;snap_ending<=0;snap_replay<=0;snap_write_bank<=0;replay_word<=0;
            active<=0;off_pending<=0;on_pending<=0;active_note<=0;wanted_note<=0;wanted_velocity<=96;gate_left<=0;pending_gate<=1;
            out_data<=0;out_valid<=0;decision_action<=0;decision_gate<=0;decision_velocity<=96;raw_note<=60;raw_pc<=0;final_note<=60;decision_cadence<=0;interval_delta<=0;
            status<=0;detail<=0;
        end else begin
            infer_start<=0;
            if(start_wait&&!infer_busy&&work==0&&!infer_start)start_wait<=0;
            status<={learn_index,active_note,(record_mode!=0 ? record_step : step_index),seed_count,panic_latched,rhythm_valid,ending,lock_pending,locked,learning,record_mode!=0,theme_recording,
                infer_busy||work!=0,active||out_valid||off_pending||on_pending,running,session};
            detail<={record_mode,direction,density,misses};
            if(us_tick)begin us_div<=0;if(remaining!=0)remaining<=remaining-1'b1;end else us_div<=us_div+1'b1;
            if(cfg_write)case(cfg_address)
                10'h3c0:begin session<=cfg_value[0];step_us<=period_shadow<10000 ? 10000 : period_shadow>1000000 ? 1000000 : period_shadow;end
                10'h3c1:period_shadow[15:0]<=cfg_value;
                10'h3c2:period_shadow[31:16]<=cfg_value;
                10'h3c3:begin key<=cfg_value[3:0]>11 ? 11 : cfg_value[3:0];minor<=cfg_value[4];form<=cfg_value[6:5]>2 ? 2 : cfg_value[6:5];end
                10'h3c4:begin density<=cfg_value[6:0];direction<=cfg_value[14:8];end
                10'h3c6:begin variation<=cfg_value[6:0];strength<=cfg_value[14:8]==0 ? 1 : cfg_value[14:8];end
            endcase
            if(out_valid&&out_ready)begin
                out_valid<=0;
                if(out_data[23:20]==9)begin active<=1;active_note<=out_data[14:8];gate_left<=pending_gate;end
                else active<=0;
            end
            if(!out_valid)begin
                if(off_pending)begin
                    if(active)begin out_data<=32'h40800000|({25'd0,active_note}<<8);out_valid<=1;end
                    off_pending<=0;
                end else if(on_pending&&running&&record_mode==0)begin
                    out_data<=32'h40900000|({25'd0,wanted_note}<<8)|wanted_velocity;out_valid<=1;on_pending<=0;
                end
            end
            if(work==1)begin
                if(feature_index==127)begin infer_start<=1;work<=2;end else feature_index<=feature_index+1'b1;
            end else if(work==2&&infer_done)begin
                if(snap_epoch!=epoch||!running)work<=0;
                else begin
                    // Previous STA: variation selection through contour/add/
                    // clamp was the 19.9ns critical path. Split it here; all
                    // snapshots remain immutable, adding only 20ns latency.
                    interval_delta<=delta[6:0];decision_action<=attack ? 2 : articulation==1&&active ? 1 : 0;
                    decision_gate<=gate_value>=8 ? 3 : gate_value>=4 ? 2 : gate_value>=2 ? 1 : 0;
                    decision_velocity<=vel_value[6:0];decision_cadence<=0;
                    work<=6;
                end
            end else if(work==6)begin
                raw_note<=candidate[6:0];
                if(snap_ending&&snap_step==60)begin raw_note<=60+snap_key;decision_action<=2;decision_gate<=2;decision_cadence<=1;end
                work<=3;
            end else if(work==3)begin
                raw_pc<=pitch_class(raw_note>=snap_key ? raw_note-snap_key : raw_note+12-snap_key);work<=4;
            end else if(work==4)begin
                // Split pitch conversion from interval selection and scheduling.
                final_note<=$signed({1'b0,raw_note})+$signed(adjustment(raw_pc,snap_minor,snap_form==2,raw_note));work<=5;
            end else if(work==5)begin
                work<=0;
                if(snap_epoch==epoch&&running&&!suspend&&record_mode==0)begin
                    if(snap_replay)begin
                        decision_action<=replay_word[6:0]>=48 ? 2 : replay_word[6:0]==1 ? 1 : 0;
                    end
                    // Replay uses the stored word, including velocity and gate.
                    if((snap_replay ? replay_word[6:0]>=48 : decision_action==2))begin
                        if(active)off_pending<=1;
                        wanted_note<=snap_replay ? replay_word[6:0] : final_note;
                        wanted_velocity<=snap_replay ? replay_word[13:7] : decision_velocity;
                        pending_gate<=1<<(snap_replay ? replay_word[15:14] : decision_gate);on_pending<=1;
                        last_note<=snap_replay ? replay_word[6:0] : final_note;
                        last_velocity<=snap_replay ? replay_word[13:7] : decision_velocity;
                        same_count<=(snap_replay ? replay_word[6:0] : final_note)==last_note ? (same_count==7 ? 7 : same_count+1'b1) : 0;
                        if(motif_anchor&&!snap_replay)motif_cursor<=motif_cursor+1>=seed_count ? 0 : motif_cursor+1'b1;
                    end else if((snap_replay ? replay_word[6:0]==0 : decision_action==0)&&active)off_pending<=1;
                    for(i=31;i>0;i=i-1)history_pitch[i]<=history_pitch[i-1];
                    for(i=15;i>0;i=i-1)history_action[i]<=history_action[i-1];
                    history_pitch[0]<=snap_replay ? (replay_word[6:0]>=48 ? replay_word[6:0] : replay_word[6:0]==1 ? last_note : 0) : decision_action==2 ? final_note : decision_action==1 ? last_note : 0;
                    history_action[0]<=snap_replay ? (replay_word[6:0]>=48 ? 2 : replay_word[6:0]==1 ? 1 : 0) : decision_action;
                    // Mirror replay as well: a live VAR/UNLOCK halfway through
                    // a loop must leave a complete prefix in the write bank.
                    phrase[{snap_write_bank,snap_step}]<=snap_replay ? replay_word : decision_word;
                    if(decision_cadence&&!snap_replay)end_count<=4;
                    if(snap_step==63)begin
                        completed<=1;completed_bank<=snap_write_bank;write_bank<=!snap_write_bank;
                        if(lock_pending||repeat_pending)begin
                            play_bank<=snap_write_bank;locked<=locked||lock_pending;replaying<=1;lock_pending<=0;repeat_pending<=0;
                        end else if(!locked)replaying<=0;
                    end
                end
            end
            if(step_tick)begin
                remaining<=step_us-1'b1;
                if(record_mode==1)begin
                    if(record_step==16)begin record_mode<=2;record_step<=0;end else record_step<=record_step+1'b1;
                end else if(record_mode==2)begin
                    if(record_step==31)begin record_mode<=0;rhythm_valid<=rhythm_mask!=0;running<=record_resume;step_index<=0;remaining<=step_us-1'b1;end
                    else record_step<=record_step+1'b1;
                end else if(running)begin
                    if(active&&gate_left!=0)begin gate_left<=gate_left-1'b1;if(gate_left==1)off_pending<=1;end
                    if(end_count!=0)begin
                        end_count<=end_count-1'b1;
                        if(end_count==1)begin running<=0;ending<=0;on_pending<=0;off_pending<=1;end
                    end else if(!infer_busy&&work==0&&!infer_start&&!on_pending&&!off_pending&&!out_valid)begin
                        snap_epoch<=epoch;snap_step<=step_index;snap_key<=key;snap_minor<=minor;snap_form<=form;snap_count<=seed_count;snap_seed_key<=seed_key;
                        snap_density<=density;snap_direction<=direction;snap_variation<=variation_steps!=0&&variation<96 ? 96 : variation;snap_strength<=strength;snap_last<=last_note;snap_velocity<=last_velocity;snap_rng<=rng;
                        snap_same<=same_count;snap_seed<=seed[(step_index==0||step_index==48) ? 0 : motif_cursor];snap_ending<=ending;
                        snap_contrast<=(step_index[3:0]==0 ? contrast_pending : contrast_active)||step_index[5:4]==2;snap_write_bank<=write_bank;
                        snap_replay<=replaying&&!ending;
                        if(replaying&&!ending)begin replay_word<=phrase[{play_bank,step_index}];decision_cadence<=0;work<=5;end
                        else begin feature_index<=0;work<=1;end
                        if(step_index==0||step_index==48)motif_cursor<=0;
                        if(step_index[3:0]==0)begin contrast_active<=contrast_pending;contrast_pending<=0;end
                        step_index<=step_index+1'b1;
                        if(variation_steps!=0)variation_steps<=variation_steps-1'b1;
                        rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};
                    end else if(misses!=65535)misses<=misses+1'b1;
                end
            end
            if(observe_valid&&note_on&&session)begin
                if(learning)begin
                    if(!pad_match)begin
                        pad_note[learn_index]<=observe_data[14:8];pad_channel[learn_index]<=observe_data[19:16];pad_valid[learn_index]<=1;
                        if(learn_index==7)learning<=0;else learn_index<=learn_index+1'b1;
                    end
                end else if(record_mode==2&&pad_on)rhythm_mask[record_step[4:0]]<=1;
                else if(theme_recording&&!pad_match&&observe_data[19:16]!=9&&seed_count<8)begin seed[seed_count]<=observe_data[14:8];seed_count<=seed_count+1'b1;end
            end
            if(action!=0&&session&&!suspend)case(action)
                1,2,14:begin
                    if(action==1&&running)begin running<=0;on_pending<=0;epoch<=epoch+1'b1;end
                    else begin
                        running<=1;start_wait<=1;theme_recording<=0;learning<=0;panic_latched<=0;record_mode<=0;step_index<=0;remaining<=0;epoch<=epoch+1'b1;
                        motif_cursor<=0;end_count<=0;ending<=0;lock_pending<=0;repeat_pending<=0;contrast_pending<=0;contrast_active<=0;
                        if(locked&&action!=14)begin locked<=1;replaying<=1;end else begin locked<=0;replaying<=0;end
                        same_count<=0;last_note<=60+key;on_pending<=0;
                        for(i=0;i<32;i=i+1)history_pitch[i]<=0;
                        for(i=0;i<16;i=i+1)history_action[i]<=0;
                        if(seed_count==0)begin seed_count<=4;seed_key<=0;seed[0]<=60;seed[1]<=64;seed[2]<=67;seed[3]<=64;end
                    end
                end
                3:begin running<=0;record_mode<=0;theme_recording<=0;learning<=0;on_pending<=0;epoch<=epoch+1'b1;ending<=0;end_count<=0;end
                4:begin rng<=rng^16'h9e37;variation_steps<=16;locked<=0;lock_pending<=0;replaying<=0;end
                5:begin repeat_pending<=1;end
                6:begin contrast_pending<=1;locked<=0;lock_pending<=0;replaying<=0;end
                7:begin if(running)begin ending<=1;locked<=0;lock_pending<=0;repeat_pending<=0;replaying<=0;end end
                8:begin if(locked||lock_pending)begin locked<=0;lock_pending<=0;replaying<=0;repeat_pending<=0;end else lock_pending<=1;end
                9:begin
                    running<=0;record_mode<=0;learning<=0;on_pending<=0;epoch<=epoch+1'b1;
                    theme_recording<=!theme_recording;
                    if(!theme_recording)begin seed_count<=0;seed_key<=key;end
                end
                10:begin record_resume<=running;running<=0;record_mode<=1;record_step<=0;remaining<=0;rhythm_mask<=0;rhythm_valid<=0;theme_recording<=0;learning<=0;on_pending<=0;epoch<=epoch+1'b1;end
                11:begin rhythm_mask<=0;rhythm_valid<=0;record_mode<=0;end
                12:begin learning<=1;learn_index<=0;pad_valid<=0;running<=0;record_mode<=0;theme_recording<=0;on_pending<=0;epoch<=epoch+1'b1;end
                13:begin seed_count<=4;seed_key<=0;seed[0]<=60;seed[1]<=64;seed[2]<=67;seed[3]<=64;theme_recording<=0;end
                // Screen TAP is independent of the user-learned pad map and
                // never injects a synthetic key/pad event into LIVE or LEARN.
                15:begin if(record_mode==2)rhythm_mask[record_step[4:0]]<=1;end
                default:begin end
            endcase
            if(!session||suspend||panic)begin
                running<=0;record_mode<=0;theme_recording<=0;learning<=0;on_pending<=0;remaining<=0;
                locked<=0;lock_pending<=0;repeat_pending<=0;replaying<=0;ending<=0;end_count<=0;
                if(panic&&session)panic_latched<=1;
            end
            if(!running||record_mode!=0||suspend||!session||panic||action==3||action==9||action==10||action==12)begin
                if(active||(out_valid&&out_data[23:20]==9))off_pending<=1;
            end
        end
    end
endmodule
