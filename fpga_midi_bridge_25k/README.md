# Primer25K USB-MIDI 中转

这是独立的新工程，不修改原 fpga_project_FM。键盘插 Primer25K Dock 的 USB-A，沿用已验证的 USB1.1 PHY/SIE + RV32I 主机固件，只把 MIDI 事件送给 138K，不在本板合成声音。

## 烧录与接线

工程：midi_bridge_25k.gprj。芯片 GW5A-LV25MG121NC1/I0，版本 B。
本目录执行 gw_sh.exe build_cli.tcl，烧录 **impl/pnr/midi_bridge_25k.fs**。

- Dock J3-15（F1）：1 Mbaud、8N1 TX → 138K P7-4（A16）。
- 两板 GND 必须连接，GPIO 信号为 3.3V。两板分别供电，不互接 5V。
- 调试 UART TX 保留 C3，115200/8N1；不要与 F1 专用事件口混淆。
- USB 键盘仍插 Dock USB-A，不插 138K 的 USB 设备口。

专用链路帧为 12 字节：A5 5A 30 STATUS DATA1 DATA2 BRIGHTNESS 00 00 00 00 CHECKSUM。
CHECKSUM 为命令 30 到末个数据字节逐字节 XOR。接收模块为 138K 的 midi_bridge_rx。
USB 断开时发送 CC64=0 和 CC123=0 释放延音与按键。通道0 Note On 的力度按 0x00→0、0x5A→127 映射，保留 0 力度松键语义；打击垫等其他通道不缩放。

## 验证范围

已通过综合/布局布线并生成比特流；尚未在两块实板上验证此次中转链路。
CLS 2926/11520（26%），BSRAM14/56（25%），DSP0.5/28。
50 MHz 域 Fmax131.687 MHz，USB47.917 MHz 域 Fmax91.086 MHz，setup/hold TNS0。
事件 UART 和接收端已通过仿真。固件初始化镜像包含在 src/usb_midi/firmware/firmware.hex，第三方许可保留。

要恢复 25K 原独立合成器，重新烧录原工程对应比特流即可；这里没有更改原工程源码。
