# 专业菜单/UI 改造进度账本

> 阶段 0..5 的唯一进度账本。先读 `AI_HANDOFF.md`；改固件读 `UI_FIRMWARE_GUIDE.md`；
> 用户说明见 `USER_MANUAL_UI.md`。本文件统一 UTF-8；不要用本机 PowerShell 的
> `Set-Content` 改中文（默认 ANSI，会毁掉 UTF-8 编码）。

## 基础事实

- 800×480 RGB565、33.333 MHz 像素时钟、无帧缓冲；RTL 逐像素合成。
- 字符层：128×32 格 ×16 bit `{attr[3:0],palette[3:0],char[7:0]}`，4 块 BSRAM；
  attr bit0 反显、bit1 下划线、bit2 填充。
- 软核 RV32I 只写"格子内容"；像素由 RTL 生成。UI 索引 `address[7:2]`。
- 命令：0x60 全局、0x61 PMS、0x62 算子、0x63 包络段、0x64 键位缩放、0x65 Pitch EG、
  0x66 全音关、0x67 路由 flags、0x69 回读。
- 回读：全局 0x000..0x00B；算子 0x040+op*0x20+0..16；Pitch EG 0x140+stage*8+0..2。

## 阶段 0（`phase0-done`）
参数回读 0x69、算法路由 flags ROM、字符显示层（字库/调色板/双口 RAM）、固件预算加固。

## 阶段 1（`phase1-done`）
固件页面引擎（页签/行选择/步进/连发/拖动滑条）、ALGORITHM 文字路由表、OSC 13 字段可读改、
频率换算（ratio/fixed/detune）全在固件 32 位整数完成；回归 + 字符流预览。

## 阶段 1.1（`phase1b-done`）
- 修主题色不生效：UI 索引 `address[5:2]`→`address[7:2]`（旧版 UI[16] 被别名成 0）。
- 页签常驻所有页面，删除"点顶部进菜单"（与 PERF 页签冲突导致闪屏/回不去）。
- 演奏页重设计：页签 + 状态行 + 右侧快捷键；删除旧右列/旧性能文本；3 套主题可选。

## 阶段 1.2（`phase1c-done`）
- `release_all()` 不再清 `control_down`（按住时每帧重复触发，OCTAVE 冲 ±3）。
- 步进 300 ms 去抖；按住 1.5 s 后才 150 ms 连发；双行 ± 只画一次符号；XY 主题色修正。

## 阶段 2a（`phase2a-done`）
ENVELOPE 页（RATE/LEVEL 4 段，0x63）、LFO 页（0x60+0x61）、0x002 回读位序修正、
新增 `__mulsi3`。

## 阶段 2b（`phase2b-done`）
Pitch EG（0x65）、ALGORITHM 移调、OSC ENABLE、NAME 页 10 字符 + 8 个用户槽 SAVE/LOAD、
预设切换重同步。用户槽在 RAM，掉电丢。

## 阶段 2c（`phase2d-done` 前后）
- RTL 包络曲线面板 `ui_eg_curve.v`：256 个高度样本，填充/亮边/网格；固件 `eg_rebuild()`
  按 RATE 非线性权重（`4+(99-rate)^2/10`）分配四段宽度，RATE 越大段越短/越陡。
- EG 页参数列收紧到第 40 列，± 按钮移到 44..58 列，曲线面板加宽到 256×256。
- OSC 页 ASCII 路由改为 3 列×2 行方框图。

## 阶段 2e（`phase2e-done`）
- 新增 `ui_algo_map.v`：512×256 2bpp 算法路由位图（32 KiB BSRAM）；固件 `build_algo_map()`
  按 flags 画 6 个算子方框 + B1/B2/OUT 三条总线 + 箭头 + 反馈回环，OP 编号由字符层叠加。
- 上传：`UI[23]` 基址 + `UI[24]` 32 位字，RTL 自动写 4 字节，上传 8192 次（约 8 ms）。
- 触摸健壮性：页重绘期间漏松手帧时，坐标跳变 >160 px 视为新触摸。
- 修复 top_138k 漏接 `algo_*`：综合曾把 32 KiB 画布优化掉（BSRAM 131），补齐后 147。
- 测试：新增 `tb_algo_map`；回归 16 项通过。
- PnR：Logic 19304、Register 11350、BSRAM 147/340；50 MHz Fmax 61.520 MHz、
  像素域 41.969 MHz，TNS 0；固件 31 192 B。

## 阶段 3a（进行中，效果器第 1 步：寄存器/命令/直通）

- 新增 `src/audio_fx.v`：32 个 16 位配置寄存器（6 位地址），默认值按方案写好；
  `sample_out` 目前是精确干声直通，后续步骤替换为 6 效果器链。
- 新增命令 **0x70** 写 FX 寄存器（payload[5:0]=addr，payload[23:8]=value），
  回读走 0x69 地址 **0x200+addr**；越界地址报 packet_error。
- `top.v` 新增 `FX2_ENABLED` 参数与 generate 分支；`top_138k` 改为
  `FM_AUDIO_ONLY=0, FX2_ENABLED=1`（旧的 pro_audio_effects / audio_effects 分支保留）。
- 测试：新增 `tb_audio_fx`（寄存器默认/读写/直通）；`tb_fm_readback` 增加 0x70→0x69
  环路与越界检查；全量回归 17 项。
- 注意：加入新分支后 50 MHz 域最差路径是原有的
  `e0_env_current -> operator_envelope_levels`，slack 仅 0.094 ns（TNS 0）；后续加效果器
  逻辑时要盯住时序，必要时给包络电平输出加一级流水。

## 阶段 3a（进行中，效果器第 1 步：寄存器/命令/直通）

- 新增 `src/audio_fx.v`：32 个 16 位配置寄存器（6 位地址），默认值按方案写好；
  `sample_out` 目前是精确干声直通，后续步骤替换为 6 效果器链。
- 新增命令 **0x70** 写 FX 寄存器（payload[5:0]=addr，payload[23:8]=value），
  回读走 0x69 地址 **0x200+addr**；越界地址报 packet_error。
- `top.v` 新增 `FX2_ENABLED` 参数与 generate 分支；`top_138k` 改为
  `FM_AUDIO_ONLY=0, FX2_ENABLED=1`（旧 pro_audio_effects / audio_effects 分支保留）。
- 测试：新增 `tb_audio_fx`（寄存器默认/读写/直通）；`tb_fm_readback` 增加 0x70→0x69
  环路与越界检查；全量回归 17 项。
- 注意：新分支后 50 MHz 域最差路径是原有的
  `e0_env_current -> operator_envelope_levels`，slack 仅 0.094 ns（TNS 0）；后续加效果器
  逻辑时要盯时序，必要时给包络电平输出加一级流水。

## 阶段 3b（FX 第 2 步：DISTORTION + FILTER + FX 页）

- `audio_fx.v` 加入 **失真**（软削波 + 一阶音色低通 + 输出电平）和 **状态变量滤波器**
  （LP/BP/HP 三选一、cutoff/Q 查表），用 13 状态的单周期 FSM 在 1024 个时钟内完成，
  每个状态最多一次乘法。
- 新增 `tools/generators/generate_audio_fx_tables.py` 与 5 张 100 项参数表
  （`fx_filter_f/q`、`fx_tone_coeff`、`fx_level_gain`、`fx_dist_gain`）。
- 固件新增 **6 FX 页**：顶部 `DIST/FILTER/CHORUS/PHASER/DELAY/REVERB` 选择按钮；
  下面 `FX MASTER`、`EFFECT`、`TYPE`（/滤波/混响）、三个参数行；进入页面用 0x69 0x200+
  读回 25 个寄存器，编辑用 0x70 写。
- 测试：`tb_audio_fx` 增加软削波、LP 通直流/衰减高频、HP 阻直流的断言；
  `tb_touch_ui` 增加 FX 页导航与 0x70 写入检查；全量回归 17 项。
- PnR：Logic 20209、Register 12099、BSRAM 167/340、DSP 29/298；
  50 MHz Fmax 56.844 MHz、像素域 39.543 MHz（TNS 见报告）。
- 当前效果链：DISTORTION → FILTER → 输出；其余 4 个效果器仍是占位（第 3/4 步）。

## 阶段 3c（FX 第 3 步：CHORUS + PHASER）

- 新增 `audio_chorus.v`：复用原 `audio_effects.v` 的 2048 样本延迟线、三角波 LFO、
  干湿混合结构，改为 freq/depth/mix 参数驱动（LFO 0.05..6 Hz，扫幅 0..396 样本）。
- 新增 `audio_phaser.v`：4 级一阶全通链，LFO 0.05..3 Hz 调制系数，depth 控制摆幅，mix 干湿。
- `audio_fx.v` 链改为：DISTORTION → FILTER → CHORUS → PHASER → 输出；子模块按
  `sample_tick` 流水（每个效果约 1 个采样延迟）。全部效果关闭时**直接干声**，无额外延迟。
- Gowin IDE 工程文件补入 `audio_fx.v`、`audio_chorus.v`、`audio_phaser.v`、
  `rtl_char_display.v`、`ui_eg_curve.v`、`ui_algo_map.v`（缺文件会导致 IDE hierarchy 展不开）；
  新增 `tools/check_project_files.py` 做提交前校验。
- 测试：`tb_audio_fx` 增加合唱脉冲回声、移相器响应、带效果时 bypass 位精确；
  全量回归通过。
- PnR：Logic 21262、Register 12444、BSRAM 169/340、DSP 35/298；
  50 MHz Fmax 59.331 MHz、像素域 42.718 MHz。

## 阶段 3d（UI 控制条统一，2026-10-21）

- 去掉每行 56×16 px 的小 `-`/`+`（容易点空、点错相邻行），改成底部统一控制条
  （第 27–29 行，48 px 高）：
  - 左：大号 `-`（88×48 px，按住 1.5 s 后连发）；
  - 中：滑条（560×48 px），点击/拖动直接设置选中行的值，右侧显示当前值；
  - 右：大号 `+`（88×48 px）。
- 行本身只负责"选中"（整行可点），不再直接改值；这样即使点偏到相邻行也只是换选中行。
- 参数列统一：标签从第 2 列开始，数值右对齐到第 22 列（原来 OSC/LFO/ALGO 是 52，EG/FX 是 40），
  选中高亮 2..38 列；所有参数页一致。
- 修掉 FX 页加减错位：`prow_eg` 把按钮画在 x≈352/416，而触摸判定只对 EG 页用 352/416，
  其它页仍按 448/512；现在统一由底部控制条处理，该类错位不再存在。
- 滑条使用 `get_sel()` 读取当前行原始值与范围（支持 ON/OFF、循环类型、0..99、0..31 等），
  再换算成一次 `adj(row, delta)`，复用原有参数写入逻辑。
- 固件 34 444 B；全量回归 17 项通过；PnR 数字不变（Logic 21262/BSRAM 169/DSP 35，
  Fmax 59.331 MHz / 42.718 MHz，TNS 0）。

## 阶段 4（DELAY + REVERB + 软限幅）

- 新增 `audio_delay.v`：循环延迟线 40..670 ms（32768 样本），DECAY 控制反馈 0.30..0.90，
  RATE 控制时间，MIX 干湿；用写计数屏蔽上电未写入的历史，避免上电噪声。
- 新增 `audio_reverb.v`：复用 `audio_effects.v` 的三梳状 + 一全通结构，TYPE 切换
  ROOM/HALL/PLATE 三组梳状长度，DECAY 控制反馈，MIX 干湿。
- `audio_fx.v` 链路补全：DIST → FILTER → CHORUS → PHASER → DELAY → REVERB → 软限幅
  （24576 软拐点）；全部效果关闭时仍直接干声。
- 测试：`tb_audio_fx` 增加延迟脉冲回声、混响尾音断言；全量回归通过。
- PnR：Logic 21946、Register 12898、BSRAM 222/340、DSP 42/298；
  50 MHz Fmax 53.718 MHz，像素域 43.533 MHz。

## 阶段 3e（UI 外观 + EG 六算子包络图）

- 底部控制条重做：紧凑 7 格宽的大 `-`/`+`（白字深灰底），中间细滑条 + 右侧 VALUE 数值，
  去掉原来大块灰色按钮和虚线字形。
- 选中反色条缩短：只覆盖标签和数值到第 24 列（原来到第 38 列，右侧留空过长）。
- EG 页改为两列：左列 RATE 1..4，右列 LEVEL 1..4（PITCH 模式为 TARGET 1..4）。
- 新增 `ui_eg_multi.v`：6 块 128 样本包络面板（3×2 排列，768 字节 RAM），
  显示框线/网格/填充/曲线；固件进 EG 页时读回 6 个算子的 EG 并一次性上传，
  编辑某个算子时只重传该面板。寄存器：UI[25] 基址、UI[26] 32 位字（自动 +4）、UI[27] 使能。
- 新增 `tb_eg_multi` 单元测试；`tb_touch_ui` 覆盖两列选择与算子面板刷新。
- 固件 34 792 B。

## 阶段 4b（UI 细节修正，2026-10-21）

- EG 六张包络图的顺序修正为 **左→右、上→下 = OP1..OP6**：
  固件内部算子序号是 DX7 SysEx 顺序（0=OP6，5=OP1），面板 p 改为取算子 5-p；
  并在每块图左上角叠加 `OP1..OP6` 字符标签，顺序一目了然。
- EG 页选中行改为与其它页一致的样式：主题色底块 + 反显（黑字），不再出现文字主题色/周围变黑。
- 底部大按钮重做：黑色底块 + 主题色 `<<` / `>>` 字形（滑条左右两侧），
  既清楚又不会和滑条主题色冲突；触摸区不变（左/右 88 px + 中间滑条）。
- 固件 34 952 B；位流 18:57；回归全过；PnR 数字不变。

## 下一步

1. 按钮圆角/按下高亮（可选；按下变色已有，圆角需要画布层或小位图）。
2. 阶段 3：效果器（合唱/混响先，滤波/失真后）接 FX 页。
3. 阶段 4：7 段数码管、主题/视觉打磨；阶段 5：收尾与发布。

## 已知限制

- 用户槽在 RAM，掉电丢；真正掉电保存需要 Flash/SD。
- EG 的 0..99 与内部定点换算可能显示差 1（声音正确）。
- 菜单整页重绘约 0.4 ms；算法图重绘约 8 ms（仅换算法/进页面时）。
- 路由图是"逻辑路由"示意（固定版式 + 真实连线），不是 DX7 原厂排版逐像素复刻。
