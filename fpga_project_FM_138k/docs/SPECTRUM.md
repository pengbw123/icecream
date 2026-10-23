# 实时频谱（2026-10-23）

## 操作

- PLAY 右侧显示切换为 WAVE / XY / FFT，键盘尺寸仍为 800×128。
- SETUP → SPECTRUM 直接回到 PLAY 并显示频谱；DISPLAY 也可在三种模式间循环。
- RGB 与 HDMI 同步选择模式。主音量、效果器和发声输出选择仍按原设置工作。
- 频谱读取最终 `monitor_sample`，即效果器和主音量之后、SPEAKER/HEADPHONE 路由之前的 PCM。
  因而可以直接看到音色谐波、效果器的频率变化与主音量变化；静音不会自动被放大。

## RTL 数据路径

`audio_spectrum_analyzer`（50 MHz、两款 138K 顶层各一份实例）→ 广播 64 列高度/峰值 →
RGB 和 HDMI 各自的 `audio_spectrum_snapshot` → 现有 RTL 光栅。

- 1024 点实数输入，周期 Hann 窗，18 位复数中间值，输入按位反转。
- 原位 radix-2 DIT FFT，蝶形旋转使用 Q15 正余弦，每级除 2 防止溢出。
- 采样率为 50 MHz / 1024 = 48,828.125 Hz，bin 间隔为 47.6837 Hz。
  采集 1024 个连续样本后进行变换，变换阶段暂停下一块视觉采集；不向音频模块施加反压。
  变换与频段扫描约 0.85 ms，约 46 次/秒输出，不要求视频帧率与 FFT 帧率相同。
- bin 1..511 映射为 64 个对数频段，范围约 48 Hz..24.4 kHz，每列取频段内最大幅度。
  最低几列重复使用同一 bin，不能解析间隔小于约 47.7 Hz 的成分；这不是 64 路倍频程 RMS 分析。
  不显示 bin 0；窗口会让输入直流分量泄漏到相邻低频 bin，不宣称做了直流消除。
- 视觉幅度近似 `max(abs(Re),abs(Im))+min(abs(Re),abs(Im))/2`，经 Hann 相干增益补偿，
  对数值单位为 1/8 octave（约 0.753 dB）。整窗 bin 对齐满幅正弦对应约 0 dBFS；
  显示范围 -72..0 dBFS，近似幅度/对数存在约 1 dB 量级误差，仅用于视觉反馈。
- 快速起跳，每 FFT 帧回落一个单位（约 34 dB/s）；峰值保持 12 帧（约 0.26 s），然后回落。
  首次运行不读取未初始化的历史数据，复位后必须采满一块再输出。

每块屏幕独立使用两个 64×14 bit 缓存，发布/应答采用翻转位跨时钟同步。
只在垂直消隐切换显示 bank，应答返回音频域后才允许重新使用旧 bank。
慢屏幕丢弃完整分析帧，不能卡住分析器或另一屏幕。
PLL 丢锁同时复位本屏幕缓存双方；恢复时忽略半截输出，直到新的第 0 列开始才接收。

RGB 柱状区域是 x=16..527、y=96..319，每柱 7 像素、间隔 1 像素，下面保留频率标注。
HDMI 使用同样的 512 像素宽柱状区域，水平居中。颜色沿用背景、主题与中性峰值标记。
软核只负责模式和菜单文字，不计算 FFT，也不逐像素绘制频谱。

## 寄存器与工程

- UI[5] bit14：spectrum_enable；bit12：XY；FFT 模式下 bit12 为 0。
  bit13 仍是耳机输出选择，bit8..11 仍是键盘八度。
- `tools/generate_spectrum_tables.py` 生成 `src/generated/spectrum_{hann,twiddle,bands}.mem`；
  表文件已纳入版本控制，无需 IP 或在线生成器。
- 新 RTL 同时登记在两个 CLI 构建脚本与 `fpga_project.gprj`，IDE 顶层保持 `top_138k_hdmi`。

## 验证

- `tb_audio_spectrum`：FFT 位序、复数符号、归一化与 Hann 增益、频段定位、12 dB 幅度比、
  静音、负满幅/Nyquist 邻域、双音同时输入、回落与峰值保持。
- `tb_spectrum_snapshot`：整帧切换、视频延迟/丢帧、bank 所有权和 PLL 恢复后丢弃半帧。
- `tb_touch_ui +spectrum`：运行真实 RV32I 固件与 Goodix I2C，检查首页三种模式、设置快捷入口、
  DISPLAY 循环及无多余 MIDI。
- `tb_rgb_visualizer +spectrum` 与 `tb_hdmi_scope_video +spectrum`：实际光栅输出中检查柱高、柱间隙；
  RGB 场景同时覆盖 PLL 丢锁恢复。

实机仍需检查：已知频率音色的峰值位置、改变主音量后的高度、静音回落、多点弹奏、快速模式切换、
RGB/HDMI 同时输出、耳机与外部音响切换。

## 发布构建

双屏位流 `impl/pnr/fm_138k_rgb_hdmi.fs`，生成于 2026-10-23 20:23:59。
SHA256：`644ED30C80B23A98A74177FDDF3BAA0405B9F98BC11A11E36FC7E04155B96CA4`。
固件 41,308 B；Logic 29100、Register 16342、BSRAM 286/340、DSP 64.5/298。
四个时钟域 setup/hold TNS=0，构建日志 `tmp/build_spectrum_release.log`。

数值加强用例：`tmp/checks_spectrum_numeric.log`；真实模式入口：`tmp/checks_spectrum_ui.log`；
RGB 频谱：`tmp/checks_spectrum_rgb_delivery.log`；HDMI 频谱：`tmp/checks_spectrum_hdmi.log`。
完整回归 `tmp/checks_spectrum_release.log` 通过，合计 21 个 testbench、29 个场景（含单独完成的两屏频谱光栅）。
早期 RGB 频谱测试只注入一次数据，碰到既有丢锁场景后缓存按设计失效；
测试已改为持续注入以覆盖恢复，早期失败日志不对应最终测试结果。
