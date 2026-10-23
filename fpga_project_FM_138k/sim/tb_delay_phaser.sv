`timescale 1ns/1ps
module tb_delay_phaser;
    reg clk=0;
    always #10 clk=~clk;
    reg reset_n=0,tick=0;
    reg signed [15:0] din=0,pin=0;
    reg den=1,pen=1;
    reg [6:0] rate=0,decay=0,dmix=99,pfreq=0,pdepth=0,pmix=99;
    wire signed [15:0] dout,pout;
    audio_delay d(.clk(clk),.reset_n(reset_n),.sample_tick(tick),.in_sample(din),
        .enable(den),.decay(decay),.rate(rate),.mix(dmix),.out_sample(dout));
    audio_phaser p(.clk(clk),.reset_n(reset_n),.sample_tick(tick),.in_sample(pin),
        .enable(pen),.freq(pfreq),.depth(pdepth),.mix(pmix),.out_sample(pout));
    task sample(input integer x,input integer y);
        begin
            @(negedge clk);din=x;pin=y;tick=1;
            @(negedge clk);tick=0;
            repeat(25) @(negedge clk);
            if((^dout)===1'bx || (^pout)===1'bx) $fatal(1,"unknown PCM output");
            if(d.st!=0 || p.st!=0) $fatal(1,"effect missed sample deadline");
        end
    endtask
    task reset;
        begin @(negedge clk);reset_n=0;repeat(3) @(negedge clk);reset_n=1;end
    endtask
    integer n,first,last_out,max_step,delta,k;
    real energy_dry,energy_notch,energy_pass,freq_hz;
    initial begin
        reset;
        // Memory deliberately remains X: warmup must suppress every unread tap.
        first=d.len_tab[0];
        for(n=0;n<=first;n=n+1) begin
            sample(n==0?16000:0,0);
            if(n<first && (dout>1 || dout< -1)) $fatal(1,"early echo at %0d: %0d",n,dout);
        end
        if(dout<15995) $fatal(1,"minimum delay impulse missing %0d",dout);
        $display("delay minimum %0d samples",first);
        // Longest delay spans >32768: catch truncated addresses and ring wrap.
        rate=99;reset;
        first=d.len_tab[99];
        for(n=0;n<=first;n=n+1) begin
            sample(n==0?-16000:0,0);
            if(n<first && (dout>1 || dout< -1)) $fatal(1,"early max-rate echo at %0d",n);
        end
        if(dout> -15995) $fatal(1,"maximum delay impulse missing %0d",dout);
        $display("delay maximum %0d samples",first);
        // Small negative feedback must eventually disappear, even after wrap.
        rate=0;decay=99;reset;
        for(n=0;n<70000;n=n+1) sample(n==0?-2:0,0);
        for(n=0;n<3000;n=n+1) begin
            sample(0,0);
            if(dout!=0) $fatal(1,"negative feedback limit cycle %0d",dout);
        end
        // Full-scale opposite polarities must saturate, never reverse sign.
        for(n=0;n<3000;n=n+1) sample(30000,0);
        if(dout<0) $fatal(1,"positive feedback wrapped");
        dmix=0;pmix=0;
        for(n=0;n<32;n=n+1) begin
            sample((n&1)?32767:-32768,(n&1)?-32768:32767);
            if(dout!==din || pout!==pin) $fatal(1,"MIX=0 not exact dry");
        end
        // Time changes use a bounded fade, with no multi-thousand-LSB jump.
        rate=0;decay=0;dmix=99;reset;
        max_step=0;last_out=0;
        for(n=0;n<6500;n=n+1) begin
            if(n==4000) rate=3;
            sample($rtoi(9000*$sin(6.28318530718*n/300.0)),0);
            if(n>4000) begin
                delta=dout-last_out;if(delta<0) delta=-delta;
                if(delta>max_step) max_step=delta;
            end
            last_out=dout;
        end
        if(max_step>700 || d.fading) $fatal(1,"delay time discontinuity %0d",max_step);
        $display("delay time fade max adjacent step %0d",max_step);
        // DEPTH=0 gives a fixed allpass corner. MIX max must retain deep
        // phase-cancellation notches instead of becoming magnitude-flat wet.
        dmix=0;pdepth=0;pmix=99;reset;
        for(k=0;k<2;k=k+1) begin
            freq_hz=k==0?309.0:750.0;
            energy_dry=0;energy_notch=0;
            for(n=0;n<10000;n=n+1) begin
                sample(0,$rtoi(6000*$sin(6.28318530718*freq_hz*n/48828.125)));
                if(n>2000) begin
                    energy_dry=energy_dry+$itor(pin)*$itor(pin);
                    energy_notch=energy_notch+$itor(pout)*$itor(pout);
                end
            end
            $display("phaser %.1f Hz energy ratio %.6f",freq_hz,energy_notch/energy_dry);
            if(k==0 && energy_notch>energy_dry*0.02) $fatal(1,"missing phaser notch");
            if(k==1 && energy_notch<energy_dry*0.8) $fatal(1,"phaser passband attenuated");
        end
        // Worst sweep and illegal controls: clamp indices, remain bounded,
        // continue working while bypassed, and settle back into silence.
        pdepth=127;pfreq=127;pmix=127;
        for(n=0;n<70000;n=n+1) sample(0,$rtoi(22000*$sin(n*0.31)));
        for(n=0;n<12000;n=n+1) sample(0,0);
        if(pout>2 || pout< -2) $fatal(1,"phaser idle residual %0d",pout);
        den=0;pen=0;
        for(n=0;n<16;n=n+1) begin
            sample(-12345,23456);
            if(dout!==din || pout!==pin) $fatal(1,"disabled effect not exact dry");
        end
        $display("PASS delay/phaser impulse, wrap, fade, feedback, notch and bypass");
        $finish;
    end
endmodule
