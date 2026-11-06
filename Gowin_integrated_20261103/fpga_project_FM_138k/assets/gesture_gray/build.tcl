add_file -type verilog "../../src/gesture/gesture_gray_frontend.v"
add_file -type verilog "../../src/gesture/gesture_gray_roi.v"
add_file -type verilog "../../src/gesture/gesture_gray_mailbox.v"
set_device GW5AT-LV138PG484AC1/I0 -device_version B
set_option -top_module gesture_gray_frontend
set_option -output_base_name gray_frontend
set_option -verilog_std sysv2017
run syn
