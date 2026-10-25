`timescale 1ns/1ps
module tb_midi_arpeggiator;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,suspend=0,sync_step=0,external_sync=0,sequence_mode=0;
    reg [159:0] config_data={32'd7000,32'd7000,32'd10000,32'd10000,32'h6000};
    reg [31:0] din=0;reg vin=0,ready=1;
    wire rin,vout;wire [31:0] dout,status;wire [6:0] brightness;wire [127:0] notes;
    midi_arpeggiator #(.CLOCKS_PER_US(1)) dut(.clk(clk),.reset_n(reset_n),
        .config_data(config_data),.suspend(suspend),.sequence_mode(sequence_mode),.sync_step(sync_step),.sync_restart(1'b0),.external_sync(external_sync),
        .in_data(din),.in_brightness(din[6:0]),.in_valid(vin),.in_ready(rin),
        .out_data(dout),.out_brightness(brightness),.out_valid(vout),.out_ready(ready),
        .status(status),.chord_notes(notes));
    integer ons=0,offs=0,ccs=0,cycles=0;
    integer pitches[0:511],velocities[0:511],on_at[0:511],off_at[0:511];
    reg [127:0] sounding=0;
    always @(posedge clk)begin
        cycles=cycles+1;
        if(vout&&ready)begin
            if(dout[23:20]==9&&dout[6:0]!=0)begin
                if(sounding[dout[14:8]])$fatal(1,"Repeated Note On without Note Off");
                sounding[dout[14:8]]=1;
                pitches[ons]=dout[14:8];velocities[ons]=dout[6:0];on_at[ons]=cycles;ons=ons+1;
            end else if(dout[23:20]==8)begin
                if(!sounding[dout[14:8]])$fatal(1,"Unowned Note Off");
                sounding[dout[14:8]]=0;off_at[offs]=cycles;offs=offs+1;
            end else if(dout[23:20]==11)begin
                ccs=ccs+1;if(dout[14:8]==123||dout[14:8]==120)sounding=0;
            end
        end
    end
    task midi(input [7:0] st,input [6:0] n,input [6:0] v);
        begin @(negedge clk);din={8'd0,st,1'b0,n,1'b0,v};vin=1;
            do @(posedge clk);while(!rin);
            @(negedge clk);vin=0;
        end
    endtask
    task start_mode(input [2:0] mode,input [1:0] octs,input hold);
        begin
            @(negedge clk);config_data[0]=0;wait(!status[1]);repeat(8)@(negedge clk);
            config_data[7:3]={octs,mode};config_data[1]=hold;config_data[0]=1;
            wait(status[1]);repeat(8)@(negedge clk);
        end
    endtask
    task expect_pitch(input integer index,input integer pitch);
        begin wait(ons>index);if(pitches[index]!=pitch)$fatal(1,"step %0d got %0d expected %0d",index,pitches[index],pitch);end
    endtask
    task pulse_step;
        begin @(negedge clk);sync_step=1;@(negedge clk);sync_step=0;end
    endtask
    integer k,before_on,before_cc;reg [31:0] stalled;
    initial begin
        #50000000;$fatal(1,"Arpeggiator timeout state=%0d status=%h",dut.state,status);
    end
    initial begin
        repeat(5)@(negedge clk);reset_n=1;
        midi(8'h90,60,80);expect_pitch(0,60);midi(8'h80,60,0);wait(offs==1);
        start_mode(0,0,0);before_on=ons;
        midi(8'h90,60,80);midi(8'h90,64,90);midi(8'h90,67,100);
        expect_pitch(before_on,60);expect_pitch(before_on+1,64);expect_pitch(before_on+2,67);expect_pitch(before_on+3,60);
        if(velocities[before_on+1]!=90)$fatal(1,"Input velocity lost");
        if(off_at[1]-on_at[before_on]<7000||off_at[1]-on_at[before_on]>7010)$fatal(1,"Gate duration");
        midi(8'h80,60,0);midi(8'h80,64,0);midi(8'h80,67,0);wait(!status[2]&&!status[3]);
        if(sounding!=0||notes!=0)$fatal(1,"Last release stuck");
        start_mode(1,0,0);before_on=ons;
        midi(8'h90,60,80);midi(8'h90,64,90);midi(8'h90,67,100);
        // The first key starts immediately; subsequent steps use the new set.
        expect_pitch(before_on,60);expect_pitch(before_on+1,64);expect_pitch(before_on+2,60);expect_pitch(before_on+3,67);
        start_mode(2,0,0);before_on=ons;
        midi(8'h90,60,80);midi(8'h90,64,90);midi(8'h90,67,100);
        expect_pitch(before_on,60);expect_pitch(before_on+1,64);expect_pitch(before_on+2,67);
        expect_pitch(before_on+3,64);expect_pitch(before_on+4,60);expect_pitch(before_on+5,64);
        start_mode(3,0,1);before_on=ons;
        midi(8'h90,67,50);midi(8'h90,60,60);midi(8'h90,64,70);
        expect_pitch(before_on,67);expect_pitch(before_on+1,60);expect_pitch(before_on+2,64);
        midi(8'h80,67,0);midi(8'h80,60,0);midi(8'h80,64,0);
        if(notes!=((128'd1<<60)|(128'd1<<64)|(128'd1<<67)))$fatal(1,"HOLD did not retain chord");
        midi(8'h90,72,100);midi(8'h90,76,100);
        if(notes!=((128'd1<<72)|(128'd1<<76)))$fatal(1,"HOLD replacement");
        // Leave editor with HOLD enabled: live notes bypass chord capture,
        // while chord-key releases and later returning to editor remain safe.
        config_data[16]=1;before_on=ons;
        midi(8'h80,72,0);midi(8'h80,76,0);
        midi(8'h90,95,85);wait(sounding[95]);
        if(notes!=((128'd1<<72)|(128'd1<<76)))$fatal(1,"Solo changed HOLD chord");
        config_data[16]=0;midi(8'h80,95,0);wait(!sounding[95]);
        wait(ons>=before_on+3);
        if(notes!=((128'd1<<72)|(128'd1<<76))||!status[2])$fatal(1,"Solo interrupted ARP");
        midi(8'h90,72,100);midi(8'h90,76,100);
        @(negedge clk);config_data[1]=0;
        midi(8'h80,72,0);midi(8'h80,76,0);wait(!status[2]&&!status[3]);
        start_mode(0,1,0);before_on=ons;config_data[2]=1;config_data[14:8]=77;
        midi(8'h90,120,20);expect_pitch(before_on,120);expect_pitch(before_on+1,120);
        if(velocities[before_on]!=77)$fatal(1,"Fixed velocity");
        if(notes[120]!=1)$fatal(1,"Full pitch range");
        midi(8'hb0,64,127);midi(8'h80,120,0);
        if(notes[120]!=1)$fatal(1,"Pedal hold");
        midi(8'hb0,64,0);wait(!status[2]&&!status[3]);
        if(notes!=0)$fatal(1,"Pedal release stuck");
        start_mode(0,1,0);before_on=ons;
        midi(8'h90,60,90);expect_pitch(before_on,60);expect_pitch(before_on+1,72);expect_pitch(before_on+2,60);
        // Hold an outgoing note immutable while controls change.
        @(negedge clk);ready=0;wait(vout);stalled=dout;
        repeat(50)begin @(negedge clk);if(!vout||dout!==stalled)$fatal(1,"Stalled output changed");end
        config_data[15]=!config_data[15];
        repeat(20)begin @(negedge clk);if(dout!==stalled)$fatal(1,"STOP corrupted pending output");end
        ready=1;wait(notes==0);repeat(10)@(negedge clk);
        if(sounding!=0||status[2])$fatal(1,"STOP did not drain notes");
        midi(8'h90,55,80);wait(status[2]);@(negedge clk);suspend=1;
        wait(!status[1]);repeat(10)@(negedge clk);
        if(sounding!=0||notes!=0)$fatal(1,"Practice suspend left notes");
        before_cc=ccs;midi(8'hb0,64,127);wait(ccs>before_cc);
        if(dout[6:0]!=0)$fatal(1,"Automatic mode let global sustain destroy note gates");
        sequence_mode=1;
        before_cc=ccs;midi(8'hb0,64,127);wait(ccs>before_cc);
        if(dout[6:0]!=127)$fatal(1,"Sequence mode blocked LIVE sustain");
        sequence_mode=0;
        before_on=ons;midi(8'h90,62,90);expect_pitch(before_on,62);midi(8'h80,62,0);
        @(negedge clk);suspend=0;wait(status[1]);repeat(10)@(negedge clk);
        if(status[2])$fatal(1,"Resume must wait for a new key");
        start_mode(4,2,0);before_on=ons;
        midi(8'h90,60,80);midi(8'h90,64,80);midi(8'h90,67,80);
        wait(ons>=before_on+16);
        for(k=before_on;k<ons;k=k+1)
            if(!(pitches[k]==60||pitches[k]==64||pitches[k]==67||pitches[k]==72||pitches[k]==76||pitches[k]==79||pitches[k]==84||pitches[k]==88||pitches[k]==91))$fatal(1,"Random pitch not in expanded chord");
        midi(8'hb0,123,0);repeat(20)@(negedge clk);
        if(sounding!=0||notes!=0)$fatal(1,"All Notes Off");
        for(k=0;k<128;k=k+1)midi(8'h90,k[6:0],80);
        if(notes!=={128{1'b1}}||status[31:24]!=128)$fatal(1,"128-note set overflow");
        midi(8'h80,64,0);wait(dut.state==0);
        if(notes[64]||status[31:24]!=127)$fatal(1,"Full-set removal / order compaction");
        midi(8'hb0,123,0);repeat(20)@(negedge clk);
        start_mode(0,0,0);external_sync=1;before_on=ons;
        midi(8'h90,60,80);expect_pitch(before_on,60);midi(8'h90,64,80);
        repeat(12000)@(negedge clk);
        if(ons!=before_on+1)$fatal(1,"External sync advanced without a step");
        pulse_step();expect_pitch(before_on+1,64);
        // An early external step must release the previous note before onset.
        pulse_step();expect_pitch(before_on+2,60);
        midi(8'hb0,123,0);repeat(20)@(negedge clk);
        $display("PASS arp bypass, up/down/bounce/order/random, octaves/range, velocity, gate, HOLD, pedal, STOP, stalls and practice suspend");$finish;
    end
endmodule
