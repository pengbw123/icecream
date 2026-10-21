# 给后续 AI 的工程交接说明

更新时间：2026-10-21（阶段 2e 完成）。目标是让接手者从当前代码和硬件状态继续，
不要把计划、候选代码或仿真结果误写成已交付功能。

## 1. 工程位置与当前状态

- 仓库根：`D:\a_My_projects\Gowin_publish`，工程目录：`fpga_project_FM_138k/`。
- 板卡：ACG720（GW5AT-LV138PG484AC1/I0，Arora V），Gowin V1.9.12.03；顶层 `top_138k`。
- 构建：`build_cli.tcl` → `impl/pnr/fm_138k_rgb.fs`；烧录用 Gowin Programmer。
- 当前可烧录：`impl/pnr/fm_138k_rgb.fs`（阶段 2e，2026-10-21 14:48）。旧位流在
  `impl/pnr/backup/`，IDE 目录里的旧 `fpga_project.fs` 不要烧。
- 标签：`phase0-done`…`phase2d-done`、`phase2e-done`。回退：`git reset --hard <tag>`。
- **进度账本**：`docs/PRO_MENU_PROGRESS.md`。
- **改 UI 固件先读**：`docs/UI_FIRMWARE_GUIDE.md`。
- **用户操作说明**：`docs/USER_MANUAL_UI.md`（零基础版）。

## 2. 系统结构

- 音频：16 声部 × 6 算子 FM，48.828125 kHz tick（50 MHz/1024），I2S 单声道→左右。
- 显示：800×480 RGB565 @33.333 MHz，无帧缓冲；RTL 逐像素合成。
- 时钟：`clk_50m`（音频/控制/RV32I/触摸）、`pixel_33m`；跨域 2FF + 帧锁存。
- 软核：RV32I，64 KiB 指令窗口（取指 14 位字地址，会回绕）、128 KiB 数据 RAM；
  固件 hex 补到 32768 字。用 `zig` 编译（`-nostdlib`、无 M 扩展）。
- 字符层：`rtl_char_display.v`，128×32 格 ×16 bit，16 色可写调色板。
- 图形层：
  - `ui_eg_curve.v`：256×256 包络曲线面板（256 个高度样本，填充/亮边/网格）。
  - `ui_algo_map.v`：512×256 2bpp 算法路由位图（32 KiB BSRAM，固件绘制后上传）。

## 3. 目录速查

| 路径 | 内容 |
|---|---|
| `src/top_138k.v` | 138K 顶层、时钟/复位、模块连线（新图形层的端口都接在这里） |
| `src/rgb_visualizer.v` | 视频时序、波形/XY/EG/键盘、字符层/曲线/位图叠加 |
| `src/rtl_char_display.v` | 字符 RAM/字库/调色板/流水 |
| `src/ui_eg_curve.v` | 包络曲线面板 |
| `src/ui_algo_map.v` | 算法路由 2bpp 画布 |
| `src/touch_ui_controller.v` | GT911/GT9147 I2C、UI 寄存器、命令注入、字符/图形写口 |
| `src/fm_poly_synth.v` | 16 声部 FM 引擎、0x69 回读 mux |
| `src/fm_uart_control.v` | 命令解析（0x60..0x69）、预设 ROM 装载 |
| `src/ui_firmware/main.c` | UI 固件：触摸、页面、参数、主题、用户槽、图形绘制 |
| `sim/run_checks.ps1` | 全量回归（16 项） |
| `tools/core/fm_patch.py` | Dexed 标定与命令包构造（PC 侧） |

## 4. 构建与验证

1. 改固件：`src\ui_firmware\build_firmware.ps1 -Zig <zig.exe>` → `firmware.hex`。
2. 回归：`sim\run_checks.ps1 -IverilogDirectory <iverilog bin>`（必须全过）。
3. 预览：`tmp/render_menu.py` / `render_eg.py` / `render_algo.py`（字符流+图形日志离线合成）。
4. 综合：`gw_sh build_cli.tcl`；烧录 `impl/pnr/fm_138k_rgb.fs`。

## 5. 最近一次已知良好数据（阶段 2e）

- 回归：16 项全过（含 EG 曲线、算法画布、菜单、用户槽）。
- PnR：Logic 19304、Register 11350、BSRAM 147/340、DSP 23/298、PLL 1/12；
  50 MHz Fmax 61.520 MHz，像素域 41.969 MHz，两域 TNS 0。
- 固件：31 192 B（64 KiB 的 48%）。

## 6. 关键协议/寄存器

- UI 索引是 `address[7:2]`（6 位，最多 64 个）。
- 0 触摸、1 微秒、2 事件忙、3 MIDI 事件、4 `{voices,algorithm,preset,volume}`、5 ui_state、
  6 字符格、7/8 命令载荷、9 命令字节、10/11/12 颜色、14 回读数据、15 回读就绪、
  16 调色板、17 字符层使能、18/19 包络曲线样本、20/21 算法图旧逐字节口、
  22 算法图层使能、23 算法图基址、24 算法图 32 位字（自动 4 字节写入）。
- 参数命令：0x60 全局、0x61 PMS、0x62 算子、0x63 包络段、0x64 键位缩放、0x65 Pitch EG、
  0x66 全音关、0x67 路由 flags、0x69 回读。
- 回读地址：全局 0x000..0x00B；算子 0x040+op*0x20+0..16；Pitch EG 0x140+stage*8+0..2。
- 字符格 `addr=(row<<7)|col`，`{attr[3:0],pal[3:0],char[7:0]}`。
- 像素时钟必须 0° 转发（`assign lcd_pclk = pclk;`）。

## 7. 硬件事项与坑

- 触摸：GT 触点 ID 会抖动；步进按钮 300 ms 去抖，按住 1.5 s 才连发；
  `release_all()` 不要清 `control_down`。页重绘期间若漏掉松手帧，固件会在坐标跳变
  >160 px 时按"新触摸"处理。
- 算法图上传走 4 字节突发（`UI[23]` 基址 + `UI[24]` 字），一次页面重绘约 8 ms；
  长上传期间触摸采样可能变慢。
- 用户槽 SAVE 要读约 123 个参数（约 0.2 s 停顿，正常），存 RAM，掉电丢。
- 固件镜像 ≤64 KiB；`__divsi3/__udivsi3/__umodsi3/__mulsi3` 在 `main.c` 顶部，别删。
- **文档编码**：本机 PowerShell 的 `Set-Content` 会写 ANSI/GBK，改中文文档会毁掉 UTF-8
  编码（已多次发生）。请只用编辑器的 UTF-8 或本仓库的 write/edit 工具改 `docs/*.md`。

## 8. 阶段计划

- 2e 已完成：ALGORITHM 矢量路由图、4 字节上传、触摸健壮性。
- 下一步：按钮圆角/按下高亮（可选，需要同一画布层或小位图）、阶段 3 效果器（合唱/混响、
  滤波/失真）接入 FX 页，阶段 4 数码管/视觉打磨。
