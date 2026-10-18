foreach f {rv32i usb11_phy usb11_regs usb11_sie usb_pll usb_midi_host} {
    add_file -type verilog "src/usb_midi/rtl/$f.v"
}
add_file -type verilog src/top_bridge.v
add_file -type verilog src/midi_frame_tx.v
add_file -type cst src/bridge.cst
add_file -type sdc src/bridge.sdc
set_device GW5A-LV25MG121NC1/I0 -device_version B
set_option -synthesis_tool gowinsynthesis
set_option -top_module top_bridge
set_option -output_base_name midi_bridge_25k
set_option -verilog_std sysv2017
set_option -use_sspi_as_gpio 1
set_option -use_cpu_as_gpio 1
run all
