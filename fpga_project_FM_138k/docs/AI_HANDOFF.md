# 给后续 AI 的工程交接说明

## 2026-10-24 性能监测与后续路线

- 用户确认后续依次推进：性能监测 → 32 复音 → 多分区/八垫鼓组 → 自研 XY 演奏 → SD 保存 → 立体声 → 64 复音。
  见 `DEVELOPMENT_ROADMAP.md`。本轮仅实现性能监测，后续项目仍是计划。
- 入口 SETUP → PERFORMANCE，菜单 page=12（page=8 已用于 Pitch EG，不能复用）。
  监测采样耗时/响应时间/忙占比/复音峰值/超时/丢采样/抢音/桥接丢事件/MIDI 背压。
- 被动 RTL 统计，显式快照；冻结和清零不改变音频。MMIO UI[56..58]，详见 `PERFORMANCE_MONITOR.md`。
- 该数字时间不等于键盘到耳机的完整演奏延迟；配置声部数量不等于比赛可闻独立振荡器数量。
- 已完成双屏构建：`impl/pnr/fm_138k_rgb_hdmi.fs`，2026-10-24 14:52:18，42,340,871 B。
  SHA256 `49B12ADF989E7FB37647B0250704B96E0BBB343483F334E6884F451421812F44`。
  前版已备份至 `impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-24_pre_performance.fs`。
- 资源：Logic 41,724/138,240；FF 21,665/139,095；BSRAM **314/340（未增加）**；DSP 65/298。
  Fmax：主域 50.002、RGB 35.811、HDMI pixel 36.507、serial 179.468 MHz；四域 setup/hold TNS=0。
  主域时序余量仍很小，扩复音必须继续检查关键路径，不可仅修改声部参数。
- 固件 60,304/65,536 B；IDE 51 个启用 RTL 文件均存在，新模块已登记两份 CLI 脚本与工程文件。
- 已通过：监测器单元测试（精确周期、忙计数、快照、清零、同沿截止期与饱和）；
  真实 FM 2/16 声部监测；128 音色/参数回读；单音滑音；桥接 UART/背压/断帧恢复。
  16 声部测试场景 render=202 clocks、response=203 clocks，17 次起音、1 次抢音；不是全部场景的最大值。
- 真实 RV32I + Goodix UI 测试通过：入口/快照读取/冻结超过刷新周期/清零/恢复刷新/返回设置/无误发 MIDI；
  真实字符写入日志渲染的 800×480 截图已核对，`tmp/performance_menu_preview.png`（数据来自测试模型，非实机读数）。
  日志 `tmp/build_performance.log`、`tmp/check_metrics_ui.log`。本轮为针对性回归，未重跑全部测试矩阵。
  未实机烧录；本轮仅交付双屏位流，25K 桥接不需更新。

更新时间：2026-10-23（800×480 可配置配色菜单，以及此前的耳机监听与效果器修正）。目标是让接手者从当前代码和硬件状态继续，
不要把计划、候选代码或仿真结果误写成已交付功能。

## 2026-10-23 UI 改版

- 改版前已提交 Git：`2616714`，包含 ES8388 / delay / phaser 的完整源码存档。
- 新 UI 的现行布局、配色、触摸区域与新增 attr 定义见 `UI_LAYOUT_2026.md`。
  旧章节中的 PERF/NAME/UTIL、橙色主题和旧控件坐标不再是当前菜单布局。
- 界面仍为纯 RTL 字符/图形扫描 + RV32I 菜单逻辑，800×480；无逐像素软核 GUI。
- 新布局单独放在 `src/ui_firmware/menu_layout.h`，修改后仍需重新编译 firmware.hex。
- FFT 已实现，详见 SPECTRUM.md；ARP / SEQ 尚未实现。最新发布状态见本文末尾。
- 本轮构建/时序与实机状态见文末 UI 发布记录；旧 14:39 位流已备份到
  `impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-23_pre_ui.fs`。

## 2026-10-23 增量交接

- 新增 `src/es8388_output.v`：板载 OUT1 接 ES8388，从模式接收现有最终 I2S 流；
  MCLK=12.5 MHz、BCLK=3.125 MHz、Fs=48.828125 kHz。数字/模拟增益固定 0 dB，
  与 MAX98357 共用现有主音量，不新增耳机音量。详见 `docs/ES8388_AUDIO.md`。
- ES8388 初始化检查三字节 ACK、支持时钟拉伸与超时、NACK 重试和九时钟总线恢复；
  确认从模式 ACK 前释放 BCLK/LRCK，防止上电默认主模式导致时钟争用。
- `top_138k` / `top_138k_hdmi`、两套 RGB CST、两个构建脚本均已接入；
  `fpga_project.gprj` 加入模块，IDE 顶层仍为 `top_138k_hdmi`。
- DELAY：65536 样本、20..1000 ms、512 间隔双抽头时间淡化、Q12 反馈低通；
  负反馈向零截断，修复负一个最低位永久循环；两个抽头独立抑制上电未知 RAM。
- PHASER：负全通系数对应 120..4500 Hz，中频扫动；16 位三角 LFO、系数插值和平滑；
  Q8 + 保护位状态；MIX=99 改为 50% 干 + 50% 全通声，保留典型抵消陷波。
  仍为四级，FREQ 仍为 0.05..3 Hz，不要求照搬旧文档的六级候选方案。
- 连续参数平滑补齐向上收敛的最后一个 Q8 单位，避免 UI 显示 99、内部永久停在 98；
  `tb_audio_fx` 增加 delay/phaser 控制的 0/99 端点与最大延迟请求检查。
- 扩容后全工程布局暴露原音源正弦插值长路径，`fm_poly_synth.v` 将窄位宽插值修正与
  基值的符号处理并行，再相加；无新增音源流水级。`tb_fm_sine_interpolation` 穷举
  512 段 × 2048 小数相位 × 4 象限，与原算式逐位相同（4,194,304 项）。
- 新增 `tb_delay_phaser`、`tb_es8388_output`、`tb_es8388_i2c_faults` 并加入全量回归；
  耳机模拟音质、输出响度、复位爆音及效果器听感仍待实机检查。
- 最终双屏位流：`impl/pnr/fm_138k_rgb_hdmi.fs`（2026-10-23 14:39）；
  Logic 26755/138240、Register 15055/139095、BSRAM 277/340、DSP 56.5/298。
  Fmax：主域 51.412、RGB 42.790、HDMI 像素 51.690、HDMI 串行 177.671 MHz，
  四域 setup/hold TNS 均为 0。旧双屏位流备份到
  `impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-22_2208_pre_codec.fs`。
- 两个 CLI 构建脚本增加 `tools/check_timing.py` 后置检查：Gowin 即使时序失败也可能
  生成位流并返回成功，必须检查 TNS 与 Fmax，不能仅看 `.fs` 是否存在。
- 最终回归：18 个 testbench，加 XY 起音及 RGB 多种显示模式，共 22 个场景全部通过；
  日志 `tmp/checks_codec_fx_release.log`、`tmp/build_codec_fx_release.log`、
  `tmp/timing_codec_fx_release.log`。Hierarchy 源文件检查通过，IDE 的本地结果文件链接
  已同步到双屏构建；当前仅交付更新后的双屏位流，单 RGB 位流需自行重建。

以下旧章节中的 2026-10-22 单 RGB 位流/资源记录属于历史版本；最新构建记录以本节为准。

## 1. 工程位置与当前状态

- 仓库根：`D:\a_My_projects\Gowin_publish`，工程目录：`fpga_project_FM_138k/`。
- 板卡：ACG720（GW5AT-LV138PG484AC1/I0，Arora V），Gowin V1.9.12.03；当前顶层 `top_138k_hdmi`。
- 当前构建：`build_cli_hdmi.tcl` → `impl/pnr/fm_138k_rgb_hdmi.fs`；烧录用 Gowin Programmer。
  单屏入口 `top_138k` / `build_cli.tcl` 仍保留，但旧 `fm_138k_rgb.fs` 未包含本次耳机改动。
- 当前可烧录：`impl/pnr/fm_138k_rgb_hdmi.fs`（2026-10-23 14:39；耳机与效果器改动尚未实机验证）。旧位流在
  `impl/pnr/backup/`，
  IDE 目录里的旧 `fpga_project.fs` 不要烧。
- 标签：`phase0-done`…`phase2d-done`、`phase2e-done`、`phase3a-done`、`phase3b-done`、`phase3c-done`、`phase3d-done`、`phase4-done`、`phase4b-done`、`phase4c-done`、`phase4d-done`、`phase4e-done`、`phase4f-done`、`phase4g-done`、`phase4h-done`。回退：`git reset --hard <tag>`。
- **进度账本**：`docs/PRO_MENU_PROGRESS.md`。
- **改 UI 固件先读**：`docs/UI_FIRMWARE_GUIDE.md`。
- **改效果器先读**：`docs/EFFECTS_SPEC.md`（六效果器原理/参数/链路/已知坑/待办）。
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

## 5. 最近一次已知良好数据（阶段 4h）

2026-10-22 失真响度匹配与 MIX 修正：全 16 位静态传递曲线单调、无阈值翻转；
旧峰值归一化在 GAIN 50 时把 16000 峰值正弦的 RMS 放大约 2.07 倍。
现在按输入/失真后平滑绝对值包络自动匹配响度，静音后用 GAIN 对应的预置系数启动；
原寄存器 8 由总音量 LEVEL 改为干湿 MIX，0=原声、99=全失真，UI 已改名并重编固件。
五档输入幅度的稳定正弦 RMS 比约 0.92–1.00；实机 ROM 音色波形/听感待确认。
PnR：Logic 23394、Register 13593、BSRAM 228/340、DSP 48/298；
50 MHz Fmax 54.845 MHz，像素域 42.853 MHz，两域 setup/hold TNS 均为 0。
失真单测、完整 RTL 回归和固件编译通过。

本轮合唱采用两个互补调制抽头、Q8 线性插值和独立预热门控，避免延迟读地址量化引起的阶跃和上电脏数据。
混响采用四路带一阶阻尼的反馈梳状延迟与两级串联全通；Room/Hall/Plate 有独立延迟长度，
DECAY 基础反馈范围 0.50..0.90。原整数 DC 阻断器留下永久尾音偏置，现改为 Q12 状态。
`sim/tb_chorus_reverb.sv` 检查双抽头位置、快速调制连续性、三种空间的尾音、DECAY 大小关系、无 X 和 MIX=0 直通。
本轮 `sim/run_checks.ps1` 全部通过，包括音频效果、真实 UI 固件、触摸和 RGB/XY 多场景回归。
本轮 PnR：Logic 24031、Register 13889、BSRAM 236/340、DSP 51.5/298；
50 MHz Fmax 54.825 MHz，像素域 40.844 MHz，两域 setup/hold TNS 均为 0。

- 回归：16 项全过（含 EG 曲线、算法画布、菜单、用户槽）。
- PnR：Logic 23048、Register 13597、BSRAM 224/340、DSP 45/298、PLL 1/12；
  50 MHz Fmax 50.667 MHz，像素域 37.331 MHz，两域 TNS 0。
- 固件：37 204 B（含 6 FX 页、底部控制条、EG 六面板、Dexed 风格 ALGO 页）。
- 效果器：六个效果器全部生效（DIST/FILTER/CHORUS/PHASER/DELAY/REVERB），链尾软限幅；
  已修完有符号位宽 bug（失真 tone 差、各效果 wet-dry 差）。
  混响已修正自激问题（每个梳状只反馈自己的抽头 + 输入/2 + DC 阻断）。
- UI：参数页"点行选中 + 底部 -/滑条/+ 编辑"；EG 页两列参数 + 六算子包络面板；
  数值列第 22 列，选中条到第 24 列；EG 六图顺序 OP1..OP6（左上→右下），带字符标签。

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
- **Gowin 工程文件**：新增 RTL 文件必须同时加入 `fpga_project.gprj`，否则 IDE 的 hierarchy
  会展不开（模块变黑盒）。提交前运行 `python tools/check_project_files.py` 校验。
- **文档编码**：本机 PowerShell 的 `Set-Content` 会写 ANSI/GBK，改中文文档会毁掉 UTF-8
  编码（已多次发生）。请只用编辑器的 UTF-8 或本仓库的 write/edit 工具改 `docs/*.md`。

## 8. 阶段计划

- 2e 已完成：ALGORITHM 矢量路由图、4 字节上传、触摸健壮性。
- 下一步：按钮圆角/按下高亮（可选，需要同一画布层或小位图）、阶段 3 效果器（合唱/混响、
  滤波/失真）接入 FX 页，阶段 4 数码管/视觉打磨。

## UI 发布构建（2026-10-23 18:33）

- 当前双屏位流：`impl/pnr/fm_138k_rgb_hdmi.fs`，2026-10-23 18:33:57，41,214,887 字节。
- SHA256：`D39C6E9E9C3BEEC79082B7E4D1A9E425727B0DE57AD84195EC2A407524AC4B68`。
- 固件 40,980 / 65,536 字节；Logic 26716、Register 14947、BSRAM 278/340、DSP 56.5/298。
- Fmax：主域 55.564 MHz、RGB 39.434 MHz、HDMI 像素 52.543 MHz、HDMI 串行 185.050 MHz；
  四域 setup/hold TNS 均为 0。构建日志 `tmp/build_ui_release.log`。
- 18 个 testbench、共 22 个场景通过。通用回归前 16 项与 XY attack 见 `tmp/checks_ui_release.log`；
  最终真实 UI 固件回归见 `tmp/checks_ui_delivery.log`（M1..M14，PASS）；四个 RGB 场景见
  `tmp/checks_ui_rgb.log`。新增布局的 EG/Pitch EG 参数化视口测试见 `tmp/checks_ui_viewports.log`。
  通用脚本早期运行中的触摸测试失败日志是历史诊断，不代表最终固件验证状态。
- 真实 UI 回归包含背景与主题色独立设置、用户槽保存/恢复的协议字段、预设载入取消/确认、
  FFT/ARP/SEQ 不误发 MIDI，以及触点 ID 复用处理。Goodix 模型锁存同一帧，避免脚本坐标撕裂。
- IDE 顶层仍为 `top_138k_hdmi`，43 个 RTL 源文件的 hierarchy 检查通过，结果文件路径对应此双屏构建。
- 此前各节位流均为历史版本；单 RGB 位流本轮未更新。
- 尚待实机检查：触摸手感、白底/暗底可读性、快速切页、用户槽保存恢复，以及 RGB/HDMI 同时运行。

## 键盘与音频输出修订（2026-10-23）

- Pitch EG 网格判定优先于曲线下方填充，曲线本身仍具有最高优先级。
- PLAY 键盘扩大到 x=0..799、y=352..479（800×128），黑键 32×80；RTL 与固件触摸使用相同分界。
  最右端 x=799 可触发高 C。移除 PANIC、ARP、SEQ 和原键盘上方按钮条，右侧保留音量、预设、
  WAVE/XY、八度；AUTO RANGE、XY DELAY、频谱预留入口在 SETUP。
- SETUP 新增 KEY VELOCITY（1..127，默认 100，仅影响后续触屏 Note On，不改变外部 MIDI）。
  AUDIO OUTPUT 选择 SPEAKER（默认外部音响）或 HEADPHONE（ES8388 OUT1），共用主音量与 PCM。
  未选接口发送数字静音，时钟持续运行；切换在完整 I2S 帧边界生效，无插孔检测。
- 音源音量目标、当前值和 UI 初始值统一为 5；首页音量数值支持完整 0..127。
  设置仍在 RAM 中，掉电恢复默认。
- UI[5] bit13 为 headphone_select；两款 138K 顶层均已连接到 i2s_tx 输出选择，
  HDMI/屏幕波形采样点不受输出接口选择影响。i2s_tx 默认参数关闭选择，保留其他旧顶层兼容性。
- 回归新增 tb_i2s_output_select：左右声道位序、padding、互斥路由、帧中请求不撕裂。
  tb_eg_curve 检查曲线下方网格；tb_touch_ui 的 +keyboard 场景检查默认音量、默认/自定义力度、
  屏幕右边缘琴键及耳机设置；完整菜单回归也已覆盖新增设置。
- 修改前位流备份：impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-23_pre_keyboard.fs。
- 最终固件 40,820 / 65,536 字节。完整基础回归与 RGB 四场景通过，见 tmp/checks_keyboard_release.log；
  最后仅补正了首页音量的三位数显示，最终固件完整菜单回归再次通过，见 tmp/checks_keyboard_final.log。
  重新编译后的键盘专项通过，见 tmp/checks_keyboard_delivery.log（+keyboard +ui_debug）。
  合计覆盖 19 个 testbench、24 个场景；项目 43 个 RTL 文件的 hierarchy 检查通过。
- 最终双屏位流：impl/pnr/fm_138k_rgb_hdmi.fs，2026-10-23 19:38:10，42,129,405 字节。
  SHA256：AC3FC474A7C3FC1C309C02FA85C7276EA8AE618EFF9BE02541AA5C96F84D0824。
  固件 40,820 B；Logic 26828、Register 14949、BSRAM 278/340、DSP 57.5/298。
  Fmax：主域 58.563 MHz、RGB 39.336 MHz、HDMI 像素 48.645 MHz、HDMI 串行 194.914 MHz，
  四域 setup/hold TNS=0。最终构建日志 tmp/build_keyboard_delivery.log；此前 final 日志为中断构建，
  release 日志为首页音量三位数补正前的中间构建，不作为本次烧录版本。
- 实机待确认：Pitch EG 网格全域可见、键盘两侧/黑键/多点触控、力度听感、上电音量 5、
  SPEAKER/HEADPHONE 互斥发声与切换瞬态，以及 RGB/HDMI 同时输出。未执行实机烧录。

## 实时频谱（2026-10-23）

- PLAY 右侧 WAVE / XY / FFT 三选一；SETUP → SPECTRUM 直接打开首页频谱，DISPLAY 可循环三种模式。
  800×128 键盘保留。RGB、HDMI 同步选择，并使用同一份分析数据。
- `audio_spectrum_analyzer.v`：纯 RTL 1024 点 Hann + radix-2 FFT，18 位复数工作 RAM，逐级 /2。
  读取最终 FX/主音量之后、输出接口路由之前的 PCM。64 个对数频段约 48 Hz..24.4 kHz，
  分辨率 47.6837 Hz、约 46 帧/秒，视觉范围 -72..0 dBFS；快速起跳、缓慢回落和峰值保持。
  窗增益已补偿；幅度是视觉近似、每频段取最大 bin，不宣称计量级精度或频带 RMS。
- `audio_spectrum_snapshot.v`：每个显示器独立双 bank；只在消隐翻页，应答后复用旧 bank；
  丢锁恢复必须等到第 0 列，不接收半帧。分析不等待屏幕，不反压音频。
- UI[5] bit14 = spectrum_enable；FFT 时 bit12 为 0，bit13 耳机选择及负八度字段保持独立。
  软核只绘制菜单文字/选择模式，FFT 与像素绘制全部为 RTL，无需新增 IP。
- 表由 `tools/generate_spectrum_tables.py` 生成并跟踪在 `src/generated/spectrum_*.mem`。
  两个 CLI 构建脚本与 IDE 工程均登记新模块，45 个 RTL 文件的 hierarchy 校验通过。
- 具体实现、显示坐标、分辨率限制与验证用例见 `docs/SPECTRUM.md`。
- 当前双屏位流 `impl/pnr/fm_138k_rgb_hdmi.fs`：2026-10-23 20:23:59，41,597,351 字节；
  SHA256 `644ED30C80B23A98A74177FDDF3BAA0405B9F98BC11A11E36FC7E04155B96CA4`。
  固件 41,308 / 65,536 B；Logic 29100、Register 16342、BSRAM 286/340、DSP 64.5/298。
  Fmax：主域 50.545、RGB 35.493、HDMI 像素 36.261、HDMI 串行 145.850 MHz，
  四域 setup/hold TNS=0；最终构建日志 `tmp/build_spectrum_release.log`。
  主域余量较小，后续任何 RTL/固件改动重新构建后都必须检查时序，不能只看是否生成 .fs。
- 修改前键盘版位流备份为 `impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-23_pre_spectrum.fs`。
- 全套回归通过，见 `tmp/checks_spectrum_release.log`；加上单独完成的 RGB/HDMI 频谱光栅场景，
  共 21 个 testbench、29 个场景。数值加强用例（双音和峰值保持）见 `tmp/checks_spectrum_numeric.log`；
  频谱入口见 `tmp/checks_spectrum_ui.log`；RGB 频谱见 `tmp/checks_spectrum_rgb_delivery.log`，
  HDMI 频谱见 `tmp/checks_spectrum_hdmi.log`。RGB 早期一次性注入在丢锁后失效是测试夹具问题，
  最终改为持续注入并验证恢复；早期 debug 失败日志不是最终发布结果。
- 实机待确认：谐波/已知频率峰值、主音量对应高度、静音回落、快速切换和两屏同时运行。

## 128 音色、单音滑音与力度修订（2026-10-23）

- 原始 USB 力度校准 0..90 改为 0..80 → 0..127，十进制 20→32；80 以上限幅 127，零保持松键。
  同时修改 `fpga_midi_bridge_25k/src/top_bridge.v` 与本工程 `top.v` 的直连 USB 默认参数。
  桥接 UART 不二次缩放；使用 25K USB 桥接板时必须同时更新该板位流。
- ROM1A、ROM1B、ROM2A、ROM2B 按顺序全部内置，共 128 个，菜单编号 001..128。
  各库源为 D:/a_files/Cartridges/rom{1a,1b,2a,2b}.syx。历史 `fm_rom1a_*.mem` 文件名保持，内容已扩容。
  预设 ID 全链路扩为 7 位，CC27 支持 0..127；UI[4] 的高两位 ID 使用 [23:22]，其他既有字段不移动。
  `fm_preset_names.h` 与参数 ROM 来自同一生成器，首页与 PATCH 支持三位编号、26 页和高库名称。
- **名称越过 32 错误**：`name_from_preset()` 原残留 `pr &=31u`，现改为 127u。
  `tb_touch_ui +performance` 的最终测试明确检查第 128 个名字前缀 EX（EXPLOSION），防止只扩编号而名字回绕。
- SETUP 新增 GLIDE MONO，默认 OFF。ON 为单音后键优先，重叠按键触发、无间隔门限；
  松开当前键时回到最近仍按住的键，全部松开后下次直接起音。延音踏板与尾音不算物理按住。
  固定约 168 ms，逐算子相位增量以宽有符号运算线性滑动并钳位到准确终点；连奏保留相位/包络/LFO，
  固定频率算子维持固定值。CC22=0 关闭、非 0 开启，值大小不改变时间。0x69/0x00C 可读模式。
  颤音本轮未改。模式切换会清理旧声部/按键历史。分配器最后一个空闲声部漏分配也已修复。
- 音色和滑音实现/验证见 `LEGATO_AND_FACTORY128.md`。用户持久保存仅方案，优先 SD 卡，
  见 `USER_PRESETS_PLAN.md`；原理图第 15 页确认 J8 MicroSD 卡座，第 2 页为配置 Flash MX25L12845G。
  计划 SD SPI + 精简 FAT32、USER 128 槽、FM+FX、原生快照 CRC/A-B 副本，与后续 MIDI 曲库共用驱动。
  **当前 8 个用户槽仍是 RAM，掉电丢失，未接入 SD/Flash 写入。**
- 138K 最终位流：impl/pnr/fm_138k_rgb_hdmi.fs，2026-10-23 22:18:58，41,746,941 字节。
  SHA256：1FC729FBAE5A59EA4847A42D7929C61DC17DF15B0DF513AB43C05576C13F9C3A。
  固件 42,684/65,536 B，Logic 32218、Register 16667、BSRAM 297/340、DSP 64.5/298。
  Fmax 主域 54.670、RGB 37.530、HDMI 像素 36.492、串行 154.652 MHz，四域 setup/hold TNS=0。
  最终构建 tmp/build_legato128_final.log；较早 build_legato128.log 尚未包含高库名称修复，不作发布位流。
- 25K 桥接最终位流：../fpga_midi_bridge_25k/impl/pnr/midi_bridge_25k.fs，2026-10-23 21:51:30，6,497,336 字节。
  SHA256：1F9E610D25C44E7509FB1B18A60217B0FA0B741D80AA68A1563EB3B6C1689A6F。
  clk_50m Fmax 127.883 MHz、USB 47.917 MHz 域 Fmax 80.395 MHz；所有 setup/hold TNS=0，
  96 MHz 派生时钟被 Gowin 明确报告无数据时序路径。验证器现接受这种显式无路径的报告，仍要求对应 TNS=0。
- 修改前频谱版备份：impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-23_pre_legato128.fs。
- 回归全部通过：`tmp/checks_legato128_release.log` 覆盖原功能、128 预设、单音滑音及所有显示场景。
  最终高库名称修复后的真实 UI 专项见 `tmp/checks_performance_final.log`；实际桥接校准遍历与 CC27 全范围见
  `tmp/checks_velocity80.log`。FM 音色解析/生成器的 10 项 Python 单测通过。
  最终 UI 固件 42,684 B；基础回归的长场景先加载名称掩码修正前的固件，随后各新启动场景使用最终固件，
  最终专项明确检查高库名称、编号、末页、滑音和按键，不以旧名称版测试代替发布检查。
  45 个工程 RTL 文件 hierarchy 校验通过，两块 FPGA 位流时序检查通过。未执行实机烧录。
- 实机待确认：四库试听、超过 32 的名称、力度手感、单音连奏与松键回退、踏板和快速开关模式。

## 辅助演奏与曲目装载接口（2026-10-23）

- SETUP 右列新增 PRACTICE，内部页面编号 9；保留底部 800×128 全宽琴键。
  上方落键与黑白键精确对齐，WAIT 等键练习、DEMO 示范、暂停/继续、重来、50..150% 五档速度。
  工厂 ROM 为自行录入的公版《小星星》42 音、默认含引导 26.624 s。
- 重复音必须收到新的非零力度 Note On；错音与提前一直按住不推进，长音暂不评松键时机。
  进入时暂时关闭单音滑音、固定显示八度 0、释放踏板；退出恢复原滑音开关与显示八度。
  当前音色、效果器和主音量继续适用。操作前先松开键和踏板。
- RGB/HDMI 共用 `lesson_view.v`，纯 RTL 绘制；每行消隐扫描 128 项，不用帧缓冲或 DDR。
  `lesson_player.v` 独立硬件时基，MIDI 握手和退出清理不会等待 UI。
  `midi_note_owners.v` 区分手动/示范持有的同音键，示范退出不会松掉手动仍按住的音。
  示范用内部事件 bit31 标记，MIDI channel 不被占用；单音模式切换同步清理所有权记录。
- 已留统一 RAM 曲目装载口 UI[31..34]，与 USB/蓝牙/SD 传输方式分离。
  当前容量 128 个单音事件，16 ms 刻度，C3..C5；检查连续地址、音域、时值、重叠、越界后提交。
  工厂 ROM 与上传 RAM 独立，播放/RGB/HDMI 各自同步读取并共享写入；复位恢复工厂曲目。
  **尚无 USB/蓝牙接收驱动、SD 驱动、曲目列表或掉电保存，不能直接装入任意完整复音 MIDI。**
  重写已选中的上传 RAM 后若中止，应恢复工厂库或重新上传；无损替换旧上传曲目要增加第二个用户 bank。
- `tools/midi_to_lesson.py` 支持 SMF 0/1、tempo map、running status 与单通道提取，
  输出版本化 JSON/`.mem`，无第三方 MIDI 包依赖；工厂 ROM 和参考 MIDI 同由 `generate_lesson.py` 生成。
- 完整使用说明、寄存器、容量边界和验证项见 `ASSISTED_PLAY.md`；49 个工程 RTL 文件已登记，
  IDE hierarchy 与两份 CLI 构建脚本一致。软核固件 45,328 / 65,536 B。
- 验证日志：`tmp/checks_lesson_release.log` 为全套回归，真实 UI 专项另见 `tmp/checks_lesson_ui.log`；
  最后增加的滑音切换所有权清理另见 `tmp/checks_lesson_owner_final.log`；暂停时未接收音符不跳过的
  修订见 `tmp/checks_lesson_player_final.log`，最终装载专项见 `tmp/checks_lesson_loader_final.log`。
  全套回归开始后进行了这两项小修，相关最终 RTL 已另外重编上述专项，Python 共 15 项单测。
  首轮构建日志为 `tmp/build_lesson_release.log`（该轮时序失败，最终发布使用下文 pipeline 日志）；
  `build_lesson.log` 为发现前向声明差异前的诊断构建，
  其中菜单逻辑被错误优化掉，绝不能作为发布结果；中间构建同样不是发布结果。
- 修改前的 128 音色/滑音版备份：`impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-23_pre_lesson.fs`。
- 代码检查点 `8a3c05b`。`build_lesson_release.log` 的首轮最终构建于 2026-10-24 00:17 完成，
  **时序失败**：主域 37.427、RGB 17.063、HDMI 像素 14.586 MHz，不可烧录。
  已将失败位流留到 `tmp/fm_138k_rgb_hdmi_lesson_timing_failed.fs`，标准 .fs 路径恢复上一版 1FC729... 位流。
  随后把像素除法/反算边界替换为同步几何 ROM，并在 MIDI 所有权判断后增加弹性队列，
  修复组合路径跨越多个复杂运算的问题。几何 ROM 与曲目一同由生成器输出，RGB 下半段白键边界也与触摸坐标对齐。
  修改后双屏光栅/丢锁专项与 MIDI 队列专项通过；原全套 37 个场景无失败，Python 15 项通过。
  `tmp/build_lesson_pipeline.log` 的修订版已通过四域时序：主域 52.899、RGB 37.614、HDMI 像素 32.906、
  HDMI 串行 166.583 MHz；全部 setup/hold TNS=0。
- **最终发布位流**：`impl/pnr/fm_138k_rgb_hdmi.fs`，2026-10-24 00:37:21，41,852,327 字节，
  SHA256 `221021C6368B185C73C0737C26F474BD0D9880160D706DA365481C8B5F9EB4ED`。
  Logic 34240/138240、Register 17479/139095、BSRAM 310/340、DSP 64.5/298；固件仍为 45,328 B。
  BSRAM 剩余 30 块，后续扩大曲库/音效缓存时需要继续核算，不能直接加入整屏帧缓冲。
- 原全套 37 个仿真场景全部完成且日志无 FAIL/FATAL；时序修订后重新编译双屏光栅专项，
  见 `tmp/checks_lesson_view_timing.log`，以及新增的所有权队列专项 `tmp/checks_midi_owner_queue.log`。
  队列验证停顿期间输入数据/亮度改变不影响已缓存事件，验证同音归属和事件顺序。
  几何 ROM 替代算术后，落键区域像素保持一致，下半段白键边界补齐并与触摸坐标一致。
  永久回归脚本现含 27 个 testbench、38 个场景（新增队列用例已单独通过）；未为了未改动的音效重跑第二遍全套。
- 本轮只需更新 138K 双屏位流，25K USB 桥接协议与位流未改。尚未执行实机烧录。
  实机待确认：触屏/USB 等键、连续重复音、变速和暂停、示范与手动同音、双屏对齐及退出后无挂音。

## 2026-10-24 琶音器

- 用户批准标准琶音器，并追加要求：完成后自主设计、实现音序器，不等待再次指令。
- 修改前标签 `archive/pre-arpeggiator-20261024` 指向 e3ddfc0；旧位流备份
  `impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-24_pre_arp.fs`，SHA256 221021C6368B185C73C0737C26F474BD0D9880160D706DA365481C8B5F9EB4ED。
- ARP 入口 SETUP 左上 ARPEGGIATOR，page10，底部全宽琴键；详见 `docs/ARPEGGIATOR.md`。
- 新 `midi_arpeggiator.v` 接于统一输入与所有权队列之间，内部生成标记 bit30；原始监视事件仍用于练习和按键显示。
- UI[36..45] 为参数/状态，37..40 影子时长由 36 写入原子提交。单音滑音、踏板、HOLD、练习的互斥与清理已接入。
- `tmp/checks_arp_rtl_final.log` 已通过，含 128 音集合与外同步预留接口。
- `tmp/checks_arp_ui_final.log` 已通过真实 RV32I + Goodix 验证：入口/全部参数/触屏/HOLD/STOP/跨页/练习互斥。
- 此代码检查点时 `tmp/checks_arp_all.log` 全套回归与 `tmp/build_arp_final.log` 布线仍在运行，尚不能把生成位流认定为发布版。
- 固件 49,948/65,536 字节。没有烧录实机；不要将综合完成误报为时序通过。

### 琶音器独立构建已验证

- ARP 实现提交 `88bf67e`。`tmp/checks_arp_all.log` 的 40 个场景全部通过，无 FAIL/FATAL。
- `tmp/build_arp_final.log` 四域时序通过：主域 50.210、RGB 34.531、HDMI 像素 33.531、串行 212.691 MHz，setup/hold TNS 均为 0。
- 2026-10-24 12:32:59 位流另存 `impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-24_arp_88bf67e.fs`，42,234,791 字节，
  SHA256 `D4124F221E56BBC222275C4D84EDD5273953EED6676150ADCD5488B2B3AD7BCD`。
  此为可回退的 ARP 单功能版本，不含后续音序器与自动演奏踏板屏蔽修订。

## 2026-10-24 音序器

- 用户追加授权后直接设计并实现，无需再确认方案；不是仅留下方案。
- SETUP 右上 STEP SEQUENCER，page11，8×16 RAM 模式，逐步音高/力度、REST/TIE、长度、循环、步进录入、二次确认清空。
- 与 ARP 共用 BPM，但 RATE/GATE/SWING 分别设置。工具页保留全宽琴键，离页可继续播放。
- `step_sequencer.v` 硬件负责初始化、录音、MIDI 和微秒时基。UI[46..55] 接口及 v1 步骤格式见 `STEP_SEQUENCER.md`。
- 录入游标（UI47）与查询地址（UI55）独立；刷新网格不会改变录音位置。
  固件任何录入期间的手动编辑先读取最新硬件游标，防止 100 ms UI 轮询延迟导致覆盖旧步骤。
- 只有一个 RAM 写端口：录入开启时拒绝手动写并置错误；固件在手写 REST/TIE 等操作时短暂取消录入再恢复。
- sequencer_active 接入 ARP suspend；练习 suspend 也独立接入音序器。进入 ARP/滑音/练习会停止音序器。
  退出练习不自动重启旧循环。内部 bit31 复用示范所有权，二者互斥；不新增保留 MIDI 通道。
- 新发现 FM 延音踏板为全局状态，会使自动音符无视 GATE：开始音序器播放/录入先发 CC64=0，
  ARP 的 suspend 直通分支也将 CC64 映射到 0，覆盖音序器和练习；普通演奏踏板规则保持。
- 当前固件 56,552/65,536 字节；没有增加软核、DDR、帧缓冲或厂商 IP。
- `tmp/checks_seq_rtl.log`、`tmp/checks_seq_ui.log`、`tmp/checks_auto_registers.log`、
  `tmp/checks_arp_rgb.log`、`tmp/checks_seq_rgb.log` 已通过。最后一组重新编译的 UI 互斥/回归与 FPGA 构建仍在执行。
- `tmp/build_seq.log` 为踏板修订前的音序器构建，不能当最终新发布；最终需重新构建并更新此处的校验值与时序。
- IDE 和两份 CLI 构建已列入新模块，`check_project_files.py` 检查 51 个 RTL 文件通过。

### 自动演奏切换补充检查

- `tmp/build_seq.log` 的踏板修订前位流已于 13:06 完成，四域时序为 50.017 / 35.511 / 37.997 / 297.560 MHz，TNS=0；
  已另存 `impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-24_seq_pre_pedal.fs`，不能作为最终发布。
- `tmp/checks_seq_ui_release.log` 以及 `checks_final_ui_seq/arp/lesson/performance.log` 已通过功能和互斥检查。
- 后续发现 MIDI 模式事件与 0x69 读回走不同队列：一个工具刚恢复滑音后，另一个工具立即读回可能读到旧 OFF。
  新增 `set_glide()`：发送模式后等待 0x00C 读回确认（轮询预算 20 ms，保留原单次访问超时，不把 0xFFFF 当作 ON），统一用于工具切换。
  ARP/SEQ 互换还保留前一工具的逻辑保存值，避免后续改变传输延迟又引入此问题。
- `tb_touch_ui +seq +glide_delay` 模拟初始 GLIDE ON、延迟 2000 个时钟才更新模式读回，检查录入/停止/ARP/SEQ/练习/退出恢复。
  `tmp/checks_auto_glide_modes.log` 已通过完整场景。对应最新固件 56,432/65,536 字节。
- `tmp/build_arp_seq_final.log` 因上述固件修订主动停止，当前最终候选重建日志为 `tmp/build_arp_seq_release.log`。
  构建完成必须重新确认时序与哈希，尚未实机烧录。
- 最终回归脚本登记 29 个 testbench、45 个场景；ARP 阶段整套 40 场景通过，SEQ/踏板/模式切换阶段按改动重新编译相关专项，未声称完整复跑全部 45 项。
- `render_ui_capture.py --prefix arp_` / `--prefix seq_` 可读取各自实际固件字符日志，避免多项 UI 仿真覆盖同一份截图日志。

### 最终发布：ARP + SEQ + 踏板保护 + 滑音切换同步

- 功能代码提交 `973b8cb`（此前 `88bf67e` 为 ARP，`c678ced` 为 SEQ）；2026-10-24 13:40:38 生成最终位流。
- 烧录文件 `impl/pnr/fm_138k_rgb_hdmi.fs`，42,107,303 字节，
  SHA256 **`0960E23B918975BDEB47459EF389ED6AD7DF1E2045C85A4F4714F3129B0FBA4D`**。
- 最终日志 **`tmp/build_arp_seq_release.log`**；CLI 自动门禁和独立 `check_timing.py fm_138k_rgb_hdmi` 均通过。
- Fmax：主域 **50.007 MHz**（要求 50）、RGB **34.770 MHz**（33.333）、HDMI 像素 **35.736 MHz**（25）、串行 **238.948 MHz**（125）。
  四域 setup/hold TNS=0，无失败端点。主域余量很小，后续每次重新构建必须重新检查，不能沿用本次结论。
- PnR 资源：Logic 40,739/138,240，Register 20,789/139,095，BSRAM **314/340（剩 26）**，DSP 65/298。
  固件 **56,432/65,536** 字节。没有新软核或外部存储依赖。
- 新模块都已列入 IDE/CLI 工程；最终 `check_project_files.py` 确认 51 个 RTL 文件的实例定义齐全。
- 最终验证矩阵：ARP 阶段全套 40 场景通过；后续分别重新编译并通过 SEQ RTL、自动演奏寄存器/原子提交、
  ARP/SEQ 页面 RGB 琴键、真实 UI SEQ/ARP/练习/128 音色与滑音，以及最终 **初始滑音 ON + 延迟读回** 完整互斥测试。
  `tmp/checks_auto_glide_modes.log` 对应最终 56,432 字节固件；`checks_arp_rtl_final.log` 包括自动演奏踏板屏蔽。
- `impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-24_arp_88bf67e.fs` 可回退到独立 ARP 版；
  `_seq_pre_pedal.fs` 仅为开发中间备份。`build_arp_seq_final.log` 为主动中止的旧构建，勿与最终 release 日志混用。
- 本轮只更新 138K 双屏位流，25K MIDI 桥接板无需更新。**没有执行实机烧录或听音**。
  待实机验证：五种 ARP 顺序/HOLD/踏板、SEQ 录入/休止/连音/长度/换组、音色与 FX、触屏/外部键盘、
  以及原先开启滑音时来回切换 ARP/SEQ/PRACTICE 的状态恢复和停音。8 组模式掉电不保存。
