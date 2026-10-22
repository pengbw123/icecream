# ACG720 双屏波形与李萨如输出

## 实现

- 原 800×480 RGB 触摸屏保持 `top_138k` / `build_cli.tcl`，继续由 `rgb_visualizer.v` 输出。
- 双屏版本使用 `top_138k_hdmi` / `build_cli_hdmi.tcl`。HDMI1 输出 640×480、25 MHz 像素时钟，约 59.5 Hz；125 MHz 串行时钟由第二个 `video_pll` 产生。仅输出视频，不发送 HDMI 音频。
- HDMI 内容由 `hdmi_scope_video.v` 逐像素生成，不使用软核或全帧缓存。它直接复用 `audio_wave_scope.v` 和 `audio_xy_scope.v`；两路屏幕各有自己的捕获银行与跨时钟握手，以免互相等待。
- 两路显示接收同一份效果器后的 PCM 和 `VIEW`、`XY DELAY`、`AUTO`、主题颜色参数。HDMI 只显示示波器图像，触摸菜单仍显示在 RGB 屏幕。
- 用户在 IDE 中生成的 Gowin DVI TX 3.0 IP 配置与端口正确。但双屏综合时，IP 的 ELVDS 缓冲映射到 Bank 7 的 LVDS25E，和同 Bank 的 3.3 V RGB 屏幕引脚冲突（CT1136）。因此双屏构建不加入该 IP，而使用工程已有 `tmds_encoder.v` 的 TMDS 编码与成对 LVCMOS33 ODDR 输出。生成的 `src/dvi_tx/` 保留供硬件电源/引脚方案变化时参考。

## 构建与验证

在工程目录运行 `gw_sh build_cli_hdmi.tcl`，目标为 `impl/pnr/fm_138k_rgb_hdmi.fs`。旧的 `impl/pnr/fm_138k_rgb.fs` 属于单 RGB 版本。

Gowin IDE 工程 `fpga_project.gprj` 已加入双屏顶层、HDMI 视频/TMDS 源文件及双屏 CST/SDC，并停用原单屏 CST/SDC 和不适用的 DVI TX IP。IDE 的 `impl/fpga_project_process_config.json` 将 `TopModule` 设为 `top_138k_hdmi`，输出名设为 `fm_138k_rgb_hdmi`；打开工程后 Hierarchy 应以 `top_138k_hdmi` 为根。此配置文件位于忽略的构建目录，重新克隆工程时可在 IDE 中手动设顶层与输出名，或直接使用 `build_cli_hdmi.tcl`。

`sim/tb_hdmi_scope_video.sv` 检查 800×525 总时序、640×480 有效区域、HS/VS 脉宽和无未知像素。`tb_audio_wave_scope`、`tb_audio_xy_scope` 分别检查波形与李萨如采集，`tb_138k_io` 检查 TMDS 编码符号。成对 LVCMOS33 输出的电气兼容性和显示器锁定仍需上板确认。

2026-10-22 的双屏 PnR 已完成，逻辑 25242/138240、寄存器 14499/139095、BSRAM 245/340、DSP 51.5/298、PLL 2/12。50 MHz 主时钟、33.333 MHz RGB 像素时钟、25 MHz HDMI 像素时钟、125 MHz HDMI 串行时钟的实际 Fmax 分别为 54.685、40.490、49.613、210.114 MHz；各时钟组的 setup/hold TNS 均为 0。双屏位流写入 `impl/pnr/fm_138k_rgb_hdmi.fs`（2026-10-22 22:08），未覆盖单 RGB 位流 `impl/pnr/fm_138k_rgb.fs`（2026-10-22 20:28）。

ACG720-138/60K 原理图的 HDMI1 J6 通道使用 R137–R144 八个 49.9 Ω 串联电阻。当前成对 LVCMOS33 输出方案能够在与 RGB 同时使用时通过布线，但显示器是否能稳定锁定、图像是否正确仍需实机验证。建议先接显示器并烧录双屏位流，分别检查 WAVE 和 XY 模式、两屏同时显示以及声音是否正常；若显示器无信号，先检查时钟/数据极性与 HDMI 供电控制，再考虑硬件 Bank 电压方案。
