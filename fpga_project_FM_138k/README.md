# ACG720 138K · FM 合成器 / RGB 触摸屏

本工程从 25K FM 分支迁移到 GW5AT-LV138PG484AC1/I0-B。保持 16 复音、6 算子、ROM1A 32 音色及原 FM 算法；本次不改动音色计算内核。当前以音色核原声输出，Chorus/Reverb 暂时旁路，方便后续 Dexed 对照。

## 当前链路

USB-MIDI 键盘 → 独立 Primer25K 中转 → 1 Mbaud UART → 138K FM → I2S。
也可通过板载 CH340（115200）使用原串口编辑器/演奏软件，或直接使用屏幕虚拟琴键。

- J1 40pin FPC：800×480 RGB565，显示完全由 RTL 生成，无 DDR 帧缓存。
- 波形、峰值/削波、6 算子包络、音色名称/算法编号/声部数、25 键高亮。
- 小型 RV32I 仅负责 GT9147/GT911 触摸和菜单事件，不负责绘图。
- 菜单：音色 ±、音量 ±5、屏幕琴键八度 ±、PANIC；支持 5 点触摸弹奏。
- WS2812：25 灯固定对应 C3～C5（MIDI 48～72），颜色随力度变化。
- HDMI 已从活动工程中排除；暂未加入 FFT、李萨如图、算子连线图或全参数菜单。

## 编译与烧录

在本目录执行：
```powershell
& 'D:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' build_cli.tcl
```

新的 138K 文件是 **impl/pnr/fm_138k_rgb.fs**。不要烧录复制目录中遗留的 fpga_project.fs。
IDE 工程为 fpga_project.gprj，顶层 top_138k；CPU/SSPI 引脚须启用作为 GPIO。
UI 固件已包含 firmware.hex；改 C 代码后运行 src/ui_firmware/build_firmware.ps1 再综合。

完整实现报告与限制见 [迁移总结](docs/ACG720_138K_SUMMARY.md)。
首次接线、下载、菜单/键盘/串口操作及故障排查请看 [138K 使用说明](docs/138K_USER_GUIDE.md)。
原分支使用说明留在 [25K 参考](docs/25K_FM_REFERENCE.md)，其中 USB 直连和 SPI 屏幕接线不适用于本工程。

## 接线

先断电接线，GPIO0 所在 Bank 电平设为 **3.3V**。

| 功能 | 138K 接口 |
|---|---|
| TFT V3.0 RGB + 触摸 | J1 原生 40pin FPC；确认同向/异向排线和 1 脚方向 |
| MAX98357 BCLK / LRC / DIN | P7-1 A13 / P7-2 A14 / P7-3 A15 |
| 25K 中转 TX 输入 | P7-4 A16 ← 25K Dock J3-15 F1 |
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

本版本已完成综合、布局布线、时序及引脚级仿真，**尚未在真实 138K + 屏幕上验证**。
Dexed 逐位还原任务没有结束，见 docs/DX7_COMPATIBILITY.md；本次显示迁移不宣称完整音色 PCM 已逐位一致。
