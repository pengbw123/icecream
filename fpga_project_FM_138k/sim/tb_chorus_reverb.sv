`timescale 1ns/1ps
module tb_chorus_reverb;
    reg clk=0;
    always #10 clk=~clk;
    reg reset_n=0, sample_tick=0;
    reg signed [15:0] input_sample=0;
    reg chorus_enable=0, reverb_enable=0;
    reg [6:0] chorus_freq=0, chorus_depth=0, chorus_mix=0;
    reg [1:0] reverb_type=0;
    reg [6:0] reverb_decay=0, reverb_mix=0;
    wire signed [15:0] chorus_out, reverb_out;
    audio_chorus chorus(.clk(clk),.reset_n(reset_n),.sample_tick(sample_tick),
        .in_sample(input_sample),.enable(chorus_enable),.freq(chorus_freq),
        .depth(chorus_depth),.mix(chorus_mix),.out_sample(chorus_out));
    audio_reverb reverb(.clk(clk),.reset_n(reset_n),.sample_tick(sample_tick),
        .in_sample(input_sample),.enable(reverb_enable),.rtype(reverb_type),
        .decay(reverb_decay),.mix(reverb_mix),.out_sample(reverb_out));
    task run(input signed [15:0] value);
        begin
            @(negedge clk); input_sample=value; sample_tick=1;
            @(negedge clk); sample_tick=0;
            repeat (24) @(negedge clk);
        end
    endtask
    integer n, first, second, peaks, diff, max_step, previous;
    integer room_late, room_short, hall_late, plate_late;
    integer energy, early_energy, middle_energy, peak_late;
    task reset_all;
        begin
            @(negedge clk);reset_n=0;
            repeat (4) @(negedge clk);
            reset_n=1;
            repeat (4) @(negedge clk);
        end
    endtask
    task reverb_tail(input [1:0] room_type, input [6:0] decay_value,
                     output integer late_energy);
        begin
            reset_all();
            chorus_enable=0;reverb_enable=1;
            reverb_type=room_type;reverb_decay=decay_value;reverb_mix=99;
            late_energy=0;
            early_energy=0;middle_energy=0;peak_late=0;
            for(n=0;n<24000;n=n+1) begin
                run((n==0)?16'sd20000:16'sd0);
                if (n>=12000 && n<24000) begin
                    energy=(reverb_out<0)?-reverb_out:reverb_out;
                    late_energy=late_energy+energy;
                    if (energy>peak_late) peak_late=energy;
                end
                if (n>=2000 && n<6000) begin
                    energy=(reverb_out<0)?-reverb_out:reverb_out;
                    early_energy=early_energy+energy;
                end
                if (n>=6000 && n<12000) begin
                    energy=(reverb_out<0)?-reverb_out:reverb_out;
                    middle_energy=middle_energy+energy;
                end
                if (^reverb_out === 1'bx)
                    $fatal(1,"reverb X at type=%0d sample=%0d",room_type,n);
            end
            $display("reverb type=%0d decay=%0d early=%0d middle=%0d late=%0d latepeak=%0d",
                room_type,decay_value,early_energy,middle_energy,late_energy,peak_late);
        end
    endtask
    initial begin
        reset_all();
        // MIX=0 and disabled must be bit-exact dry, even while RAM runs.
        chorus_enable=1;chorus_freq=99;chorus_depth=99;chorus_mix=0;
        reverb_enable=1;reverb_type=1;reverb_decay=99;reverb_mix=0;
        for(n=0;n<1100;n=n+1) begin
            run((n&1)?-16'sd12000:16'sd12000);
            if (chorus_out!==input_sample || reverb_out!==input_sample)
                $fatal(1,"MIX=0 altered dry PCM at %0d: in=%0d chorus=%0d reverb=%0d",
                    n,input_sample,chorus_out,reverb_out);
        end
        reset_all();
        reverb_enable=0;chorus_enable=1;chorus_freq=0;
        chorus_depth=99;chorus_mix=99;
        first=0;second=0;peaks=0;
        for(n=0;n<1000;n=n+1) begin
            run((n==0)?16'sd20000:16'sd0);
            if (chorus_out>16'sd2000) begin
                peaks=peaks+1;
                if(first==0)first=n;
                else if(n>first+100)second=n;
            end
            if (^chorus_out === 1'bx)
                $fatal(1,"chorus X at sample=%0d",n);
        end
        if(first<395 || first>410 || second<780 || second>810)
            $fatal(1,"chorus dual tap positions wrong: %0d, %0d",first,second);
        // Sweeping delay must not create full-scale discontinuities.
        chorus_freq=99;chorus_depth=99;chorus_mix=70;
        previous=0;max_step=0;
        for(n=0;n<4000;n=n+1) begin
            run($rtoi(8000.0*$sin(6.283185307179586*n/97.0)));
            diff=chorus_out-previous;
            if(diff<0)diff=-diff;
            if(diff>max_step)max_step=diff;
            previous=chorus_out;
        end
        if(max_step>6000)
            $fatal(1,"chorus modulation clicked, max step=%0d",max_step);
        reverb_tail(2'd0,7'd0,room_short);
        reverb_tail(2'd0,7'd99,room_late);
        reverb_tail(2'd1,7'd99,hall_late);
        reverb_tail(2'd2,7'd99,plate_late);
        $display("reverb late energies room=%0d hall=%0d plate=%0d",room_late,hall_late,plate_late);
        if (room_late<=0 || hall_late<=0 || plate_late<=0)
            $fatal(1,"missing reverb tail");
        if (hall_late < room_late * 5 / 4 || hall_late < plate_late * 5 / 4)
            $fatal(1,"hall tail is not longer than room and plate");
        if (room_late <= room_short)
            $fatal(1,"DECAY control does not lengthen the room tail");
        $display("PASS chorus dual taps/interpolation and reverb room/hall/plate tails");
        $finish;
    end
endmodule
