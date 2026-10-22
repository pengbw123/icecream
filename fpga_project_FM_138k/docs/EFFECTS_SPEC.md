# FM-1 六效果器实现说明（给后续 AI / 开发者的交接文档）

本文只写**当前项目真实需求、原理、参数作用、已有实现和待办**，目的是让另一个 AI 不用翻大量历史对话就能继续改。

---

## 0. 权威需求：以实机为准

用户手里有一台 **M-VAVE FM-1**，实机有 **6 个可独立开关的效果器**，面板/参数顺序固定为：

```
FILTER -> REVERB -> DELAY -> DISTORTION -> CHORUS -> PHASER
```

注意：

- 这是**信号处理顺序**，也是 FX 页按钮从左到右的顺序；
- 6 个效果器**互相独立**，可以同时开任意多个（允许双开/全开），不是二选一；
- 之前项目根目录的 `M-VAVE_FM1_全套效果器_FPGA_实现工程文档（AI生成代码专用）.txt`
  把顺序写成 `Filter -> Distortion -> Chorus/Phaser -> Delay -> Reverb`，且声称 Chorus/Phaser 互斥，
  **这两点和实机不符，不要按它改**；
- M-VAVE 官方开源工作台只暴露了共享混响/延迟，不能代表整机 FX 全貌；
  **本文的 6 效果器顺序和参数以用户实机为准**。

目标：在这块 FPGA 上**尽量还原实机六效果器的原理、参数作用和听感**，不要求逐样本复刻原厂代码。

---

## 1. 系统与代码位置

- 音频采样率：`48.828125 kHz`（`sample_tick` 每 1024 个 50 MHz 时钟一次）。
- 音频格式：16-bit signed，内部可用 24/32/40/48-bit 中间结果。
- FX RTL：`src/audio_fx.v`（链、寄存器、滤波、失真、软限幅）。
- 子模块：
  - `src/audio_chorus.v`
  - `src/audio_phaser.v`
  - `src/audio_delay.v`
  - `src/audio_reverb.v`
- 参数表：`src/generated/fx_*.mem`，由
  `tools/generators/generate_audio_fx_tables.py` 生成。
- UI 固件：`src/ui_firmware/main.c`，FX 页 `draw_fx()/adj_fx()/load_fx()`；
  写寄存器用命令 `0x70`，回读用 `0x69` 地址 `0x200+addr`。
- 约束：所有效果器都在**一个 sample_tick 内**用多周期 FSM 完成；不能用浮点。

### 1.1 当前链路（已实现）

```
dry
 -> FILTER
 -> REVERB
 -> DELAY
 -> DISTORTION
 -> CHORUS
 -> PHASER
 -> soft limiter
 -> sample_out
```

- 6 个 enable 全关，或 FX master 关，或 bypass 打开：输出**逐位等于 dry**；
- 否则输出经过整条链 + 链尾软限幅（>0.75 FS 后 1/4 斜率压缩，最后饱和到 16-bit）。

---

## 2. FX 寄存器映射（6-bit 地址，16-bit 值）

| 地址 | 效果器 | 含义 | 范围/默认 |
|---|---|---|---|
| 0 | GLOBAL | bit0 master enable，bit1 bypass | 默认 0x0001 |
| 1 | FILTER | enable | 0/1 |
| 2 | FILTER | type：0=LP，1=BP，2=HP | 默认 0 |
| 3 | FILTER | cutoff 0..99 | 默认 99 |
| 4 | FILTER | Q 0..99 | 默认 20 |
| 5 | DIST | enable | 0/1 |
| 6 | DIST | gain 0..99 | 默认 20 |
| 7 | DIST | tone 0..99 | 默认 50 |
| 8 | DIST | level 0..99 | 默认 80 |
| 9 | CHORUS | enable | 0/1 |
| 10 | CHORUS | freq 0..99 | 默认 30 |
| 11 | CHORUS | depth 0..99 | 默认 40 |
| 12 | CHORUS | mix 0..99 | 默认 30 |
| 13 | PHASER | enable | 0/1 |
| 14 | PHASER | freq 0..99 | 默认 25 |
| 15 | PHASER | depth 0..99 | 默认 40 |
| 16 | PHASER | mix 0..99 | 默认 30 |
| 17 | DELAY | enable | 0/1 |
| 18 | DELAY | decay（反馈量）0..99 | 默认 35 |
| 19 | DELAY | rate（时间）0..99 | 默认 40 |
| 20 | DELAY | mix 0..99 | 默认 30 |
| 21 | REVERB | enable | 0/1 |
| 22 | REVERB | type：0=ROOM，1=HALL，2=PLATE | 默认 0 |
| 23 | REVERB | decay 0..99 | 默认 45 |
| 24 | REVERB | mix 0..99 | 默认 30 |

FX 页显示顺序（与链一致）：

```
FILTER > REVERB > DELAY > DIST > CHORUS > PHASER
```

每个按钮下显示 ON/OFF；TYPE 行只对 FILTER/REVERB 有意义；参数行按上表显示。

---

## 3. 每个效果器的原理、参数作用与当前实现

### 3.1 FILTER（第一个）

**原理**：可调截止频率的滤波器，放在最前，先塑造进入混响/延迟/失真的频谱。
实机有三种模式：Low Pass / Band Pass / High Pass；Cutoff 控制转折点；Q 控制转折点附近的共振峰。

**参数作用**：

- TYPE：
  - LP：保留低频，切高频；
  - BP：只保留中间频段；
  - HP：保留高频，切低频；
- CUTOFF：0..99 映射到频率，数值越大通过的频率越高；
- Q：0..99，Q 越大，转折点越尖、共振越明显。

**当前实现**：

- 用 Chamberlin 状态变量滤波器（LP/BP/HP 三选一）；
- 截止频率目前映射 **30 Hz .. 8 kHz**（受 Chamberlin 稳定性限制）；
- Q 约 0.5..12；
- 参数已加平滑。

**待办/目标**：

- 实机/市场 FM 合成器一般到 **20 Hz..20 kHz**；需要换 TPT SVF（g=tan(πfc/fs)）或 Biquad，
  保证 20k 附近稳定。换 TPT 需要处理每采样除法，建议参数变化时用小除法 FSM 算系数。

---

### 3.2 REVERB（第二个）

**原理**：多个不同长度的梳状延迟（Comb）并联，形成密集反射；再用全通（Allpass）扩散；
Decay 控制反馈量，Mix 控制干湿。实机有 Room / Hall / Plate 三种空间。

**参数作用**：

- TYPE：三套延迟长度/反馈/阻尼配置；
  - ROOM：短、紧凑；
  - HALL：长、空旷；
  - PLATE：明亮、金属感（DX7 常用）；
- DECAY：0..99，越大尾音越长；本质是梳状反馈系数；
- MIX：0..99，干湿比。

**当前实现**（`src/audio_reverb.v`）：

- 3 个梳状 + 1 个全通；
- 每种 Type 有独立延迟长度；
- 反馈表 `fx_reverb_fb.mem` 目前映射 **0.40..0.85**；
- 有输入阻尼、DC 阻断、wet/dry。

**已知问题**：

- 尾音偏短，Hall/Plate 名不副实；
- 3 梳+1 全通密度不足；
- 反馈上限 0.85 对应 RT60 只有约 1~2 秒。

**目标**：

- 4 梳状 + 2 全通（或 6+3，视 BSRAM）；
- DECAY 映射到约 0.5..0.95；
- 梳状反馈路径加一阶低通 damping；
- 目标 RT60：ROOM≈1 s，HALL≈3–6 s，PLATE≈1.5–3 s；
- Type 只切长度/反馈/阻尼参数，不重搭电路；
- 保留 DC 阻断和输出限幅，防止自激。

---

### 3.3 DELAY（第三个）

**原理**：环形缓冲 + 反馈递归；把声音延迟一段时间再放出，并送回输入形成回声。

**参数作用**：

- DECAY：反馈量，0..99，越大回声重复越多、尾越长；
- RATE：延迟时间，0..99，数值越大间隔越长；
- MIX：0..99 干湿比。

**当前实现**（`src/audio_delay.v`）：

- 32768 样本延迟线；
- 时间 **40..670 ms**；
- 反馈 **0.30..0.90**；
- 单写口、登记读口、饱和加法。

**已知问题**：

- 实机要求 **20..1000 ms**，当前范围不够；
- RATE 改变时没有交叉淡化，会有指针跳变/咔哒；
- 反馈上限 0.90 略高，需配合限幅/低通。

**目标**：

- 20..1000 ms（1000 ms × 48.8 kHz ≈ 48828 样本，需要扩延迟线到 65536）；
- 时间变化用交叉淡化或平滑读指针；
- 反馈路径加低通，DECAY 上限约 0.90–0.92。

---

### 3.4 DISTORTION（第四个，重点）

**原理**：前置驱动把信号推进非线性区，产生谐波；再低通塑形（TONE）；最后 LEVEL 独立音量。
实机原则：**GAIN 只改变失真度，不应明显改变整体音量；LEVEL 是独立末级音量。**

**参数作用**：

- GAIN：0..99，控制进入非线性的驱动量；越大谐波越多、声音越粗；
- TONE：0..99，失真后的低通，低值闷、高值亮；
- LEVEL：0..99，输出音量，独立于 GAIN/TONE。

**当前实现**（`src/audio_fx.v`）：

- 归一化 tanh：`y = tanh(drive*x) / tanh(drive)`；
- 512 点 tanh LUT（z=0..8），drive 1..8（Q8），
  由 `fx_tanh_lut.mem` / `fx_dist_drive.mem` / `fx_dist_makeup.mem` 提供；
- TONE 为一阶低通（500 Hz..12 kHz）；
- LEVEL 为最后一级 Q15 乘法；
- 已修两个严重 bug：
  1. 负半周取绝对值用无符号减法导致正负不对称、单边削顶；
     现在用 `{sign,value}` 符号扩展后取绝对值；
  2. 参数平滑整数右移 8 位变成 0，参数实际不动；
     现在用 Q8 状态（24-bit）平滑，约 5 ms。
- 实测：±10000 直流输入输出 ±16589 对称；0.8 FS 正弦 GAIN20/99 峰值约 24765/25050，
  基本不变，RMS 约 +1.4 dB。

**注意**：

- 不要把“Gain 不改变音量”理解成硬性 AGC；当前是峰值归一化 tanh。
  低电平信号在高 GAIN 下仍可能变响，这是 tanh 特性；如果实机听感要求更严格，
  需要加输入包络检测/归一化（复杂度更高）。
- 失真在 DELAY 之后，所以它也会处理混响/延迟的尾音，这是实机顺序。

---

### 3.5 CHORUS（第五个）

**原理**：LFO 调制短延迟线的读指针，制造微小音高抖动；干声 + 湿声叠加使声音变厚。
实机/市场 chorus 典型结构：正弦 LFO、10–30 ms 基础延迟、Depth 控制摆幅、Mix 干湿。

**参数作用**：

- FREQ：LFO 速度，0..99，越大越快；
- DEPTH：延迟摆动幅度，0..99，越大越厚/越飘；
- MIX：干湿比，0..99，通常不做 100% 湿（会失去干湿拍频）。

**当前实现**（`src/audio_chorus.v`）：

- 2048 样本延迟线；
- 三角 LFO，约 0.05..6 Hz；
- 单抽头，延迟约 8..16 ms；
- 无分数延迟插值；
- 默认 freq30/depth40/mix30。

**已知问题**：

- 听感弱：单抽头 + 三角 LFO + 无插值 + 默认太慢太浅；
- 高 Mix 时只剩湿声，失去 chorus 的干湿拍频。

**目标**：

- 正弦 LFO（查表）；
- 两路抽头（相位差约 90°/180°），基础延迟 10–25 ms，Depth 0–8 ms；
- 抽头做线性插值，消除量化颗粒；
- 默认 freq≈0.5 Hz、depth≈5 ms、mix≈40%，保证一开就听得出；
- Mix 建议上限 50–70%（或允许 99 但要保留干声）。

---

### 3.6 PHASER（最后一个）

**原理**：多级一阶全通滤波器（APF）级联，LFO 扫全通系数，使不同频率相位变化；
与干声叠加形成移动的相位抵消（“抽吸”）。不使用延迟线。

**参数作用**：

- FREQ：LFO 扫描速度；
- DEPTH：扫描幅度/相位变化范围；
- MIX：干湿比。

**当前实现**（`src/audio_phaser.v`）：

- 4 级全通；
- 三角 LFO；
- freq/depth/mix 参数已平滑。

**目标**：

- 6 级全通（更深的相位陷波）；
- 正弦 LFO，范围与实机对齐；
- 干湿混合，无反馈自激。

---

## 4. 全局设计规则（必须保持）

1. **链路顺序不可改**：
   `FILTER -> REVERB -> DELAY -> DISTORTION -> CHORUS -> PHASER`。
2. **6 个 effect enable 完全独立**，允许同时开；不要强制互斥。
3. **FX master 关 / bypass / 全部 enable 关** 时输出必须逐位等于 dry。
4. **参数平滑**：所有连续参数用约 5 ms 一阶平滑（Q8 状态，不要用整数右移直接截断）；
   enable/type 可以立即生效。
5. **增益/电平解耦**：失真 GAIN 只改谐波，LEVEL 独立；不得出现负半周不对称。
6. **防止溢出**：所有乘法中间结果位宽足够；加法/输出饱和；链尾软限幅。
7. **定点**：不使用浮点；参数表由 Python 生成，不要手改 mem（改生成器再重新生成）。
8. **UI 顺序 = 链顺序**：`FILTER > REVERB > DELAY > DIST > CHORUS > PHASER`。

---

## 5. 测试与验收

- 仿真：`sim/run_checks.ps1 -IverilogDirectory <iverilog bin>`，共 18 项；
- FX 单测：`sim/tb_audio_fx.sv`
  - 寄存器默认值/回读；
  - bypass/master/dry 逐位；
  - 失真：GAIN 20 vs 99 的 RMS 差 ≤2 倍（当前约 1.36），无溢出；
  - 滤波 DC/高频；
  - chorus/phaser/delay/reverb 基本行为；
- 固件：`src/ui_firmware/build_firmware.ps1 -Zig <zig.exe>`；
- 位流：`gw_sh build_cli.tcl`。

验收建议：

- 失真：示波器看正负半周对称，GAIN 扫动时峰值基本不变，无直流偏移；
- 合唱：一开就能听出变厚/轻微音高漂移，而不是纯延迟；
- 混响：Hall 尾音明显长于 Room；
- 延迟：改 RATE 无咔哒；
- 滤波：20k 上限（待办）；
- 所有效果器同时开不削顶/不溢出。

---

## 6. 当前完成度与下一步

已完成：

- FX 链路顺序、UI 顺序；
- 失真归一化 tanh、增益解耦、对称性修复；
- 全部连续参数 Q8 平滑；
- 现有 5 个效果器子模块可运行；
- 回归 18 项全过。

下一步（按优先级）：

1. **CHORUS**：双抽头 + 正弦 LFO + 线性插值 + 默认值，解决“听不出”；
2. **REVERB**：4 梳+2 全通、damping、DECAY 上限 0.95、Room/Hall/Plate 分档；
3. **DELAY**：20–1000 ms、时间交叉淡化、反馈低通；
4. **FILTER**：TPT SVF/Biquad，cutoff 到 20 kHz；
5. **PHASER**：4→6 级；
6. UI 单位（Hz/ms/%/RT60）和默认值微调。

资源参考（当前位流，2026-10-22）：

- Logic 23048/138240，Register 13597/139095；
- BSRAM 224/340，DSP 45/298；
- Fmax 50.667 MHz（50 MHz 时钟）、37.331 MHz（像素域）。

改动时请保持这些余量，尤其混响/延迟扩 BSRAM 和滤波除法器的时序。

---

## 7. 常见坑（前车之鉴）

1. **负数取绝对值**：不要用 `17'd0 - {1'b0, signed16}`；会得到错误大数。
   正确：先 `{sign, value}` 符号扩展成 17 位 signed，再取负。
2. **参数平滑**：`(target-cur) >>> 8` 在 0..99 整数上等于 0；必须用 Q8/Q16 状态。
3. **链顺序**：不要按旧文档的 `Filter->Dist->Chorus...` 改回来。
4. **UI 顺序**：按钮/箭头必须和链顺序一致，否则用户看到的和听到的不一致。
5. **失真增益补偿**：如果改 makeup 表，先测 `GAIN 20/99` 的峰值/RMS，防止再次出现“开失真音量暴涨/骤降”。
6. **改参数表**：只改 `tools/generators/generate_audio_fx_tables.py`，重新生成所有 `fx_*.mem`，不要手改。
7. **位流重建**：改 RTL 后必须重新跑 `gw_sh build_cli.tcl`；只改固件不需要重跑 PnR。
