create_clock -name clk_50m -period 20.000 [get_ports {clk}]
create_generated_clock -name pixel_25m -source [get_ports {clk}] -multiply_by 1 -divide_by 2 [get_pins {u_video/u_video_pll/u_pll/CLKOUT0}]
create_generated_clock -name serial_125m -source [get_ports {clk}] -multiply_by 5 -divide_by 2 [get_pins {u_video/u_video_pll/u_pll/CLKOUT1}]
# Waveform bank ownership crosses by request/acknowledge; status has synchronizers.
set_clock_groups -asynchronous -group [get_clocks {clk_50m}] -group [get_clocks {pixel_25m serial_125m}]
