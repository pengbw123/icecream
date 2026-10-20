# 给后�?AI 的工程交接说�?
更新时间�?026-10-20（阶�?2b 完成轮）。目标是让接手者从当前代码和硬件状态继续，
不要把计划、候选代码或仿真结果误写成已交付功能�?
## 1. 工程位置与当前状�?
- 仓库根：`D:\a_My_projects\Gowin_publish`，工程目录：`fpga_project_FM_138k/`�?- 板卡：ACG720（GW5AT-LV138PG484AC1/I0，Arora V），Gowin V1.9.12.03；顶�?`top_138k`�?- 构建：`build_cli.tcl` �?`impl/pnr/fm_138k_rgb.fs`；烧录用 Gowin Programmer�?- 当前可烧录：`impl/pnr/fm_138k_rgb.fs`（阶�?2b 版，2026-10-20 21:01）。旧位流都在
  `impl/pnr/backup/`，IDE 工程目录里可能有更旧�?`fpga_project.fs`，不要误烧�?- 标签：`phase0-done`、`phase1-done`、`phase1b-done`、`phase1c-done`、`phase2a-done`�?  `phase2b-done`。回退：`git reset --hard <tag>`�?- **进度账本**：`docs/PRO_MENU_PROGRESS.md`（阶�?0..5，含寄存�?回读地址/已知限制）�?- **�?UI 固件先读**：`docs/UI_FIRMWARE_GUIDE.md`（软�?RTL 分工、寄存器与命令、构建流程、坑）�?- **用户操作说明**：`docs/USER_MANUAL_UI.md`（零基础版，含每个页�?参数解释）�?
## 2. 系统结构（一句话版）

- 音频�?6 声部 × 6 算子 FM�?8.828125 kHz 采样 tick�?0 MHz/1024），I2S 单声道→左右�?- 显示�?00×480 RGB565 @33.333 MHz，无帧缓冲；RTL 逐像素合成波�?XY/电平/EG/键盘�?- 时钟：`clk_50m`（音�?控制/RV32I/触摸）、`pixel_33m`；跨�?2FF + 帧锁存�?- 软核：RV32I�?4 KiB 指令窗口（取�?`instruction_mem[w_addr1[13:0]]`，会回绕）�?28 KiB 数据 RAM�?  固件 hex 补到 32768 字（128 KiB）。用 `zig` 交叉编译（`-nostdlib`、无 M 扩展）�?- 字符层：`rtl_char_display.v`�?28×32 �?×16 bit�? �?BSRAM�?6 色可写调色板�?
## 3. 目录速查

| 路径 | 内容 |
|---|---|
| `src/top_138k.v` | 138K 顶层、时�?复位、模块连�?|
| `src/rgb_visualizer.v` | 视频时序、波�?XY/EG/键盘、字符层合成 |
| `src/rtl_char_display.v` | 字符 RAM/字库/调色�?流水 |
| `src/touch_ui_controller.v` | GT911/GT9147 I2C、UI 寄存器、命令注入、字�?调色板写 |
| `src/fm_poly_synth.v` | 16 声部 6 算子 FM 引擎�?x69 回读 mux |
| `src/fm_uart_control.v` | UART/本地命令解析�?x60..0x69）、预�?ROM 装载 |
| `src/ui_firmware/main.c` | UI 固件：触摸、页面、参数编辑、主题、用户槽 |
| `src/ui_firmware/build_firmware.ps1` | zig 编译 + hex/bin |
| `sim/run_checks.ps1` | 全量回归�?4 项） |
| `sim/tb_touch_ui.sv` | 真实固件 + I2C 触摸模型回归 |
| `tools/core/fm_patch.py` | PC �?patch 模型（Dexed 标定、命令包构造） |
| `docs/` | 交接、进度、固件指南、用户手册、兼容性说�?|

## 4. 构建与验证流�?
1. 改固件：`src\ui_firmware\build_firmware.ps1 -Zig <zig.exe>` �?`firmware.hex`�?2. 回归：`sim\run_checks.ps1 -IverilogDirectory <iverilog bin>`（必须全过）�?3. 版面预览：`tmp/render_menu.py --time <ns> --out xxx.png`；演奏页合成预览 `tmp/compose_perf.py`�?4. 综合：`& 'D:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' build_cli.tcl`�?5. 烧录 `impl/pnr/fm_138k_rgb.fs`�?
## 5. 最近一次已知良好数据（阶段 2b�?
- 回归�?4 项全过（�?transpose、pitch EG、OSC enable、NAME 编辑、用户槽 SAVE/LOAD）�?- PnR：Logic 18931、Register 11214、CLS 14397、BSRAM 130/340、DSP 23/298、PLL 1/12�?  50 MHz �?Fmax 53.752 MHz，像素域 41.433 MHz，两�?TNS 0�?- 固件�?8 612 B�?4 KiB �?44%）�?- 已知限制：用户槽�?RAM（掉电丢）；EG 显示换算可能�?1；菜单整页重绘约 0.4 ms�?
## 6. 关键协议/寄存�?
- UI 寄存器见 `PRO_MENU_PROGRESS.md` �?`UI_FIRMWARE_GUIDE.md`；注意索引是 `address[7:2]`�?- 命令�?x60 全局�?x61 PMS�?x62 算子�?x63 包络段�?x64 键位缩放�?x65 Pitch EG�?  0x66 全音关�?x67 路由 flags�?x69 回读�?- 0x69 回读地址：全局 0x000..0x00B；算�?0x040+op*0x20+0..16；Pitch EG 0x140+stage*8+0..2�?- 字符格：`addr=(row<<7)|col`，`{attr[3:0],pal[3:0],char[7:0]}`；attr bit0 反显/bit1 下划�?bit2 填充�?- 像素时钟必须 0° 转发（`assign lcd_pclk = pclk;`）；�?ODDR(D0=0,D1=1) 会反�?180° 导致实板丢点�?
## 7. 硬件事项与坑

- 实板已验证：背光、扫描、触摸、WAVE/XY、字体（像素时钟修复后）�?- 触摸：GT 触点 ID 会抖动；固件�?id 记录 `control_down`，步进按钮有 300 ms 去抖�?  按住 1.5 s 才连发。`release_all()` 千万不要�?`control_down`（会导致按住时重复触发）�?- 用户�?SAVE �?0x69 �?123 个参数，�?0.2 s 停顿属正常�?- 固件镜像上限 64 KiB；`__divsi3/__udivsi3/__umodsi3/__mulsi3` �?`main.c` 顶部，别删�?- **文档编码**：不要用 Windows PowerShell �?`Set-Content` 改含中文的文件（本机默认 ANSI/GBK�?  会产�?UTF-8/GBK 混合乱码，且不可逆）。用编辑器的 UTF-8 保存，或本仓库的 write/edit 工具�?
## 8. 阶段计划（详见进度账本）

- 阶段 2b 已完成：Pitch EG、ALGORITHM 路由图与 TRANSPOSE、OSC ENABLE、NAME/用户槽、预设重同步�?- 阶段 3：效果器（合�?混响先，滤波/失真后）接入 FX 页�?- 阶段 4�? 段数码管、主�?视觉打磨�?- 阶段 5：时�?性能收尾、实板清单、发布�?
