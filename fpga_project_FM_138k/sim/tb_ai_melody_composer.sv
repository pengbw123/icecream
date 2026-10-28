`timescale 1ns/1ps
module tb_ai_melody_composer;
    localparam STEP=40000;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,cfg_write=0,suspend=0,observe_valid=0,out_ready=1;
    reg [9:0] cfg_address=0;reg [15:0] cfg_value=0;reg [31:0] observe_data=0;
    wire consume_input;wire [31:0] out_data,status,detail;wire out_valid;
    wire gesture_valid=1'b0;wire [3:0] gesture_action=4'd0;
    wire gesture_ready,gesture_allowed,gesture_cancel;
    ai_melody_composer #(.CLOCKS_PER_US(1)) dut(.*);
    integer ons=0,offs=0,last_on=0,held=-1,case_id=0,cycles=0,fd;
    integer attacks[0:3],pitch_sum[0:3];reg [127:0] used=0;
    reg check_rhythm=0,stalled=0;reg [31:0] stalled_word;
    reg [15:0] saved_phrase[0:63];integer changed=0;
    always @(posedge clk)if(reset_n)begin
        cycles=cycles+1;
        if(stalled&&(!out_valid||out_data!==stalled_word))$fatal(1,"Composer violated stalled output");
        stalled<=out_valid&&!out_ready;stalled_word<=out_data;
        if(out_valid&&out_ready)begin
            $fwrite(fd,"%0d,%0d,%02x,%0d,%0d\n",case_id,cycles,out_data[23:16],out_data[14:8],out_data[6:0]);
            if((^out_data)===1'bx)$fatal(1,"Unknown composer output %h",out_data);
            if(out_data[31:24]!=8'h40)$fatal(1,"Composer BACKING ownership");
            if(out_data[23:20]==9)begin
                if(held!=-1)$fatal(1,"Composer overlapped two gates");
                held=out_data[14:8];last_on=held;ons=ons+1;used[held]=1;
                if(held<48||held>84||out_data[6:0]==0)$fatal(1,"Composer pitch/velocity bounds");
                if(held%12==1||held%12==3||held%12==6||held%12==8||held%12==10)$fatal(1,"Out of C major scale %d",held);
                if(case_id<4)begin attacks[case_id]=attacks[case_id]+1;pitch_sum[case_id]=pitch_sum[case_id]+held;end
                if(check_rhythm&&!dut.rhythm_mask[dut.snap_step[4:0]])$fatal(1,"Attack outside user rhythm");
                if(dut.locked&&dut.snap_replay&&(out_data[14:8]!==dut.replay_word[6:0]||out_data[6:0]!==dut.replay_word[13:7]))$fatal(1,"LOCK output differs from stored note/velocity");
            end else if(out_data[23:20]==8)begin
                if(held!=out_data[14:8])$fatal(1,"Composer unmatched NoteOff");held=-1;offs=offs+1;
            end else $fatal(1,"Unexpected composer MIDI");
        end
    end
    task cfg(input [9:0] a,input [15:0] v);
        begin @(negedge clk);cfg_address=a;cfg_value=v;cfg_write=1;@(negedge clk);cfg_write=0;repeat(2)@(negedge clk);end
    endtask
    task cmd(input [3:0] a);begin cfg('h3c5,a);end endtask
    task midi(input [7:0] s,input [6:0] n,input [6:0] v);
        begin @(negedge clk);observe_data={8'd0,s,1'b0,n,1'b0,v};observe_valid=1;@(negedge clk);observe_valid=0;repeat(2)@(negedge clk);end
    endtask
    task setup;
        begin @(negedge clk);reset_n=0;repeat(4)@(negedge clk);reset_n=1;
            stalled=0;held=-1;ons=0;offs=0;used=0;cfg('h3c1,STEP);cfg('h3c2,0);cfg('h3c0,1);end
    endtask
    integer i,n,count;reg [31:0] mask;reg [31:0] saved_word;reg [15:0] saved_rng;
    initial begin
        fd=$fopen("tmp/ai_composer_events.csv","w");$fwrite(fd,"case,cycle,status,note,velocity\n");
        for(i=0;i<4;i=i+1)begin attacks[i]=0;pitch_sum[i]=0;end
        for(i=0;i<3;i=i+1)begin
            setup();case_id=i;
            if(i==0)cfg('h3c4,(64<<8)|20);
            if(i==1)cfg('h3c4,(64<<8)|110);
            if(i==2)cfg('h3c4,(110<<8)|110);
            repeat(STEP)@(negedge clk);if(ons)$fatal(1,"Composer played without START");
            cmd(2);repeat(STEP*65)@(negedge clk);cmd(3);repeat(20000)@(negedge clk);
            if(held!=-1||ons!=offs||dut.misses)$fatal(1,"Composer stop/deadline accounting");
        end
        if(attacks[1]<=attacks[0]+5)$fatal(1,"XY density did not change rhythm %d/%d",attacks[0],attacks[1]);
        if(pitch_sum[2]/attacks[2]<=pitch_sum[1]/attacks[1]+2)$fatal(1,"XY direction did not lift melody");
        setup();case_id=3;
        cmd(9);midi('h90,62,96);midi('h90,65,96);midi('h90,69,96);cmd(9);
        if(dut.seed_count!=3||dut.seed[0]!=62||dut.seed[2]!=69)$fatal(1,"Theme input not stored");
        n=ons;cmd(2);wait(ons>n);if(last_on!=62)$fatal(1,"First lead did not use entered theme");
        cmd(8);wait(dut.locked);if(!dut.replaying)$fatal(1,"LOCK did not enter replay");
        for(i=0;i<64;i=i+1)saved_phrase[i]=dut.phrase[{dut.play_bank,6'(i)}];
        repeat(STEP*10)@(negedge clk);cmd(4);cmd(8);wait(dut.locked);
        for(i=0;i<64;i=i+1)begin
            if((^dut.phrase[{dut.play_bank,6'(i)}])===1'bx)$fatal(1,"VAR then LOCK incomplete slot %0d word %h bank%0d wb%0d step%0d",i,dut.phrase[{dut.play_bank,6'(i)}],dut.play_bank,dut.write_bank,dut.step_index);
            if(dut.phrase[{dut.play_bank,6'(i)}]!==saved_phrase[i])changed=changed+1;
        end
        if(changed==0)$fatal(1,"VARIATION did not change the phrase");
        repeat(STEP*130)@(negedge clk);if(!dut.locked||dut.misses)$fatal(1,"Locked replay failed");
        cmd(3);repeat(20000)@(negedge clk);cmd(2);repeat(STEP*5)@(negedge clk);
        if(!dut.locked||!dut.replaying)$fatal(1,"STOP/START lost locked phrase");
        cmd(7);wait(!dut.running);repeat(100)@(negedge clk);
        if(held!=-1||last_on!=60)$fatal(1,"END failed to cadence and release");
        cmd(12);
        cmd(15);if(dut.learn_index!=0||!dut.learning)$fatal(1,"Screen TAP changed pad learning");
        for(i=0;i<8;i=i+1)midi('h91,60+i,90);
        if(dut.learning||dut.pad_valid!=255||dut.pad_note[7]!=67||dut.pad_channel[7]!=1)$fatal(1,"Pad learning failed");
        saved_rng=dut.rng;midi('h91,61,90);if(dut.rng==saved_rng)$fatal(1,"Learned pad VAR did nothing");
        midi('h91,60,90);wait(dut.running);midi('h91,60,90);wait(!dut.running);repeat(20000)@(negedge clk);
        cmd(10);wait(dut.record_mode==2);mask=0;
        for(i=0;i<32;i=i+1)begin
            if(i==0||i==4||i==10||i==16||i==20||i==28)begin
                mask[i]=1;if(i==0||i==16)cmd(15);else midi('h91,61,100);
            end
            while(dut.record_mode==2&&dut.record_step==i)@(negedge clk);
        end
        wait(dut.record_mode==0);if(!dut.rhythm_valid||dut.rhythm_mask!==mask)$fatal(1,"Two-bar rhythm mismatch %h/%h",dut.rhythm_mask,mask);
        check_rhythm=1;n=ons;cmd(2);repeat(STEP*64)@(negedge clk);cmd(3);repeat(20000)@(negedge clk);check_rhythm=0;
        if(ons-n!=12)$fatal(1,"Rhythm replay count %d",ons-n);
        // Stop/restart during inference must discard the old snapshot.
        cmd(2);wait(dut.infer_busy);cmd(3);cmd(2);repeat(STEP*2)@(negedge clk);
        out_ready=0;wait(out_valid);saved_word=out_data;midi('hb0,123,0);repeat(30)@(negedge clk);
        if(!out_valid||out_data!==saved_word)$fatal(1,"Panic changed stalled packet");
        out_ready=1;repeat(20000)@(negedge clk);
        if(held!=-1||dut.running||!dut.panic_latched||dut.misses)$fatal(1,"Panic / restart did not drain safely");
        cfg('h3c0,0);repeat(100)@(negedge clk);
        $fclose(fd);
        $display("PASS composer: density %0d/%0d attacks; neutral/up mean pitch %0d/%0d; theme, full phrase LOCK replay, tonic END, pad learn/actions, count-in/two-bar rhythm, rapid restart, backpressure/panic and zero missed steps",attacks[0],attacks[1],pitch_sum[1]/attacks[1],pitch_sum[2]/attacks[2]);$finish;
    end
    initial begin #2000000000;$fatal(1,"Composer timeout step=%d work=%d run=%d ons=%d",dut.step_index,dut.work,dut.running,ons);end
endmodule
