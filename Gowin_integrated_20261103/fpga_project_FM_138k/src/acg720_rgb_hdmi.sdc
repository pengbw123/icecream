create_clock -name clk_50m -period 20.000 [get_ports {clk}]
create_generated_clock -name pixel_33m -source [get_ports {clk}] -multiply_by 2 -divide_by 3 [get_pins {u_video/u_video_pll/u_pll/CLKOUT0}]
create_generated_clock -name hdmi_pixel_25m -source [get_ports {clk}] -divide_by 2 [get_pins {u_hdmi/u_video_pll/u_pll/CLKOUT0}]
create_generated_clock -name hdmi_serial_125m -source [get_ports {clk}] -multiply_by 5 -divide_by 2 [get_pins {u_hdmi/u_video_pll/u_pll/CLKOUT1}]
create_generated_clock -name camera_xclk_24m -source [get_ports {clk}] -multiply_by 16 -divide_by 33 [get_pins {u_hdmi/u_camera_pll/u_pll/CLKOUT1}]
# Ch45 auto PCLK mode: cover up to 85MHz (the 24.242MHz reference is separate).
create_clock -name camera_pclk_85m -period 11.764706 [get_ports {camera_pclk}]
# 0x4740[5]=1: sensor launches DVP on falling edge; sample rising edge.
# Conservative board/sensor budget; check this half-cycle input path in STA.
set_input_delay -clock camera_pclk_85m -clock_fall -max 5.000 [get_ports {camera_data[*] camera_href camera_vsync}]
set_input_delay -clock camera_pclk_85m -clock_fall -min 0.500 [get_ports {camera_data[*] camera_href camera_vsync}]
set_clock_groups -asynchronous -group [get_clocks {clk_50m}] -group [get_clocks {pixel_33m}] -group [get_clocks {hdmi_pixel_25m hdmi_serial_125m}] -group [get_clocks {camera_pclk_85m}] -group [get_clocks {camera_xclk_24m}]
