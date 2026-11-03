# 25K / 138K 下载、固化与首次看到现象

## 当前下载文件核对 2026年11月3日

40Pin测量候选已经完成，不再处于构建中：`impl/pnr/fm_138k_gesture_probe.fs`，完成时间2026-11-02 20:59，SHA256 `97A853217B176CC843B84EB1C58901323496DCD4F7C3BDD1066EDB67D99F6773`。全时钟约束Setup/Hold TNS为0、回归通过，工具未自动烧录。P7-15输出延迟标记，LED0为心跳；键盘默认CH376直接接138K，无需25K。

`fm_138k_gesture_performance.fs`为19:47的LED0标记版本；标准`fm_138k_rgb_hdmi.fs`仍是11月1日文件；根目录`fm_138k_rgb.fs`为历史文件。请按SHA256和发布收据区分，不按相近文件名选择。当前资源及完整版本边界见[技术状态](CURRENT_TECHNICAL_STATUS_2026_11_03.md)，测量接线见[40Pin说明](LATENCY_PROBE_40PIN.md)。

以下按日期保留开发记录，出现“构建中”“当前下载版”“尚未完成”仅表示当时状态；当前状态以上述完成收据为准。生成位流不代表实机全功能验收。

## 2026-11-02 已完成手势演奏位流；新40Pin延迟脉冲版构建中

- fm_138k_gesture_performance.fs已于19:47生成并通过全部时序/回归，SHA256 688E582974430D80DB64262CD2CB4E84E068F188DB3A17C38E6832B80B4AC488；快照tmp/gesture_performance_timing_build_v2。主50MHz Fmax51.786、RGB33.333MHz Fmax36.782、摄像头112.201、HDMI25 75.695/串行249.582，全时钟Setup/Hold TNS0。标准FS未覆盖，未烧录。该可用版本仍为LED0/M22延迟标记。
- 用户新要求把延迟测量输出从LED移到40Pin。已新增HDMI正式顶层latency_probe，CST定位D14 = GPIO0_12 = P7-15；LED0恢复heartbeat。P7-12为GND。GPIO0 VCCIO保持3.3V；不与模块输出短接。依据板厂引脚表及原理图第11页核实。内部起止计时逻辑没有更改，仍为板内可见输入到I2S起音的数字延迟，不等同完整模拟端到端延迟。
- 已冻结并启动tmp/gesture_performance_probe_build，gw_sh PID38012，后台5376；helper工具finish_gesture_timing_build.ps1新增可配置SnapshotDirectory/ArtifactName/ReleaseName参数。合格后生成独立fm_138k_gesture_probe.fs，不覆盖当前可用fm_138k_gesture_performance.fs或标准FS。结果见该目录background_result.json，发布记录2026-11-02_latency_probe.json。本次仍需布局布线/时序，不能提前告诉用户P7-15在旧位流有效。
- 32声部测试：预选持续正弦、关闭ARP/SEQ/AI/练习/曲谱/手势CONTROL及FX，首页VOICES按S0启动32个MIDI96..127音，32格及计数到32；点FFT两次进入LIN FFT看32谱峰；S0或S1停止释放到0。手势：SETUP/GESTURES先识别后控制；按住CEG，PALM原声/FIST切音/V跨两八度琶音，固定120BPM，当前LIVE音色；控制关闭恢复原声。无需25K，CH376直接接键盘。尚未实机验证新手势演奏版。

## 2026-11-02 手势版时序优化（最新构建）

- 原tmp/gesture_performance_build在18:37已生成候选FS，但主50MHz域Fmax48.443/TNS-48.168ns/160端点，RGB33.333MHz域Fmax33.115/TNS-0.197ns/1端点，不能烧录。不是卡住；正式FS仍旧版610db0d65cc770fa3c3c94056380fb60239623ddc621f73990c49adbff01f170。
- 已优化：切音增益两级系统时钟寄存；MIDI入口仅空槽ready断开分类→ACK长路径；音频已接受事件观察寄存；板级原始按键观察器寄存再送tutorial；FFT幅度管线并增加对齐等待；键盘除法改精确平衡比较树；灯带填充计数器32位缩为按灯数寻址宽度。没有改时钟约束、32音测试模块或删除功能。固件不变81720字节，工程106RTL。
- 已过FFT/32频点、生产32声PCM32峰、手势FM32+FX、MIDI17次数字延迟脉冲计数、三个RGB视图/800像素键盘边界、输入观察器、160及1灯边界、曲谱练习联合32项。包含手势的32声部额外回归tmp/opt_poly_gesture.log待最终确认。原菜单代码未变，保留前轮真实UI通过证据。
- 当前不可变构建tmp/gesture_performance_timing_build_v2，gw_sh PID47848，后台收尾4668，工具tools/finish_gesture_timing_build.ps1。548文件清单source_manifest.json；全部测试和所有约束时钟TNS=0、当前/冻结源码哈希均通过后才复制独立impl/pnr/fm_138k_gesture_performance.fs，标准FS不覆盖、不烧录。结果background_result.json/test_result.json、docs/releases/2026-11-02_gesture_performance_timing.json。
- tmp/gesture_performance_timing_build(PID1716)是在布局布线前主动取消的中间快照，以便批量加入另两条已知路径修复。不要误报其结束为最终完成。下次先检查最新v2测试、PNR和时序结果，如失败继续针对报告优化。用户允许等待PNR时结束当前轮；尚未有合格的新位流。
- 详情GESTURE_TIMING_OPTIMIZATION.md。没有自动提交推送。

## 2026-11-02 CH376直连与独立手势演奏（当前任务）

- 用户新指示：不用25K中转，恢复CH376；原32复音演示代码不改；实现张手原声/拳头切音/V手势琶音；暂时移除手势对AI旋律控制；本轮生成位流。此前“终止”只覆盖旧MIDI问题排查，未继续追查双发或做去重。
- top_138k_hdmi和top_138k默认LEGACY_BRIDGE_ENABLED=0、CH376_ENABLED=1。新增gesture_performer与gesture_chopper，复用原ARP并锁定LIVE来源使用当前音色；普通ARP仍BACKING。原声与琶音切换清理/重建按键和踏板；短暂UNKNOWN保持；控制关闭恢复原声；自动模式优先。32音测试透明旁路，polyphony_test32.v与上一轮完成快照对比相同。
- SETUP顶部三按钮ARP/SEQ/GESTURES，独立PAGE15，保留琴键。识别和控制默认OFF，显示实际NORMAL/CHOP/ARPEGGIO；固定120BPM、切音1/16、琶音1/8跨两八度75%门长。AI composer生产实例GESTURE_ENABLED=0且输入固定0，菜单保留AI手动操作，删除旧gesture BASIC/PERFORM界面。主固件81720字节，BSS10828，栈16584，工程105RTL文件。
- 专项逻辑/音量平滑/正负满幅/按键恢复/踏板/背压/普通ARP接管通过；RGB PAGE15键盘实像素通过。真实菜单tmp/gesture_ui.log、生产FM32+FX tmp/gesture_production.log、原32演示带手势旁路tmp/gesture_polyphony.log现已全部PASS；原ARP/AI旋律回归也PASS。证据assets/gesture_performance。初次音频回归超时来自Icarus忽略嵌套节拍参数覆盖，改测试台驱动分频器终值后PASS，未改综合RTL；清单记录该测试文件修订。
- 冻结构建tmp/gesture_performance_build，gw_sh进程44076，后台收尾48092，入口tmp/finish_gesture_wait.ps1转调tools/finish_gesture_performance_build.ps1。全部回归+全时钟时序TNS=0+冻结/当前源哈希通过后才复制独立impl/pnr/fm_138k_gesture_performance.fs；结果background_result.json/test_result.json和docs/releases/2026-11-02_gesture_performance.json。标准FS不覆盖、不烧录，旧25K位流不发布。当前尚未生成新文件，需先检查构建和回归结果。用户允许布局布线等待时结束当前轮。
- 详情GESTURE_PERFORMANCE.md。源码未提交/推送。下一轮优先检查测试、构建是否失败，需要则继续优化，不得把启动构建当完成。

## 2026-11-02 恢复 25K 中转（当前构建）

- 用户要求恢复原25K USB MIDI中转。RGB+HDMI和单RGB顶层默认LEGACY_BRIDGE_ENABLED=1、CH376_ENABLED=0；CH376输出保持CS高/SCK低/MOSI低，数据/状态归零，不参与键盘输入。保留可编译CH376分支作为历史排查，但未确认双发根因。
- 正式普通固件81776字节，MIDI_TRACE_ENABLED=0，未用probe菜单。保留当前32格真实声部、32音测试、线性FFT和GOWIN Logo等改动。
- 真实1Mbaud TX/RX串口贯通到生产FM32+FX2回归通过：单NoteOn一声部、触屏一声部、两通道两声部；弯音/CC/背压/半帧恢复也通过。证据tmp/bridge_restore_checks.log，脚本sim/run_midi_ingress_checks.ps1。
- 冻结构建tmp/bridge25k_restore_build，gw_sh进程30628；后台收尾进程43900，脚本tmp/finish_bridge25k_build.ps1。完成后检查所有约束时钟TNS=0、冻结和当前输入哈希一致才自动备份并发布impl/pnr/fm_138k_25k_bridge.fs和标准fm_138k_rgb_hdmi.fs；结果background_result.json和docs/releases/2026-11-02_25k_bridge.json。若失败或输入变化则保留旧版。没有自动烧录或Git提交。
- 先前tmp/midi_double_probe_build已按用户新要求停止，不再等待该诊断版。标准FS在本次后台发布之前仍为11月1日CNN正式版，不能误报新位流已完成。
- 接线：25K USB-A接键盘；Dock J3-15/F1 TX → 138K P7-4/A16 RX；25K GND → 138K P7-12 GND；3.3V信号，两板各自供电不互接5V。25K使用现有2026-10-23 21:51 midi_bridge_25k.fs，SHA256 1F9E610D25C44E7509FB1B18A60217B0FA0B741D80AA68A1563EB3B6C1689A6F，已含0–80力度映射，不需重建。详情25K_BRIDGE_RESTORE.md。

## 2026-11-02 复音显示、32音测试和Logo（构建中）

- 新增首页VOICES 4×8真实声部槽显示，来源fm_poly_synth.voice_active；保留原波形/XY/对数FFT。FFT按钮重复点按切换线性512频点，真实FFT结果，无预画谱峰。
- 首页VOICES按S0(F15)启动，测试中任意页面按S0或S1(A20)停止。开始要求32槽空闲且ARP/SEQ/AI/练习/曲谱关闭。发MIDI96..127力度32，用户预先选正弦音色；同一生产引擎和音频输出。停止NoteOff后LIVE限定CC123清理，恢复滑音配置。其它页面S0保留曲谱功能。
- GOWIN官方Logo首页(688,80)，64×24，两色加白底，静态RTL行常量，不增加BSRAM。全部新增功能综合较前版+482 LUT/+196 FF/+1 BSRAM（线性快照）；最终资源和时序待PNR。
- 固件81776/81920字节；专项回归32声部、零抢占/丢采样/超时、生产FM32+效果器实际PCM32峰和停止到0、512频点快照、RGB格子/Logo/线性/对数显示均通过。真实UI五视图回归后台运行；修复的是测试脚本动作编号重号，生产代码未因此更改。
- 当前构建tmp/polyphony_logo_final_build，进程14608，布线中；后台收尾脚本tmp/polyphony_background_finish.ps1，结果ui_result.json和background_result.json。源码哈希source_manifest.json，构建输入不可再修改。用户允许在布局布线时结束当前轮，后台继续；下次先检查结果、源指纹、时序和资源，再备份/发布标准FS。标准FS当前仍为2026-11-01 CNN正式版610db0d65cc770fa3c3c94056380fb60239623ddc621f73990c49adbff01f170，尚未替换。
- 说明docs/POLYPHONY_TEST_AND_LOGO.md；频率表docs/POLYPHONY_TEST_FREQUENCIES.csv，证据assets/polyphony_logo，品牌来源assets/branding/SOURCE.txt。代码未提交/推送，本轮无自动烧录。


## 2026-11-01 CNN乘加修复正式版（当前下载版）

标准位流impl/pnr/fm_138k_rgb_hdmi.fs，SHA256 610db0d65cc770fa3c3c94056380fb60239623ddc621f73990c49adbff01f170。构建完成2026-11-01 20:17，快照tmp/gray_macfix_production_build。SELF_TEST=0，恢复正常判定、投票与动作。全部约束时钟setup/hold TNS=0；主域50.024MHz、RGB33.521MHz，裕量较小。回退impl/pnr/backup/fm_138k_rgb_hdmi_pre_macfix_20261101.fs。用户已验证修复诊断版，正式版待实机验证。未自动烧录。此前构建中记录为历史。


## 2026-11-01 灰度 CNN 乘加修复（正式构建中）

- 用户确认修复诊断版实机已能正确识别手势。旧 CNN RTL 与 Gowin 综合后网表结果不一致：样本0网表输出663/117/-1755/429，FIST领先234=00EA，复现实机现象；具体工具内部映射缺陷未细分。
- 改为显式补码移位加法乘法，乘积寄存后再累加，避开旧融合DSP MAC结构。552图/2208分数RTL正确，完整灰度回归通过；新版单模块综合网表4图/16分数正确，旧版同样测试失败。新推理27409周期=548.18us。
- 正式工程顶层GESTURE_SELF_TEST=0，恢复接受门限、多帧投票和手势动作。HDMI小图改为归一化后CNN输入的16×16抽样，位置掩码仍使用原始灰度。保留可编译自检参数，默认关闭。
- 修复诊断版impl/pnr/fm_138k_gray_macfix_selftest.fs，SHA256 00A9A9AA349E0EB51250610C8A6E057EA6EC68E92196E646EC43F084AB48F021，已通过全部时序；该诊断版强制禁用接受与动作，因此NN保持UNKNOWN不代表故障。
- 正式构建tmp/gray_macfix_production_build，等待完成并检查全部时序后再发布标准FS。当前标准FS尚未替换。详情GESTURE_CNN_MAC_FIX_2026_11_01.md和GESTURE_CNN_SELFTEST.md。


## 2026-10-31 灰度自适应与USB MIDI延迟版（当前下载版）

- 构建源码 `10261d8`；标准位流 `impl/pnr/fm_138k_rgb_hdmi.fs`，时间 `2026-10-31T19:41:30.115293+08:00`，SHA256 `F81BA6D996B481463EC20F8F504A9009EB65E7F1B270402115576059CE2421EB`。未自动烧录、未推送。
- 新增32×32灰度背景平面补偿/黑端估计/跨度下限32的有限增益归一化，保留灰度。Python训练与RTL整数处理一致，重新训练160轮，验证选择第114轮。训练及局限见GRAY_ADAPT_AND_MIDI_LATENCY.md；公开手势原始分类312/372，正确且过门限304/372，不能据此宣称实机准确率。HDMI小窗仍为传感器原始灰度，新增R:F/P/V/O显示网络赢家，UNKNOWN原因仍可见。
- 延迟起点前移至板级USB/触屏/桥接仲裁接受NoteOn、输入FIFO之前；USB cable/CIN已剥离，16通道/cable及触屏17次生产FM32/I2S回归通过。LED0/M22同一标记引脚高电平宽度逐时钟等于统计计数。测试音色数字延迟136469时钟=2729.38us，不是实测模拟端到端延迟，不含键盘扫描或USB/CH376前段。
- METERS显示MODE BLOCKED、WAIT VOICES=0、WAIT QUIET、READY: ONE NOTE、MEASURING。统计23保留低4位并新增bit4声部为0、bit5当前幅度低于门限。原USB实机不触发的唯一根因未复现；新路径已做全通道回归，仍需实机验收。脉冲不用于手势延迟。
- 固件81304/81920字节，BSS10832，栈余量17000；真实菜单统计页/清零/键盘/输出选择/AI旋律预览回归通过。保留32复音、8192事件蓝牙曲谱、原效果/AI/摄像头功能，未降低约束。
- 最终资源：逻辑81318/138240，寄存器46065/139095，BSRAM335/340，DSP90/298；所有约束时钟setup/hold TNS=0。主域Fmax50.097MHz；余量与风险以实现报告为准。记录releases/2026-10-31_gray_adapt_latency.json，证据assets/gray_adapt_latency。
- 回退 `impl\pnr\backup\fm_138k_rgb_hdmi_2026-10-31_pre_gray_adapt_latency.fs`。此前待联合构建的诊断与GESTURE_GRAY黑白回退参数已纳入本版；默认仍灰度，参数设0需重新构建。手势改善及USB实机测量尚未验收，不得宣称已解决所有UNKNOWN或已满足完整模拟端到端5ms。以下旧版记录保留历史含义。

## 2026-10-31 蓝牙曲谱与灯带集成版（历史下载版）

- 来源提交 `7bc0f80a8fd6eb9835cd11b5081097794c8b2048`；本工程构建源码 `1a5ab49`。标准位流 `impl/pnr/fm_138k_rgb_hdmi.fs`，时间 `2026-10-31T17:08:43.639953+08:00`，SHA256 `6AD99FFAD53FBA789D8ADF28C5E3B60940AC473755C194197BC427C2EA4FC02C`。未自动烧录、未推送。
- 独立 JDY UART115200：P7-9/E13 接模块 TX，P7-10/E14 接模块 RX；原 PC CH340 控制口保留。灯带数据 P7-6/A19，160 灯，可用手机配置25键灯位；个人灯位未写入ROM。S0开始内置练习，S1停止。
- 保留8192×48bit曲谱缓存、32复音能力协商，兼容8事件窗口和最终CRC封存；上传后断开蓝牙可继续回放，断电不保存。内置《晴天》支持跟拍和弹对再走。Android/PC配套源码在仓库根目录，未构建/签名新APK。
- UI DATA RAM 从物理96KiB缩至48KiB，地址窗口不变：低16KiB BSS＋高32KiB常量/栈。综合网表低DATA由32块变8块，省24块，恰好用于24块的8192事件缓存；指令ROM保持80KiB。固件镜像重新编译与原版一致，81092字节、BSS10832、栈余量17212。布局校验和完整镜像/真实UI回归通过。
- 自动曲谱标签0x88，停止清理限LIVE Part；播放/收尾暂时屏蔽单音滑音，结束恢复用户值；手动panic仍全局。与ARP/SEQ/AI/原屏幕练习互斥，其他模式启用时取消曲谱，不删除这些功能。回放中暂停手弹延迟测量，避免污染统计。声部和音色使用当前LIVE，未新增第三Part/多轨独立音色。
- 最终资源：逻辑81094/138240，寄存器45964/139095，BSRAM333/340，DSP86/298；所有约束时钟setup/hold TNS=0，未降低约束，未删功能。主50MHz域Fmax为50.074MHz，余量较小；BSRAM仅余7块，后续新增缓存须先重新核算。完整结果见 `releases/2026-10-31_bluetooth_score.json`，证据在 `assets/bluetooth_score`。
- 回退位流 `impl\pnr\backup\fm_138k_rgb_hdmi_2026-10-31_pre_bluetooth_score.fs`。手机蓝牙吞吐、灯位/声音及本次集成实机兼容性仍待验收。操作、限制、测试命令与实机检查清单见 `BLUETOOTH_SCORE_PORT.md`。以下旧版条目保留历史含义，不覆盖本节。

## 2026-10-31 数字起音延迟测量版（历史下载版）

- 源码`f9d3b20`；标准位流`impl/pnr/fm_138k_rgb_hdmi.fs`已更新，时间`2026-10-31T13:32:56.634831+08:00`，SHA256 `A27AC2CEC52F2B9B7DE1FC2B1A224A0E970F632A6B3E6F38DFA16EA25D74B6ED`；未自动烧录。
- 新增被动LIVE NoteOn可见入口→最终起音I2S左声道最后一位计时，METERS显示最近/最大整数微秒、成功/超时及跳过数。6个新快照字为索引18..23，0..17兼容原布局。安静32帧、声部数0、幅度门限32LSB、250ms超时；禁止AI/ARP/SEQ/练习模式干扰，多NoteOn重叠取消。不是并发音符因果追踪。
- 原status_led[0]心跳改为测量标记（FPGA M22），用于示波器CH1；模拟端建议测ES8388耳机口。普通地夹不可接MAX98357 SPK-。标记只覆盖FPGA可见事件之后，不含键盘/触屏扫描或上游USB/FIFO；板内数值不含DAC。完整模拟延迟须实测，不得据仿真或UI注入数字声明≤5/10ms。
- 专项精确I2S终点/背压/重叠/超时/清理测试、I2S输出选择、生产AI/FM32/I2S与真实RV32I统计页测试通过。新固件81092/81920字节，BSS10832字节。没有新增BSRAM缓冲。
- 全部约束时钟setup/hold TNS为0；逻辑70122/138240，寄存器39430/139095，BSRAM329/340，DSP83/298。模型、摄像头配置及引脚约束不变。
- 测量流程及多频现场验证见NOTE_LATENCY.md。tools/multitone_probe.py提供4/8/16/32音的PC串口测试序列，需要先准备单载波正弦音色；不是预录音频，也不是已完成板载一键测试模式。
- 记录releases/2026-10-31_note_latency.json，回退`impl\pnr\backup\fm_138k_rgb_hdmi_2026-10-31_pre_note_latency.fs`。本轮无真实延迟测量数据。

## 2026-10-31 AI菜单入口优化（历史下载版）

- 编译源码`36f63ca`；位流北京时间`2026-10-31T00:36:02.305729+08:00`，SHA256 `4F369D5142FAD66536DC8BAAE0B36713AF82540DC23844F73B04174FF183A688`。标准`impl/pnr/fm_138k_rgb_hdmi.fs`已更新，未自动烧录。
- SETUP并列AI BACKING（AI伴奏）与AI MELODY（AI旋律），不必先进入伴奏才能到旋律。旋律操作面直接进入GESTURES，手势页SURFACE直接返回操作面，EXIT MODE回SETUP。入口176×48，实固件800×480预览见assets/ai_menu_navigation/setup_800x480.png。
- 修复按住导航按钮后，新页面钢琴区域误发音：切页触点抬起前不参与琴键映射。外部MIDI不受此触屏状态影响。
- 五项真实RV32I/I2C回归通过：直接旋律/手势导航且零意外琴键音符、AI伴奏、旋律主题/节奏录制、滑音时间、全宽琴键/力度/输出选择。固件81052/81920字节，BSS10808字节。
- RTL、模型、摄像头配置和时序约束与上一灰度版逐文件核对相同；本轮继承灰度CNN回归及局限，不重复声称新的模型准确率或实机验收。RECOGNITION和CONTROL仍默认关闭。
- 完整布局布线通过，全部约束时钟setup/hold TNS为0；逻辑69601/138240、寄存器39089/139095、BSRAM329/340、DSP83/298。
- 说明AI_MENU_NAVIGATION.md；发布记录releases/2026-10-31_ai_navigation.json；回退`impl\pnr\backup\fm_138k_rgb_hdmi_2026-10-31_pre_ai_navigation.fs`。

## 2026-10-30 灰度CNN手势版（历史下载版）

- 编译源码`18b9fb2`；位流北京时间`2026-10-30T23:43:08.392638+08:00`，SHA256 `43ADDC2B29B28A0FF1F2A8F7B2090FD83611FD75CAE95311B753C52F15BA3562`。标准`impl/pnr/fm_138k_rgb_hdmi.fs`已更新，未自动烧录。
- 生产摄像头RGB565抽头→32x32连续灰度→跨时钟邮箱→纯RTL量化CNN（436权重/8偏置）→四类分差判定→原投票/音乐控制。FIST/PALM/V/OTHER中OTHER禁止发命令；分类不再依赖二值轮廓。BASIC/PERFORM及默认OFF保留。
- HDMI左侧为真实32x32输入的16x16灰度降采样预览；E改为平均灰度0..255，M仍为分差。灰度双缓冲块RAM及独立324位结果包均只在消隐切换；二者不保证同一次推理。RGB菜单RAW可显示OTHER。辅助二值轮廓只供位置重心，不进入分类器。
- 552输入/2208分数全部与软件逐位一致，推理18909周期（50MHz下378.18us，不含采集/投票）。原17项回归、新灰度链路/四类门槛/预览、6项摄像头与真实RV32I菜单回归通过。
- 公开三手势测试330/372正确，合成OTHER171/180正确；均不是实机准确率。固定中央ROI仍限制位置变化，合成压力测试失败案例保留，不能宣称任意背景可靠。
- 逻辑69601/138240、寄存器39089/139095、BSRAM329/340、DSP83/298。所有约束时钟setup/hold TNS为0，无降频/放宽约束/删模块。摄像头初始化不变。
- 说明GESTURE_GRAY_CNN.md；记录releases/2026-10-30_gray_cnn.json；回退`impl\pnr\backup\fm_138k_rgb_hdmi_2026-10-30_pre_gray_cnn.fs`。先只开识别，关闭控制验收新版实机效果。

## 2026-10-29 手势旋律演奏版（历史下载版）

- 源码`4a86829`；位流北京时间`2026-10-29T22:53:25.611115+08:00`，SHA256 `569F13D4F466B02229F8FD4E59283CDC18AB32B290C67A79125A6346FE21579C`。标准`impl/pnr/fm_138k_rgb_hdmi.fs`已更新，未自动烧录。
- 手势页新增MODE BASIC/PERFORM，默认BASIC。切换关闭CONTROL，需重新开启。PERFORM张掌开始/下一小节恢复生成，握拳循环最近完整16步小节，V在下一小节退出循环并变奏；无完整小节时等待第一个小节。原四小节触屏LOCK保留。
- 稳定且当前通过的张掌位置按三档迟滞控制密度及旋律上行/下行倾向，在下一拍生效。录入节奏仍优先于密度。模型和摄像头配置不变。
- 17项手势、6项摄像头回归，真实RV32I/I2C模式切换、原COMPOSER完整回归及额外BASIC/PERFORM停止清理测试通过。固件80752/81920字节。所有约束时钟setup/hold TNS为0，未降频或放宽约束。
- 逻辑72624/138240、寄存器43094/139095、BSRAM331/340、DSP85/298。新版手势演奏实机待验收。
- 使用说明`GESTURE_PERFORM.md`，发布记录`releases/2026-10-29_gesture_perform.json`。回退`impl\pnr\backup\fm_138k_rgb_hdmi_2026-10-29_pre_gesture_perform.fs`。

## 2026-10-29 手势稳定与输入预览版（历史下载版）

- 编译源码`5880388`，位流北京时间`2026-10-29T18:43:21.269255+08:00`，SHA256 `87253458FEF7D2EB0FCAA32EABD8F4F4AFAC567E9C7351C680F91C4E924E6844`；标准`impl/pnr/fm_138k_rgb_hdmi.fs`已更新，未自动烧录。完整记录`releases/2026-10-29_gesture_vote.json`，使用说明`GESTURE_VOTE_DEBUG.md`。
- 用户实测上一版已偶尔识别PALM/V，FIST较稳定，但类别跳变且复杂背景仍困难。本轮优先改时间滤波及诊断，不更换模型、摄像头配置或音频固件；持续认错仍需训练数据/模型改善。
- 最近5个结果中3票首次确认、4票切换；短暂不同/拒识保持稳定标签，连续3次拒识或5次不匹配退出跟踪，1秒断流清理状态。手动操作优先，保持手势不重复触发，音乐控制仍默认OFF。
- 开RECOGNITION后HDMI左侧显示16x16真实MLP输入的8倍图（白=前景、黑=背景），标注NN INPUT；底部右侧新增EMPTY/FILL/BORDER/NOISE/LOW GAP/VOTING/HOLD/STABLE等状态。324位轮廓/状态包仅在消隐更新，显示等待不增加音乐控制路径延迟。
- 14项手势及6项摄像头回归通过，384000特征及原因逐项一致、13个完整推理结果的真实输入掩码和分数一致；约209万摄像头画面像素及预览不对称图案坐标/整帧一致性检查通过，延迟应答、停钟、复位和手动优先均通过。
- 所有约束时钟setup/hold TNS为0；逻辑71491/138240、寄存器42217/139095、BSRAM331/340、DSP85/298。未降频、未放宽约束、未删模块。新版稳定效果仍待实机验证。
- 先只开RECOGNITION、关闭CONTROL对比RAW与STABLE，并看黑白轮廓是否确实保留指间空隙；原因说明见使用文档。回退文件`impl\pnr\backup\fm_138k_rgb_hdmi_2026-10-29_pre_gesture_vote.fs`。

## 2026-10-29 背景补偿手势版（历史下载版）

- 编译源码`65e32dd`，位流北京时间`2026-10-29T12:36:27.170736+08:00`，SHA256 `AC246BFF0E7295DE35A9A49DDE4E392C4573A05892F9E926F66D82AAD6A09855`；标准`impl/pnr/fm_138k_rgb_hdmi.fs`已更新，未自动烧录。完整记录`releases/2026-10-29_gesture_plane.json`，实现与使用说明`GESTURE_PLANE.md`。
- 用户已确认上一版TFT配置有实际摄像头画面且FRAMES增加，但手势一直UNKNOWN。本轮保留传感器配置、XCLK、PCLK约束和HDMI模式，修复固定亮度阈值，新增四角背景明暗补偿及面积/边缘/周边过滤，使用几何增强训练的INT8权重；仍无可靠的神经网络无手第四类。
- 新增预处理采用分布式缓存；BSRAM 331/340，逻辑 70378/138240，寄存器 40905/139095，DSP 85/298。所有约束时钟setup/hold TNS均为0，未降频、未放宽约束、未删除模块。
- 验证：12项手势与6项摄像头回归通过；1500帧/384000特征与软件逐项一致，13个完整摄像头特征流的分数及能量一致；真实COMPOSER开始/停止/变奏、手动优先、断流和关闭后恢复通过；约231万HDMI像素检查通过。固件、音频引擎未改动。
- 公开原始尺寸测试318/372（85.48%）；372张一组的合成渐变照明测试中正确且接受318张；49张合成无手探针全拒绝。均不是新模型的真人验收结果，实机手势准确率仍未知。
- 先只开RECOGNITION、保持CONTROL关闭；亮色背景、手在中央框内，四角尽量只含背景。HDMI `E`为十六进制前景能量（0000表示空白或形态过滤拒绝），`M`为分差（至少0800才通过）。识别/控制默认OFF不变。旧版回退文件`impl\pnr\backup\fm_138k_rgb_hdmi_2026-10-29_pre_gesture_plane.fs`。

## 2026-10-28 22:17 TFT原配置摄像头版（历史下载版）

- 生产源码`72b42ac`，位流北京时间2026-10-28 22:17:31，SHA256 `DB541725601D2D5C547B01C77A745BFCDE75FAEA40D5D19BD69B73013C071155`；标准`impl/pnr/fm_138k_rgb_hdmi.fs`已更新，未自动烧录。
- 用户实测21:24版仍无图。本轮采用第45章TFT已验证的完整252项800×480 RGB565配置，独立参考PLL为50×16÷33约24.242MHz；SCCB约400kHz，硬复位1ms/释放后20ms/软复位5ms。撤销原QVGA缩放、窗口与手动PCLK补丁。生产十帧正确预热，启动10秒/稳定后2秒恢复逻辑保留。
- 中央裁剪640×480后4×4降采样为160×120；原帧缓存容量和NN输入不增加。HDMI失锁不再复位摄像头/NN；摄像头参考PLL失锁则清除采集/NN状态。RGB菜单、音频、NN权重/门限/默认OFF不变。
- 外部PCLK时序要求收紧为85MHz，0.5～5ns输入延迟预算保持；新增24.242MHz参考时钟。所有约束时钟setup/hold TNS=0；Fmax MHz：主域50.257、PCLK103.650、RGB35.820、HDMI像素76.511、串行352.943；参考时钟为无数据路径，频率已在报告核对。
- Logic67675、FF37213、BSRAM331/340、DSP82/298、PLL3/12；比21:24版多4 Logic、6 FF和一个PLL，BSRAM/DSP不增加。未删模块或放宽约束。主域最差slack0.102ns，现为频谱RAM读出到band_max路径。
- 独立对照工具核验TFT原表全部252项、顶层尺寸/镜像/实际PLL一致；六项摄像头回归通过。800×480/84.75MHz采集249600个精确像素/十帧预热；整链约230万显示像素、原始采集到真实NN、HDMI失锁期间NN继续计数、独立PLL恢复均通过。模拟PLL/传感器，不等于实机已出图；不变的UI/FM/MIDI完整矩阵沿用既有证据。
- 详见CAMERA_TFT_PROFILE.md与`releases/2026-10-28_camera_tft.json`。新正常值R=01E0、B=0640-0640、N=4B00、十帧预热后S通常E8～EB。先关闭识别看完整诊断，再只开识别/关闭控制检查FRAMES持续增加。本轮实机图像和手势识别仍待验收。
- 回退`impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-28_pre_camera_tft.fs`，SHA256 `46898EAB7B7F7148207A1B5AE74AEEC04A857E58B6DE8EA02317B66F48EA0201`。快照tmp/camera_tft_build_72b42ac，完整日志tmp/build_camera_tft_72b42ac.log，证据assets/camera_tft/。GPRJ与两份CLI清单已同步，文件检查81项通过。

## 2026-10-28 21:24 摄像头启动恢复修正（历史下载版）

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

适用：Primer25K 独立 MIDI 中转 + ACG720-138K RGB/触摸/FM/WS2812 版本。
本次仅生成文件、验证仿真和编译，没有远程给实板烧录，也没有擦写你的 Flash。

## 一、先分清三个动作

- **综合/布局布线**：在电脑上生成 .fs，不会让板子运行。
- **SRAM Program**：通过 JTAG 把 .fs 下载到 FPGA，立即运行；断电后丢失这次 SRAM 内容。若 Flash 内有旧程序，下次上电又会载入旧程序。
- **外部 Flash 烧写（固化）**：将启动配置写入板上外部 NOR Flash，之后每次上电 FPGA 自动装载，不必重新下载。

屏幕软核固件、25K USB主机固件和ROM1A音色初始表都已经合成进对应 .fs。**不必再单独给 RISC-V 烧 firmware.hex，也不要选择 exFlash C Bin 来下载本工程。**
串口运行中改动的音色参数仍然是RAM数据，不能因此自动永久保存；固化的是当前比特流内的上电初值。

## 二、文件对照：两块板不能烧反

| 目标 | 比特流 | Programmer扫描器件 |
|---|---|---|
| Primer25K中转 | D:/a_My_projects/Gowin_publish/fpga_midi_bridge_25k/impl/pnr/midi_bridge_25k.fs | 本工程 GW5A-25B，封装 MG121 |
| ACG720-138K主机 | D:/a_My_projects/Gowin_publish/fpga_project_FM_138k/impl/pnr/fm_138k_rgb.fs | GW5AT-138B，封装 PG484A |

扫描实际器件必须与工程版本吻合。Sipeed早期资料有25A版本示意，不要为了照抄截图把自己的25B强改成25A。芯片实物若确实不同，应停止并重新核对工程器件。
目录中旧 fpga_project.fs 不能代替本次 fm_138k_rgb.fs。确认文件修改时间和完整路径。

## 三、138K首次测试：先不接25K也能看屏幕、弹奏

### 1. 断电接线

1. TFT V3.0 接 J1 40pin FPC，先确认1脚、排线同向/异向和触点朝向，锁好座子。禁止带电插拔。
2. GPIO0 Bank 电压设3.3V。MAX98357 BCLK→P7-1，LRC→P7-2，DIN→P7-3，GND→P7-12或28。功放按模块规格供电，使能脚保持正常，扬声器接SPK+/SPK-。
3. 暂不接灯条和25K，先验证最短链路。板载ES8388音频插孔本版还没有驱动。
4. 用合适下载器连接138K板上 **P1 JTAG**，红线方向对准1脚，确认Vref、GND及3.3V接口。下载器接电脑USB。
5. 按开发板要求给板子供电并开启电源；不能把“下载器USB插上了”当作主板已正确供电。
6. 可另接板载CH340的USB串口看诊断。**CH340串口USB、FX2 USB2.0通信口不是本工程的JTAG下载口。**

### 2. 下载到SRAM

1. 从IDE打开 fpga_project_FM_138k/fpga_project.gprj。若已有最新 .fs，可直接打开 Gowin Programmer，不必每次重新综合。
2. IDE的 Process → Program Device，或 Tools → Programmer；也可打开 D:/Gowin/Gowin_V1.9.12.03_x64/Programmer/bin/programmer.exe。
3. USB Cable Setting 选实际下载器，初次JTAG频率先用较保守的2MHz。电脑同时连两板时务必选对下载器，最稳妥是先只接要下载的那块。
4. 扫描设备，应出现 GW5AT-138B。No USB Cable / 扫不到芯片时，先排查数据线、驱动、板电源、JTAG方向，不要改音源代码。
5. 双击 Operation，Access Mode选 **SRAM Mode**，Operation选 **SRAM Program**。如果软件对当前器件提供SRAM Program and Verify，也可使用带校验的选项。
6. File name选择 fm_138k_rgb.fs，Save，点击工具栏 Program/Configure（开始下载）。等待日志明确成功。

### 3. 应该看到哪些现象

- 屏幕显示 FM SYNTH ACG720、默认 BRASS 1，右侧预设/音量/八度/PANIC以及VIEW和XY DELAY，底部25键。
- LED0周期变化，LED1视频PLL锁定。触摸识别成功后LED3亮、屏幕TOUCH OK。
- CH340串口115200/8N1，复位后可看到 ACG720 138K FM RGB/GT UI ready、GT地址/ID/分辨率。串口助手应在按复位前打开，防止错过启动打印。
- 按右侧PRESET切换预设；找 E.PIANO1 可用P11（CC索引10）。VOLUME加减每次5，默认96。
- 按底部琴键：琴键高亮、V声部数变化、波形活动，接好MAX后有声。松键按音色释放段收尾，可能仍有尾音。
- 右侧 VIEW：左WAVE，右XY。XY DELAY ±调整1～96采样点，默认24。XY模式用当前PCM和延迟PCM描点，展示随音色变化的闭合/复杂轨迹；不需电脑生成图片。
- 无音时XY通常收敛到中心点；很小音量轨迹也很小，这是幅度显示而非故障。不同频率/延迟可能形成斜线、椭圆或复杂轨迹；先长按单音再调延迟观察。

看见图像说明显示链路成功，不代表触摸、声音、USB已经全部验证；按上述顺序逐项确认。

## 四、再接25K中转，直到外部键盘发声

1. 先断开两板供电。将25K Dock **J3-15 F1 TX → 138K P7-4 A16 RX**，再共地。只有TX和GND必需，不连接两板5V。
2. 给25K和138K分别可靠供电。25K Dock 的USB-C是板载下载/调试连接；USB-A接MIDI键盘。
3. Gowin Programmer扫描25K，选择匹配的GW5A-25B，SRAM Mode / SRAM Program，下载 midi_bridge_25k.fs。原独立25K合成程序会在本次运行时被中转程序替代。
4. 中转调试UART C3为TX，115200/8N1。原板载双串口中哪个对应C3沿用之前已验证的通道，不能只按COM号码大小猜测；必要时用3.3V USB-TTL接C3和GND。
5. 键盘接入后应看到USB枚举成功及 USB-MIDI ready。若只有device connect，说明还没有枚举完成，不能判定USB正常。
6. 138K上的LED2随事件闪亮；按物理琴键应发声。MODE/CC20调音量，TRANSPOSE/CC27数值0～31选预设，Pitch滑条和MOD沿用现有控制。
7. 两板事件串口是 **1Mbaud、8N1、专用12字节帧**；不要把它当作115200调试口或直接把三字节MIDI送入。
8. 最后再接WS2812：P7-6经合适电平转换接DIN，外部5V供电并共地。第1～25灯固定MIDI48～72，超音区可以发声但不点这些灯。

## 五、确认SRAM都正常，再固化两块板

烧写会覆盖目标Flash相应区域原有启动程序，包括原先的工厂演示或旧工程；需要保留的比特流先自行保存到电脑。这里不要求擦除整个Flash，也不启用加密、安全锁或写保护。

两块芯片都属于Arora V。当前 Programmer 手册的模式名是：

- Access Mode：**External Flash Mode Arora V**。
- Operation：优先 **exFlash Erase,Program,Verify Arora V**，若该版本只提供Erase,Program，则使用对应Arora V项并在烧后核验启动。
- 老版软件/板厂截图可能写 **External Flash Mode 5A/5AT**、**exFlash Erase,Program 5A/5AT**，是版本命名差异；不要选择GW1N的embFlash模式。

### 25K

1. 扫描并选中25K那一行，双击Operation。
2. 选上述外部Flash Arora V模式，文件用 **midi_bridge_25k.fs**。
3. Flash起始地址 **0x000000**。本地核心板原理图U1200标W25Q64，64Mbit=8MiB；以实际板批次/器件识别为准。支持时保留Generic Flash或选择确切兼容型号，不因为型号列表没有完整后缀就随便选容量不同的器件。
4. Save → Program，等待擦写和校验完成。不要中途断电或移动USB接头。
5. 完成后给25K真正断电再上电，不执行SRAM下载；USB键盘能重新枚举，中转能发送才算启动验证成功。

### 138K

1. 扫描并选中GW5AT-138B那一行，双击Operation。
2. 外部Flash Arora V模式，文件用 **fm_138k_rgb.fs**。
3. 起始地址 **0x000000**。本地ACG720原理图U3标 **MX25L12845G，128Mbit=16MiB**；资料包里的N25Q128手册不能代替实物型号。以实物批次为准，支持时用Generic Flash或匹配型号。
4. Save → Program，等日志写入/校验成功。Flash操作可能暂时装入编程桥，完成后先断电重启，不要把烧写中的画面消失当作音源故障。
5. 保持开发板正常出厂的SPI Flash启动配置，不随意改模式脚或启用MSPI 2nd Boot。冷启动后应重新显示界面、恢复默认音色并能触摸发声。

**验证“固化成功”必须真的断电，而不是只按S4：S4是本工程逻辑复位，不会重新证明Flash配置装载。**
电脑USB、GPIO、灯条或串口模块可能反向供电。冷启动测试时避免外部信号让已断电板仍半供电，确认板上确实掉电后再启动；两板跨接线可在断电后拆下、启动后按安全顺序恢复。

## 六、常见卡点

- 扫不到138K：USB串口有COM口只证明CH340连上，不证明JTAG下载器连上。先检查P1下载器和电源。
- 下载成功黑屏：核对新文件、器件B版、FPC方向、背光及LED1。编译时必须允许CPU/SSPI复用脚作GPIO。
- Flash写成功但冷启动是旧版：核对是否只做了SRAM Program、是否选错下载器/Flash地址、是否烧了旧路径。不要把两板.fs混用。
- Flash模式没有Arora V/5A选项：先确认扫描的器件，使用支持该芯片的Programmer版本，不能以普通exFlash菜单强行替代。
- 校验失败：先换可靠USB数据线、降低JTAG速率、查电源与下载器方向，再核对FlashID/容量。不要用重复全片擦除掩盖原因。
- 固化后没有菜单编辑的音色：本版尚未把运行时编辑参数写入Flash，重新上电恢复默认是预期行为。
- 键盘能在电脑用但138K无响应：查25K的USB-MIDI ready、F1→A16及公共地；138K本身还不能直插USB键盘。

## 核对依据

- 本地板厂教程《第2章 Gowin软件基本开发流程》2.9～2.10：SRAM下载与程序固化。
- 本机《SUG502-2.5.1 Gowin Programmer用户指南》3.4.1、3.4.5、4.9.3：Arora V外部Flash操作。
- ACG720-138&60K通用原理图第2页（U3），Tang_Primer_25K_52300_Schematic（U1200）。
- [Sipeed Primer25K官方说明：外部Flash下载](https://wiki.sipeed.com/hardware/zh/tang/tang-primer-25k/primer-25k.html#burn_flash)。
