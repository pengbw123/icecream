# MIDI 单次按键重复事件排查（2026-11-02）

用户确认键盘实际只发送一个事件。实机单次按键 VOICES 从 0 到 2，METERS MIDI ACCEPTED 增加 2；屏幕琴键正常。按板内链路重复接收排查，不以键盘双发为结论，也不按音高或短时间窗口丢弃事件。

## 已验证及限制

- `sim/tb_usb_single_voice.sv` 使用实际解码、板级仲裁、输入队列、曲谱仲裁和生产 top/FM：单条 USB NoteOn 一个声部；屏幕 NoteOn 一个声部；两个通道各一条 NoteOn 保留两个声部。
- CH376 完整 SPI 模型回归通过，覆盖枚举、64 字节事件包、背压、重插、超时等。日志 `tmp/usb_double_host.log`。
- 上述 RTL 仿真尚未复现实机故障，不能据此宣称已修复，也不能排除 USB 主机状态或综合后实现问题。

## 被动硬件记录

`top_138k_hdmi` 开启 `MIDI_TRACE_ENABLED`，不改变事件传输逻辑：

| 统计索引 | 内容 |
| --- | --- |
| 12 | 合成器入口接受消息总数，原 MIDI ACCEPTED |
| 24 | CH376 输出被板级仲裁接受的消息总数 |
| 25 / 26 | USB 端最近 / 前一条 32 位消息 |
| 27 / 28 | 合成器入口最近 / 前一条 32 位消息 |

USB 消息保留 cable/CIN；音频入口消息最高字节为内部来源标签。比较时需分别解释最高字节，不能直接要求两个完整字相等。计数包括所有接受的消息，不只 NoteOn。清零、快照与原性能统计共用。

固件 `build_firmware.ps1 -MidiProbe` 临时将 METERS 三行替换为：

- USB / AUDIO COUNT
- USB LAST / PREV
- AUDIO LAST / PREV

数值以十进制显示，拍照后可转换十六进制解析。普通固件不改变菜单。诊断固件真实 CPU/MMIO 菜单仿真通过，日志 `tmp/midi_probe_ui.log`；记录器专项测试 `sim/tb_midi_input_trace.sv` 通过。

## 构建与实机操作

诊断不可变快照 `tmp/midi_double_probe_build`，`source_manifest.json` 记录文件哈希与 `-DMIDI_INPUT_PROBE=1`。构建和时序结果看该目录 `background_result.json`，菜单验证看 `ui_result.json`。正式下载文件尚未替换；不要将构建中状态当作位流可用。

诊断位流完成并确认全部约束时钟 setup/hold TNS 为 0 后，发布为独立文件 `impl/pnr/fm_138k_midi_probe.fs`。

1. 关闭 ARP、SEQ、AI、练习、曲谱和 32 音测试，松开所有键，等待 VOICES 为 0。
2. METERS 清零，按住一个 MIDI 琴键，等待一秒后冻结统计。
3. 拍下上述三行。不要先松键，以免 NoteOff 混入最近消息。

USB 计数 1、音频计数 2 指向 USB 输出握手之后的链路；USB 计数 2、音频计数 2 指向 CH376 输出及其上游板内接收处理。再根据消息内容确定是否同一个 NoteOn 被重复提交。若有其它 MIDI 消息，必须逐条解释，不能只凭总数判断。
