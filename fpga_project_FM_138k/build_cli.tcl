# Command-line build script for Gowin gw_sh.
# Run this script from the project root so $readmemh relative paths resolve.

add_file -type verilog "src/i2s_tx.v"
add_file -type verilog "src/uart_rx.v"
add_file -type verilog "src/fm_uart_control.v"
add_file -type verilog "src/fm_poly_synth.v"
add_file -type verilog "src/midi_performance_control.v"
add_file -type verilog "src/audio_effects.v"
add_file -type verilog "src/audio_output_stage.v"
add_file -type verilog "src/fm_status_lcd.v"
add_file -type verilog "src/usb_midi/rtl/rv32i.v"
add_file -type verilog "src/usb_midi/rtl/usb11_phy.v"
add_file -type verilog "src/usb_midi/rtl/usb11_regs.v"
add_file -type verilog "src/usb_midi/rtl/usb11_sie.v"
add_file -type verilog "src/usb_midi/rtl/usb_pll.v"
add_file -type verilog "src/usb_midi/rtl/usb_midi_host.v"
add_file -type verilog "src/top.v"
add_file -type verilog "src/top_138k.v"
add_file -type verilog "src/midi_bridge_rx.v"
add_file -type verilog "src/ws2812_keys.v"
add_file -type verilog "src/video_pll.v"
add_file -type verilog "src/rgb_visualizer.v"
add_file -type verilog "src/audio_xy_scope.v"
add_file -type verilog "src/audio_wave_scope.v"
add_file -type verilog "src/rtl_performance_text.v"
add_file -type verilog "src/rtl_char_display.v"
add_file -type verilog "src/visual_auto_gain.v"
add_file -type verilog "src/rtl_menu_text.v"
add_file -type verilog "src/gt9147_reset.v"
add_file -type verilog "src/touch_ui_controller.v"
add_file -type cst "src/acg720_rgb.cst"
add_file -type sdc "src/acg720_rgb.sdc"

set_device GW5AT-LV138PG484AC1/I0 -device_version B
set_option -synthesis_tool gowinsynthesis
set_option -top_module top_138k
set_option -output_base_name fm_138k_rgb
set_option -verilog_std sysv2017
set_option -use_sspi_as_gpio 1
set_option -use_cpu_as_gpio 1

run all
