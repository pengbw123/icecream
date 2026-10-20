# UI 软核与菜单固件说明

本文写给第一次改这套 UI 的人：说清楚哪些代码在软核里、像素是怎么来的、以及改固件的完整流程。
菜单/参数的当前实现状态见 `PRO_MENU_PROGRESS.md`，用户操作说明见 `USER_MANUAL_UI.md`。

## 1. 分工：软核负责"逻辑"，RTL 负责"像素"

| 部分 | 位置 | 做什么 |
|---|---|---|
| RV32I 软核 | `src/usb_midi/rtl/rv32i.v` + `src/ui_firmware/*` | 轮询 GT911/GT9147、驱动 I2C、处理触摸手势、决定当前页面、写字符格、发参数命令、读回参数、切主题、用户槽 |
| 字符层 RAM | `src/rtl_char_display.v` | 128×32 格、每格 16 bit（`{attr,palette,char}`），4 块 BSRAM；写口 50 MHz、读口 33.3 MHz |
| 字库/调色板 | 同上 + `src/generated/font8x16.mem` | 8×16 字形只读 ROM；16 色可写调色板 |
| 光栅合成 | `src/rgb_visualizer.v` | 800×480 RGB565 逐像素合成：字符层、波形、XY、EG、电平、键盘 |
| 音频/FM | `fm_poly_synth.v` 等 | 与 UI 解耦，只接收命令和 MIDI 事件 |

**没有软核帧缓存**：软核只写"哪个格子放什么字符、什么颜色、什么属性"，像素由 RTL 扫描时实时生成。
改菜单布局不增加内存开销，也不拖慢音频/视频时序。

字符格地址：`addr = (row << 7) | col`，`col 0..99`（800px/8），`row 0..29`（480px/16）。
属性位：bit0 反显（整格填色、字形用调色板 0）、bit1 下划线（末两行）、bit2 整格填充、bit3 保留。

## 2. 软核寄存器映射（`0x23000000` 起，索引 = 字节地址/4）

| 索引 | 读 | 写 |
|---|---|---|
| 0 | 触摸引脚/复位状态 | I2C 开漏控制 |
| 1 | 微秒计数 | — |
| 2 | MIDI 事件忙 | — |
| 3 | MIDI 事件字 | 触发一个 MIDI 事件 |
| 4 | `{voices,algorithm,preset,volume}` 实时状态 | — |
| 5 | `ui_state`（页号 [27:24]、波形/XY、八度、XY 延时、AUTO 位 31） | 写 ui_state |
| 6 | — | 字符格：`addr[11:0]`、`{attr[3:0],pal[3:0],char[7:0]}` 在 bit[31:16] |
| 7/8 | — | 命令载荷低/高 32 位 |
| 9 | 命令口就绪 | 写命令字节（0x30/0x50/0x60..0x69） |
| 10/11/12 | — | 背景/波形/XY 颜色（24 bit） |
| 13 | — | numeric_display（保留给数码管） |
| 14 | 参数回读数据 | — |
| 15 | 回读就绪 bit0 | 写任意值清零就绪 |
| 16 | — | 调色板项：`{index[27:24], color[23:0]}` |
| 17 | 字符层使能 | bit0 = 使能字符层 |

> 寄存器号是 `address[7:2]`（6 位，最多 64 个）。旧版用 4 位导致 `UI[16]` 被别名成 0，主题色一直不生效。

## 3. 参数命令与回读

走 `UI[7]/UI[8]/UI[9]` 时不需要 A5 5A 头和校验（硬件本地注入）：

| 命令 | 作用 | 关键字段（payload 位） |
|---|---|---|
| 0x60 | 全局 | alg[4:0], fb[10:8], osc_sync[11], lfo_sync[12], transpose[22:16], lfo_wave[26:24], speed[38:32], delay[46:40], PMD[54:48], AMD[62:56] |
| 0x61 | PMS | sensitivity[2:0] |
| 0x62 | 算子 | index[2:0], enable[8], fixed[9], detune[13:10], detune_valid[14], freq[47:16], level[63:48] |
| 0x63 | 包络段 | index[2:0], stage[9:8], qrate[31:16], level[47:32], rate_scaling[50:48], velocity[58:56], AMS[61:60] |
| 0x64 | 键位缩放 | index[2:0], bp[14:8], left_depth[22:16], right_depth[30:24], left_curve[33:32], right_curve[41:40] |
| 0x65 | Pitch EG | stage[1:0], coefficient[23:8], target[46:24]（23 位 Q8.15） |
| 0x66 | All Notes Off（不是参数提交） | — |
| 0x67 | 算法路由 flags（覆盖） | flags[47:0] |
| 0x68 | 已废弃 | 返回错误 |
| 0x69 | 参数回读 | address[9:0]；结果从 `UI[14]` 读，`UI[15]` bit0 表示就绪 |

回读地址表见 `PRO_MENU_PROGRESS.md`。固件封装：`cmd(op,lo,hi)`、`rd(addr)`；`rd()` 等 `UI[15]`，
读完写 0 清零。

## 4. 改固件的完整流程

1. **改代码**：`src/ui_firmware/main.c`（新增源文件时同时加到 `build_firmware.ps1` 的 `$sources`）。
2. **编固件**（必须，综合只读现成 hex）：
   ```powershell
   src\ui_firmware\build_firmware.ps1 -Zig 'D:\a_files\赛道选题详情\tmp\ziglang\ziglang\zig.exe'
   ```
   成功会打印 `Touch/UI firmware: N / 65536` 并重写 `firmware.hex`。
3. **跑回归**：
   ```powershell
   sim\run_checks.ps1 -IverilogDirectory 'D:\a_files\赛道选题详情\tmp\iverilog\bin'
   ```
   `tb_touch_ui` 用真实固件 + I2C 模型走一遍所有菜单页，并把字符写流导出。
4. **看版面预览**（不用上板）：
   ```powershell
   python tmp\render_menu.py --time 336000000 --out menu_eg.png
   ```
5. **综合/布局布线**：
   ```powershell
   & 'D:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' build_cli.tcl
   ```
6. **烧录**：`impl/pnr/fm_138k_rgb.fs`。

## 4.1 参数存在哪里、什么时候会丢

- 编辑只写 FPGA 内部的 patch 寄存器（RAM），**不落盘、不写 ROM、不写 Flash**。
- 同一个音色内：菜单里来回切页、退出菜单再回来，参数都保持（寄存器没动，UI 从 FPGA 回读）。
- 切换到别的音色再切回来：从 ROM1A 重新装载该音色的原始参数，**你的编辑丢失**。
- 断电/复位：全部丢失。外部 MIDI 的 Program Change / CC27 也会覆盖当前编辑。
- 用户槽（7 NAME 页）把当前全部参数快照到固件 RAM（8 个槽），切音色/退出菜单不丢，但**断电仍丢**；
  真正掉电保存需要加 Flash/SD，尚未实现。

## 5. 常见改动

- **加参数行**：`draw_xxx()` 里加 `prow(row,"LABEL",value,sel_row==n)`；`menu_press()`/`adj_xxx()`
  加行号与加减逻辑；改完确认 `editable_rows()`/`content_top()`。
- **加页**：`tab_names[]` 固定 8 页；`draw_page()` 分支、`menu_press()` 触摸处理、必要时改
  `editable_rows()`/`content_top()`；页号写进 `publish()` 的 bit[27:24]。
- **改配色/主题**：`theme_pal[3][16]` 与 `theme_bg/theme_wave/theme_xy`；`apply_theme()` 一次写完
  调色板和 RTL 的背景/波形/XY 颜色。`8 UTIL` 页点一下切换主题。
- **改布局**：用 `c_at(col,row,ch,pal,attr)`、`text()`、`text_r()`、`fill_cells()`、`btn_cells()`、
  `btn_tall()`；坐标单位是字符格（8×16 px）。改按钮位置**必须同步触摸判定**。
- **发自定义命令**：组好 64 位载荷（分 `lo`/`hi`）调 `cmd(0x??,lo,hi)`；0x60 是全量载荷。

## 6. 约束与坑

- 固件镜像必须 ≤64 KiB（当前约 28 KiB，取指 14 位地址；超了会静默回绕）。
- 无 libc；`__udivsi3`/`__divsi3`/`__umodsi3`/`__mulsi3` 在 `main.c` 顶部自己实现，别删。
- 字符 RAM **没有初值**：开机必须先 `clear_all()`、画好首屏，再写 `UI[17]=1` 使能字符层。
- 命令串行：`cmd()` 等 `UI[9]`；`rd()` 之间不要并发发送。
- 整屏重绘约 0.4 ms；用户槽 SAVE 要读约 123 个参数，会有约 0.2 s 的停顿（正常）。
- 触摸坐标与布局强耦合；改布局后务必看渲染预览或上板核对。
- 改 C 后忘了跑 `build_firmware.ps1` 是最常见的"改了没效果"原因。
- **文档编码**：不要用 Windows PowerShell 5.1 的 `Set-Content` 改含中文的文件（默认 ANSI，
  会产生 UTF-8/GBK 混合乱码）。用编辑器/本仓库的 write/edit 工具写 UTF-8。

## 7. 调试手段

- 串口 115200：`putc()/puts()/hex()` 打印启动、触摸、页面切换日志。
- `tb_touch_ui`：真实固件 + 模拟 I2C 触摸；检查页号、0x60/0x62/0x63/0x64/0x65 发送、
  0x69 读、主题写入、用户槽 SAVE/LOAD；字符写导出到 `tmp/menu_cells.txt`。
- `tmp/render_menu.py`：把字符写流离线渲染成 PNG，支持 `--time` 截取中间画面、`--theme` 选配色。
- `tmp/compose_perf.py`：演奏页"RTL 图形近似 + 字符层"合成预览。
- `tb_char_display`：单独验证字符层字形/属性/调色板/流水对齐。
