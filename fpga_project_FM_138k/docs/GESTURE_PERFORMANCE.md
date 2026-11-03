# 独立手势演奏（2026-11-02）

本轮恢复CH376直接接收USB MIDI，关闭25K中转入口；没有继续排查此前的CH376重复事件问题，也没有按音高去重。原32复音演示源文件与上一轮完成快照逐字节归一化对比一致。

## 操作

SETUP顶部依次为ARPEGGIATOR、SEQUENCER、GESTURES。点击GESTURES进入独立演奏页，保留下方全宽触屏琴键；进入时退出AI伴奏、AI旋律、普通ARP和音序，避免自动音符混入。识别与控制默认OFF。

1. 先选择一个能够持续发声的音色，例如风琴或弦乐；短衰减钢琴在按住较长时间后自然变小，不利于演示切音。保持原有音量和效果器设置，手势不自动加大音量。
2. 打开RECOGNITION，确认HDMI的稳定识别正常，再打开CONTROL。
3. 在键盘或屏幕按住C、E、G，依次做以下手势：

| 手势 | SOUND MODE | 声音 |
| --- | --- | --- |
| 张手PALM | NORMAL | 正常同时演奏和弦，沿用当前音色和用户效果 |
| 握拳FIST | CHOP | 整体输出按约120 BPM的十六分音符通断，50%占空比 |
| V SIGN | ARPEGGIO | 按当前和弦音高从低到高、跨两个八度循环；120 BPM八分音符，75%音符门长 |

以MIDI60/64/67为例，V依次生成60、64、67、72、76、79。它不产生AI旋律、不识别和声、不随机改音。现阶段速度固定120 BPM，暂未增加速度编辑控件。切音按48828.125 Hz采样率量化为6104样本一个周期，约125.010 ms；音量边沿128样本线性渐变，约2.62 ms。

SOUND MODE显示音频适配器实际模式，不直接把RAW类别当作执行成功。短暂UNKNOWN保留当前模式；关闭CONTROL或RECOGNITION恢复NORMAL。离开页面继续有效。启用其它自动演奏模式时，手势控制暂被阻止并退出附加模式，以手动功能优先。CONTROL OFF不强制松开仍实际按住的琴键。

识别模型、摄像头采集和训练权重未改。原有背景、位置和照明限制仍然存在。手势页去掉了原来的BASIC/PERFORM和手掌位置对AI旋律的操作，生产top中的composer以GESTURE_ENABLED=0实例化，手势输入固定0；AI旋律自身的屏幕操作保留。

## 实现

- `gesture_performer.v`维护按键、力度、通道和延音状态，在原声/琶音切换时先清理旧LIVE音符，再重建仍按住或由踏板保持的和弦。支持有效/就绪背压，不改写等待中的事件。
- 复用现有`midi_arpeggiator.v`，手势琶音使用LIVE音色；普通琶音仍使用原BACKING音色。生成消息的来源在ARP内部锁定，音符开/关和清理使用同一来源，避免跨音色释放错误。手势琶音期间暂不滑音。
- `gesture_chopper.v`在最终效果器输出后执行增益门控，两路音频输出和示波/频谱观察同一份结果。显式平衡移位加法实现有符号增益。32音测试期间完全旁路，不改变测试波形。
- 和原ARP一样，以音高记录和弦。不同MIDI通道的同音高不构成独立和弦项；普通模式事件仍原样传递。
- 主菜单固件81720/81920字节，BSS10828，栈余量16584字节；Gowin工程文件列表105份RTL，新增模块已列入hierarchy。

## 验证和构建

已通过专项单元测试：原声/切音/六音跨八度序列、UNKNOWN保持、实际按键/延音恢复、关闭控制、普通ARP接管、背压、增益正负满幅、防爆音渐变和32音旁路。`sim/tb_gesture_performer.sv`、`sim/tb_gesture_chopper.sv`；RGB手势页键盘像素验证通过。真实RV32I触摸菜单、FM32+FX音频链路、包含手势模块的原32音演示回归均通过，原ARP与AI旋律功能回归也通过。证据见assets/gesture_performance/validation.json及日志。生产音频仿真只加速测试台内的ARP节拍和切音周期，I2S采样时钟不变；初次超时是Icarus未应用嵌套节拍参数覆盖，已改测试台驱动既有分频器终值后通过，无需更改综合逻辑。测试台更正在构建清单simulation_fixture_corrections中记录，不涉及综合输入RTL。尚未进行本轮实机声音和手势动作验收。

构建快照`tmp/gesture_performance_build`，源清单`source_manifest.json`。构建进程见`build.pid`，日志`build.log`；后台收尾`tools/finish_gesture_performance_build.ps1`。待真实菜单、生产音频、RGB、32音测试和所有约束时钟setup/hold TNS=0均通过后，核对冻结/当前输入哈希并另存`impl/pnr/fm_138k_gesture_performance.fs`。不覆盖标准`fm_138k_rgb_hdmi.fs`，不发布上一轮25K中转位流，不自动烧录。

结果`tmp/gesture_performance_build/background_result.json`，测试汇总`test_result.json`；合格时另记`docs/releases/2026-11-02_gesture_performance.json`。构建或测试失败则停在NEEDS_REVIEW，不把失败候选文件当作可下载版。
