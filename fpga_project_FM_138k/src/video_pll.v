// ACG720 display clock. RGB TFT uses PIXEL_DIV=30 -> 33.333 MHz.
// The dormant HDMI path uses 25/125 MHz with default parameters.
module video_pll #(
    parameter integer PIXEL_DIV=40,
    parameter integer ENABLE_SERIAL=1
) (
    input wire clkin,
    output wire pixel_clk,
    output wire serial_clk,
    output wire lock
);
    // GW5AT-138B uses PLL (Arora-V ports), rather than Primer25K PLLA.
    // VCO=50/IDIV*MDIV=1000 MHz.
    PLL u_pll (
        .LOCK(lock), .CLKOUT0(pixel_clk), .CLKOUT1(serial_clk),
        .CLKOUT2(),.CLKOUT3(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6(),
        .CLKFBOUT(),.CLKIN(clkin),.CLKFB(1'b0),
        .RESET(1'b0),.PLLPWD(1'b0),.RESET_I(1'b0),.RESET_O(1'b0),
        .IDSEL(6'b0),.FBDSEL(6'b0),.MDSEL(7'b0),.MDSEL_FRAC(3'b0),
        .ODSEL0(7'b0),.ODSEL0_FRAC(3'b0),.ODSEL1(7'b0),
        .ODSEL2(7'b0),.ODSEL3(7'b0),.ODSEL4(7'b0),.ODSEL5(7'b0),.ODSEL6(7'b0),
        .ENCLK0(1'b1),.ENCLK1(1'b1),.ENCLK2(1'b0),.ENCLK3(1'b0),
        .ENCLK4(1'b0),.ENCLK5(1'b0),.ENCLK6(1'b0),
        .DT0(4'b0),.DT1(4'b0),.DT2(4'b0),.DT3(4'b0),
        .PSSEL(3'b0),.PSDIR(1'b0),.PSPULSE(1'b0),
        .SSCPOL(1'b0),.SSCON(1'b0),.SSCMDSEL(7'b0),.SSCMDSEL_FRAC(3'b0),
        .ICPSEL(6'b0),.LPFRES(3'b0),.LPFCAP(2'b0)
    );
    defparam u_pll.FCLKIN = "50";
    defparam u_pll.IDIV_SEL = 1;
    defparam u_pll.FBDIV_SEL = 1;
    defparam u_pll.MDIV_SEL = 20;
    defparam u_pll.ODIV0_SEL = PIXEL_DIV;
    defparam u_pll.ODIV1_SEL = 8;
    defparam u_pll.CLKOUT0_EN = "TRUE";
    defparam u_pll.CLKOUT1_EN = ENABLE_SERIAL ? "TRUE" : "FALSE";
    defparam u_pll.CLKFB_SEL = "INTERNAL";
endmodule
