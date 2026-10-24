# 音频性能监测

入口：**SETUP → PERFORMANCE >**。真实 RTL 计数器持续运行，界面每 500 ms 读取一次快照。
2026-10-24 复音扩容后生产容量为 32，声部计数为 8 位；容量通过 UI[59] 回读，见 `POLYPHONY_32.md`。
FREEZE METRICS 只冻结查看数据；声音和后台计数继续运行。CLEAR COUNTERS 清除累计统计和峰值，
不复位音源、不清除 MIDI、不停止琶音器/音序器。返回 SETUP 或其他页后继续统计。

## 数据定义

| 屏幕项目 | 含义 |
|---|---|
| VOICES NOW / PEAK | 已分配声部数量及峰值，含松键后的尾音，不保证每个声部当前可闻 |
| RENDER NOW / MAX | 最近/最大 FM 计算耗时：FSM 消费采样请求到 ENGINE_OUTPUT 写入结果的时钟数 |
| READY NOW / MAX | 最近/最大 FM 请求响应时间：sample_tick 到上述结果写入，含等待调度时间 |
| BUSY NOW / PEAK | 最近完整采样间隔内 FSM 非 IDLE 时钟占比及峰值，包含音符初始化；不是整个 FPGA 的资源占用率 |
| SAMPLE PERIOD CLKS | 实测相邻 sample_tick 的时钟间隔，正常 1024 |
| RENDERED FRAMES | 已完成 FM 采样计算次数 |
| DEADLINE MISSES | 下一个 tick 到来时，上一个请求仍待处理或仍在计算的次数；同边沿才写结果也算迟到 |
| LOST SAMPLE TICKS | tick 到来时单项 sample_pending 已占用的次数；现有引擎会合并请求，不能排队保留每个 tick |
| VOICE STEALS | 多音模式新 Note On 覆盖已分配声部的次数，包含抢掉尾音；单音重触发/连奏不计 |
| BRIDGE DROPS | 138K 桥接接收端已收到合法 MIDI 帧，但输出暂存被占用而丢弃的事件数 |
| MIDI ACCEPTED | 经所有者队列送入 FM 的事件握手次数，含 CC 和 Note Off，不只统计音符 |
| MIDI STALL CLKS | FM 输入 valid && !ready 的累计时钟数，是背压等待，不等于丢事件 |

正常目标：DEADLINE MISSES、LOST SAMPLE TICKS、BRIDGE DROPS 都为 0。
VOICE STEALS 大于 0 可能只是复音用满。BUSY 是最近一帧及历史峰值，不是长时间平均。
清零后第一个 tick 用于建立完整统计窗口；期间负载暂为 0，随后恢复。
周期/耗时饱和于 65535 clocks（50 MHz 下约 1.31 ms），累计事件计数饱和于 0xffffffff。

**READY 不等于物理按键到耳机总延迟。**它不包含键盘扫描、USB/25K 桥接、入口排队、
效果链后续流水和 DAC 模拟延迟，也不测量可闻起音阈值。比赛总延迟需要额外物理测量。
本版没有自动改变音色/发声的压力测试，也没有实现独立多频测试音模式。

## RTL 与读写接口

- `fm_poly_synth.v` 只导出状态观察信号；监测器没有反馈到音源控制或算术通路。
- `audio_performance_monitor.v`：计数、16 位耗时跟踪、18×32 位同步快照；无软件逐样本计算。
- `midi_bridge_rx.v`：增加丢弃脉冲，原 16 位 dropped_events 改为饱和；监测器另存独立累计数，支持单独清零。
- 两种 138K 顶层均连接，IDE 与两份 CLI 脚本均登记新模块。

MMIO 基址 `0x23000000`：

| UI 索引 | 操作 |
|---|---|
| 56 | R/W：快照字索引 0..31 |
| 57 | R：所选快照字；18..31 返回 0 |
| 58 | W：bit0 捕获快照，bit1 清统计；固件分次写入清零/快照 |

快照 0..17：

0. `0x50455231`（PER1，布局版本 1）。
1. 时钟 Hz（50,000,000）。
2. 标称采样周期 clocks（1024）。
3. 最近实测周期 clocks。
4. FM 已完成帧数。
5. `{max_render[15:0], last_render[15:0]}`。
6. `{max_response[15:0], last_response[15:0]}`。
7. `{max_busy[15:0], last_busy[15:0]}`。
8. Deadline misses。
9. Lost sample ticks。
10. Voice steals。
11. Bridge drops。
12. FM MIDI accepted。
13. `{capacity[15:0], peak_voices[7:0], current_voices[7:0]}`。
14. FM MIDI stall clocks。
15. 最终 PCM 在 tick 上的最大绝对值（包括负满幅 32768），保留给诊断工具。
16. Tick 累计次数。
17. `[2:0]={engine_busy,sample_pending,render_active}`。

快照固定到下一次捕获，不随计数变化。捕获得到该边沿之前的统计；同边沿清零和捕获会捕获清零前值。
清零不打断在途耗时跟踪，之后完成的一帧仍报告完整耗时。

## 实机建议

1. 进入监测页并清零，检查 SAMPLE PERIOD=1024；放置一分钟，三个错误计数应为 0。
2. 弹满和弦并踩延音，观察 VOICES 峰值、BUSY 峰值和抢音次数。
3. 打开全部效果、FFT、HDMI，运行 ARP/SEQ，检查错误计数是否保持 0。
4. 冻结查看、清零、恢复，确认声音不受按钮影响。
5. 复音扩展前后使用相同演奏事件和音色，比较最大 READY 与 BUSY，保留数据记录。

编译、仿真、资源与时序实测结果见 AI_HANDOFF.md 最新发布记录。尚未烧录验证的结果不得写为实机通过。
