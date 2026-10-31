# ACG720 138K · FM 合成器 / RGB 触摸屏

当前下载版加入灰度光照自适应与统一USB/触屏音符到I2S标记脉冲；见 [更新说明](docs/GRAY_ADAPT_AND_MIDI_LATENCY.md)。数字脉冲不是完整模拟端到端延迟证明。

AI/协作者接手本工程请先读 [工程交接说明](docs/AI_HANDOFF.md)，它记录当前工作树、模块关系、硬件排查经验和未完成事项。
改 UI 固件读 [UI 软核与菜单固件说明](docs/UI_FIRMWARE_GUIDE.md)；多阶段的改造进度看
[菜单改造进度账本](docs/PRO_MENU_PROGRESS.md)；实际怎么操作看 [触摸屏使用说明](docs/USER_MANUAL_UI.md)。

当前主工程为 GW5AT-LV138PG484AC1/I0-B：32复音、6算子FM、128套DX7默认音色、LIVE/BACKING两Part，带SD用户音色与六类效果器。当前状态及实机验证界限以交接文档最新条目为准。

## 当前链路

USB-MIDI键盘 → CH376S SPI主机 → 138K FM → I2S，可选MAX98357或ES8388耳机输出。也可使用CH340串口或RGB屏幕琴键；25K中转仅作为默认关闭的兼容路径。

- J1 RGB565触屏800×480，RTL生成像素，RV32I只处理触摸、菜单和参数；底部全宽琴键，力度及声音输出口可在SETUP设置。
- 页签：PLAY、ALGO、OSC、EG、LFO、FX、PATCH、SETUP。支持波形/李萨如/频谱、算子包络及性能/数字起音延迟统计。
- ARP、音序、屏幕辅助演奏、AI伴奏和AI旋律；P4 OV5640采集，HDMI显示摄像头预览，灰度CNN手势可影响AI旋律。识别/控制默认关闭。
- 新增独立JDY蓝牙串口、手机25键灯位校准、160灯指引与等键练习、8192事件RAM曲谱上传/回放。接线及验收见 [蓝牙曲谱移植](docs/BLUETOOTH_SCORE_PORT.md)；配套 [Android源码](../android_control/README.md)。这些模式与已有自动演奏互斥，不删除原功能。

## 编译与烧录

在本目录执行：
```powershell
& 'D:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' build_cli_hdmi.tcl
```

新的 138K 文件是 **impl/pnr/fm_138k_rgb_hdmi.fs**。不要烧录复制目录中遗留的 fpga_project.fs。
IDE 工程为 fpga_project.gprj，顶层 top_138k_hdmi；CPU/SSPI 引脚须启用作为 GPIO。
UI 固件已包含 firmware.hex；改 C 代码后运行 src/ui_firmware/build_firmware.ps1 再综合。

完整实现报告与限制见 [迁移总结](docs/ACG720_138K_SUMMARY.md)。
首次接线、下载、菜单/键盘/串口操作及故障排查请看 [138K 使用说明](docs/138K_USER_GUIDE.md)。
从下载到看到现象、以及25K/138K断电保存程序，请看 [下载与固化步骤](docs/PROGRAM_AND_FLASH.md)。
原分支使用说明留在 [25K 参考](docs/25K_FM_REFERENCE.md)，其中 USB 直连和 SPI 屏幕接线不适用于本工程。

## 接线

先断电接线，GPIO0 所在 Bank 电平设为 **3.3V**。

| 功能 | 138K 接口 |
|---|---|
| TFT V3.0 RGB + 触摸 | J1 原生 40pin FPC；确认同向/异向排线和 1 脚方向 |
| MAX98357 BCLK / LRC / DIN | P7-1 A13 / P7-2 A14 / P7-3 A15 |
| 25K 中转 TX 输入（默认关闭） | P7-4 A16 ← 25K Dock J3-15 F1 |
| JDY TX / RX | 模块TX→P7-9 E13；模块RX←P7-10 E14，3.3V逻辑 |
| WS2812 数据 | P7-6 A19 → 建议 74AHCT125 电平转换 → 灯条 DIN |
| 公共地 | P7-12 或 P7-28 GND |
| 复位 | S4，B21，低有效 |

25K 与 138K 各自供电，只连接 TX 和公共地，不互接 5V 电源。灯条使用合适的独立 5V 电源并共地，不能从 FPGA 信号脚供电。
独立中转工程为 ../fpga_midi_bridge_25k，未修改原 fpga_project_FM。

板载 CH340 串口参数：115200 / 8N1。可看到 UI 启动与 GT 识别诊断；原编辑器接收端口保持可用。
1 Mbaud 是两块 FPGA 之间的专用事件链路，不要把它接到电脑的 115200 串口输入。

## 触摸与验证

复用了 piano1 中验证过的 GT 复位/INT 时序：20ms 拉低、INT 选地址、释放复位后延迟，再释放 INT。
读取 0x814E 就绪位、读取全部触点、最后清就绪位；没有新帧时保留现有按键，不误当松键。
不再自动向 GT 写入猜测的配置表。若识别正常却不出触点，保留串口日志排查，不能只凭 I2C 地址响应认定触摸正常。

本轮蓝牙集成已通过RTL/软件回归及完整时序验收，手机蓝牙、灯位与声音仍待实机验证；此前功能实测状态见交接文档。
Dexed 逐位还原任务没有结束，见 docs/DX7_COMPATIBILITY.md；本次显示迁移不宣称完整音色 PCM 已逐位一致。
