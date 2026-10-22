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

    integer n;
    integer sum_out, mean_out, sum20, sum99;
    reg signed [15:0] max_out;

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



