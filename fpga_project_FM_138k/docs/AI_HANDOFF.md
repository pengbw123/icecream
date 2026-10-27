# 给后续 AI 的工程交接说明

<!-- CAMERA_HW_FIX_PENDING_START -->
## 摄像头首次实机故障修正（验收中）

- 用户首版实机反馈为蓝/红条交替、格子底图，无真实摄像头图像；不能继续标记为实机已验证。
- 明确发现通用原理图与GW5AT138K第59章厂商CST差异：四根数据脚修正，显式PWDN=L1拉低。新增16信号独立约束检查。是否消除这块板的成帧问题待实机确认。
- 新增8项配置/唤醒/极性回读，以及HDMI四行可读诊断：ID、错误码、ready、PCLK频率/停钟、原始H/V计数、上帧行数/行字节范围/像素数/失败标志。整帧快照跨域握手、消隐锁存，重配保留最后故障证据。
- 配置、捕获、独立恢复、诊断数值/字形及1100800像素整链仿真通过；本次集中构建验收后才更新标准位流，未烧录。详情CAMERA_CAPTURE.md。
<!-- CAMERA_HW_FIX_PENDING_END -->

## 2026-10-27 OV5640采集/HDMI预览（最新发布）

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

## 2026-10-25 BSRAM与AI伴奏（前一版验收记录）

- 已完成代码、针对性回归、整机PnR和四域时序验收；没有自动烧录，实机音质/兼容性待用户验证。
- 标准双屏位流impl/pnr/fm_138k_rgb_hdmi.fs已更新，2026-10-25 **21:05:40**（北京时间），**42,340,871 B**。
  SHA256 **6953519ED85D38F8ABEB8BCD7889AA4EF1294DDD1423263759C2959A8B60C592**。
- 最终Logic **61332/138240（45%）**、FF **32897/139095（24%）**、BSRAM **294/340（87%，精确86.47%）**、DSP **73.5/298（25%）**。
  含AI与新增菜单后，比上次319块仍净少 **25块、7.35个百分点**，剩余46块；不要把中间失败版的287当作最终占用。
- Fmax主域 **50.120**、RGB **36.557**、HDMI pixel **32.124**、serial **160.030 MHz**，四域setup/hold TNS=0。
  主域最紧slack **0.048ns**（FM scheduler_voice→voice_age使能），余量仍小，不能直接提高时钟。
- 最终硬件源码为22e955e，后续提交仅测试/文档。隔离构建tmp/ai_build_22e955e，日志tmp/build_ai_scanline.log；
  生成物和源码清单已复制回标准impl，根目录重新运行时序与62文件清单检查通过。CRLF规范化后全部生产src与快照一致。
- 使用与限制见AI_BASS.md、USER_MANUAL_UI.md；阶段表见AI_ACCOMPANIMENT_PROGRESS.md。
  首版为指定和声的单轨流行低音伴奏，共享BACKING，与ARP/SEQ/PRACTICE互斥；总32复音、共享FX/音量。
- 本轮新/修改路径的针对性回归通过，未重跑整个sim/run_checks.ps1全矩阵。
  额外做了现有RV32I无M扩展的优化C基线，真实特征109248周期、全127压力特征413584周期，RTL均3664周期，分数一致。
  这是周期仿真内核对照，不是桌面CPU结论或应用整体延迟。详见AI_BASS.md。

### 开发过程记录（历史；以下失败与恢复状态均已由上述最终发布取代）

- 用户要求先释放BSRAM，再构建AI伴奏，并要求19:30前持续推进；不是19:30停止任务。
- 开始前标签archive/pre_bram_ai_20261025；代码提交b51f3f2（矩形图+96KiB RAM）、a167590（训练INT8伴奏）、
  0070da6（AI页键盘显示）、7f18fbe（图形比较门控）、22e955e（扫描线图形器）。
- 96KiB单数组被Gowin按128KiB映射，已改显式64+32KiB，UI数据综合原语64→48；栈顶由链接器决定。
- 初次并行矩形版PnR确认BSRAM319→287（减少32块、9.41个百分点），但Logic70587、FF39090，
  Fmax48.849MHz，主域setup TNS=-41.682ns/202端点失败。最紧包括FM voice_age、ARP、XY峰值和FFT。
  这不是可烧录发布。失败位流保存为impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-25_bram_FAILED_TIMING.fs。
- 已将标准impl/pnr/fm_138k_rgb_hdmi.fs恢复为上次时序通过的FE76300D...旧版（2026-10-24 23:18:01）。
  不要把该标准路径的旧位流说成含AI或BSRAM优化；只有新STA全部通过后再替换。
- 为降低逻辑/布线压力，ui_algo_map改为一个36bit描述表BSRAM+双行寄存缓存，逐行提前渲染、每拍处理8像素。
  接口仍index*8，0..3低字节先写，字节4提交36bit条目，0x7ff8/9提交条数；保持关闭图层、50us等待、上传、开启的协议。
  C绘图缓冲变为256项矩形列表；全部32标准图+32反馈自编辑图与旧位图每像素一致。
  扫描线RTL对应golden采样点通过，256重叠矩形压力行769/1056时钟内完成，输出仍两拍。
- AI为实际训练的48→32→8 MLP，不是GRU。POP909固定提交的前48首中47首4/4，31/8/8歌曲级划分；
  PIANO轨提取受限单音低声部标签。1792个INT8权重、40个INT32偏置；测试准确率83.29%，多数类79.61%，
  各类平均召回34.12%，仅是小样本流行伴奏原型，不能宣传为通用编曲或专业乐手水平。
- ai_bass_inference纯RTL串行MAC，162向量/1296分数全部与软件一致，固定3664时钟（73.28us，不含节拍等待）。
  ai_bass_accompaniment观察LIVE副本，不对观察口反压；按十六分音符决策，独立寄存仲裁插入BACKING bit30事件。
  STOP精确松开AI音符；全局panic锁存停机；改变速度不重启；和声切换避免保持无关旧音。
- SETUP下部METERS / AI BASS；先选贝斯音色START抓取BACKING，再选LIVE音色即兴；BPM、KEY、DENSITY、VELOCITY、
  I-vi-IV-V循环/静态大小三和弦；和声由用户给定。AI与ARP/SEQ/PRACTICE互斥，总32复音、共享FX/音量。
  新0x6A地址3F0控制、3F1/2周期影子，UI[60]状态。两个顶层、CLI、IDE清单同步（62文件）。
- 实际top/仲裁/所有权/FM32/I2S联合回归通过：30 LIVE声部+AI，非零PCM、LIVE换预设不污染BACKING、局部STOP不杀LIVE、无漏采样。
  真实RV32I/I2C的AI菜单、SEQ、GLIDE MS以及96KiB后的普通菜单回归通过；分块RAM边界/字节写/独立指令回归通过。
  预览tmp/ai_menu_preview.png、tmp/bram_algo_preview.png来自固件日志，未叠加纯RTL琴键；AI页琴键另有RGB像素回归。
- 进度及日志索引见AI_ACCOMPANIMENT_PROGRESS.md、AI_BASS.md。数据manifest和许可证在assets/ai，原始曲库留tmp不入Git。
  assets/ai/ai_bass_demo.mid为原创主奏+模型输出演示，不是FPGA实机录音；GM试听音色与板载DX7音色不同。
- 隔离快照tmp/ai_build_22e955e已完成并通过，源码与SHA256清单build_source_manifest.json。
  首次并行绘图失败日志tmp/build_bram_banked.log，报告备份tmp/bram_parallel_failed_reports；中间a167590/7f18fbe隔离构建已中止，不能使用。
  旧通过版备份impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-25_pre_bram_ai.fs；FAILED_TIMING位流只留作审计。

## 2026-10-25 HOLD 调参、滑音时间与双 Part（历史发布）

- 已完成用户要求的三项：HOLD 调参不中断、SETUP 增加 GLIDE MS（10..1000 ms，默认170 ms）、
  单流水线32复音 LIVE/BACKING 两 Part。详细操作、协议和限制见 `TWO_PARTS.md`。
- HOLD 根因是 ARP 改共享BPM时刷新停止中的SEQ，SEQ错误置清理状态，UI又把内部busy当作transport占用。
  现仅实际transport切换清理，内部初始化/编辑不暂停ARP。点按一步、450 ms后每50 ms重复保持不变。
- LIVE为手动键盘/触屏；BACKING为ARP或SEQ，两者仍互斥。ARP开启时抓取当前音色；SEQ首次录制时抓取，
  每个Pattern各有RAM快照。SEQ停止时可用 CAPTURE LIVE PATCH 更新伴奏音色。播放/录制中锁定Pattern切换。
  LIVE换预设/改参数不改变伴奏；同音高独立分配、松键/踏板/清音按Part处理，LFO和Pitch EG参数隔离。
  仍是总计32复音动态共享，主音量与效果器链共享；八个Pattern及快照断电不保存，SD格式未改。
- GLIDE仍是单音连奏，重叠按键触发；增加线性频率滑行时长，连奏保留相位/包络。
  新0x6A辅助编译参数写端口供BACKING上传及滑音倒数原子提交，不污染LIVE编辑接口。
- 固件 **70,268/81,920 B**，text70216、data52、bss42004；静态区结束0x1001b690，余18,800 B供栈等使用。
  firmware.hex与firmware_high.hex同次生成，两份顶层和IDE文件清单已核对。
- 最终双屏位流 `impl/pnr/fm_138k_rgb_hdmi.fs`，生成时间2026-10-24 **23:18:01**（北京时间），42,234,791 B。
  SHA256 `FE76300D4C7C2EFFB95896A8FEC316257533461B604FD34FD892CABBA02BB55C`。
  构建日志 `tmp/build_parts.log`。四域setup/hold TNS=0；Fmax主域 **50.032**、RGB **38.150**、
  HDMI pixel **34.795**、serial **180.091 MHz**。Logic **56298/138240（41%）**、FF **29323/139095（22%）**、
  BSRAM **319/340（94%）**、DSP **70/298（24%）**。
- 主域最紧路径是 ARP step_left 寄存器到 ordered 寄存器使能，slack **0.013 ns**，时序通过但余量很小。
  下一轮扩展应继续关注控制路径与BSRAM，不能因单采样调度尚有空余就直接提升时钟或复音。
- FM针对性回归：BACKING与冻结单音色参考逐样本一致；LIVE换预设后仍一致；混合发声时BACKING算子状态与输出仍一致。
  覆盖同音独立声部、踏板/局部停止、ARP/SEQ标记；32满载432事件固定1024周期无漏采样；滑音端点/时长/原子提交通过。
  日志 `tmp/check_parts_pcm_release.log`；其他矩阵已完成部分见 `tmp/check_parts_all.log`。
  完整大回归在UI阶段被用户中断，不能宣称全矩阵完成；恢复后真实RV32I/I2C的GLIDE MS、ARP、SEQ、PERFORMANCE四项菜单回归全部通过，日志
  `tmp/check_parts_ui_glide_time.log`、`tmp/check_parts_ui_arp.log`、`tmp/check_parts_ui_seq.log`、`tmp/check_parts_ui_performance.log`。
- 已检查800×480实际固件写入日志生成的SETUP预览 `tmp/parts_setup.png`，新增GLIDE MS布局正常。
  未自动烧录，听感、实际长时间播放及触屏操作仍待实机验证。
- 修改前Git标签 `archive/pre_parts_20261024` 指向d8caac4；旧位流备份
  `impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-24_pre_parts.fs`。本轮代码Git提交 `56b06b7`，验证完成后另补文档记录。

## 2026-10-24 长按提速与用户槽重命名（历史发布）

- 用户要求加快ARP/SEQ长按增减，重复周期100→**50 ms**，约每秒20步；触发门槛仍450 ms，点按仍一步。
  普通编辑页与PLAY控制条不变。固件和真实I2C/RV32I触摸回归已同步更新。
- 用户实机反馈：RENAME后PATCH右侧USER槽仍显示旧名，再STORE SD才更新。
  原因是RENAME只修改cur_name，槽列表读取slots[].name；STORE SD才将完整快照同步回RAM槽。
  修复为DONE时同步当前名称与选中非空USER槽的名称，**只改槽的名称字段、不覆盖其音源参数、不自动写SD**。
  状态提示NAME EDITED / SD NOT UPDATED；落盘仍需STORE SD。补齐短名称末尾字符编辑的空格扩展，避免旧NUL遮住新字符。
- 真实固件回归通过：USER行与顶部立即更新、LOAD RAM后保留新名、原缩放/Pitch EG等参数可恢复、重命名无MIDI/SD写入。
  最终固件 **68,240/81,920 B**，firmware.hex与firmware_high.hex已同次更新。
- 用户第三问仅讨论双音色的时序代价，本轮没有实现双音色或扩生产复音。建议先单流水线32复音双part，参数选择设置寄存边界；
  当前主域余量很小，双核不能直接解决FFT/XY/控制长路径。详见 `DUAL_TIMBRE_TIMING.md`。
- 仅在独立testbench探测64复音：`tb_fm_readback -Ptb_fm_readback.TEST_VOICES=64 +metrics`，
  render778、response779 clocks，65次逐帧起音/采样和一次抢音通过；这不是固定1024周期密集输入、整机PnR或实机验收。
  生产配置仍32复音单音色。用户已撤回本轮SD载入操作说明的问题，不需重复展开。
- 双屏发布位流 `impl/pnr/fm_138k_rgb_hdmi.fs`，2026-10-24 **21:28:02**（北京时间），42,234,791 B。
  SHA256 `4E27772A325A0BF21FDB22A46FF05045F16D00A438F005FF7AF87BF3930BAD47`。
  最终构建 `tmp/build_repeat50_rename.log`，四域setup/hold TNS=0；Fmax主域50.139、RGB37.323、
  HDMI pixel33.800、serial331.798MHz。资源与20:15版相同：Logic53648、FF27898、BSRAM316/340、DSP65.5/298。
  未自动烧录、未实机验证，本轮只重建双屏位流。
  期间仅提速的首次构建已在收到重命名补充后中止；最终构建包括两项修改。
  20:15版备份 `impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-24_pre_repeat50.fs`。
- 测试日志 `tmp/check_repeat50_final.log`、`tmp/check_rename50.log`、`tmp/check_probe64.log`。

## 2026-10-24 ARP/SEQ 交互、HOLD 即兴与 SD 用户音色（20:15历史发布）

- ARP/SEQ 参数加减：点按一步，450 ms 后每100 ms连续一步；其他编辑页仍1.5 s/150 ms。
  修复该页新按键未初始化 held_x、被错误当成坐标跳变反复点按的问题；ARP八度加减也接入统一重复逻辑。
- ARP config bit16表示离开编辑页，touch_ui_controller 的 UI[36] 写掩码同步扩到17位。
  HOLD且离开ARP页时锁住和弦，新音符直通即兴；返回编辑页后仍能正确松开即兴音符。
  midi_note_owners 将bit30 ARP与bit31自动演奏一并纳入人手/自动所有权保护。
  同音仍共享一个音源声部；当前踏板全局共享，HOLD即兴时不将踏板按下传给音源，避免破坏ARP门限。
- **伴奏独立音色本轮未实现**：用户允许复杂时先给方案。当前换音色仍会改变伴奏。
  双part参数、LFO、Pitch EG、分配器及Pattern快照方案见 `ACCOMPANIMENT_PATCH_PLAN.md`。
- 板载SD卡槽：SPI CS# K6、CLK N3、MOSI N4、MISO R1，LVCMOS33。新增sd_spi_byte（200kHz/5MHz）和0x26000000 MMIO。
  PATCH新增READ SD（确认后整体恢复八个RAM槽，再LOAD RAM应用）和STORE SD（确认后保存当前音色至选中槽）。
  FAT32 SDHC/SDXC，根目录预置FMUSER.BIN，支持碎片簇链；不写FAT或目录、不分配簇。
  每槽两个CRC32/generation记录，写另一副本并读回验证，CRC16检查SD数据。
  空白库 `assets/sd/FMUSER.BIN`，生成器 `tools/prepare_sd_user_bank.py`，操作/格式/限制见 `SD_USER_PATCHES.md`。
- UI固件 **67,988/81,920 B**，改-Oz，指令ROM64+16KiB，数据RAM仍128KiB。
  .text67940、.data48、.bss39600，静态结束0x1001a444，剩余23484B供栈使用。
  firmware.hex和firmware_high.hex必须同次生成；共享CPU默认仍64KiB，仅UI启用高段。
- 已过针对性验证：ARP单元、原自动所有权/队列及ARP同音、SEQ单元；真实固件/I2C的
  ARP/SEQ点按与450ms/100ms长按、HOLD离页同音即兴、SEQ录制/切页/参数/清除、SD确认/无卡返回、
  普通菜单EG/LFO/Pitch/命名/用户槽/FX回归。未重跑全量回归矩阵。
  SD生产C协议/文件系统模型及RTL移位器通过；覆盖两种簇大小、活动FAT、碎片/无分区卷、
  八槽、CRC标准向量、坏链、坏头、无卡、数据CRC和写入中断恢复。实卡兼容性和掉电行为待实机。
- IDE启用59个RTL文件均存在，两份CLI和两套CST同步，无重复引脚。800×480 PATCH字符层预览已检查。
- 最终双屏位流 `impl/pnr/fm_138k_rgb_hdmi.fs`，2026-10-24 **20:15:04**（北京时间），42,234,791 B。
  SHA256 `630246611F79A2E723B81FB89A2172644FA63ABC5DBCD8D3013C9E21764C8764`。
  Logic **53,648/138,240（39%）**、FF **27,898/139,095（21%）**、BSRAM **316/340（93%）**、DSP **65.5/298（22%）**。
  Fmax：主域 **50.139**、RGB **37.323**、HDMI pixel **33.800**、serial **331.798 MHz**；四域setup/hold TNS=0。
  主域余量仍小，不能据此直接提升主时钟；新增UI指令区实际仅增加两块物理BSRAM。
  构建日志 `tmp/build_sd_arp_release.log`；未自动烧录、未实机验收，只重建双屏位流。
  首次构建在发现UI[36]掩码漏位后中止，最终构建已包含修正；旧位流备份
  `impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-24_pre_sd_arp.fs`。
- 验证日志：`tmp/check_sd_store.log`、`tmp/check_ui_repeat_sd.log`、`tmp/check_ui_hold_sd.log`、
  `tmp/check_ui_seq_sd.log`、`tmp/check_ui_sd_entry.log`、`tmp/check_ui_base_sd.log`。
  `tmp/sd_patch_menu_preview.png`为真实固件字符/调色板写入日志渲染，数据来自仿真模型，不是实机照片。

## 2026-10-24 CH376S USB MIDI 移植（历史发布）

- 移植队友 `tlemon229/Gowin-Instrument-138K` 提交 `7bc0f80a8fd6eb9835cd11b5081097794c8b2048`
  的六个 CH376/SPI/USB MIDI 模块，未导入其蓝牙、手机、曲谱或 UI/音源实现。
- 键盘插外接 **CH376S 模块 USB-A**，SPI 连 138K；不是把 ACG720 USB 设备口改作 Host。
  25K 桥接默认禁用（wrapper 的 LEGACY_BRIDGE_ENABLED=0），无需中转；可显式启用历史对照。
  接线、模块模式、D5..D7 状态说明见 `CH376_USB_MIDI.md`。
- 力度继续通道 1 的 0..80 → 0..127，一次校准；其余通道及触屏不缩放。
  USB cable/CIN 字节进入主事件流时清零，避免 cable 高位冒充 demo/ARP 标记。
- 新增两项寄存器 MIDI FIFO，隔离上游 ready 与下游组合控制；没有增加 USB 软核或启用原 USB PLL。
  32×6 FM、FX、ES8388、双屏、练习、ARP/SEQ 均沿用本地分支。
- 三项新增仿真通过：CH376 描述符/128 档力度/仲裁；SPI 模型枚举/64-byte/NAK/STALL/拔插/超时；
  事件入口 FIFO/标记隔离/来源公平性/暂停稳定性。均加入 sim/run_checks.ps1。
  相关模型仅为 Icarus 做等价语法调整，不能作为真实键盘/CH376 已验收的证据。
- 双屏位流：`impl/pnr/fm_138k_rgb_hdmi.fs`，2026-10-24 **18:16:29**，42,213,383 B。
  SHA256 `3D56DE737F0CC73C8B0C2AE8DA64E72A6A0A06DDF9FAF500C047D7F8C68DAD2E`。
  上版 32 复音位流备份：`impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-24_pre_ch376.fs`。
- PnR：Logic **52,763/138,240（39%）**、FF **27,727/139,095（20%）**、
  BSRAM **314/340（93%）**、DSP **65.5/298（22%）**。
  Fmax：主域 **50.162**、RGB **36.544**、HDMI pixel **30.148**、serial **242.673MHz**；四域 setup/hold TNS=0。
  主域最紧 slack约0.065ns，现路径在FFT real_mem输出→band_max。余量仍较小，不能直接升主时钟。
- `RESOURCE_AND_PIPELINE.md` 和 `tools/report_bram_usage.py` 记录主要内存去向与候选优化；
  UI 软核96、delay66、reverb25、FM22、算法图16为**综合原语**数，不能冒充逐模块PnR物理计数。
- 新增文件已登记两份 CLI 与 IDE；两个 wrapper/CST 同步。仅构建双屏位流，未自动烧录，未实板验收。
  本轮未改 UI firmware.hex、音源或音频串行格式；未重跑全部既有回归矩阵。
- 日志：`tmp/build_ch376.log`、`tmp/check_ch376_units.log`、`tmp/check_ch376_host.log`。
  用户另反馈8Ω/15W喇叭经MAX98357低音量仍杂、耳机正常；供电不是已证实根因，优先独立稳压5V对照、
  核对GAIN/型号/I2S短线与地线/OUT±接法。不因这条反馈擅自修改音频算法。

## 2026-10-24 32 复音扩容

- 当前生产顶层为 32×6 FM、Fs=48.828125 kHz；配置位于两个 wrapper 的 AUDIO_VOICES。
  独立 `fm_poly_synth` 默认参数仍为 16，顶层显式传入 32。详见 `POLYPHONY_32.md`。
- 槽位地址按 192 项加宽为 8 位，修正原 128 项地址截断；声部计数通路为 8 位平衡计数树。
- 待处理采样在 IDLE 中优先于新 MIDI；已开始事件仍完整完成，解决持续事件流饿死采样的风险。
- UI[4] 声部低 5 位保留，高 3 位放在 [26:24]；音色高位 [23:22] 不变。
  UI[59] 返回容量，标题与性能页同步显示 32。
- 已通过核心/密集输入/踏板/高槽位/32 算法 PCM 等价/32 配置滑音/真实 UI 针对性测试。
  满载 FM render=394 clocks，连续 256 起音场景 max response=457 clocks，deadline/lost=0；非所有场景最大值。
- 固件 60,604/65,536 B。双屏位流：`impl/pnr/fm_138k_rgb_hdmi.fs`，2026-10-24 15:34:07，42,234,791 B。
  SHA256 `EECA47984401519C28F34A819E53A918F1D69909F5C6F4A1E1A40788E69FB12F`。
  前版性能监测位流已备份为 `impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-24_pre_poly32.fs`。
- 最终资源：Logic **48,036/138,240（35%）**，FF **25,517/139,095（19%）**；
  BSRAM **314/340（93%，未增加）**，DSP **65/298（22%，未增加）**。
  增加声部状态使用了既有 RAM 块的可用深度，没有直接复制完整合成引擎。
- Fmax：主域 **50.005**、RGB **35.612**、HDMI pixel **33.452**、serial **169.509 MHz**；
  四域 setup/hold TNS=0。最紧路径仍是 ARP/事件路由到 SEQ 写控制，主域余量很小。
- 构建日志 `tmp/build_poly32.log`；仿真日志 `tmp/check_poly32_equivalence.log`、
  `tmp/check_poly32_legato.log`、`tmp/check_poly32_ui.log`；测试已加入全量回归入口。
  生产源文件集合未改变，IDE hierarchy 保持正确。仅针对相关风险回归，未重跑完整矩阵。
- **未实机烧录**；25K 桥接无需更新。本次只交付双屏位流；单 RGB 脚本/顶层已同步但未重建。

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
