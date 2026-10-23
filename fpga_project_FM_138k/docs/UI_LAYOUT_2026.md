# 800×480 仪器菜单

2026-10-23，按已确认的“独立背景色 / 主题色、实心选中底色”方案实现。
改版前 Git 存档为 `2616714`。

## 使用

- 顶部 8 页：PLAY / ALGO / OSC / EG / LFO / FX / PATCH / SETUP，按钮 96×48。
- 状态栏 y=48..79：音色、编辑标记、算法、声部数、八度、主音量。
- 参数先点选，底部 `-1` / 滑条 / `+1` 编辑；按住 1.5 秒后每 150 ms 连续步进。
- ALGO 左边参数、右边 512×256 路由图；图形跟随算法更新。
- OSC 左选算子，右边 PITCH / RESPONSE / KEY SCALE 分组；所选算子右侧 ON/OFF 可直接切换。
- EG 上面 4×2 参数区，下面六算子曲线；点曲线切算子。底部左键切换算子 EG 与 PITCH EG。
- LFO 两列各四行；FX 左选效果器和开关，右侧编辑对应类型与参数；底部左键是 FX MASTER。
- DELAY 第一行 TIME 对应寄存器 19，显示 20..1000 ms；第二行 DECAY 对应寄存器 18。
- PATCH 左侧选 ROM 预设，再按 LOAD ROM；右侧 8 个 RAM 用户槽，分两组显示。
  STORE RAM 保存合成器参数和名称，LOAD RAM 恢复；覆盖已用槽和覆盖当前编辑有确认。
  RAM 槽不包含 FX 参数，断电丢失，不是 Flash 保存。
- SETUP 的 BACKGROUND 和 ACCENT 独立选择，文字及图形随明暗改变。
  背景有 WHITE / COOL GRAY / CHARCOAL / BLACK；主题有 BLUE / CYAN / TEAL / VIOLET / SLATE。
  默认 BLACK + BLUE，配色设置在断电后恢复默认。
- 主音量仍控制现有扬声器和 ES8388 共同输出，没有新增独立耳机音量。
- PLAY 的 FFT / ARP / SEQ 当前只有预留入口，提示 RESERVED，不显示伪实时频谱。
  后续各自增加内部页即可，不必缩小顶层导航。

## 实现

- `src/ui_firmware/main.c` 保留触摸 I2C、MIDI/参数协议、参数回读、曲线/算法计算。
- `src/ui_firmware/menu_layout.h` 负责新菜单绘制、配色和与之对应的触摸区域。
  与 main.c 同一编译单元，不需要额外软核或帧缓冲。
- 坐标按 8×16 字符格对齐，主按钮高度 48，底栏起点 y=416。
  保持 16 色调色板；配色无需抗锯齿或新的字库。
- 字符 `attr[3]` 新增不透明前景/背景配对：pal 是底色，attr[0]=0 时文字用 palette[1]，
  attr[0]=1 时文字用 palette[9]。原 attr[0..2] 的兼容路径保留。
- 字符层导出像素域调色板给 RGB 的曲线、算法图、网格使用，避免白底黑图/多色残留。
- RGB scope=(16,96,512,256)，键盘=(16,400,600,80)。触摸命中区域同步更新。
- ALGO viewport=(272,144,512,256)；六路 EG 曲线图从 y=208/320 开始，240×80。
- Pitch EG 沿用 256 样本 RAM，显示为 (272,192,512,208)。对外发布菜单号 8 表示此视口；
  固件编辑页仍为 EG（3），HDMI 的波形/XY模式不受影响。
- 同时修正 Pitch EG `0x65` 的 23 位目标值打包（payload[46:24]），以及 RAM 恢复
  右键位缩放曲线的字段（payload[41:40]）。这两个字段原来分别溢出/错位。

## 构建与核对

1. `src/ui_firmware/build_firmware.ps1 -Zig <zig.exe>`，固件必须小于 65536 字节。
2. `sim/run_checks.ps1 -IverilogDirectory <iverilog bin>`，包含真实 RV32I 固件与 Goodix I2C 模型。
3. `tools/render_ui_capture.py --time <ns> --page <0..8> --out <png>` 从仿真写日志还原菜单。
   页面 8 为 Pitch EG。不是浏览器原型，波形/键盘另由 RGB RTL 仿真核对。
4. `gw_sh build_cli_hdmi.tcl`，之后必须检查 Fmax 及各域 setup/hold TNS。
5. `python tools/check_project_files.py` 检查 IDE hierarchy 文件列表。

实机还需要确认触摸手感、字体可读性、快速切页、音色保存/恢复和 HDMI 同时显示。
仿真通过不能替代这些检查。

## 本轮构建

双屏位流生成于 2026-10-23 18:33，固件 40,980 B；BSRAM 278/340，DSP 56.5/298。
四个时钟域的 setup/hold TNS 均为 0，主域 Fmax 55.564 MHz，RGB 域 39.434 MHz。
新版图形窗口单测日志为 `tmp/checks_ui_viewports.log`；基础回归日志为 `tmp/checks_ui_release.log`，最终触摸固件回归为 `tmp/checks_ui_delivery.log`，RGB 回归为 `tmp/checks_ui_rgb.log`。

触摸鲁棒性：菜单重绘期间可能漏掉松手帧。固件记录各触点上次按下位置，
当复用 ID 的坐标出现明显横向/纵向跳变时重新识别点击；正在拖动底部滑条时保持原拖动。
真实 I2C 回归模型也按 Goodix 的坐标报告机制锁存同一帧，避免脚本在读字节途中切换触点而制造假坐标。
