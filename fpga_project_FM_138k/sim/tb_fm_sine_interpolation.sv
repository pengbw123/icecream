`timescale 1ns/1ps
// Exhaust every actual sine-ROM segment, fractional phase and quadrant.
// Compare the core's timing refactor against the previous arithmetic order.
module tb_fm_sine_interpolation;
    fm_poly_synth dut();
    integer addr,frac,quadrant,step_value,magnitude,checks;
    reg signed [16:0] expected;
    initial begin
        checks=0;
        #1;
        for(addr=0;addr<512;addr=addr+1) begin
            dut.p1_sine_base=dut.sine_quarter_delta[addr][23:8];
            dut.p1_sine_delta=dut.sine_quarter_delta[addr][7:0];
            for(frac=0;frac<2048;frac=frac+1) begin
                dut.p1_sine_fraction=frac;
                step_value=(dut.p1_sine_delta*frac)>>11;
                for(quadrant=0;quadrant<4;quadrant=quadrant+1) begin
                    dut.p1_sine_reverse=quadrant[1];
                    dut.p1_sine_negative=quadrant[0];
                    magnitude=quadrant[1]
                        ? dut.p1_sine_base+dut.p1_sine_delta-step_value
                        : dut.p1_sine_base+step_value;
                    expected=quadrant[0]?-magnitude:magnitude;
                    #1;
                    if(dut.p1_sine_interpolated !== expected)
                        $fatal(1,"sine changed addr=%0d frac=%0d quadrant=%0d: %0d != %0d",
                            addr,frac,quadrant,dut.p1_sine_interpolated,expected);
                    checks=checks+1;
                end
            end
        end
        $display("PASS bit-identical FM sine interpolation: %0d phases/quadrants",checks);
        $finish;
    end
endmodule
