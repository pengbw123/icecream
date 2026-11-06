`timescale 1ns/1ps
// Full user MIDI mapped by the Android implementation. UART framing and the
// real FM core are covered separately by tb_key_plan_top; this test drives
// the decoded App frames into the production player and physical-key router.
module tb_key_plan_full;
    localparam integer N=1690;
    reg clk=0;always #5 clk=~clk;reg reset_n=0;
    reg cmd_valid=0;reg [7:0] command=0;reg [63:0] payload=0;
    wire done,error,playing,flushing,loaded,mapped;
    wire [31:0] guide_event;wire guide_valid;wire [127:0] guide_mask;
    wire [6:0] first_key;wire [24:0] target_valid;wire [174:0] target_notes;
    reg [31:0] key_data=0;reg key_valid=0;wire key_ready;
    wire [31:0] sound_data;wire sound_valid,router_busy;
    wire fresh=key_valid&&key_ready&&key_data[23:20]==4'h9&&key_data[6:0]!=0;
    score_player #(.CLK_HZ(10000),.RAM_DEPTH(2048),.MAX_EVENTS(2048),.ENABLE_KEY_PLAN(1)) player(
        .clk(clk),.reset_n(reset_n),.cmd_valid(cmd_valid),.cmd_command(command),.cmd_payload(payload),.score_done(done),.score_error(error),
        .midi_event_data(guide_event),.midi_event_valid(guide_valid),.midi_event_ready(1'b1),
        .volume_event_data(),.volume_event_valid(),.volume_event_ready(1'b1),
        .fresh_key_valid(fresh),.fresh_key_note(key_data[14:8]),.key_plan_allowed(1'b1),
        .key_plan_active(mapped),.key_plan_first(first_key),.key_plan_valid(target_valid),.key_plan_notes(target_notes),
        .guide_count_in(),.guide_beat_active(),.guide_mask(guide_mask),.loaded(loaded),.playing(playing),.flush_active(flushing),.upload_crc32());
    score_key_router router(.clk(clk),.reset_n(reset_n),.enabled(mapped),.first_key(first_key),
        .target_valid(target_valid),.target_notes(target_notes),.disconnect(1'b0),
        .in_data(key_data),.in_valid(key_valid),.in_ready(key_ready),.out_data(sound_data),.out_valid(sound_valid),.out_ready(1'b1),.busy(router_busy));
    reg [95:0] frames[0:N+1];
    reg [24:0] physical_held=0,voice_held=0;reg [6:0] voice_pitch[0:24];
    integer checked=0,on_count=0,off_count=0,overlap_seen=0;
    integer idx,k,expected_key,expected_pitch;reg expected_on;
    always @(posedge clk)begin
        if(reset_n&&sound_valid)begin
            if(checked>=N)$fatal(1,"extra key event");
            expected_key=frames[checked+1][60+:5];expected_pitch=frames[checked+1][72+:8];expected_on=frames[checked+1][80+:8]!=0;
            idx={sound_data[16],sound_data[27:24]};
            if(!sound_data[29]||idx!=expected_key||sound_data[14:8]!=expected_pitch||
               (sound_data[23:20]!=(expected_on?4'h9:4'h8)))
                $fatal(1,"event %0d actual key=%0d pitch=%0d status=%h expected key=%0d pitch=%0d on=%b",
                    checked,idx,sound_data[14:8],sound_data[23:20],expected_key,expected_pitch,expected_on);
            if(expected_on)begin
                if(voice_held[idx])$fatal(1,"physical key allocated twice");
                for(k=0;k<25;k++)if(voice_held[k]&&voice_pitch[k]==expected_pitch)overlap_seen=overlap_seen+1;
                voice_held[idx]=1;voice_pitch[idx]=expected_pitch;on_count++;
            end else begin
                if(!voice_held[idx]||voice_pitch[idx]!=expected_pitch)$fatal(1,"wrong voice released");
                voice_held[idx]=0;off_count++;
            end
            checked++;
        end
    end
    task automatic tick;@(posedge clk);#1;endtask
    task automatic send_frame(input int pos);
        @(negedge clk);command=frames[pos][16+:8];payload=frames[pos][24+:64];cmd_valid=1;
        @(negedge clk);cmd_valid=0;
        while(!done&&!error)tick();if(error)$fatal(1,"App upload frame %0d rejected",pos);
        tick();
    endtask
    task automatic play_key(input int key,input bit down);
        @(negedge clk);key_data={8'd0,down?8'h90:8'h80,8'(48+key),down?8'd80:8'd0};key_valid=1;
        while(!key_ready)tick();tick();
        @(negedge clk);key_valid=0;physical_held[key]=down;
    endtask
    integer steps,pick;bit down;
    initial begin
        $readmemh("sim/app_huahai_keyplan.mem",frames);repeat(5)tick();@(negedge clk);reset_n=1;
        for(int i=0;i<N+2;i++)send_frame(i);
        if(!loaded)$fatal(1,"score not sealed");
        @(negedge clk);command='h5a;payload={24'h315047,16'd500,8'd0,8'd1,8'd100};cmd_valid=1;
        @(negedge clk);cmd_valid=0;while(!done&&!error)tick();if(error)$fatal(1,"mapped practice start rejected");
        steps=0;
        while(playing||flushing||(|physical_held)||router_busy||sound_valid)begin
            tick();pick=-1;down=0;
            for(int i=0;i<25;i++)if(pick<0&&target_valid[i]!=physical_held[i])begin pick=i;down=target_valid[i];end
            if(pick>=0)play_key(pick,down);
            steps++;if(steps>1000000)$fatal(1,"score did not finish: checked=%0d target=%h held=%h",checked,target_valid,physical_held);
        end
        repeat(5)tick();
        if(checked!=N||on_count!=845||off_count!=845||voice_held!=0||overlap_seen<7)
            $fatal(1,"incomplete score checked=%0d on=%0d off=%0d held=%h overlap=%0d",checked,on_count,off_count,voice_held,overlap_seen);
        $display("KEY_PLAN_FULL_OK App frames=%0d on=%0d off=%0d overlapping_unisons=%0d",N+2,on_count,off_count,overlap_seen);$finish;
    end
    initial begin #20000000;$fatal(1,"full model timeout");end
endmodule
