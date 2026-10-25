# BSRAM优化与AI伴奏进度

## 2026-10-25 板载数码管（最新发布）

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
