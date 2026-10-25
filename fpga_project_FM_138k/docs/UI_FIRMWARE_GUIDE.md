# UI 软核与菜单固件说明

2026-10-24 SD 用户音色版：UI 指令窗口扩为 **80 KiB（64+16）**，数据 RAM 仍128 KiB；
`build_firmware.ps1` 使用 `-Oz` 并同时生成 `firmware.hex` 和 `firmware_high.hex`。
旧章节中的64 KiB指令上限已不适用于此版。ARP/SEQ 加减点按一步，450 ms 后每50 ms重复；
HOLD离开ARP页锁定和弦并直通即兴按键。SD说明见 `SD_USER_PATCHES.md`。
LIVE/BACKING 双 Part 与 GLIDE MS 已实现，当前固件70,268/81,920B，详见 `TWO_PARTS.md`。

2026-10-24 32 复音版：声部计数高 3 位新增到 UI[4][26:24]，音色高位仍在 [23:22]，
UI[59] 只读返回声部容量。必须使用 `status_voices()`，不能继续仅取 5 位。
当前固件 60,604 / 65,536 B；详见 [POLYPHONY_32.md](POLYPHONY_32.md)。

2026-10-24：新增性能监测子页（page=12），入口 SETUP → PERFORMANCE >；
UI[56]=快照索引，UI[57]=只读数据，UI[58] bit0=捕获、bit1=清统计。
逻辑在 `ui_firmware/performance_menu.h`，详见 [PERFORMANCE_MONITOR.md](PERFORMANCE_MONITOR.md)。
本版固件 60,304 / 65,536 B，增加功能时仍须检查指令 ROM 上限。

> 2026-10-23 菜单已改版：当前八页为 PLAY / ALGO / OSC / EG / LFO / FX / PATCH / SETUP。
> 新版布局、独立背景/主题色、触摸操作、预留入口与编译方法以 [UI_LAYOUT_2026.md](UI_LAYOUT_2026.md) 为准。
> 以下旧阶段记录及旧布局描述保留作历史参考；音源参数的含义仍可参考。


本文写给第一次改这套 UI 的人：哪些代码在软核里、像素怎么来、改固件的流程。
实现状态见 `PRO_MENU_PROGRESS.md`；用户说明见 `USER_MANUAL_UI.md`。

## 1. 分工：软核做逻辑，RTL 做像素

| 部分 | 位置 | 做什么 |
|---|---|---|
| RV32I 软核 | `usb_midi/rtl/rv32i.v` + `ui_firmware/main.c` | 触摸、页面、字符格、参数命令/回读、主题、用户槽、图形位图绘制 |
| 字符层 | `rtl_char_display.v` | 128×32 格 ×16 bit，4 块 BSRAM，16 色可写调色板 |
| 包络曲线 | `ui_eg_curve.v` | 256×256 面板，256 个高度样本查表画填充/亮边/网格 |
| 算法位图 | `ui_algo_map.v` | 512×256 2bpp 画布（32 KiB BSRAM）；类 1=载波绿、2=调制蓝、3=白 |
| 效果器 | `audio_fx.v` | 32×16 位配置寄存器；FILTER→REVERB→DELAY→DIST→CHORUS→PHASER + 软限幅；失真为 tanh 软削波、动态响度匹配与干湿混合，连续参数平滑 |
| 注意 | — | 音频算术必须先扩位再相减；16 位 wet-dry 差会溢出（已修） |
| 合唱 | `audio_chorus.v` | 2048 样本延迟线 + LFO，freq/depth/mix |
| 移相 | `audio_phaser.v` | 4 级全通 + LFO，freq/depth/mix |
| 延迟 | `audio_delay.v` | 40..670 ms 延迟线，decay/rate/mix（下一步扩到 20..1000 ms） |
| 混响 | `audio_reverb.v` | 3 梳状（各自反馈）+ 全通 + DC 阻断，type/decay/mix |
| EG 六面板 | `ui_eg_multi.v` | 6×128 样本包络面板（3×2）；面板 p 显示算子 5-p（DX7 内部序号 0=OP6） |
| 光栅合成 | `rgb_visualizer.v` | 800×480 RGB565：波形/XY/EG/键盘 + 字符层/曲线/位图叠加 |
| FM 引擎 | `fm_poly_synth.v` 等 | 与 UI 解耦，只收命令/MIDI |

没有软核帧缓冲：软核写"字符格"和图形位图，像素由 RTL 扫描时实时合成。

字符格 `addr=(row<<7)|col`（col 0..99、row 0..29），`{attr[3:0],pal[3:0],char[7:0]}`；
attr bit0 反显、bit1 下划线（末两行）、bit2 填充。

## 2. UI 寄存器（`0x23000000`，索引 = 地址/4 = `address[7:2]`）

| 索引 | 读 | 写 |
|---|---|---|
| 0 | 触摸/复位状态 | I2C 开漏 |
| 1 | 微秒 | — |
| 2 | MIDI 事件忙 | — |
| 3 | MIDI 事件 | 触发事件 |
| 4 | `{voices,algorithm,preset,volume}` | — |
| 5 | ui_state（页号 [27:24] 等） | 写 ui_state |
| 6 | — | 字符格 `{addr[11:0], attr[19:16], pal[23:20], char[31:24]}` |
| 7/8 | — | 命令载荷 lo/hi |
| 9 | 命令口就绪 | 命令字节 |
| 10/11/12 | — | 背景/波形/XY 颜色 |
| 14 | 回读数据 | — |
| 15 | 回读就绪 bit0 | 写 0 清零 |
| 16 | — | 调色板 `{index[27:24], color[23:0]}` |
| 17 | — | 字符层使能 bit0 |
| 18/19 | — | 旧单曲线面板（保留，当前 138K 不再使用） |
| 25/26 | — | 六算子包络面板基址 / 32 位字（自动 +4 字节） |
| 27 | — | 六算子包络面板使能 bit0 |
| 20/21 | — | 算法图旧逐字节上传口（保留） |
| 22 | — | 算法图使能 bit0 |
| 23/24 | — | 算法图上传基址 / 32 位字（RTL 自动写 4 字节并 +4） |

> 索引位是 6 位：旧版用 4 位导致 `UI[16]` 被别名成 0，主题色一直不生效。

## 3. 命令与回读

走 `UI[7]/[8]/[9]` 不需要 A5/5A 头和校验：

| 命令 | 作用 | 关键字段 |
|---|---|---|
| 0x60 | 全局 | alg[4:0], fb[10:8], osc_sync[11], lfo_sync[12], transpose[22:16], lfo_wave[26:24], speed[38:32], delay[46:40], PMD[54:48], AMD[62:56] |
| 0x61 | PMS | sensitivity[2:0] |
| 0x62 | 算子 | index, enable[8], fixed[9], detune[13:10], detune_valid[14], freq[47:16], level[63:48] |
| 0x63 | 包络段 | index, stage[9:8], qrate[31:16], level[47:32], rs[50:48], vel[58:56], AMS[61:60] |
| 0x64 | 键位缩放 | index, bp[14:8], ld[22:16], rd[30:24], lc[33:32], rc[41:40] |
| 0x65 | Pitch EG | stage, coefficient[23:8], target[46:24]（23 位 Q8.15） |
| 0x66 | All Notes Off | — |
| 0x67 | 路由 flags | flags[47:0] |
| 0x69 | 回读 | address[9:0]；结果 UI[14]，UI[15] 就绪；0x200+addr 读 FX 寄存器 |
| 0x70 | FX 写 | payload[5:0]=FX 寄存器地址（0..31），payload[23:8]=16 位值 |

固件封装 `cmd(op,lo,hi)`、`rd(addr)`；`rd()` 等 UI[15]，读完写 0。

## 4. 改固件流程

1. 改 `src/ui_firmware/main.c`（新增源文件要加进 `build_firmware.ps1` 的 sources）。
2. 编固件：`src\ui_firmware\build_firmware.ps1 -Zig <zig.exe>`（必须，综合只读 hex）。
3. 回归：`sim\run_checks.ps1 -IverilogDirectory <iverilog bin>`。
4. 预览：`tmp/render_menu.py --time <ns>`、`render_eg.py`、`render_algo.py`。
5. 综合：`gw_sh build_cli.tcl`；烧 `impl/pnr/fm_138k_rgb.fs`。

## 4.1 参数存在哪里、什么时候丢

- 编辑只写 FPGA patch RAM，不落盘；同一音色内切页/退出菜单保持。
- 换音色再回来：从 ROM1A 重装原始参数，编辑丢失；掉电全丢；外部 CC27 也覆盖。
- 用户槽（7 NAME）快照全部参数到固件 RAM（8 槽），切音色/退出不丢，断电仍丢。

## 5. 常见改动

- 加参数行：`draw_xxx()` 里加 `prow(row,"LABEL",value,sel_row==n)`；`menu_press()`/`adj_xxx()`
  加行号与加减；确认 `editable_rows()`/`content_top()`。
- 加页：`tab_names[]` 固定 8 页；`draw_page()` 分支、`menu_press()` 触摸、页号写进 publish()。
- 改主题：`theme_pal[3][16]` 与 `theme_bg/theme_wave/theme_xy`，`apply_theme()` 一次写完。
- 布局：`VALUE_COL`（统一第 22 列）、`draw_bottom()`（第 27–29 行控制条，黑色按钮 + 主题色 << >> + 细滑条）、
  `get_sel()/slider_apply()`（选中行取值与滑条映射）；行点击只选中，编辑走底部控制条。
- 改布局：`c_at/text/text_r/fill_cells/btn_cells/btn_tall`；坐标是 8×16 字符格；
  **必须同步触摸判定**。
- ALGO 页：`build_algo_map()` 从 flags 模拟 bus1/bus2 得到调制图并自动排版；
  载波在最下排、绿色，调制器在上方、蓝色，最下排接 OUT 轨；
- FX 页：`draw_fx()`、`load_fx()`（0x69 0x200+）、`fx_write()`（0x70）；
  按钮下 ON/OFF 状态、按钮间 `>` 顺序箭头都在 `draw_fx()` 里画。
- 算法图/包络图：`build_algo_map()`/`eg_rebuild()` 只画到内存后上传；改版式要同步
  `label_rows[]` 和触摸区。

## 6. 约束与坑

- 固件镜像 ≤64 KiB（当前约 31 KiB）；无 libc；运行时函数在 `main.c` 顶部，别删。
- 字符 RAM 无初值：开机先 `clear_all()` 画首屏，再 `UI[17]=1`。
- 命令串行；`cmd()` 等 UI[9]，`rd()` 之间不要并发。
- 整页重绘约 0.4 ms；算法图重绘约 8 ms（4 字节突发上传）；用户槽 SAVE 约 0.2 s。
- 触摸与布局强耦合；改完看渲染预览或上板核对。
- 改 C 后忘了 `build_firmware.ps1` 是最常见的"改了没效果"。
- **文档必须用 UTF-8 工具改**；本机 PowerShell 的 `Set-Content` 会写 ANSI，混合编码不可逆。

## 7. 调试

- 串口 115200：`putc()/puts()/hex()`。
- `tb_touch_ui`：真实固件 + I2C 模型，检查页号/命令/字符层/曲线/算法图/用户槽，
  导出 `tmp/menu_cells.txt`、`tmp/eg_curve.txt`、`tmp/algo_map.txt` 供离线渲染。
- `tb_eg_curve`、`tb_algo_map`、`tb_char_display`：纯 RTL 图形单元测试。
