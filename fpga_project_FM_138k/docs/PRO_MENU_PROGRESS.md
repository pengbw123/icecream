# 专业菜单/UI 改造进度账本

> 本文件是阶段 0..5 的唯一进度账本。接手前先读 `AI_HANDOFF.md`，改 UI 固件先读 `UI_FIRMWARE_GUIDE.md`，
> 用户操作说明见 `USER_MANUAL_UI.md`。本文件统一使用 UTF-8；不要在 Windows PowerShell 5.1 里用
> `Set-Content` 直接改中文（默认 ANSI 会造成编码混合）。

## 屏幕与输入的基础事实

- 800×480 RGB565、33.333 MHz 像素时钟、无帧缓冲；波形/XY/电平/EG/键盘由 RTL 逐像素画。
- 字符层：128 列 × 32 行、每格 16 bit `{attr[3:0], palette[3:0], char[7:0]}`，4 块 BSRAM；
  `attr` bit0 反显、bit1 下划线（末两行）、bit2 整格填充。
- 软核 RV32I 只写"哪个格子放什么"，不存像素；触摸坐标与按钮位置强耦合。
- UI 寄存器（`0x23000000`，索引 = 地址/4，**索引位是 `address[7:2]`**）：
  0 触摸/I2C、1 微秒、2 事件忙、3 MIDI 事件、4 `{voices,algorithm,preset,volume}`、5 ui_state
  （页号 [27:24]）、6 字符格、7/8 命令载荷、9 命令字节、10/11/12 背景/波形/XY 色、13 numeric、
  14 回读数据、15 回读就绪、16 调色板 `{index[27:24],color[23:0]}`、17 字符层使能。
- 本地参数命令：0x60 全局、0x61 PMS、0x62 算子、0x63 包络段、0x64 键位缩放、0x65 Pitch EG、
  0x66 全音关、0x67 路由 flags、0x69 参数回读（payload[9:0]=地址，结果在 UI[14]，UI[15] bit0 就绪）。
- 回读地址：全局 0x000..0x00B；算子 0x040+op*0x20+offset（0 detune/fixed/enable，1/2 频率，
  3 电平，4 BP，5/6 左右深度，7 左右曲线，8 rs/vel/AMS，9..12 四段 qrate，13..16 四段电平）；
  Pitch EG 0x140+stage*8（0 系数，1 目标低 16 位，2 目标高 7 位）。

## 阶段 0（已完成，`phase0-done`）

- 参数回读 0x69、算法路由 flags ROM、字符显示层（字库/调色板/双口 RAM）、固件预算加固。
- 修复：字符 RAM 调色板阵列推断成 DPB 导致 PA2122；字符层 2 级流水对齐背景。

## 阶段 1（已完成，`phase1-done`）

- 固件页面引擎：调色板、页签、行选择、`-/+`、长按连发、拖动滑条、整屏重绘。
- ALGORITHM 页（文字路由表）与 OSC 1-6 页（13 个字段）可读改；0x69→0x60/0x62/0x63/0x64。
- 频率换算（ratio 公式、fixed 4×100 表、detune 定点）全部固件内 32 位整数完成。
- 编辑 rs/vel/AMS 时复用 0x63：先读回该算子 stage0 的 qrate/level 原样带回。
- 回归：`tb_touch_ui` 真实固件菜单路径；字符流导出 + `tmp/render_menu.py` 预览。

## 阶段 1.1（已完成，`phase1b-done`）

- 修复主题色不生效：`touch_ui_controller` 的 UI 索引从 `address[5:2]` 改为 `address[7:2]`
  （旧版 `UI[16]` 被别名成寄存器 0，调色板写入全丢，屏上一直是 RTL 默认的橙黄色）。
- 页签常驻所有页面；删除"点顶部进菜单"的隐藏区域（旧版会和 PERF 页签冲突，导致闪屏/回不去）。
- 演奏页重设计：页签 + 状态行 + 右侧 16px 网格快捷键；RTL 只保留波形/XY、电平、EG、键盘；
  删除旧 `rtl_performance_text` 与右列图形；波形/键盘颜色跟随 `wave_color`。
- 3 套主题（GRAPHITE/AMBER/ICE），`8 UTIL` 页点击切换（调色板 + 背景/波形/XY 颜色）。
- 新增 `UI_FIRMWARE_GUIDE.md`；`tb_rgb_visualizer` 补 `text_enable=0`。

## 阶段 1.2（已完成，`phase1c-done`）

- 修复步进按钮重复触发：`release_all()` 不再清 `control_down`（否则按住的手指每帧都算"新按下"，
  OCTAVE 会一路冲到 ±3）；步进类按钮加 300 ms 去抖（首次按下不受影响）。
- 连发策略：按住 1.5 s 后才开始，每 150 ms 一步（演奏页快捷键与菜单 ± 一致）；菜单 ± 另加 120 ms
  去抖，切页时清零。
- 双行 ± 视觉问题：2 格高按钮只在上格画一次符号；VOLUME/OCTAVE/XY DELAY 标签行显示当前值。
- XY 主题色：GRAPHITE 红橙 0xFF6A2C、AMBER 0xFFC040、ICE 0x9BE8FF。
- 参数持久化行为写进 `UI_FIRMWARE_GUIDE.md` 4.1。

## 阶段 2a（已完成，`phase2a-done`）

- ENVELOPE 页（4 EG）：OP1..OP6、RATE1..4 / LEVEL1..4（0..99）、右侧 4 段柱状预览；写 0x63。
  qrate 与电平换算与 `tools/core/fm_patch.py` 的 Dexed 标定一致。
- LFO 页（5 LFO）：WAVE/SPEED/DELAY/PMOD/AMOD/PMS/LFO SYNC/KEY SYNC；写 0x60+0x61。
- 修正 0x002 回读位序：实际 `wave[4:2], lfo_sync[1], osc_sync[0]`。
- 新增 `__mulsi3`（移位加），固件 23 176 B；回归 14 项通过。

## 阶段 2b（已完成，`phase2b-done`）

- Pitch EG：EG 页 `AMP EG / PITCH EG` 切换；PRATE1..4、TARGET1..4（0..99，TARGET 50=原音高）；
  写 0x65，系数/目标按 `fm_patch.py` 的 DX7 表（`DX7_PITCH_RATE/LEVEL`）换算；回读 0x140+stage*8。
- ALGORITHM 页：新增 TRANSPOSE（0..48）；路由由文字表改为 6 个方框的实时图（OUT/IN/FB），
  纯字符层绘制（无额外 RTL）；并把 `ENABLE` 行加到 OSC 页（写 0x62）。
- NAME 页（7 NAME）：10 字符命名（点字符选中，`-/+` 换字符）；8 个用户槽 SAVE/LOAD。
  槽快照 = 9 个全局字 + 6×17 算子字 + 12 个 Pitch EG 字（0x69 读取，0x60/0x62/0x63/0x64/0x65 写回）。
  存在固件 RAM，切音色/退出菜单不丢，**断电仍丢**。
- 预设切换（CC27/外部）后自动更新音色名，并在菜单页重载当前页缓存；演奏页刷新状态行。
- 验证：`tb_touch_ui` 新增 transpose、pitch EG、OSC enable、NAME 编辑、SAVE/LOAD 检查；
  全量回归 14 项通过。PnR：Logic 18931、Register 11214、BSRAM 130/340；50 MHz Fmax 53.752 MHz、
  像素域 41.433 MHz，TNS 0。固件 28 612 B（64 KiB 的 44%）。
- 预览：`tmp/menu_algo.png`、`tmp/menu_eg_pitch.png`、`tmp/menu_name.png`。

## 后续阶段

- 阶段 3：效果器（合唱/混响、滤波/失真），FX 页接上参数。
- 阶段 4：7 段数码管、更多主题/视觉打磨。
- 阶段 5：性能/时序收尾、实板清单、发布。

## 已知限制

- 用户槽在 RAM，掉电丢失；真正掉电保存需要 Flash/SD。
- EG 的 0..99 与内部定点换算可能显示差 1（声音正确）。
- 菜单页重绘约 0.4 ms，快速拖动可能轻微闪烁。
- 路由图是"逻辑路由"表示，不是 DX7 原厂算法图的精确排版。
