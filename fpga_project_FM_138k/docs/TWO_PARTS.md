# LIVE / BACKING 双 Part

## 使用方式

- 共用一条 FM 流水线、合计 **32 复音**；按空闲声部和最老声部动态分配，不固定切成 16+16。
- **LIVE**：USB MIDI 键盘、触屏键盘、编辑器当前音色。PATCH、算子、算法、包络和 LFO 页继续编辑 LIVE。
- **BACKING**：ARP 生成音符及 STEP SEQUENCER 播放音符。ARP/SEQ 保留互斥关系。
- 两 Part 具有独立完整音色、LFO 相位/延迟/深度、Pitch EG 参数、同音音符及延音踏板状态。
  键盘调制条和弯音控制 LIVE。主音量、效果器链、耳机/音响输出选择仍共享。
- 练习模式示范继续使用 LIVE，保留示范/人手同音所有权保护，不占用 BACKING 音色。

### 琶音

1. 选择希望用于伴奏的音色，然后打开 ARP。开启时抓取当前完整音色。
2. 输入和弦、开启 HOLD，离开 ARP 页可进行手动即兴。
3. 更换 LIVE 音色或调整其参数，不会覆盖 BACKING。
4. 修改 BPM、RATE、ORDER、OCTAVES、GATE、VELOCITY、SWING 不清除 HOLD 和弦，不重启播放。
   当前一步按旧时值完成，新时值从后续一步生效。
5. 需要更换琶音伴奏音色时，关闭 ARP，选择新的 LIVE 音色，再开启 ARP 并输入和弦。

### 音序

- 每个 Pattern 在首次录制时抓取一份完整音色。首次直接播放尚未抓取音色的 Pattern 时，抓取当前 LIVE。
- 停止、切换 LIVE 音色、再次 START，仍使用该 Pattern 已抓取的音色。
- 停止时，在音序 SETTINGS 按 **CAPTURE LIVE PATCH**，可用当前 LIVE 音色替换该 Pattern 的伴奏音色，无需重录音符。
- 新一轮 STEP REC 会重新抓取当前 LIVE 音色。播放/录制中锁定 Pattern 选择；先 STOP 再切换 Pattern。
- 播放中可以调整 BPM、RATE、GATE、SWING、LENGTH，保持 transport 运行。
- 八个 Pattern 及其音色快照均为 RAM 数据，断电不保存；SD 用户音色库格式不变，不包含 Pattern。

## HOLD 中调参停止的根因

`arp_adj()` 同步发布 ARP 和 SEQ 的共享 BPM。旧 SEQ 逻辑每次收到 run=0 的配置写入都会置
`reset_pending`；`sequencer_active` 又把内部 busy 位当作播放状态，导致 ARP suspend，清空和弦。

修复两层：只有真正的开始/停止/录制切换/重启请求产生清理；SEQ 对外的 transport ownership
仅由 running、recording、实际 sounding/pending MIDI 决定，初始化或编辑 RAM 不暂停琶音。

## RTL 与协议

- `voice_part[]` 保存每个物理声部的归属。Note Off、踏板释放按 Part 匹配；LIVE patch commit 仅清 LIVE。
- 事件 bit30=ARP/BACKING；bit28=SEQ/BACKING，SEQ 同时保留 bit31 自动演奏标记。
  练习的 bit31 单独标记继续进入 LIVE。物理 USB cable 字节仍在入口清零。
- ARP 清理使用带 bit30 的 CC64/CC123，避免停止伴奏时关掉手动演奏；外部全局 CC120/123 保留清音行为。
- 生产 `midi_owner_queue.INDEPENDENT_PARTS=1`：BACKING 不参与 LIVE/练习的同音抑制；旧模块默认值保留单 Part 测试兼容性。
- UART/local command **0x6A**：payload[9:0]=辅助地址，payload[31:16]=16-bit 编译参数。
  地址 0x000..0x00B、0x040+op*32+offset、0x140+stage*8+offset 对应现有 readback 编译格式，写 BACKING。
  0x3FF 写 0 使 BACKING 无效并清理其声部，完整上传后写 1 生效；上传由固件在该 Part 停止时执行。
  不修改 `fm_uart_control` 的 LIVE 参数输出，因此不会污染编辑器、ROM 预设或用户槽。
- 固件 `backing_t` 在既有 260-byte slot 图像之外额外保存三个 routing flags word，兼容自编辑算法路由。
- 不增加第二条 FM 运算流水线，也不复制效果器缓冲。额外参数和 LFO 控制状态随 Part 分开；算子/包络实时状态仍随 voice 存储。

## 滑音时间

- SETUP → **GLIDE MS**：10..1000 ms，固件默认 170 ms，开关仍为 GLIDE MONO。
- 继续保持“前一键仍按着时按下一键”才滑音，没有按键间隔时间窗口。
- 线性频率变化；连奏保留相位和包络。修改时长用于下一次滑音，不重写当前正在滑行的步长。
- 固件按 Fs=48.828125 kHz 计算样本数和 Q0.32 倒数；音源在 Note On 初始化时计算有符号步长，采样通路只累加、比较和钳位。
- 0x6A 辅助地址：0x3FD/3FE 写倒数低16/高8位影子；0x3FC 写毫秒并原子提交倒数。
  readback 0x00C=开关、0x00D=毫秒、0x00E=BACKING 图像有效。
- 硬件复位兼容历史 8192-sample（约168 ms）默认；UI 启动时设置 170 ms。

## 验证入口

- `tb_fm_readback +parts`，TEST_VOICES=32、TEST_COMPARE=2：BACKING 与单音色参考核逐样本一致，
  LIVE ROM 换音色后仍一致；混合发声时逐帧检查 BACKING 声部输出和六算子状态仍与参考一致；
  同音高分配、独立松键/踏板、ARP/SEQ 标签和局部停止。
- `+parts_dense`：32 满载、432 个事件、固定1024-clock采样间隔，无 deadline miss / lost sample tick。
- `+glide_time`：10/1000 ms、倒数原子提交、读回、单调变化和快速滑音精确终点。
- `tb_touch_ui +arp`：真实 RV32I/I2C，HOLD 后调 BPM/ORDER 不丢和弦。
- `tb_touch_ui +seq`：录制音色快照、后续 LIVE 参数变化隔离、播放中改时值参数。
- `tb_touch_ui +glide_time`：设置项、点按、滑条、倒数上传且不改变滑音开关。
- 全工程发布仍必须检查四时钟域 setup/hold 和实际资源报告；单元仿真不替代实机听音。

## 本次发布的实现结果

双屏位流2026-10-24 23:18:01生成，2026-10-25恢复中断后核验。四个时钟域setup/hold TNS均为0。
主50 MHz域Fmax为50.032 MHz，最紧slack为0.013 ns，路径位于ARP步长控制到和弦排序寄存器使能。
Logic 56298/138240（41%）、FF 29323/139095（22%）、BSRAM 319/340（94%）、DSP 70/298（24%）。
主域时序和BSRAM仍需关注，完整报告与位流校验值见AI_HANDOFF.md。尚未自动烧录或实机验收。
