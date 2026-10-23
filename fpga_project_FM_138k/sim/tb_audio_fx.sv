`timescale 1ns/1ps
// Checks the audio_fx register file, defaults, readback and exact dry bypass.
module tb_audio_fx;
    reg clk = 0;
    always #10 clk = ~clk;      // 50 MHz
    reg reset_n = 0;
    reg sample_tick = 0;
    reg signed [15:0] dry = 16'sd1234;
    reg cfg_write = 0;
    reg [5:0] cfg_addr = 0;
    reg [15:0] cfg_value = 0;
    reg [5:0] read_addr = 0;
    wire [15:0] read_value;
    wire signed [15:0] sample_out;

    audio_fx dut(.clk(clk), .reset_n(reset_n), .sample_tick(sample_tick),
        .dry_sample(dry), .cfg_write(cfg_write), .cfg_addr(cfg_addr),
        .cfg_value(cfg_value), .read_addr(read_addr),
        .read_value(read_value), .sample_out(sample_out));

    task wr(input [5:0] a, input [15:0] v);
        begin
            @(posedge clk) begin cfg_addr <= a; cfg_value <= v; cfg_write <= 1'b1; end
            @(posedge clk) cfg_write <= 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task tick_once;
        begin
            sample_tick <= 1'b1; @(posedge clk);
            sample_tick <= 1'b0; repeat (24) @(posedge clk);
        end
    endtask

    // Run one sample through the FSM and return the settled output.
    reg signed [15:0] last_out;
    task run_sample(input signed [15:0] in);
        begin
            dry = in;
            sample_tick <= 1'b1; @(posedge clk);
            sample_tick <= 1'b0;
            repeat (24) @(posedge clk);
            last_out = sample_out;
        end
    endtask

    integer n, shape_changes, amplitude;
    integer sum_out, mean_out, sum20, sum99, sum_dry;
    reg signed [15:0] max_out;
    reg signed [15:0] previous_shape;
    reg [23:0] previous_smooth;
    reg signed [15:0] high_level_out;

    task expect_reg(input [5:0] a, input [15:0] v, input [127:0] name);
        begin
            read_addr = a;
            repeat (2) @(posedge clk);
            if (read_value !== v) $fatal(1, "%0s: got %04h expected %04h", name, read_value, v);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        reset_n = 1;
        repeat (5) @(posedge clk);

        expect_reg(6'd0, 16'h0001, "global default");
        expect_reg(6'd3, 16'd99, "filter cutoff default");
        expect_reg(6'd6, 16'd20, "distortion gain default");
        expect_reg(6'd24, 16'd30, "reverb mix default");

        // Both ends of the smoothed controls must reach the requested
        // integer. Upward Q8 truncation used to strand RATE/FREQ/DEPTH/MIX
        // one UI count below 99, despite readback reporting the requested 99.
        wr(6'd19,16'd99);wr(6'd14,16'd99);
        wr(6'd15,16'd99);wr(6'd16,16'd99);
        repeat(4096) run_sample(0);
        if(dut.sm_drate !== (24'd99<<8) || dut.sm_pfreq !== (24'd99<<8) ||
           dut.sm_pdepth !== (24'd99<<8) || dut.sm_pmix !== (24'd99<<8))
            $fatal(1,"smoothed delay/phaser controls did not reach 99");
        if(dut.u_delay.delay_a !== dut.u_delay.len_tab[99] &&
           dut.u_delay.delay_b !== dut.u_delay.len_tab[99])
            $fatal(1,"delay RATE=99 did not request the maximum delay");
        wr(6'd19,16'd0);wr(6'd14,16'd0);
        wr(6'd15,16'd0);wr(6'd16,16'd0);
        repeat(4096) run_sample(0);
        if(dut.sm_drate !== 0 || dut.sm_pfreq !== 0 ||
           dut.sm_pdepth !== 0 || dut.sm_pmix !== 0)
            $fatal(1,"smoothed delay/phaser controls did not reach zero");
        @(negedge clk);reset_n=0;
        repeat(5) @(negedge clk);
        reset_n=1;repeat(5) @(negedge clk);

        // register write/readback
        wr(6'd3, 16'h4321);
        expect_reg(6'd3, 16'h4321, "register write");
        wr(6'd24, 16'h0055);
        expect_reg(6'd24, 16'h0055, "register write 2");

        // step 1: the chain is dry, and bypass/master must still pass dry exactly
        tick_once;
        if (sample_out !== dry) $fatal(1, "master-on output %04h", sample_out);
        wr(6'd0, 16'h0003);      // bypass
        tick_once;
        if (sample_out !== dry) $fatal(1, "bypass output %04h", sample_out);
        wr(6'd0, 16'h0000);      // master off
        tick_once;
        if (sample_out !== dry) $fatal(1, "master-off output %04h", sample_out);

        // ---- distortion: normalized tanh, GAIN must not change loudness ----
        wr(6'd0, 16'h0001);      // master on
        wr(6'd5, 16'h0001);      // distortion on
        wr(6'd7, 16'd99);        // tone open
        wr(6'd8, 16'd99);        // level
        wr(6'd6, 16'd20);        // low gain
        for (n = 0; n < 2560; n = n + 1)
            run_sample(((n / 32) % 2) ? 16'sd12000 : -16'sd12000);
        sum20 = 0;
        for (n = 0; n < 4096; n = n + 1) begin
            run_sample(((n / 32) % 2) ? 16'sd12000 : -16'sd12000);
            sum20 = sum20 + ((last_out * last_out) >>> 16);
        end
        wr(6'd6, 16'd99);        // high gain
        for (n = 0; n < 2560; n = n + 1)
            run_sample(((n / 32) % 2) ? 16'sd12000 : -16'sd12000);
        sum99 = 0;
        for (n = 0; n < 4096; n = n + 1) begin
            run_sample(((n / 32) % 2) ? 16'sd12000 : -16'sd12000);
            sum99 = sum99 + ((last_out * last_out) >>> 16);
            if (last_out > 16'sd32767 || last_out < -16'sd32768)
                $fatal(1, "distortion overflow %0d", last_out);
        end
        $display("distortion gain RMS sums: %0d vs %0d", sum20, sum99);
        if (sum20 < sum99 / 2 || sum99 < sum20 / 2)
            $fatal(1, "distortion gain changed loudness: %0d vs %0d", sum20, sum99);

        // Peak-normalized tanh used to make ordinary signals much too loud.
        // Match input and output RMS across several input amplitudes.
        wr(6'd6, 16'd50);
        for (amplitude = 2000; amplitude <= 32000; amplitude = amplitude * 2) begin
            for (n = 0; n < 2048; n = n + 1)
                run_sample($rtoi(amplitude * $sin(6.283185307179586 * n / 127.0)));
            sum_dry = 0;
            sum_out = 0;
            for (n = 0; n < 2048; n = n + 1) begin
                run_sample($rtoi(amplitude * $sin(6.283185307179586 * n / 127.0)));
                sum_dry = sum_dry + ((dry * dry) >>> 16);
                sum_out = sum_out + ((last_out * last_out) >>> 16);
            end
            if (sum_out * 4 < sum_dry * 3 || sum_out * 4 > sum_dry * 5)
                $fatal(1, "distortion loudness mismatch amp=%0d dry=%0d wet=%0d",
                    amplitude, sum_dry, sum_out);
        end

        // Sweep the complete signed PCM range. A wrap at any clip threshold
        // would reverse direction or create a large join in this transfer.
        repeat (8) run_sample(-16'sd32768);
        previous_shape = dut.dist_shaped;
        for (n = -32768; n <= 32767; n = n + 16) begin
            run_sample(n);
            if (dut.dist_shaped < previous_shape ||
                dut.dist_shaped - previous_shape > 16'sd100)
                $fatal(1, "waveshaper discontinuity near input=%0d: %0d -> %0d",
                    n, previous_shape, dut.dist_shaped);
            previous_shape = dut.dist_shaped;
        end

        // A slow low-level ramp must not turn into a staircase at the tanh LUT.
        // Inspect the waveshaper before TONE, which would conceal missing
        // interpolation by smoothing the steps after they have been created.
        wr(6'd6, 16'd20);
        for (n = 0; n < 2600; n = n + 1) run_sample(16'sd0);
        previous_shape = dut.dist_shaped;
        shape_changes = 0;
        for (n = 0; n < 250; n = n + 1) begin
            run_sample(n * 8);
            if (dut.dist_shaped > previous_shape) shape_changes = shape_changes + 1;
            if (dut.dist_shaped < previous_shape)
                $fatal(1, "distortion ramp is not monotonic at %0d", n);
            previous_shape = dut.dist_shaped;
        end
        if (shape_changes < 150)
            $fatal(1, "distortion waveshaper has visible steps: %0d changes", shape_changes);

        // Peak normalization is above unity at low drive and tends to unity
        // as GAIN rises; the Q2.14 table must not be uniformly saturated.
        if (dut.dist_makeup[20] <= dut.dist_makeup[99])
            $fatal(1, "distortion makeup does not fall as GAIN rises");

        // LEVEL controls wet/dry mix. Zero must preserve the original PCM;
        // changing GAIN must not turn it into an overall volume control.
        wr(6'd8, 16'd0);
        previous_smooth = dut.sm_level;
        for (n = 0; n < 3000; n = n + 1) begin
            run_sample(16'sd12000);
            if (dut.sm_level > previous_smooth)
                $fatal(1, "LEVEL smoothing rose while target fell: %0d -> %0d",
                    previous_smooth, dut.sm_level);
            previous_smooth = dut.sm_level;
        end
        if (dut.sm_level !== 24'd0 || dut.lgain !== 16'sd0)
            $fatal(1, "LEVEL=0 did not converge: state=%0d gain=%0d",
                dut.sm_level, dut.lgain);
        for (n = 0; n < 128; n = n + 1) begin
            run_sample(16'sd12000);
            if (last_out !== 16'sd12000)
                $fatal(1, "DIST MIX=0 did not preserve dry audio: %0d", last_out);
        end
        wr(6'd0, 16'd0);
        run_sample(16'sd12345);
        if (last_out !== 16'sd12345)
            $fatal(1, "FX master bypass lost exact dry with MIX=0");
        wr(6'd0, 16'd1);
        wr(6'd8, 16'd99);
        previous_smooth = dut.sm_level;
        for (n = 0; n < 3000; n = n + 1) begin
            run_sample(16'sd12000);
            if (dut.sm_level < previous_smooth || dut.sm_level > (24'd99 << 8))
                $fatal(1, "LEVEL smoothing wrapped while target rose: %0d -> %0d",
                    previous_smooth, dut.sm_level);
            previous_smooth = dut.sm_level;
        end
        if (dut.level_i < 7'd98)
            $fatal(1, "LEVEL=99 did not converge: %0d", dut.level_i);
        high_level_out = last_out;
        if (high_level_out < 16'sd10800 || high_level_out > 16'sd13200)
            $fatal(1, "MIX=99 loudness differs from dry: %0d", high_level_out);
        wr(6'd8, 16'd10);
        previous_smooth = dut.sm_level;
        for (n = 0; n < 3000; n = n + 1) begin
            run_sample(16'sd12000);
            if (dut.sm_level > previous_smooth)
                $fatal(1, "LEVEL=10 smoothing rose while target fell");
            previous_smooth = dut.sm_level;
        end
        if (dut.level_i < 7'd9 || dut.level_i > 7'd10 ||
            last_out < 16'sd10800 || last_out > 16'sd13200)
            $fatal(1, "MIX=10 loudness differs from dry: low=%0d high=%0d index=%0d",
                last_out, high_level_out, dut.level_i);

        // ---- low-pass filter passes DC, kills alternating Nyquist input ----
        wr(6'd5, 16'd0);         // distortion off
        wr(6'd1, 16'd1);         // filter on
        wr(6'd2, 16'd0);         // LP
        wr(6'd3, 16'd50);        // ~900 Hz
        wr(6'd4, 16'd50);        // mid Q
        repeat (400) run_sample(16'sd1000);
        if (last_out < 16'sd800 || last_out > 16'sd1200)
            $fatal(1, "LP DC gain wrong: %0d", last_out);
        repeat (200) run_sample(((last_out & 1) ? 16'sd1000 : -16'sd1000));
        if (last_out > 16'sd300 && last_out < -16'sd300)
            $fatal(1, "LP did not attenuate high frequency: %0d", last_out);

        // ---- high-pass blocks DC ----
        wr(6'd2, 16'd2);         // HP
        repeat (400) run_sample(16'sd1000);
        if (last_out > 16'sd300 && last_out < -16'sd300)
            $fatal(1, "HP did not block DC: %0d", last_out);

        // ---- chorus: an impulse must reappear as a delayed echo ----
        wr(6'd1, 16'd0);         // filter off
        wr(6'd9, 16'd1);         // chorus on
        wr(6'd10, 16'd50);       // LFO speed
        wr(6'd11, 16'd99);       // maximum sweep
        wr(6'd12, 16'd99);       // full wet
        max_out = 0;
        for (n = 0; n < 3000; n = n + 1) begin
            run_sample((n == 0) ? 16'sd20000 : 16'sd0);
            if (last_out > max_out) max_out = last_out;
            if (-last_out > max_out) max_out = -last_out;
        end
        if (max_out < 16'sd200)
            $fatal(1, "chorus produced no delayed echo (max %0d)", max_out);

        // ---- phaser: an impulse produces an all-pass response ----
        wr(6'd9, 16'd0);         // chorus off
        wr(6'd13, 16'd1);        // phaser on
        wr(6'd14, 16'd99);
        wr(6'd15, 16'd99);
        wr(6'd16, 16'd99);
        max_out = 0;
        for (n = 0; n < 200; n = n + 1) begin
            run_sample((n == 0) ? 16'sd20000 : 16'sd0);
            if (last_out > max_out) max_out = last_out;
            if (-last_out > max_out) max_out = -last_out;
        end
        if (max_out < 16'sd100)
            $fatal(1, "phaser produced no response (max %0d)", max_out);

        // ---- bypass must stay bit-exact even with effects enabled ----
        wr(6'd0, 16'h0003);      // bypass
        run_sample(16'sd12345);
        if (last_out !== 16'sd12345) $fatal(1, "bypass mismatch %0d", last_out);

        // ---- delay: an impulse must come back as a delayed echo ----
        wr(6'd0, 16'h0001);      // master on, no bypass
        wr(6'd9, 16'd0);         // chorus off
        wr(6'd13, 16'd0);        // phaser off
        wr(6'd17, 16'd1);        // delay on
        wr(6'd18, 16'd60);       // feedback
        wr(6'd19, 16'd0);        // shortest time (~40 ms)
        wr(6'd20, 16'd99);       // full wet
        max_out = 0;
        for (n = 0; n < 6000; n = n + 1) begin
            run_sample((n == 0) ? 16'sd20000 : 16'sd0);
            if (last_out > max_out) max_out = last_out;
            if (-last_out > max_out) max_out = -last_out;
        end
        if (max_out < 16'sd200)
            $fatal(1, "delay produced no echo (max %0d)", max_out);

        // ---- reverb: an impulse must produce a decaying tail ----
        wr(6'd17, 16'd0);        // delay off
        wr(6'd21, 16'd1);        // reverb on
        wr(6'd22, 16'd0);        // room
        wr(6'd23, 16'd80);       // long decay
        wr(6'd24, 16'd99);       // full wet
        max_out = 0;
        for (n = 0; n < 3000; n = n + 1) begin
            run_sample((n == 0) ? 16'sd20000 : 16'sd0);
            if (last_out > max_out) max_out = last_out;
            if (-last_out > max_out) max_out = -last_out;
        end
        if (max_out < 16'sd100)
            $fatal(1, "reverb produced no tail (max %0d)", max_out);

        // A steady DC input must not make the reverb run away, saturate or
        // shift the output away from the input level.
        max_out = 0;
        sum_out = 0;
        for (n = 0; n < 4000; n = n + 1) begin
            run_sample((n & 1) ? -16'sd1000 : 16'sd1000);
            if (last_out > max_out) max_out = last_out;
            if (-last_out > max_out) max_out = -last_out;
            if (n >= 3000) sum_out = sum_out + last_out;
        end
        if (max_out > 16'sd16000)
            $fatal(1, "reverb runaway (max %0d)", max_out);
        mean_out = sum_out / 1000;
        if (mean_out > 300 || mean_out < -300)
            $fatal(1, "reverb DC offset (mean %0d)", mean_out);

        $display("PASS audio_fx registers, bypass, distortion, filter, chorus, phaser, delay and reverb");
        $finish;
    end
endmodule



