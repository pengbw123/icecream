# 给后续 AI 的工程交接说明

更新时间：2026-10-23（800×480 可配置配色菜单，以及此前的耳机监听与效果器修正）。目标是让接手者从当前代码和硬件状态继续，
不要把计划、候选代码或仿真结果误写成已交付功能。

## 2026-10-23 UI 改版

- 改版前已提交 Git：`2616714`，包含 ES8388 / delay / phaser 的完整源码存档。
- 新 UI 的现行布局、配色、触摸区域与新增 attr 定义见 `UI_LAYOUT_2026.md`。
  旧章节中的 PERF/NAME/UTIL、橙色主题和旧控件坐标不再是当前菜单布局。
- 界面仍为纯 RTL 字符/图形扫描 + RV32I 菜单逻辑，800×480；无逐像素软核 GUI。
- 新布局单独放在 `src/ui_firmware/menu_layout.h`，修改后仍需重新编译 firmware.hex。
- FFT / ARP / SEQ 仅预留入口，不能当作已经实现。
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
