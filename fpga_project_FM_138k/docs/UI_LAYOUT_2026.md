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
- 主音量默认 5（MIDI 原始值 0..127），控制选定的音频输出；SETUP → AUDIO OUTPUT 在 SPEAKER / HEADPHONE 二选一，未选输出发送数字静音。
- PLAY 提供 WAVE / XY / FFT 三种实时显示；SETUP 的 SPECTRUM 直接打开首页频谱，DISPLAY 也可切换。
  ARP / SEQ / PANIC 与原琴键上方控制条已移除，后续工具仍可增加内部页。

## 实现

- `src/ui_firmware/main.c` 保留触摸 I2C、MIDI/参数协议、参数回读、曲线/算法计算。
- `src/ui_firmware/menu_layout.h` 负责新菜单绘制、配色和与之对应的触摸区域。
  与 main.c 同一编译单元，不需要额外软核或帧缓冲。
- 坐标按 8×16 字符格对齐，主按钮高度 48，底栏起点 y=416。
  保持 16 色调色板；配色无需抗锯齿或新的字库。
- 字符 `attr[3]` 新增不透明前景/背景配对：pal 是底色，attr[0]=0 时文字用 palette[1]，
  attr[0]=1 时文字用 palette[9]。原 attr[0..2] 的兼容路径保留。
- 字符层导出像素域调色板给 RGB 的曲线、算法图、网格使用，避免白底黑图/多色残留。
- RGB scope=(16,96,512,256)，键盘=(0,352,800,128)。触摸命中区域同步更新。
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

## 前次 UI 构建（键盘扩大前）

双屏位流生成于 2026-10-23 18:33，固件 40,980 B；BSRAM 278/340，DSP 56.5/298。
四个时钟域的 setup/hold TNS 均为 0，主域 Fmax 55.564 MHz，RGB 域 39.434 MHz。
新版图形窗口单测日志为 `tmp/checks_ui_viewports.log`；基础回归日志为 `tmp/checks_ui_release.log`，最终触摸固件回归为 `tmp/checks_ui_delivery.log`，RGB 回归为 `tmp/checks_ui_rgb.log`。

触摸鲁棒性：菜单重绘期间可能漏掉松手帧。固件记录各触点上次按下位置，
当复用 ID 的坐标出现明显横向/纵向跳变时重新识别点击；正在拖动底部滑条时保持原拖动。
真实 I2C 回归模型也按 Goodix 的坐标报告机制锁存同一帧，避免脚本在读字节途中切换触点而制造假坐标。

## 2026-10-23 扩大键盘与输出选择

- 15 个白键覆盖全宽 800 像素，每键 53/54 像素；键盘 y=352..479，高 128。
  黑键宽 32、高 80，显示与触摸共用相同分界公式。按下/松手仍按音符集合去重。
- 首页右侧保留主音量、预设、WAVE/XY、八度，删除 PANIC、ARP、SEQ 与键盘上方控制条。
- SETUP → KEY VELOCITY：1..127，默认 100，仅用于触屏 Note On；不改外部 MIDI 力度。
  调整后作用于新按下的音符，已有音符不会重触发。设置断电后恢复默认。
- SETUP → AUDIO OUTPUT：SPEAKER（默认，外部 MAX98357 音响）或 HEADPHONE（ES8388 OUT1）。
  两路共用同一最终 PCM 和主音量，未选路输出 0 样本；时钟始终运行，选择仅在完整 I2S 帧边界锁存。
  该选择不影响音源运算、FX、RGB/HDMI 波形输入，也不做插孔自动检测。
- Pitch EG 先判曲线边缘，再判网格，最后判填充，网格不再被曲线下方的背景填充遮挡。
- UI 控制寄存器 UI[5] 新增 bit13 headphone_select（0 音响、1 耳机），不改变原 visual_mode bit12。
- 音源 master_volume_target/current 与 UI 复位值同步改为 5，防止仅改显示但上电仍然大音量。
- 新测试 `tb_i2s_output_select` 检查两路互斥、左右样本位序、padding 静音及帧中切换。

本次最终双屏位流生成于 2026-10-23 19:38:10，固件 40,820 B；BSRAM 278/340，DSP 57.5/298。
四个时钟域 setup/hold TNS 均为 0。最终构建日志 `tmp/build_keyboard_delivery.log`；
全套回归 `tmp/checks_keyboard_release.log`，最终固件完整菜单回归 `tmp/checks_keyboard_final.log`，
键盘专项 `tmp/checks_keyboard_delivery.log`。位流校验值和实机检查事项见 `AI_HANDOFF.md` 末节。

## 实时频谱

首页保留 800×128 键盘，右侧 WAVE / XY / FFT 为三个 48 像素高按钮。
频谱使用 64 个对数频段柱与峰值标记，显示 -72..0 dBFS，主题颜色沿用既有设置。
RGB 主图 y=96..319，下面标注频率，右侧标注 dBFS；HDMI 同步显示同一份分析数据。
FFT、平滑、缓存和逐像素绘制均为 RTL，软核只选择模式和绘制菜单文字。
实现、频率分辨率与验证说明见 `SPECTRUM.md`。

## 128 原厂音色与单音滑音

PATCH 的原厂表扩为 ROM1A/1B/2A/2B 共 128 个，三位编号 001..128，26 页，每页 5 个、末页 3 个。
首页 PREV/NEXT 在两端循环，名称读取使用完整 7 位索引，修复超过 32 时重复前库名称的问题。
SETUP 右侧新增第四行 GLIDE MONO（默认 OFF），先选中，再用底部 ± 或滑条切换。
滑音为后键优先的单音 Legato，不设按键间隔门限；固定约 168 ms，松开最新键可回到仍按住的旧键。
用户持久保存方案见 `USER_PRESETS_PLAN.md`；当前 8 个 RAM 槽仍会掉电丢失。

## 辅助演奏

SETUP 右侧第五行（y=320..367）为 PRACTICE 入口，进入内部页面 9。
保留顶部八页签及底部 y=352..479 的全宽琴键；进入时固定显示八度 0，退出恢复。
y=48..79 为曲名、等待音高/状态与进度；y=80..127 为 WAIT/DEMO、START/PAUSE、RESTART 和速度。
y=128..351 为纯 RTL 下落音符，底部为判定线；黑白键与滑条沿用同一几何关系。
HDMI 同步显示 640×480 的落键和琴键，RGB 保持 800×480 的可触控完整菜单。
详见 `ASSISTED_PLAY.md`。

## 琶音器与 16 步音序器

SETUP 的 y=80..127 左右两个 368×48 入口分别为 ARPEGGIATOR 和 STEP SEQUENCER，
不挤占已有十个设置项。内部页面 10、11 都保留 y=352..479 全宽触屏琴键，顶栏仍选中 PLAY。

ARP：y=80..127 为 ON/HOLD/STOP/BPM，y=128..271 为六组参数行，y=272..319 为键盘八度及提示，
y=320..351 显示和弦音名、当前音、运行和踏板。所有 ± 为 48 像素高。

SEQ：y=80..127 为 START/STOP、STEP REC、REST、TIE、CLEAR BANK、SETTINGS；
y=128..223 是两排各八步、每步 96×48 的网格，y=224..271 编辑音高/力度，
y=272..319 为模式/长度，y=320..351 是播放/录入状态与 RAM 易失性说明。
SETTINGS 在相同上半屏切换 BPM/RATE/GATE/SWING/长度/模式参数；底部琴键保持可用。

播放指针用 `>`，编辑选择沿用主题底色；背景和强调色使用已有设置，无新增颜色体系。
离开工具页可继续外部键盘或 HOLD/音序器演奏。详见 `ARPEGGIATOR.md`、`STEP_SEQUENCER.md`。
