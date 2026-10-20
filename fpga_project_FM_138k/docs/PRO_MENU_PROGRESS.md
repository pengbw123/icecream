# 专业菜单/UI/效果器改造进�?
本文件是多阶段改造的**唯一进度账本**。每个阶段：开工前打标�?`phaseN-start`，完成后�?`phaseN-done`
并在此记录改动、验证结果、已知限制和下一阶段入口。新会话接手先读本文件，再读 `AI_HANDOFF.md`�?
阶段划分（每个阶段一次会话）�?- 0 地基：协议回�?算法路由/字符渲染/固件预算
- 1 编辑器骨�?+ PERFORM / ALGORITHM / OSC �?- 2 ENVELOPE / PITCH EG / LFO / 键位缩放 / 命名 / 用户�?- 3 效果�?A：合�?+ 混响移植
- 4 效果�?B：滤�?+ 失真
- 5 数码�?+ 主题落定 + 总回�?
已确认的默认决策：风格以 B「CONSOLE」为主、A「PANEL」为内置第二主题；保存先做内存用户槽�?效果器先 A �?B；交互为纯触摸（长按连发 + 滑条）；PC 侧可通过回读同步屏幕编辑结果�?
---

## 阶段 0�?026-10-20�?
### 已完�?
**1. 参数回读（新命令 0x69�?*
- `fm_poly_synth.v` 新增 `patch_read_address[9:0]` / `patch_read_data[15:0]`，直接读取实时的
  patch 寄存器（不复制存储）；回答寄存一拍�?- `fm_uart_control.v` 新增 0x69 处理与三拍等�?FSM，输�?`readback_data` / `readback_valid`�?  `top.v`、`top_138k.v` 透传�?- 软核接口：读寄存�?14 = 回读数据�?5 = 状态（bit0 就绪；写 15 清零）。固件流程：
  �?reg7/8 命令载荷 �?�?reg9 触发 �?轮询 reg15 �?�?reg14�?
回读地址表（10 位）�?
| 地址 | 内容 |
|---|---|
| 0x000 | algorithm 0..31 |
| 0x001 | feedback 0..7 |
| 0x002 | {13'd0, lfo_wave[2:0], lfo_sync, osc_sync} |
| 0x003 | transpose |
| 0x004/5/6/7 | LFO speed / delay / PMD / AMD |
| 0x008 | pitch mod sensitivity |
| 0x009/A/B | algorithm flags[47:0] 三段 |
| 0x040 + op*0x20 + n | 算子字段，op=0 �?OP6（与命令一致） |
| n=0 | {10'd0, detune[3:0], fixed, enable} |
| n=1/2 | frequency �?�?16 �?|
| n=3 | output level |
| n=4/5/6 | breakpoint / left depth / right depth |
| n=7 | {14'd0, right_curve, left_curve} |
| n=8 | {8'd0, AMS[1:0], velocity[2:0], rate_scaling[2:0]} |
| n=9..C | EG stage0..3 qrate�? 位有效） |
| n=D..10 | EG stage0..3 level |
| 0x140 + stage*8 + n | Pitch EG：n=0 step，n=1 target[15:0]，n=2 target[22:16] |

**2. 算法路由修复**
- `fm_uart_control.v` 内置 32×48 bit `algorithm_flags_rom`（新文件
  `src/generated/fm_algorithm_flags.mem`，由 `tools/generators/generate_algorithm_flags.py` �?  `tools/core/fm_patch.py` �?ALGORITHM_FLAGS 生成）�?- 0x60 现在同时写入 algorithm 和对应的 routing flags：屏上算法号与真实路由不会再矛盾�?  0x67 仍保留为显式覆盖，PC 工具原有流程�?x60 + 0x67）兼容�?
**3. 命令协议修正**
- 0x64 不再�?synth 侧回�?rate_scaling / velocity / AMS；这三位跟随 0x63（envelope）与预设装载�?- 0x68（per-key gain）标记为不支持：现在返回 `packet_error`，不再假装生效�?- 0x66 语义在文档中明确�?All-Notes-Off（不是参数提交）�?- 本地命令注入不再可能吞掉 UART 字节：新增一深保持寄存器 + `local_command_ready` 额外条件�?
**4. 字符显示层（多页菜单的渲染基础�?*
- 新模�?`src/rtl_char_display.v`�?28 �?× 32 行�?6 bit/�?  `{attr[3:0], palette[3:0], char[7:0]}`；写�?50 MHz、读�?33.3 MHz，严格简单双口且无初值，
  目标推断�?4 �?BSRAM（综合报告确认后回填）�?- attr：bit0 反显（整格填色、字形用 palette[0]）、bit1 下划线（末两行）、bit2 整格填充�?- 16 色可写调色板（写入来自软核），默认色板对应当前主题，后续主题切换只改调色板�?- 流水与背�?DE 对齐：格地址→格 RAM�? 拍）→字库（1 拍）→像素选择（组合）�?  �?`background_pipe` 同深度（hcount-2）�?- `rgb_visualizer.v` 用新层替换原 `rtl_menu_text` 候选（后者不再例化）；性能�?  （`menu_page==0`）仍不显示字符层，行为不变；`ENABLE_MENU_TEXT` 参数删除�?- 软核 text 口：reg6 �?`{addr[11:0], data[31:16]}`；新�?reg16 写调色板
  `{4'd0, index[27:24], color[23:0]}`�?
**5. 固件预算**
- `linker.ld` 增加 64 KiB 镜像断言与说明；`build_firmware.ps1` 注释说明 64 KiB 取指窗口�?  128 KiB 数据镜像的由来（行为不变：镜�?�?4 KiB、hex 固定 32768 字）�?
**6. 回归**
- 新增 `sim/tb_fm_readback.sv`�?x62/0x63 写后经真�?synth 回读�?x60 自动�?flags�?x68 报错�?  注入�?UART 字节保持、预设装载后 flags 正确�?- 新增 `sim/tb_char_display.sv`：字形像素、反�?填充/下划线、调色板、禁用层、流水对齐�?- `sim/run_checks.ps1` 已包含两个新用例�?
### 验证结果
- 两个�?testbench 通过；`sim/run_checks.ps1` 全量通过（含既有 IO/触摸/RGB/波形/XY 用例）�?- 完整综合、布局布线、位流生成成功（2026-10-20 16:52，`impl/pnr/fm_138k_rgb.fs`）：
  - 资源：Logic 19388 (15%)、Register 10567、CLS 14308、BSRAM 119/340、DSP 23.5/298�?  - 字符阵列推断�?**SDPB +4 �?*�?7�?1），无寄存器爆炸；确�?PA2122 已规避�?  - 时序�?0 MHz �?Fmax 51.218 MHz（slack +0.476 ns）、像素域 47.214 MHz（slack �?+8.7 ns），
    两域 setup/hold TNS 均为 0�?  - 曾出现一�?PA2122：调色板同步寄存器被推断�?WRITE_MODE=2'b10 �?DPB。已�?    `syn_ramstyle = "registers"` 强制为触发器后通过（与 rv32i 的处理方式一致）�?- 代价：回�?mux �?Logic +1705�?0 MHz 余量�?3.46 ns 收到 0.476 ns。仍满足约束，但后续阶段
  若要更多 50 MHz 逻辑，优先把回读改成"写镜�?RAM + 单口�?以换回余量�?
### 已知限制 / 下一阶段注意
- 字符层当前只�?`menu_page != 0` 时显示；固件仍未�?menu_page/字符 RAM（阶�?1）�?- 回读地址�?生效�?：detune 无效位不会回读（默认 7），固定模式频率�?Q0.32 原始字�?- 0x69 与本地命令共享解析器：固件必须等 reg9 就绪再发下一条，阶段 1 会实现发送队列�?- 综合后必须确认字�?RAM 推断�?BSRAM（Register 增量应为几百而非上万）。若失败，改用显�?SDPB�?- 50 MHz 域最差路径仍是预设装载（preset_global_memory �?lfo_fade），与回读无直接关系�?  但新增逻辑改变了布局；阶�?1 加菜单逻辑后必须重新看两域 TNS �?Fmax�?
---

## 阶段 1�?026-10-20�?
### 已完�?
**固件（本次主要工作量�?5 708 B / 64 KiB�?*
- `main.c` 重写为页面引擎：16 色可写调色板�? 个页签、行选择、`-/+` 步进、长按连发（500 ms 后每 100 ms）�?  横向拖动滑条、整屏字符层重绘�?- 页面�? PERFORM 保持�?RTL 画面与右列控制不变，只新�?点顶部标题条进入菜单"�? ALGORITHM�?  3 OSC 1-6�?..8 �?PHASE 2 占位�?- 回读：进入页面用 0x69 读取当前值（全局 11 项、每算子 17 项）；编辑用 0x60/0x62/0x63/0x64 下发�?  算法选择�?0x60 同时装路�?flags，屏上算法号与声音一致�?- 频率换算在固件完成（�?32 位整数，无浮点、无 64 位、无 libgcc 乘法依赖）：
  ratio 模式 `(coarse==0?0.5:coarse)*(1+fine/100)*detune_ratio`，fixed 模式�?4×100 预计算表�?  detune �?15 项定点增量；反解 coarse/fine 用解析式（ratio）或最近邻（fixed）�?- 编辑 rate scaling / velocity / AMS 时复�?0x63：先读回该算�?stage0 �?qrate/level 原样带回�?  避免覆盖包络（阶�?0 的协议语义修正在这里被实际使用）�?- 主题 B 调色板在启动时写入；RTL 菜单页背景改为平坦底色并隐藏演奏页图形�?
**RTL**
- `rgb_visualizer.v`：`page_frame!=0` 时整屏铺 `bg_frame`，删除演奏页�?4 处旧菜单特判�?  其余沿用阶段 0 的字符层�?
**回归**
- `tb_touch_ui.sv` 扩展为真实固件菜单回归：顶部进入 ALGO（检�?0x69 读、字符层写入）→ 行选择 �?  `+` 键发 0x60 �?�?PERF �?再进 ALGO �?�?OSC �?�?OP1；并把字符写流导出到
  `tmp/menu_cells.txt`，用 `tmp/render_menu.py` 离线渲染�?`tmp/menu_preview.png` 核对版面�?- 调试中发�?testbench �?松手"窗口�? ms）短于固件轮询周期，会被当成"按住同一触点"�?  实机抬手帧持�?>10 ms，不会触发。测试窗口已改为 8 ms�?- 全量 `sim/run_checks.ps1` 通过�?4 项，含新增的字符层、回读、菜单三项）�?
### 验证
- 位流：`impl/pnr/fm_138k_rgb.fs`�?026-10-20 17:46）�?- 资源：Logic 19375 (15%)、Register 10567、CLS 14352、BSRAM 123/340、DSP 23.5/298、PLL 1/12�?- 时序�?0 MHz �?Fmax 56.449 MHz（slack +2.29 ns），像素�?43.015 MHz，两�?setup/hold TNS 均为 0�?
### 已知限制
- ALGORITHM 页目前是**文字版路由表**（OP6..OP1 �?OUT/IN/FB），六算子连线图留到阶段 2�?- 4..8 页为占位；EG/Pitch EG/LFO/键位缩放/命名/用户槽在阶段 2�?- 暂未�?operator enable 行与 LFO 全局字段页；MODE 切换会把 coarse/fine 归零�?- 预设切换（CC27）会覆盖编辑�?UI 缓存不会自动刷新；阶�?2 加用户槽与重同步�?- 值改变后整页重绘�?0.4 ms，快速拖动时可能有轻微闪烁；样式阶段优化为局部刷新�?- 回读数据�?生效�?：无�?detune 位不回读；固定模式频率以 Q0.32 字反解�?
---

## 阶段 1.1�?026-10-20，实板反馈后的两处修�?+ 演奏页重设计�?
### 问题与根�?1. **主题色不生效（预览红色、实板橙黄）**：`touch_ui_controller.v` �?`address[5:2]` �?4 位寄存器号，
   `UI[16]`�?x23000040）被别名成寄存器 0，调色板写入全部丢失，屏上一直用 RTL 默认�?`0xFFB95A`�?   已改�?`address[7:2]`�? 位，最�?64 个寄存器），调色�?新寄存器都能正常工作�?2. **�?PERF 后闪屏、无法稳定返�?*：旧演奏页把"点顶部标题条(y<16)"当进入菜单，�?PERF 页签本身就在
   y<16；手指未抬起时会被再次判�?点顶�?�?再进菜单。现在页签在所有页面常驻，顶部不再有隐藏进入区�?   PERF 页签按下是幂等操作，不会重复进入�?
### 本次改动
- **页签常驻所有页�?*（第 0 行），字符层�?仅菜单页"改为由软�?`UI[17]` 使能，开机清屏后再开�?- **演奏页重设计**（`draw_perf`）：页签�?+ 状态行（预设号/名称/音量/八度/算法/声部�? 右侧 16 px 网格
  快捷控制（PRESET/VOLUME/OCTAVE/PANIC/VIEW/XY DELAY/AUTO）；RTL 只保留波�?XY、电平�? �?EG、键盘，
  删掉旧右列与�?`rtl_performance_text` 文本；波�?XY/电平/EG/键盘颜色跟随 `wave_color`（主题驱动）�?- **主题可�?*�? 套内置主题（GRAPHITE/AMBER/ICE），`8 UTIL` 页点一下切换；主题同时�?16 色调色板�?  RTL 的背�?波形/XY 颜色�?- **操作说明**：菜单行改为从第 6 行开始（ALGO/OSC），触摸判定同步 `content_top()`；OSC �?OP 选择行在�?4 行�?- 新增 `docs/UI_FIRMWARE_GUIDE.md`：软�?RTL 分工、寄存器映射、命令与回读、改固件流程、坑�?
### 验证
- `tb_touch_ui` 扩展：常驻页签、PERF 页签按住不重复进入、主题写入与切换、字符层使能�?  `tb_rgb_visualizer` �?`text_enable=0`（保持纯 RTL 图形回归）�?- 全量回归通过；综�?PnR：Logic 18931、Register 11214、CLS 14397、BSRAM 130/340、DSP 23/298�?  50 MHz �?Fmax 53.752 MHz、像素域 41.433 MHz，两�?TNS 0�?- 版面预览：`tmp/menu_perf.png`（字符层）、`tmp/perf_composite.png`（叠�?RTL 图形近似）�?  `tmp/menu_osc.png`、`tmp/menu_theme.png`；由真实固件字符�?+ `tmp/render_menu.py` 生成�?
### 已知限制
- 预览中的参数值是 testbench 的模拟回读（常数），实机为真实值；预览图形是近似合成，不是真机照片�?- 主题只覆盖字符层 + 波形/XY/电平/EG/键盘；示波器网格与面板底色保持中性深色�?- `8 UTIL` 目前只做主题；EG/Pitch/LFO/命名/用户槽仍在阶�?2�?
---

## 阶段 2 入口清单（下次会话直接照做）

1. ALGORITHM 六算子连线图：RTL 画布（按 48 bit flags 画盒�?总线/箭头�? 固件标签坐标约定�?2. ENVELOPE 页：6 算子 × 4 段速率/电平，带 4 段柱状图；Pitch EG 页；LFO 页（波形/速度/延迟/PMD/AMD/Sync）�?3. 键位缩放曲线预览；operator enable 行；全局字段补齐�?4. 命名页（10 字符）、用户槽保存/读取、ROM1A 复制、CC27 拦截�?UI 重同步�?5. 每步保持 `sim/run_checks.ps1` 通过；阶段末完整 PnR + 实板确认清单�?

