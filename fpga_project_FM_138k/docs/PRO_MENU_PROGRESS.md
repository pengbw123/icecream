# 专业菜单/UI 改造进度账本

> 2026-10-23 菜单已改版：当前八页为 PLAY / ALGO / OSC / EG / LFO / FX / PATCH / SETUP。
> 新版布局、独立背景/主题色、触摸操作、预留入口与编译方法以 [UI_LAYOUT_2026.md](UI_LAYOUT_2026.md) 为准。
> 以下旧阶段记录及旧布局描述保留作历史参考；音源参数的含义仍可参考。


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

## 阶段 4c（混响修复 + FX 页状态/顺序标识，2026-10-21）

- 修混响自激：原实现把三个梳状抽头之和反馈进**每一个**梳状，等效环路增益 3×feedback，
  DECAY 稍大就 >1；表现为波形直流偏移、李萨如中心偏移、音量巨大并削成方波。
  现改为每个梳状只反馈**自己的**抽头（与 `audio_effects.v` 一致），并恢复原始量级：
  输入/2 注入、feedback 0.40..0.85、三路求和后再 >>1、原全通结构；湿路径加约 30 Hz DC 阻断。
- `tb_audio_fx` 新增"混响接交流信号不失控/无直流"断言（4000 样本，峰值与均值都有界）。
- FX 页每个效果器按钮下显示 `ON/OFF`，按钮之间用 `>` 表示
  `DIST > FILTER > CHORUS > PHASER > DELAY > REVERB` 的处理顺序；右上显示 MASTER 状态。
- 固件 35 256 B；位流 19:49；PnR：Logic 22232、Register 13114、BSRAM 222/340、DSP 44/298；
  50 MHz Fmax 55.201 MHz，像素域 36.292 MHz。

## 阶段 4d（效果器算术审计，2026-10-21）

按用户要求对照已验证的 `audio_effects.v` / `pro_audio_effects.v` 逐项排查，发现并修复了两类
**有符号位宽/溢出**问题（不是参数问题）：

- **失真**：`clipped - tone_state` 先在 16 位里相减，正负满幅时 -54721 会回卷成 +10815，
  导致音色滤波锁死在正半轴（直流 + 持续削顶）。改为先扩到 32 位相减、乘积用 48 位。
- **所有干湿混合**：`wet - dry` 同样在 16 位里溢出（±65534 超出 16 位有符号范围），
  大信号时混音会爆音/偏直流。合唱、延迟、移相、混响的差值都改成 17/32 位扩展后再乘；
  混响的 `mix_prod` 扩到 48 位。
- 用 1 kHz 正弦做了逐效果 RMS/峰值/均值探针（幅值 6000）：
  BYPASS 增益 1.00；DIST 5.08（无直流，mean≈24）；FILTER LP 0.08；
  CHORUS 0.98；PHASER 1.00；DELAY 0.66；REVERB room 0.59、hall 1.18（mean≈130）。
  全部无失控/无持续偏置。
- 按用户要求**暂不调整"夸张度"**：参数范围、默认值全部保持原方案。
- PnR：Logic 22165、Register 13104、BSRAM 222/340、DSP 44/298；
  50 MHz Fmax 59.232 MHz，像素域 37.593 MHz。

## 阶段 4e（ALGORITHM 页改成 Dexed 风格，2026-10-21）

- 不再用固定 6 行方框 + B1/B2/OUT 总线的示意，而是**按当前算法自动排版**：
  - 从 48 位路由 flags 以 OP6→OP1 顺序模拟 bus1/bus2 的写入/覆盖/累加，恢复真实调制关系；
  - 载波（dest=输出）放最下排、绿色；调制器放上方、蓝色；框内叠加算子编号；
  - 连线走直角，最下排算子向下接到 OUT 横轨，右侧标 `OUT`；
  - 自反馈算子在右边画一个更大的直角回环（带箭头）。
- 画布仍是 512×256 2bpp（`ui_algo_map.v`）；颜色类改为 1=绿、2=蓝、3=白。
- 修了布局过程中的两个坐标 bug：位置 u8 截断、未分配位置的算子导致整屏填充，
  现在所有算法都有合法位置，页面重绘耗时正常。
- 固件 36 944 B；回归全过；PnR：Logic 22172、Register 13104、BSRAM 222/340、DSP 44/298；
  50 MHz Fmax 54.632 MHz，像素域 37.293 MHz。
- 说明：自动排版是"同风格、同语义"，不是 Dexed 逐像素复刻；个别算法的方框间距可再手调。

## 阶段 4f（ALGO 页细节，2026-10-21）

- **OUT 汇总轨修复**：原来画轨道时 `minx/maxx` 用了 u8，载波 x>255 被截断，
  导致只有部分载波连到 OUT。改为 u16 后，最下排所有载波都向下接到同一条 OUT 横轨，
  右侧标 OUT（载波和=输出）。
- **算子数字居中**：不再用字符层（8×16 网格与 28 px 方框对不齐，数字会偏上/出格），
  改为在 2bpp 位图里用 3×5 字体放大 2 倍画在方框正中心。
- 固件 37 216 B；回归全过；PnR 数字同 4e（Logic 22172、BSRAM 222、DSP 44）。

## 阶段 4g（ALGO 布局方案 A，2026-10-22）

- 右侧给反馈环预留 46 px 安全边距：方框中心允许范围改为 [26, 440]，
  最右回环最多到 486，不再被 512 画布裁掉（修算法 32 最右 OP6 回环）。
- 同层方框最小中心距从 62 提到 76：反馈环占 24 px，右侧仍有 8 px 间隙，
  不再压到右边算子（修算法 8/17/18 的回环压框）。
- 载波排布也限制在 [26,440]，6 个载波间距约 82 px，全部接入同一条 OUT 轨。
- 离线自检 `tools/check_algo_layout.py`：遍历 32 个算法，检查方框/回环出界、
  回环与其他方框重叠；当前 **0 错误**。
- 固件 37 220 B；回归全过；位流 2026-10-22 15:00。
- PnR 不变：Logic 22172、BSRAM 222/340、DSP 44/298；Fmax 54.632 / 37.293 MHz。

## 阶段 4h（FM-1 六效果器：第 1、2 步，2026-10-22）

- **链路顺序按实机改正**：
  `FILTER -> REVERB -> DELAY -> DISTORTION -> CHORUS -> PHASER`（链尾软限幅）。
  原先的 `DIST->FILTER->...` 与机器不符。
- **FX 页按钮/箭头顺序同步**：
  `FILTER > REVERB > DELAY > DIST > CHORUS > PHASER`；参数行按各自效果器显示。
- **失真改为归一化 tanh**：
  - 新增 512 点 tanh LUT（z=0..8）、drive 1..8（Q8）、RMS 补偿表；
  - GAIN 只改变谐波，LEVEL 独立末级音量；
  - 仿真实测 gain20 与 gain99 的输出 RMS 完全相同（5417600 vs 5417600）。
- **参数平滑**：所有连续 FX 参数（cutoff/Q/gain/tone/level、chorus/phaser freq/depth/mix、
  delay decay/rate/mix、reverb decay/mix）加约 5 ms 一阶平滑；enable/type 仍立即生效。
- 资源：Logic 23093、Register 13483、BSRAM 225/340、DSP 45/298；
  Fmax 56.302 / 40.274 MHz（比之前略升）。固件 37 204 B。
- 回归 18 项全过。

### 阶段 4h 修正（失真对称性与增益解耦）

- 发现并修复两处严重问题：
  1. 失真取绝对值时用 17 位无符号减法，负半周幅度被算成 75536，导致正负半周不对称、负半周严重削顶、带直流偏移；改为符号扩展后取绝对值。
  2. 参数平滑的差分右移 8 位在 0..99 整数上直接截断成 0，参数根本不动；改为 Q8 平滑（24 位状态），时间常数约 5 ms。
- 修复后：±10000 直流输入输出 ±16589 对称；0.8 FS 正弦在 GAIN 20/99 时峰值 24765/25050，基本不变；RMS 约 +1.4 dB。
- PnR（16:48）：Logic 23048、Register 13597、BSRAM 224/340、DSP 45/298；
  Fmax 50.667 / 37.331 MHz（比修正前略低，仍过 50 MHz）。
- 回归 18 项全过。

## 下一步

1. 按钮圆角/按下高亮（可选；按下变色已有，圆角需要画布层或小位图）。
2. 阶段 3：效果器（合唱/混响先，滤波/失真后）接 FX 页。
3. 阶段 4：7 段数码管、主题/视觉打磨；阶段 5：收尾与发布。

## 已知限制

- 用户槽在 RAM，掉电丢；真正掉电保存需要 Flash/SD。
- EG 的 0..99 与内部定点换算可能显示差 1（声音正确）。
- 菜单整页重绘约 0.4 ms；算法图重绘约 8 ms（仅换算法/进页面时）。
- 路由图是"逻辑路由"示意（固定版式 + 真实连线），不是 DX7 原厂排版逐像素复刻。
