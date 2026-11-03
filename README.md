# Gowin 138K 实时FM电子乐器

当前主工程为 `fpga_project_FM_138k/`，面向ACG720 GW5AT-138 B。使用32声部、六算子FM、128组预置音色，支持USB MIDI与触摸、双Part、RGB可视化、SD用户音色、琶音/音序、手机曲谱与灯带等功能。

## 当前入口 2026年11月3日

- IDE工程：`fpga_project_FM_138k/fpga_project.gprj`；RGB+HDMI构建入口：`build_cli_hdmi.tcl`。具体源文件、工具版本及约束以工程和冻结清单为准。
- 已通过构建的候选位流：`fpga_project_FM_138k/impl/pnr/fm_138k_gesture_probe.fs`，2026-11-02 20:59生成。SHA256 `97A853217B176CC843B84EB1C58901323496DCD4F7C3BDD1066EDB67D99F6773`。它把延迟脉冲送P7-15；LED0为心跳。
- 最新状态与证据：[技术状态](fpga_project_FM_138k/docs/CURRENT_TECHNICAL_STATUS_2026_11_03.md)。标准 `fm_138k_rgb_hdmi.fs` 尚未覆盖，根目录 `fm_138k_rgb.fs` 是旧文件，请勿作为当前交付使用。
- 本目录Android配套源码为 `android_control/`，Manifest版本0.4.6/code17；App界面存在不等于其中全部音色控件已接入当前FM蓝牙协议。
- 使用CH376直接接138K，默认不需25K中转。下方25K说明仅适用于历史加法合成工程，不是当前138K接线和资源数据。

## 文档与验收

修订作品报告为根目录 `基于FPGA的实时多音色合成电子乐器_作品报告_20261103_r7.docx`。本次只修文档，不改RTL、不重新构建或烧录。资源与时序、逻辑回归、实板观察分开记录，模拟总延迟和外部脉冲测量仍待闭合。

---

# 历史工程 Tang Primer 25K USB-MIDI加法合成器

这是面向Tang Primer 25K的实时数字乐器工程。MIDI键盘通过Dock板USB-A接口连接FPGA，RV32I软核完成USB Host枚举和USB-MIDI协议处理，RTL音频引擎完成8复音、每音16谐波的加法合成，并通过I2S连接MAX98357功放模块输出声音。

当前版本同时支持四基准谐波音色插值、谐波独立衰减、ADSR、力度、延音踏板、总音量、Pitch Bend、Vibrato、Portamento，以及Chorus、Delay和Reverb三种后级效果。

## 仓库结构

```text
fpga_project3/
├─ src/                  FPGA RTL、约束、USB Host软核和固件
│  ├─ generated/        正弦表、音高表、包络表和默认音色参数
│  └─ usb_midi/         USB 1.1 Host RTL与RV32I固件
├─ sim/                  加法合成器RTL测试平台
├─ tools/                谐波编辑器、UART参数工具和表生成脚本
├─ fpga_project.gprj     Gowin IDE工程
├─ build_cli.tcl         Gowin命令行完整构建脚本
└─ README.md             原理、控制映射、接线和验证说明
```

构建目录、位流、IDE用户配置、诊断工程、Python缓存和本地可执行文件不提交到仓库，可由源码重新生成。

## 快速开始

### 1. 构建FPGA工程

使用Gowin EDA `1.9.12.03`打开：

```text
fpga_project3/fpga_project.gprj
```

器件必须选择：

```text
GW5A-25B / GW5A-LV25MG121NC1/I0 / Device Version B
```

也可以在已配置`gw_sh`的终端中执行：

```powershell
cd fpga_project3
gw_sh .\build_cli.tcl
```

构建完成后下载`fpga_project3/impl/pnr/fpga_project.fs`。

### 2. 连接硬件

- MIDI键盘接Dock板USB-A Host口；
- MAX98357的BCLK、LRC、DIN分别连接J3-15、J3-16、J3-17；
- MAX98357使用J3的5V和GND供电；
- 扬声器只接MAX98357的`SPK+`和`SPK-`，不要将其中一端接地；
- USB-C用于下载、115200波特率日志和UART音色参数传输。

### 3. 启动谐波编辑器

```powershell
cd fpga_project3\tools
.\install_python_requirements.bat
.\run_harmonic_editor.bat
```

编辑器用四组可拖动柱状图修改C2/C3/C4/C6的16次谐波幅度，并直接显示和编辑四基准各自的16项相对衰减时间；64项衰减参数不再经过全局频率曲线近似，可与ADSR一起通过UART实时发送到FPGA。
上电默认载入`pianotone2.json`，其四组谐波已做安全归一化，避免高增益音色与长混响叠加后持续削顶。

### 4. 分析真实乐器录音

```powershell
cd fpga_project3\tools
.\run_instrument_analyzer.bat
```

频谱分析器读取WAV/AIFF/FLAC单音录音，以可独立全屏的高对比热力图显示STFT频谱；纵轴可自动缩放到前32次谐波，鼠标悬停任意频点会在热力图上方浮动显示该频率的时间—幅度曲线。工具还能以自动增益播放原始选段并动画联动时间线和32谐波柱状图，同时提供谐波峰值表、衰减拟合以及JSON/CSV导出。首次使用仍执行同一个`install_python_requirements.bat`安装依赖。

阶段二程序`fpga_project3/tools/run_timbre_builder.bat`同时处理C2/C3/C4/C6四个真实单音，把绝对谐波幅度分解为总能量包络与相对音色变化，避免与FPGA全局ADSR重复衰减；可A/B试听原声、16谐波和32谐波重建，并导出相对衰减Q0.24参数。工具目录的用途索引见`fpga_project3/tools/README.md`。

## 当前验证状态

- USB-MIDI键盘枚举、按键、力度和总音量已完成实板验证；
- 加法合成、四基准插值和UART编辑链路已完成RTL与实板验证；
- Pitch Bend、Vibrato、Portamento和三种数字效果已通过完整综合、布局布线与时序分析，等待进一步实板听感调校；
- 长混响保留上一版强度；效果器反馈运算已修正为32位中间结果，USB端点、MIDI邮箱、软核和合成状态机均已加入自恢复；
- 最终资源：Logic 59%、Register 23%、BSRAM 84%、DSP 88%；
- 50 MHz音频域Fmax为50.904 MHz，Setup/Hold违例为0，TNS为0。

详细MIDI映射、DSP原理、引脚表和测试步骤见[工程说明](fpga_project3/README.md)。

## 第三方代码

USB Host相关RTL和软核代码的许可说明见`fpga_project3/src/usb_midi/LICENSE.third-party.txt`。
