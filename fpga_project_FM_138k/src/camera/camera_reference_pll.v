// Match the working ch45 TFT top's ACTIVE camera XCLK source:
// Gowin_PLL CLKOUT1, 50MHz input, IDIV=1 MDIV=16 ODIV1=33.
// Its unused camera_pll.v is not the reference. Independent of HDMI clocks.
module camera_reference_pll(input wire clkin,reset_n,output wire clkout,lock);
    PLL u_pll (
        .LOCK(lock),.CLKOUT0(),.CLKOUT1(clkout),
        .CLKOUT2(),.CLKOUT3(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6(),
        .CLKFBOUT(),.CLKIN(clkin),.CLKFB(1'b0),
        .RESET(~reset_n),.PLLPWD(1'b0),.RESET_I(1'b0),.RESET_O(1'b0),
        .IDSEL(6'b0),.FBDSEL(6'b0),.MDSEL(7'b0),.MDSEL_FRAC(3'b0),
        .ODSEL0(7'b0),.ODSEL0_FRAC(3'b0),.ODSEL1(7'b0),
        .ODSEL2(7'b0),.ODSEL3(7'b0),.ODSEL4(7'b0),.ODSEL5(7'b0),.ODSEL6(7'b0),
        .ENCLK0(1'b0),.ENCLK1(1'b1),.ENCLK2(1'b0),.ENCLK3(1'b0),
        .ENCLK4(1'b0),.ENCLK5(1'b0),.ENCLK6(1'b0),
        .DT0(4'b0),.DT1(4'b0),.DT2(4'b0),.DT3(4'b0),
        .PSSEL(3'b0),.PSDIR(1'b0),.PSPULSE(1'b0),
        .SSCPOL(1'b0),.SSCON(1'b0),.SSCMDSEL(7'b0),.SSCMDSEL_FRAC(3'b0),
        .ICPSEL(6'b0),.LPFRES(3'b0),.LPFCAP(2'b0)
    );
    defparam u_pll.FCLKIN="50";
    defparam u_pll.IDIV_SEL=1;
    defparam u_pll.FBDIV_SEL=1;
    defparam u_pll.MDIV_SEL=16;
    defparam u_pll.MDIV_FRAC_SEL=0;
    defparam u_pll.ODIV0_SEL=16;
    defparam u_pll.ODIV1_SEL=33;
    defparam u_pll.CLKOUT0_EN="FALSE";
    defparam u_pll.CLKOUT1_EN="TRUE";
    defparam u_pll.CLKFB_SEL="INTERNAL";
endmodule
