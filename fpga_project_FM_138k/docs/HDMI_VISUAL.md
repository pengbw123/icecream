# ACG720 双屏波形与李萨如输出

## 2026-10-28 21:24 摄像头启动恢复修正（当前下载版）

- 生产源码`9d6a9d3`，位流北京时间2026-10-28 21:24:05，SHA256 `46898EAB7B7F7148207A1B5AE74AEEC04A857E58B6DE8EA02317B66F48EA0201`，标准文件`impl/pnr/fm_138k_rgb_hdmi.fs`已更新，未自动烧录。
- 启动首次稳定帧宽限10秒，首次正确帧后保持2秒断流重试；传感器QVGA配置、帧几何检查、NN权重/门限/默认OFF均未改。数码管统计增加一拍以拆分显示换算长路径，音频样本不变。
- 七项专项通过，含延迟首帧、一直无帧的有界重试、正常流后的断流、1100800像素整链、诊断/停钟恢复和数码管真实引脚；未重跑不变的完整UI/NN/FM/MIDI矩阵，沿用20:15版本证据。
- 五域setup/hold TNS=0；Fmax MHz：主域50.012、相机88.488、RGB33.346、HDMI像素78.070、串行347.032。主域slack0.005ns、RGB0.012ns，余量仍小。
- Logic67671、FF37207、BSRAM331/340、DSP82/298；比20:15版多19 Logic、18 FF，BSRAM/DSP不增加。未删模块、未降频、未放宽约束。
- 用户已确认第45章TFT摄像头显示成功；20:15版本在OBS可见诊断底图，但蓝条READY1/P02710/SC0且无完整帧，开启识别后FRAMES始终0。启动逻辑修正尚未实机确认，不能声称已解决无帧，更不能归咎摄像头硬件或仅归咎OBS。
- 第45/47章SCCB和DVP文件完全相同，前252寄存器表达式相同；第47章多503D=00，尺寸/实际XCLK/初始化复位/DDR/HDMI有差异。详细对照与根因边界见`CAMERA_HDMI_DIAGNOSIS.md`。
- 本轮记录`releases/2026-10-28_camera_startup.json`；回退`impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-28_pre_camera_startup.fs`，SHA256 `A443C69D6247B4A9E44E5DEB3B8CC409970D1B3978F116366F1B56B105E12117`。

## 2026-10-28 手势集成：最终构建验收

- 生产源码 `9cf7ec2`，标准位流北京时间 `2026-10-28 20:15:42`，SHA256 `A443C69D6247B4A9E44E5DEB3B8CC409970D1B3978F116366F1B56B105E12117`。
- Logic 67652/138240，FF 37189/139095，BSRAM 331/340，DSP 82/298。
- 未删模块、未降频、未放宽约束；四拍手势后处理与一拍动作译码，FM调度周期不变。
- 五域setup/hold TNS=0；Fmax(MHz)：clk_50m=50.069, camera_pclk_50m=106.012, pixel_33m=34.835, hdmi_pixel_25m=73.67, hdmi_serial_125m=358.422。
- 最终固件真实RV32I/I2C手势页与琴键回归通过，时序优化后COMPOSER回归重新通过，另有NN/ROI/CDC/控制联合、FM32/I2S、MIDI入口、摄像头诊断/显示回归。
- 默认识别/控制OFF，未自动烧录。摄像头实机无图仍未解决，真实手势准确率未验收；公开CGI测试81.72%。
- 回退：`impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-28_pre_gesture.fs`，SHA256 `D1491687FD1979D5A3309A66F4BF6C0AEEFC3E67A7E9335BD14E9472FCE87747`。完整记录`releases/2026-10-28_gesture_integration.json`。


## 2026-10-27 QVGA缩放/PCLK模式修正（历史发布）

- 第二次实机反馈仍只有蓝条/格子；ID5640/E0/READY1，P3880/H926E/V0006，但R/N/G=0。原F00可能是从未收到帧快照的初值，不是有效帧证明。
- 核对用户新提供的第47章完整例程，引脚与当前版一致；发现QVGA补丁未开5001[5]缩放、未开460C[1]手动分频。修正5001=A3、460C=22、3824=04、3035=41、3036=60；25MHz XCLK不变，模式回读扩至13项。
- 旧16位1ms测频在80MHz时恰好溢出为3880，故上一照片不能据其断言14.464MHz。新20位Gray计数、五位P值已通过80MHz测试；S增加复位释放、已见同步及预热数。
- 配置、捕获、停钟恢复、80MHz测频/字形和1100800像素整链仿真通过；未改音频/CPU固件，本次未重跑全部矩阵或音频回归。
- Logic 65855、FF 35828、BSRAM 324/340、DSP 80/298。
- 五域setup/hold TNS=0；Fmax：clk_50m 50.02MHz, camera_pclk_50m 68.808MHz, pixel_33m 34.798MHz, hdmi_pixel_25m 71.894MHz, hdmi_serial_125m 409.626MHz。
- 标准位流`impl/pnr/fm_138k_rgb_hdmi.fs`，北京时间2026-10-27 23:00:57，42340871B，SHA256 `D1491687FD1979D5A3309A66F4BF6C0AEEFC3E67A7E9335BD14E9472FCE87747`。
- 生产提交abaa0d6，完整构建`tmp/camera_build_abaa0d6`，日志`tmp/build_camera_abaa0d6.log`，发布记录`docs/releases/2026-10-27_camera_modefix.json`。
- 未自动烧录，实机是否消除故障及实际PCLK速率仍待确认；若无图，应结合新S与P/R/B/N诊断定位。CAMERA_CAPTURE.md含状态位和历史故障证据。

## 2026-10-27 摄像头首轮实机问题修正与可读诊断（历史发布）

- 首个摄像头版本实机只有红/蓝条和格子，没有真实画面；不能视为采集已成功。
- 明确修正通用图与同型号厂商例程CST的差异：D0/D1/D3/D6改为J2/J1/H2/D1；补PWDN=L1并明确驱动低。新增16信号引脚回归及冲突检查。是否解决这块板的完整帧故障需再次实机确认。
- 配置回读增加3008唤醒位和4740极性/门控，共八项；采集帧完整性检查仍保留，没有通过放宽检查输出半帧。
- HDMI底部128像素显示四行诊断：ID/E/READY、PCLK活动/原始H/V计数、上帧行数/行字节范围/像素数/错误标志、显示/丢弃/坏帧计数。全部十六进制，正常R=00F0、B=0280-0280、N=4B00、F=00。
- 16位Gray测频独立于ready；72位持有快照/toggle确认跨域，消隐锁存，重配保留故障证据。新增字库使用1块BSRAM，不改CPU固件。
- 配置/捕获/停钟恢复/测频及字符数值/整链1100800像素/引脚夹具通过，真实RTL画面已检查；仿真不代表实机根因已排除。音频功能源未改，本次未重跑音频或全部矩阵。
- Logic 65899、FF 35781、BSRAM 324/340、DSP 80/298；GPRJ 72个RTL文件。
- 五域setup/hold TNS=0；Fmax：clk_50m 50.007MHz, camera_pclk_50m 93.493MHz, pixel_33m 34.431MHz, hdmi_pixel_25m 61.793MHz, hdmi_serial_125m 419.633MHz。
- 标准位流`impl/pnr/fm_138k_rgb_hdmi.fs`，北京时间2026-10-27 21:39:06，42213383B，SHA256 `69F1A097D39E85140745E5094E65195F30469C0BE441A50C31816488DA8432A8`。
- 生产提交6d39de0，完整构建`tmp/camera_build_6d39de0`，日志`tmp/build_camera_6d39de0.log`，发布记录`docs/releases/2026-10-27_camera_hwfix.json`。
- 未自动烧录，新版实机验证待用户完成；若仍无图，应读取完整四行诊断再定位，不继续盲改。操作和标志定义见CAMERA_CAPTURE.md。

## 2026-10-27 OV5640采集/HDMI预览（历史发布）

- 摄像头接P4；HDMI1/J6临时改为摄像头彩色预览，RGB菜单、32复音音频及演奏功能保留，未加入手势识别。
- 25MHz XCLK复用原HDMI PLL；320×240 RGB565采集，160×120 RGB332双缓冲（38400B），放大为640×480，约59.52Hz HDMI。
- 芯片ID/252项写入/六项配置回读、故障重试、四帧预热、逐行逐帧完整性、整帧丢弃、消隐切换、停流及PLL恢复；状态条和帧/错误/丢帧计数。
- SCCB引脚级异常/恢复、DVP边界、停PCLK复位、整链1484800像素/无撕裂、RGB琴键及实际FM32/I2S/MIDI回归通过，未重跑全部矩阵。
- 上轮AI旋律19.9ns最差路径增加有符号音程寄存级，仅增加20ns延迟；三组164个MIDI事件音高/力度/顺序一致，网络及规则不变。
- 固件未改、未增加软核ROM/RAM；工程清单71个RTL文件。
- Logic 65454、FF 35314、BSRAM 323/340（较上版+19）、DSP 80/298。
- 五域setup/hold TNS=0；Fmax：clk_50m 50.127MHz, camera_pclk_50m 88.054MHz, pixel_33m 36.769MHz, hdmi_pixel_25m 81.896MHz, hdmi_serial_125m 470.684MHz。
- 标准位流`impl/pnr/fm_138k_rgb_hdmi.fs`，北京时间2026-10-27 17:43:38，42340871B；SHA256 `4053136259170173349B0E5FB1D94CD8DBBAF3EAAB11DF6ADCE901CFF2F8A5F3`。
- 生产提交194c61e，完整构建`tmp/camera_build_194c61e`，日志`tmp/build_camera_194c61e.log`。首个33a3b0f实现因诊断复位计数问题在最终布线前取消，不是发布物。
- 备份`impl/pnr/backup/fm_138k_rgb_hdmi_pre_camera.fs`，发布记录`docs/releases/2026-10-27_camera_capture.json`，使用说明CAMERA_CAPTURE.md。
- 未自动烧录，摄像头实拍、电气时序及长期音频稳定性待板上验收。资料中的手册接口编号与V5原理图相反，接线按实际3.3V/GND丝印和P4对应。

2026-10-23 更新：双屏顶层已加入板载 ES8388 耳机监听，仍与 RGB、HDMI 同时运行。
最新 `impl/pnr/fm_138k_rgb_hdmi.fs` 为 2026-10-23 14:39 构建；Logic 26755、Register 15055、
BSRAM 277/340、DSP 56.5/298。主域/RGB/HDMI 像素/HDMI 串行 Fmax 分别为
51.412/42.790/51.690/177.671 MHz，四域 setup/hold TNS 均为 0。
本次还修正 delay/phaser 和参数平滑端点，详见 `ES8388_AUDIO.md`、`EFFECTS_SPEC.md`。
下文 2026-10-22 的资源与位流日期保留为历史记录。

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
