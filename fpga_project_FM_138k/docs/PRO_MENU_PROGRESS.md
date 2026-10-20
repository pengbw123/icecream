# 专业菜单/UI 改造进度账�?
> 本文件是阶段 0..5 的唯一进度账本。接手前先读 `AI_HANDOFF.md`，改 UI 固件先读 `UI_FIRMWARE_GUIDE.md`�?> 用户操作说明�?`USER_MANUAL_UI.md`。本文件统一使用 UTF-8；不要在 Windows PowerShell 5.1 里用
> `Set-Content` 直接改中文（默认 ANSI 会造成编码混合）�?
## 屏幕与输入的基础事实

- 800×480 RGB565�?3.333 MHz 像素时钟、无帧缓冲；波形/XY/电平/EG/键盘�?RTL 逐像素画�?- 字符层：128 �?× 32 行、每�?16 bit `{attr[3:0], palette[3:0], char[7:0]}`�? �?BSRAM�?  `attr` bit0 反显、bit1 下划线（末两行）、bit2 整格填充�?- 软核 RV32I 只写"哪个格子放什�?，不存像素；触摸坐标与按钮位置强耦合�?- UI 寄存器（`0x23000000`，索�?= 地址/4�?*索引位是 `address[7:2]`**）：
  0 触摸/I2C�? 微秒�? 事件忙�? MIDI 事件�? `{voices,algorithm,preset,volume}`�? ui_state
  （页�?[27:24]）�? 字符格�?/8 命令载荷�? 命令字节�?0/11/12 背景/波形/XY 色�?3 numeric�?  14 回读数据�?5 回读就绪�?6 调色�?`{index[27:24],color[23:0]}`�?7 字符层使能�?- 本地参数命令�?x60 全局�?x61 PMS�?x62 算子�?x63 包络段�?x64 键位缩放�?x65 Pitch EG�?  0x66 全音关�?x67 路由 flags�?x69 参数回读（payload[9:0]=地址，结果在 UI[14]，UI[15] bit0 就绪）�?- 回读地址：全局 0x000..0x00B；算�?0x040+op*0x20+offset�? detune/fixed/enable�?/2 频率�?  3 电平�? BP�?/6 左右深度�? 左右曲线�? rs/vel/AMS�?..12 四段 qrate�?3..16 四段电平）；
  Pitch EG 0x140+stage*8�? 系数�? 目标�?16 位，2 目标�?7 位）�?
## 阶段 0（已完成，`phase0-done`�?
- 参数回读 0x69、算法路�?flags ROM、字符显示层（字�?调色�?双口 RAM）、固件预算加固�?- 修复：字�?RAM 调色板阵列推断成 DPB 导致 PA2122；字符层 2 级流水对齐背景�?
## 阶段 1（已完成，`phase1-done`�?
- 固件页面引擎：调色板、页签、行选择、`-/+`、长按连发、拖动滑条、整屏重绘�?- ALGORITHM 页（文字路由表）�?OSC 1-6 页（13 个字段）可读改；0x69�?x60/0x62/0x63/0x64�?- 频率换算（ratio 公式、fixed 4×100 表、detune 定点）全部固件内 32 位整数完成�?- 编辑 rs/vel/AMS 时复�?0x63：先读回该算�?stage0 �?qrate/level 原样带回�?- 回归：`tb_touch_ui` 真实固件菜单路径；字符流导出 + `tmp/render_menu.py` 预览�?
## 阶段 1.1（已完成，`phase1b-done`�?
- 修复主题色不生效：`touch_ui_controller` �?UI 索引�?`address[5:2]` 改为 `address[7:2]`
  （旧�?`UI[16]` 被别名成寄存�?0，调色板写入全丢，屏上一直是 RTL 默认的橙黄色）�?- 页签常驻所有页面；删除"点顶部进菜单"的隐藏区域（旧版会和 PERF 页签冲突，导致闪�?回不去）�?- 演奏页重设计：页�?+ 状态行 + 右侧 16px 网格快捷键；RTL 只保留波�?XY、电平、EG、键盘；
  删除�?`rtl_performance_text` 与右列图形；波形/键盘颜色跟随 `wave_color`�?- 3 套主题（GRAPHITE/AMBER/ICE），`8 UTIL` 页点击切换（调色�?+ 背景/波形/XY 颜色）�?- 新增 `UI_FIRMWARE_GUIDE.md`；`tb_rgb_visualizer` �?`text_enable=0`�?
## 阶段 1.2（已完成，`phase1c-done`�?
- 修复步进按钮重复触发：`release_all()` 不再�?`control_down`（否则按住的手指每帧都算"新按�?�?  OCTAVE 会一路冲�?±3）；步进类按钮加 300 ms 去抖（首次按下不受影响）�?- 连发策略：按�?1.5 s 后才开始，�?150 ms 一步（演奏页快捷键与菜�?± 一致）；菜�?± 另加 120 ms
  去抖，切页时清零�?- 双行 ± 视觉问题�? 格高按钮只在上格画一次符号；VOLUME/OCTAVE/XY DELAY 标签行显示当前值�?- XY 主题色：GRAPHITE 红橙 0xFF6A2C、AMBER 0xFFC040、ICE 0x9BE8FF�?- 参数持久化行为写�?`UI_FIRMWARE_GUIDE.md` 4.1�?
## 阶段 2a（已完成，`phase2a-done`�?
- ENVELOPE 页（4 EG）：OP1..OP6、RATE1..4 / LEVEL1..4�?..99）、右�?4 段柱状预览；�?0x63�?  qrate 与电平换算与 `tools/core/fm_patch.py` �?Dexed 标定一致�?- LFO 页（5 LFO）：WAVE/SPEED/DELAY/PMOD/AMOD/PMS/LFO SYNC/KEY SYNC；写 0x60+0x61�?- 修正 0x002 回读位序：实�?`wave[4:2], lfo_sync[1], osc_sync[0]`�?- 新增 `__mulsi3`（移位加），固件 23 176 B；回�?14 项通过�?
## 阶段 2c（进行中，图形化第一批）

- **EG 曲线面板（RTL�?*：新�?`src/ui_eg_curve.v`。固件把 192 �?0..255 的高度样�?  （每像素列一个）通过 UI[18]/UI[19] 写入一�?192×9 的双时钟 BSRAM；视频侧按列查表�?  逐像素比较得�?填充/亮边/网格"三类，再叠加到字符层下方。面�?192×256 像素�?  带网格、顶部亮边和主题色填充。AMP/PITCH 两种包络都走这条通路�?  固件 `eg_rebuild()`：按 RATE 反比分配四段宽度、按 LEVEL 换算高度，PITCH 模式�?50（原音高）出发�?- **OSC �?ASCII 路由**：页面底部新�?6 �?`ROUTING (ASCII)`，显示每个算子的 OUT/IN/FB�?  flags 缓存�?`g_flags[3]`，只在该页进�?换算法时�?0x69，避免拖动时反复读�?- **测试**：新�?`sim/tb_eg_curve.sv`（填�?亮边/网格/禁用四类断言）�?- 综合：Logic 19110、Register 11263、BSRAM 131/340�?0 MHz Fmax 59.254 MHz�?  像素�?45.439 MHz，TNS 0；固件约 29.6 KiB�?- 预览：`tmp/menu_eg_pitch.png`（PITCH 曲线）、`tmp/menu_eg_amp.png`（AMP 曲线）�?
### 2d 待做（图形化第二批）
- ALGORITHM 页的 Dexed 风格矢量算法图：32 套版式表 + 方框/正交连线/箭头/反馈环；
  需�?`tools/generators/generate_algorithm_layout.py` �?RTL 画布�?- 按钮圆角/按下高亮：按下变色已有（反显），圆角需要同样的画布层，计划与算法图一起做�?
## 阶段 2b（已完成，`phase2b-done`�?
- Pitch EG：EG �?`AMP EG / PITCH EG` 切换；PRATE1..4、TARGET1..4�?..99，TARGET 50=原音高）�?  �?0x65，系�?目标�?`fm_patch.py` �?DX7 表（`DX7_PITCH_RATE/LEVEL`）换算；回读 0x140+stage*8�?- ALGORITHM 页：新增 TRANSPOSE�?..48）；路由由文字表改为 6 个方框的实时图（OUT/IN/FB），
  纯字符层绘制（无额外 RTL）；并把 `ENABLE` 行加�?OSC 页（�?0x62）�?- NAME 页（7 NAME）：10 字符命名（点字符选中，`-/+` 换字符）�? 个用户槽 SAVE/LOAD�?  槽快�?= 9 个全局�?+ 6×17 算子�?+ 12 �?Pitch EG 字（0x69 读取�?x60/0x62/0x63/0x64/0x65 写回）�?  存在固件 RAM，切音色/退出菜单不丢，**断电仍丢**�?- 预设切换（CC27/外部）后自动更新音色名，并在菜单页重载当前页缓存；演奏页刷新状态行�?- 验证：`tb_touch_ui` 新增 transpose、pitch EG、OSC enable、NAME 编辑、SAVE/LOAD 检查；
  全量回归 14 项通过。PnR：Logic 18931、Register 11214、BSRAM 130/340�?0 MHz Fmax 53.752 MHz�?  像素�?41.433 MHz，TNS 0。固�?28 612 B�?4 KiB �?44%）�?- 预览：`tmp/menu_algo.png`、`tmp/menu_eg_pitch.png`、`tmp/menu_name.png`�?
## 后续阶段

- 阶段 3：效果器（合�?混响、滤�?失真），FX 页接上参数�?- 阶段 4�? 段数码管、更多主�?视觉打磨�?- 阶段 5：性能/时序收尾、实板清单、发布�?
## 已知限制

- 用户槽在 RAM，掉电丢失；真正掉电保存需�?Flash/SD�?- EG �?0..99 与内部定点换算可能显示差 1（声音正确）�?- 菜单页重绘约 0.4 ms，快速拖动可能轻微闪烁�?- 路由图是"逻辑路由"表示，不�?DX7 原厂算法图的精确排版�?
