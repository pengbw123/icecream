create_clock -name clk_50m -period 20.000 [get_ports {clk}]
create_generated_clock -name clk_usb_48m -source [get_ports {clk}] -multiply_by 23 -divide_by 24 [get_pins {u_usb_pll/PLLA_inst/CLKOUT0}]
create_generated_clock -name clk_usb_bram_96m -source [get_ports {clk}] -multiply_by 23 -divide_by 12 -phase 45 [get_pins {u_usb_pll/PLLA_inst/CLKOUT1}]
set_clock_groups -asynchronous -group [get_clocks {clk_50m}] -group [get_clocks {clk_usb_48m clk_usb_bram_96m}]
