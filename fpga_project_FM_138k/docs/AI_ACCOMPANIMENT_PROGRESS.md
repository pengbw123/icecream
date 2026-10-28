# BSRAM优化与AI伴奏进度

## 2026-10-28 22:17 TFT原配置摄像头版（当前下载版）

- 生产源码`72b42ac`，位流北京时间2026-10-28 22:17:31，SHA256 `DB541725601D2D5C547B01C77A745BFCDE75FAEA40D5D19BD69B73013C071155`；标准`impl/pnr/fm_138k_rgb_hdmi.fs`已更新，未自动烧录。
- 用户实测21:24版仍无图。本轮采用第45章TFT已验证的完整252项800×480 RGB565配置，独立参考PLL为50×16÷33约24.242MHz；SCCB约400kHz，硬复位1ms/释放后20ms/软复位5ms。撤销原QVGA缩放、窗口与手动PCLK补丁。生产十帧正确预热，启动10秒/稳定后2秒恢复逻辑保留。
- 中央裁剪640×480后4×4降采样为160×120；原帧缓存容量和NN输入不增加。HDMI失锁不再复位摄像头/NN；摄像头参考PLL失锁则清除采集/NN状态。RGB菜单、音频、NN权重/门限/默认OFF不变。
- 外部PCLK时序要求收紧为85MHz，0.5～5ns输入延迟预算保持；新增24.242MHz参考时钟。所有约束时钟setup/hold TNS=0；Fmax MHz：主域50.257、PCLK103.650、RGB35.820、HDMI像素76.511、串行352.943；参考时钟为无数据路径，频率已在报告核对。
- Logic67675、FF37213、BSRAM331/340、DSP82/298、PLL3/12；比21:24版多4 Logic、6 FF和一个PLL，BSRAM/DSP不增加。未删模块或放宽约束。主域最差slack0.102ns，现为频谱RAM读出到band_max路径。
- 独立对照工具核验TFT原表全部252项、顶层尺寸/镜像/实际PLL一致；六项摄像头回归通过。800×480/84.75MHz采集249600个精确像素/十帧预热；整链约230万显示像素、原始采集到真实NN、HDMI失锁期间NN继续计数、独立PLL恢复均通过。模拟PLL/传感器，不等于实机已出图；不变的UI/FM/MIDI完整矩阵沿用既有证据。
- 详见CAMERA_TFT_PROFILE.md与`releases/2026-10-28_camera_tft.json`。新正常值R=01E0、B=0640-0640、N=4B00、十帧预热后S通常E8～EB。先关闭识别看完整诊断，再只开识别/关闭控制检查FRAMES持续增加。本轮实机图像和手势识别仍待验收。
- 回退`impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-28_pre_camera_tft.fs`，SHA256 `46898EAB7B7F7148207A1B5AE74AEEC04A857E58B6DE8EA02317B66F48EA0201`。快照tmp/camera_tft_build_72b42ac，完整日志tmp/build_camera_tft_72b42ac.log，证据assets/camera_tft/。GPRJ与两份CLI清单已同步，文件检查81项通过。

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


## 2026-10-28 手势菜单与演奏控制集成

识别链路已实例化到HDMI摄像头顶层，RGB菜单增加RECOGNITION/CONTROL独立开关，HDMI复用字体显示状态与ROI方框；COMPOSER增加模式保护、UI/打击垫优先与手势握手。默认全部OFF，未改摄像头引脚和配置。源码`1af0e10`，UI80404/81920B；八组专项和音频/MIDI/摄像头针对性回归通过。最终真实UI回归和统一PnR验收进行中，尚未替换标准位流；前次路由过程被中断，恢复构建日志`tmp/build_gesture_1af0e10_resume.log`。实机采集与识别仍待验证，离线测试81.72%不代表实际镜头效果。

## 2026-10-28 摄像头识别离线推进（历史阶段）

按用户要求暂停无图故障定位，先实现神经网络手势原型：ROI取样、跨域特征邮箱、INT8 MLP、连续帧确认和可关闭的演奏动作输出。公开白底CGI训练/测试已完成，测试81.72%，372×3输出与RTL逐位一致；五组仿真通过。尚未接生产顶层/菜单/命令仲裁，未生成新位流，不能称为实机手势已可用。源代码、进度与限制见`GESTURE_RECOGNITION.md`，训练/验证日志见`assets/ai/gesture/`。真实采集与数据校准完成后，合并其他待接入模块统一PnR。

## 2026-10-27 后续摄像头采集发布

HDMI临时改为摄像头彩色预览，RGB菜单和AI演奏保留，未加入手势识别。原AI音程关键路径新增20ns寄存级，三组164事件音高/力度/顺序等价；主域Fmax50.127MHz，五域setup/hold TNS=0。最新标准位流、资源和实机状态见`CAMERA_CAPTURE.md`及`releases/2026-10-27_camera_capture.json`。

## 2026-10-27 AI COMPOSER第1阶段（历史发布）

- 新增互动主旋律：SETUP → AI BASS → COMPOSE >。进入时抓取AI音色，LIVE仍可独立即兴；共用32复音和FX，与其他自动演奏模式互斥。
- 触屏高低/疏密、1～8音主题、变奏/重复/对比/收尾、四小节锁定复播与停止后继续；打击垫学习、预备拍与两小节节奏输入。
- 模型128→48→36，7872权重/84偏置；POP909 MELODY轨84/20/20首隔离，35轮。网络计算15912周期/318.24us；明确乐句规则与网络共同生成。
- 网络162向量/5832分数一致；1776音阶边界；闭环疏密16/33起音、平均音高62/71，锁定/变奏/收尾/节奏/背压通过。
- 实际FM32/I2S、RGB键区、96KiB物理RAM和真实RV32I/I2C的COMPOSER/AI BASS/ARP/SEQ/SD无卡返回/RENAME/KEYBOARD针对性回归通过，未重跑全部矩阵。
- 未训练的节奏/对比权重置零，恒定变化量64精确折入偏置；128个真实特征输出不变，162×8次控制扰动验证通过。控制动作由RTL规则处理。
- MIDI入口增加一级弹性寄存，USB邮箱在接收前保留事件；三来源144事件并发/背压验证无丢失或重复。屏幕TAP采用独立命令，不依赖学习后的垫映射。
- 首轮2a2d631主域47.724MHz/TNS=-389.721ns未发布；通过入口寄存缩短FIFO→译码→ARP/SEQ路径，最终结果以下述本次报告为准。
- UI镜像80648/81920B；BSS通过既有数据地址别名复用指令副本区，没有扩大RAM，常量隔离且栈余17656B，保留至少12KiB检查。
- 位流 `impl/pnr/fm_138k_rgb_hdmi.fs`，北京时间 2026-10-27 12:17:50，42213383B。
  SHA256 `5CD28EAE91E702DE29F6CBFAFBC26393A241D5C49D9A493E6D596AFD8713819B`。
- Logic 66548、FF 35537、BSRAM 304/340、DSP 81/298。
- 四域setup/hold TNS=0；Fmax：clk_50m 50.022MHz, pixel_33m 35.95MHz, hdmi_pixel_25m 32.462MHz, hdmi_serial_125m 190.039MHz。
- 常规完整实现；源码1932728，快照`tmp/composer_build_1932728`，日志`tmp/build_composer_1932728.log`。
- 说明AI_COMPOSER.md，机器记录`docs/releases/2026-10-27_ai_composer.json`，原位流备份`impl/pnr/backup/fm_138k_rgb_hdmi_pre_ai_composer.fs`。
- 未自动烧录，听感/长期稳定性待实机。第2阶段回听/撤销/SD乐句保存及第3～5阶段尚待后续实施。

## 2026-10-26 AI BASS V2（历史发布）

- 左手大小三和弦/转位/单根音跟随，分区默认 MIDI60（可调36～84）；右手力度、起音疏密、触键时长影响伴奏。
- FOLLOW等待演奏，松键/踏板释放后约一拍收尾；CONTINUE持续背景。BPM手动设定，未加入自动追拍。
- 模型96→32→17，四头为起音、音级、门控、强弱；3616个INT8权重、49个偏置，推理7330周期/146.6us。
- 124首POP909按84/20/20首隔离，训练45轮。测试起音F1约0.782；标签仍是PIANO低音代理，不能等同实用听感。
- 当前源码成对RTL测试：轻/重平均力度41/107，稀疏/密集四小节17/32次起音；和声、长短触键、踏板、无输入静默/收尾通过。
- 精确网络向量、MIDI事件、真实FM32/I2S音频、RV32I/I2C菜单回归通过；没有重跑全部回归矩阵。
- 最终位流 `impl/pnr/fm_138k_rgb_hdmi.fs`，北京时间 2026-10-26 20:16:24，42340871 B。
  SHA256 `10C8DA614921845D5121BD30F28CD14E463F3F0BEDD7458E5EF60185A1B7B691`。
- Logic 63743、FF 33932、BSRAM 296/340、DSP 79.5/298。
- 四域setup/hold TNS=0；Fmax：clk_50m 50.045MHz, pixel_33m 34.586MHz, hdmi_pixel_25m 32.198MHz, hdmi_serial_125m 146.889MHz。
- 增量复用尝试未通过（主域39.399MHz、RGB31.670MHz、HDMI像素22.032MHz），已弃用，失败产物保留在tmp/ai_build_05c7187；标准位流来自下述常规构建。
- 使用常规重新综合及PnR。原时钟约束和实现设置不变；源码快照 `tmp/ai_build_05c7187_full`，生产提交 05c7187。
- 固件74196/81920B，未增加软核存储容量；GPRJ仍为63个生产RTL文件，和声辅助模块位于既有AI文件内。
- 说明见 `AI_BASS_V2.md`，六组成对MIDI在 `assets/ai/v2/`（GM试听，不是FPGA音色）。发布记录 `docs/releases/2026-10-26_ai_bass_v2.json`。
- 未自动烧录，实际听感与长时间稳定性待实机验证。旧版备份见发布JSON rollback_bitstream。

## 2026-10-25 板载数码管（历史发布）

- 数码管显示 `L xxP xx`：最终 PCM 的 40ms 窗口峰值 0–99，加活动复音数（含释放尾音/伴奏）。
- 使用原有 50MHz 时钟使能，HC595 50kHz；DP 关闭、每轮快照一致。新增电路未使用 BSRAM/DSP。
- RGB 与双屏顶层/CST/GPRJ 均接入，工程清单检查为 63 个 RTL 文件。
- 两项针对性仿真通过（边界及默认生产参数/实际引脚解码）；未重跑全矩阵，未自动烧录，实机仍待验证。
- 最终位流 `impl/pnr/fm_138k_rgb_hdmi.fs`，北京时间 2026-10-25 23:56:59，42234791 B。
  SHA256 `5BF9AC841EC3303D47E779521F341ACB5CDFF360737C31D4690F01E3C1F9499A`。
- 最终 Logic 61528、FF 33026、BSRAM 294/340、DSP 73.5/298。
- 四个时钟域 setup/hold TNS=0；Fmax：clk_50m 50.145MHz, pixel_33m 33.651MHz, hdmi_pixel_25m 33.14MHz, hdmi_serial_125m 203.151MHz。
- 生产源码 25427e5，隔离构建 `tmp/ai_build_25427e5`，日志 `tmp/build_seg8_timing.log`。
- 首轮 e6feb3e 主域49.243MHz、51个setup端点失败，未发布；随后锁存FM复音统计、ARP计时器零标志，并在既有周期锁存失真绝对值。
  ARP时序谓词逐周期断言及FX/32复音/滑音/双Part/AI联合回归通过；统计仅多1个时钟显示延迟，不增加音频处理周期。
- 训练入门和源码导航见 `AI_BASS_BEGINNER_GUIDE.md`，原始训练日志已保存 `assets/ai/ai_bass_training.log`。
- 详情见 `SEG8_STATUS.md`；发布机器记录 `docs/releases/2026-10-25_seg8.json`。

以下保留前一版 BSRAM/AI 的阶段验收记录。

用户授权日期：2026-10-25。开始前标签：archive/pre_bram_ai_20261025。

| 阶段 | 产物 | 验收条件 | 状态 |
|---|---|---|---|
| 1. 连接图存储优化 | 以矩形/线段显示列表替代32KiB画布；移除软核32KiB暂存 | 全32算法逐像素对照；自编辑路由仍可绘制；不改变菜单外观 | 已通过64图逐像素及RTL回归 |
| 2. 数据RAM整理 | UI独立96KiB RAM、链接/栈/镜像同步 | 固件栈余量检查、真实RV32I菜单回归 | 已通过；显式64+32KiB，综合数据RAM64→48原语 |
| 3. FPGA重新实现 | 双屏位流、资源与时序报告 | 四域setup/hold通过；报告实际BSRAM收益 | 完成；含AI最终294/340，四域setup/hold通过 |
| 4. MIDI伴奏数据与软件原型 | 因果特征、训练/验证分离、固定点模型、试听MIDI | 数据来源可追溯；与规则基线比较；不能将程序规则标注成训练结果 | 已完成；原创旋律+模型伴奏演示MIDI已导出 |
| 5. INT8推理RTL | 小型时序网络、权重导入、软件一致性回归 | 与固定点参考逐项一致；测量最坏推理周期 | 162向量/1296分数全部一致，3664时钟 |
| 6. 伴奏事件调度与音源接入 | LIVE不阻塞、BACKING发声、启动/停止及NoteOff | 固定采样节拍、满载与停止无挂音；与ARP/SEQ互斥 | 单元及实际top/FM32/I2S联合仿真通过 |
| 7. 菜单与最终发布 | 风格/速度/调性/伴奏控制、位流和说明 | 菜单回归、整机时序通过；实机听感由用户验收 | 菜单、RGB键盘、最终PnR已通过；未烧录，待实机 |

首版范围：指定BPM、4/4、指定调性/和弦，单轨贝斯伴奏；根据主奏历史调整音符/休止/持续，复用BACKING音色。
训练在电脑完成，推理在FPGA完成。LIVE事件直接发声，AI观察独立副本；不等待推理，不修改音频采样期限。
模型输出受到音域/和声/复音/时值约束。AI和ARP/SEQ争用同一BACKING，因此首版互斥。

限制：少量合成训练样例只能验证学习/量化/RTL链路，不能据此宣称具有人类乐手水平或通用风格能力。
若没有适用且授权明确的主奏/贝斯配对数据，必须如实记录，保留用户MIDI数据导入接口。

当前原型：POP909前48首中的47首4/4样例，按歌曲划分31训练/8验证/8测试；PIANO轨提取受限单音低声部标签，
不是独立标注的真实贝斯轨。模型48→32→8，1792个INT8权重、40个INT32偏置，非通用即兴音乐模型。
测试18712步，准确率83.29%，多数类基线79.61%，各类平均召回率34.12%；不能用准确率替代听感验收。
数据仓库固定提交、文件SHA256见下载manifest；生成权重和完整指标见src/generated/ai_bass/training_report.json。
来源：https://github.com/music-x-lab/POP909-Dataset ，d83e6edba6872a704f5d3b8b32f5cb540088dae6。

BSRAM注意：第一次声明96KiB数组被Gowin向上取整，UI数据RAM仍映射64个综合BSRAM实例。
因此改为显式64KiB+32KiB存储体并重跑实现，不把声明容量下降当成实际资源收益。

第一次物理结果：BSRAM287/340，Logic70587，FF39090，DSP70；主域Fmax48.849MHz，202个setup端点失败。
该中间位流标记FAILED_TIMING，不能烧录；最终验收前曾恢复旧版，现标准路径已更新为下述成功发布。
原256路矩形比较改为一个36-bit描述表BSRAM + 双行寄存缓存，逐行提前绘制，预计多用一块BSRAM但大幅减少逻辑和布线。
64个标准/反馈自编辑图形的扫描线RTL回归已通过；256重叠矩形压力用例769/1056像素时钟内完成，像素仍延迟两拍。
首次失败日志tmp/build_bram_banked.log；新结果必须经过实际STA检查后才发布，不以仿真或估算替代。

最终发布：2026-10-25 21:05:40，impl/pnr/fm_138k_rgb_hdmi.fs，42340871B。
SHA256：6953519ED85D38F8ABEB8BCD7889AA4EF1294DDD1423263759C2959A8B60C592。
Logic61332、FF32897、BSRAM294/340、DSP73.5/298；含AI和新增菜单后比原版319块净少25块（7.35个百分点），余46块。
Fmax主域50.120/RGB36.557/HDMI像素32.124/串行160.030MHz，四域setup/hold TNS=0；主域最紧余量0.048ns。
日志tmp/build_ai_scanline.log，生产源快照22e955e，最终报告与源文件清单已复制回标准impl并重新核验。
本轮针对性回归全部通过，未重跑整个大矩阵；没有自动烧录，仍需用户试听和长时间实机验收。

AI菜单：SETUP底部左侧拆成METERS / AI BASS两个入口，原GLIDE MS保留。
先选贝斯音色→AI BASS→START（抓取BACKING）→返回PATCH切换LIVE音色→即兴。
可调BPM、KEY、DENSITY、VELOCITY；选择固定I-vi-IV-V每小节一个和弦，或静态大小三和弦。
当前模型只有流行数据原型，未提供虚假的多风格选择。
硬件在AI启动时保留正常LIVE通路，AI事件经独立有界寄存仲裁插入，不等待推理。
验证日志：tmp/check_ai_inference.log、tmp/check_ai_accompaniment.log、tmp/check_ai_audio_final.log、tmp/check_ui_ai.log。
原菜单内存调整回归：tmp/check_bram_ui_banked.log（ALGO/EG/LFO/Pitch/FX/命名/槽位/主题）。
新增AI固件的SEQ与GLIDE MS回归也已通过：tmp/check_ai_ui_seq.log、tmp/check_ai_ui_glide_time.log。
数据存储独立回归覆盖64/96KiB边界、不别名、字节写、一拍读与指令独立性：tmp/check_ui_memory96.log。
实际固件写入日志生成的800×480预览已检查：tmp/ai_menu_preview.png、tmp/bram_algo_preview.png。
AI固件73876/81920B，text73820、data56、bss10792；静态区结束0x10014abc，96KiB内余13636B供栈等使用。

补充计算基线：同模型优化标量C运行在现有RV32I无M扩展软核，真实特征向量109248时钟、全127数值压力向量413584时钟，
RTL均3664时钟，输出分数完全一致。只限该软核/实现/输入，不是桌面CPU对比；详见AI_BASS.md。
