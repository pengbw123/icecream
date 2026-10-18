create_clock -name clk_50m -period 20.000 [get_ports {clk}]
create_generated_clock -name pixel_33m -source [get_ports {clk}] -multiply_by 2 -divide_by 3 [get_pins {u_video/u_video_pll/u_pll/CLKOUT0}]
set_clock_groups -asynchronous -group [get_clocks {clk_50m}] -group [get_clocks {pixel_33m}]
