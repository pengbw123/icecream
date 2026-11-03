# 当前工程技术状态与提交证据

核对日期：2026年11月3日。本页统一报告与工程入口；旧文档中的构建中、旧App版本、旧资源表和旧接线须按所指版本理解。本轮不修改RTL、固件、约束或手势功能。

## 版本依据

| 项目 | 当前依据 |
|---|---|
| 主工程 | `fpga_project_FM_138k/fpga_project.gprj`，顶层 `top_138k_hdmi` |
| 器件与工具 | GW5AT-138 B / GW5AT-LV138PG484AC1/I0，Gowin V1.9.12.03 |
| 已完成候选 | `impl/pnr/fm_138k_gesture_probe.fs`，2026-11-02 20:59 |
| SHA256 | `97A853217B176CC843B84EB1C58901323496DCD4F7C3BDD1066EDB67D99F6773` |
| 冻结输入 | `tmp/gesture_performance_probe_build/source_manifest.json` |
| 收据 | `docs/releases/2026-11-02_latency_probe.json`，构建与回归PASS，脚本未自动烧录 |
| 键盘路径 | CH376直连138K；默认关闭25K中转 |
| Android源码 | 仓库根目录 `android_control/AndroidManifest.xml`，0.4.6 / versionCode 17 |
| Git | 最近已推送基线ffda094，候选包含后续未提交修改；应同时归档冻结清单 |

`impl/pnr/fm_138k_rgb_hdmi.fs`仍为11月1日标准文件（SHA256 `610db0d65cc770fa3c3c94056380fb60239623ddc621f73990c49adbff01f170`），未被候选覆盖。19:47的`fm_138k_gesture_performance.fs`把标记放LED0，而20:59的probe版本移到P7-15。根目录`fm_138k_rgb.fs`是10月18日历史文件，不是本次交付。实际安装APK的哈希、签名与手机型号尚需随验收补记，本轮没有生成APK。

## 当前功能边界

- 六算子、32种算法、128组预置；32个声部总池、192份独立算子状态，运算流水共享。LIVE/BACKING共用32声部，不是各32，也不是固定16+16。
- Note Off按音高和Part匹配。同Part同音高的多个活动声部会一起进入释放，不保证实体键身份级独立释放。
- 内置《晴天》提供固定跟拍、弹对再走，由人工按键发声。上传曲谱由`score_player.v`按时间自动产生音符，不是当前已接入的一键多音手弹路由。
- 上传容量8192×48 bit，Note On和Note Off分别计事件。0x55/57探测，0x50/51/52写入和CRC封存，0x53播放，0x54停止；当前无0x5A处理分支。板端声明32复音，与手弹共用。
- JDY口115200 8N1专用于曲谱和灯位等控制，CH340保留FM参数协议。当前没有把手机音色页的全部控件接到JDY→FM参数路径。
- SD支持FAT32 SDHC、预建FMUSER.BIN、八槽双副本校验。READ SD只读入RAM，选槽LOAD RAM才应用；不保存FX、主音量或ARP/SEQ Pattern。
- ARP启动抓取BACKING音色，HOLD可跨页手弹；SEQ按Pattern保存音色快照。ARP/SEQ互斥，播放中BPM等调节不中止transport。Pattern与其音色快照断电丢失。

历史App0.7.2、r2实体键动态映射和《花海》身份配对记录不能直接作为本目录同版本证据。作品报告r7已收窄相应描述，原r6保留。

## 资源与时序

取自同一冻结构建的`impl/pnr/fm_138k_rgb_hdmi.rpt.txt`与`fm_138k_rgb_hdmi_tr_content.html`，已经包含RGB、HDMI和摄像头等逻辑。

| 资源 | 使用 / 可用 | 精确占比保留一位 |
|---|---:|---:|
| Logic | 80559 / 138240 | 58.3% |
| Register | 45530 / 139095 | 32.7% |
| CLS | 57633 / 69120 | 83.4% |
| BSRAM | 337 / 340 | 99.1% |
| DSP | 87 / 298 | 29.2% |
| I/O | 90 / 297 | 30.3% |

BSRAM只剩3块；工具显示的100%为其整数显示口径，非340块全占。资源按当前结构综合分配，不能直接用剩余DSP推断可增加多少复音。

| 时钟 | 约束MHz | 报告Fmax MHz | Setup/Hold TNS |
|---|---:|---:|---|
| 主系统 | 50.000 | 50.114 | 0 / 0 |
| 摄像头PCLK | 85.000 | 106.307 | 0 / 0 |
| RGB像素 | 33.333 | 35.514 | 0 / 0 |
| HDMI像素 | 25.000 | 76.412 | 0 / 0 |
| HDMI串行 | 125.000 | 264.059 | 0 / 0 |

静态时序通过限于既有约束；Fmax不是实际运行频率，也不代表未约束外部路径或异步交接已经实物验收。主域余量小，后续新增功能应重看存储与关键路径。

## 赛题证据与演示

| 要求 | 展示方法 | 证据范围 |
|---|---|---|
| 实时生成声音 | 六算子相位、包络及逐样本调度 | ROM存参数/函数，不存乐器录音 |
| 至少两种独立演奏维度 | 固定力度改音高；固定音高改力度；可补充弯音 | 启用力度灵敏度，同音色对照 |
| 至少32独立声部 | 持续纯正弦，首页VOICES按S0，LIN FFT数32峰 | 不把FM谐波当独立声部；同时保留音频与统计 |
| 小于5ms延迟 | 同版本、固定起音条件，输入参考与模拟输出双通道测量 | 当前尚无完整模拟端实测结论 |

32音测试使用MIDI96..127，力度32，约2093.00至12543.85 Hz。同一FM和输出链实时发声，S0/S1停止。1024点FFT间隔47.6837 Hz，本组高音便于分峰；预期频率见[频率表](POLYPHONY_TEST_FREQUENCIES.csv)。准备及操作见[32声部测试](POLYPHONY_TEST_AND_LOGO.md)。

## 延迟测量与未闭合项

probe版本：P7-15 / GPIO0_12 / D14为latency_probe，P7-12为地；3.3V逻辑，LED0恢复心跳。NOTE>I2S起点为板内已接受Note On，终点为达到起音门限后的I2S左声道最后位，不含上游键盘扫描、USB前段和DAC模拟路径。详见[延迟说明](NOTE_LATENCY.md)及[接线](LATENCY_PROBE_40PIN.md)。

用户反馈触屏一次NOTE>I2S为358μs、OK/TIMEOUT 1/0、SKIPPED 0；外部P7-15仍未见脉冲，此项未闭合。不能把UI数字当作示波器实测，更不能声明整机模拟端小于5ms。

另有USB单键VOICES和MIDI ACCEPTED各加2的实机反馈，用户确认键盘只发一条事件，之后已要求终止排查。单事件仿真通过不能据此声称实机已修复；提交前需复测并记录。手势相关内容本轮不处理。

## 验证与归档入口

已归档PASS日志位于工程`tmp/opt_poly.log`、`opt_latency.log`、`opt_ingress.log`、`opt_rgb_voices.log`、`opt_rgb_linear.log`、`opt_observer.log`、`opt_tutorial.log`和`opt_strip160.log`。它们证明各自仿真覆盖范围，不代替现场验收。

复现入口包括`sim/run_bluetooth_score.ps1`、`sim/run_sd_checks.ps1`、`sim/run_polyphony_checks.ps1`；请按脚本参数配置工具路径。所引日志、原始PnR及时序报告、CST/SDC、冻结清单和完成收据已复制至[持久证据目录](../assets/documentation_2026_11_03/README.md)，并附各文件SHA256。本次核对548项冻结输入与当前工程一致，未改RTL或构建输入。源码完整交付仍应保留对应源树或正式Git提交，哈希清单本身不能重建源码。

文档修订清单：根目录README、作品报告r7、本页、PROGRAM_AND_FLASH、NOTE_LATENCY、LATENCY_PROBE_40PIN及PERFORMANCE_MONITOR。原报告r6保留，本轮不修改手势章节，不新增构建或实机通过声明。
