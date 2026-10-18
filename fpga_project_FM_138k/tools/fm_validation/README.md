# FM音色差分验证（第一阶段）

这套工具的目标是把“听着像不像”变成可以重复的测试。入口是
`tools/cli/fm_dx7_diff.py`，使用`numpy`；`core-reference`还需要`g++`
以及本机Dexed源码（默认寻找`D:\a_files\dexed-master\dexed-master`）。
工具不修改、复制或提交用户的Dexed源码；编译时直接引用其`msfa`的
`sin.cc`、`exp2.cc`、`fm_core.cc`和`fm_op_kernel.cc`，编译产物放在临时目录。
请保留原项目的版权和许可说明。

也可以双击`tools/launchers/run_fm_validation.bat`打开图形界面，或从
`tools/run_tools_menu.bat`选择“DX7-FPGA音色差分验证”。界面既可以做
静态算子核心测试，也可以选 SYX 音色库、音色序号、音符、力度、按住时长
和尾音时长，生成完整 Dexed 单音参考；随后可试听、查看波形、导入 FPGA
WAV 比较音量/包络/频谱，或对原始32位整数PCM做严格逐样点比较。
试听音量倍率只作用于播放WAV，不修改随附的`.i32le`整数原始数据。

## A. 先检查静态算法路由

在`fpga_project_FM`根目录执行：

```powershell
python tools/cli/fm_dx7_diff.py audit
```

这一项直接解析本机Dexed的32组6算子路由，并和当前工具生成的FPGA路由比较。
它只证明“路由配置相同”，不证明运行时反馈、相位、包络或声音逐样本相同。

## B. 生成一组可重复的完整音色测试

```powershell
python tools/cli/fm_dx7_diff.py case --bank D:\a_files\Cartridges\rom1a.syx --index 10 --note 60 --velocity 100 --hold-ms 1000 --out D:\fm_test\epiano1_c4
```

生成`test_note.mid`和`case.json`。本机ROM1A的索引10是`E.PIANO 1`。
MIDI包含250 ms预滚、1秒按键、1.5秒松键尾音。`case.json`记录Bank哈希，
以防两次比较时不小心换了不同版本的音色。
仓库内已附一组小型示例：`examples/rom1a_epiano1_c4/`，可直接拿其中的
`test_note.mid`做第一次A/B。

1. 在Dexed里加载同一Bank，选择索引10的音色，关闭插件/DAW的效果器、
   自动音量和额外处理，导入`test_note.mid`，导出无压缩PCM WAV。
2. 在FPGA上用Transpose旋钮选同一预设（或用现有MIDI播放器加载
   `test_note.mid`通过UART演奏），以**数字路径**获取I2S/PCM。
   当前板端尚无PCM回传通道；可用支持I2S的采集硬件，或后续添加仿真
   `sample_out`导出。若只通过麦克风录喇叭，结果只能用于粗略听感对照，
   不能据此判定RTL和Dexed是否逐样本相同。
3. 两路都保存为PCM WAV（16/24/32位整数、单声道或立体声）；输入相同
   `compare`命令：

```powershell
python tools/cli/fm_dx7_diff.py compare D:\fm_test\dexed.wav D:\fm_test\fpga.wav --hold-ms 1000 --json D:\fm_test\report.json
```

输出按整段、起音0～100 ms、按键稳定段、松键前500 ms给出音量差、
最佳音量对齐后的波形相关度/残差，以及80～8000 Hz的中位频谱差。
不同采样率会线性重采样以便**诊断**，报告会显式标记；重采样、
采集时钟差、相位和线路延迟都使逐样本结论无效。要作逐样本结论，
应在两端固定相同实际采样率、同一起始状态、同一事件时刻并采集数字样点。

严格比较Dexed与FPGA输出的32位有符号小端整数流：

```powershell
python tools/cli/fm_dx7_diff.py compare-raw D:\fm_test\dexed.i32le D:\fm_test\fpga.i32le
```

此命令不作增益拟合、重采样或自动对齐。可以用`--reference-offset`和
`--fpga-offset`指定两份文件各自要跳过的样点数；报告会列出首个差异、
不同样点数、最大误差和RMS误差。只有数据格式、数值标度、采样率和演奏
事件都一致时，“所有样点都相等”才说明这一段逐位相同。

**不要把MAX98357A的桥接功放输出直接接电脑声卡线路输入。** 它不是线路级
信号。没有数字捕获设备时，先用声学录音看时间包络和频谱趋势即可。

## C. 把FM内核单独隔离出来

```powershell
python tools/cli/fm_dx7_diff.py core-reference --algorithm 32 --feedback 0 --freqs 440,0,0,0,0,0 --gains 0.25,0,0,0,0,0 --seconds 1 --out D:\fm_test\single_operator.wav
```

频率和增益依次对应DX7的算子6、5、4、3、2、1。输出同时保存`.i32le`
（Dexed内部32位原始序列）、试听用`.wav`和包含源文件哈希的`.json`。
这是真正Dexed/msfa的**FM内核**输出，但增益保持常数，没有导入DX7音色的
EG、力度、LFO和按键释放；因此不能把它当作完整`E.PIANO 1`参考。
它适合先分离检验正弦、算子连接和反馈，再扩展到包络。

## D. 生成完整 Dexed 单音参考

```powershell
python tools/cli/fm_dx7_diff.py voice-reference --bank D:\a_files\Cartridges\rom1a.syx --index 10 --note 60 --velocity 100 --hold-ms 1000 --tail-ms 2000 --out D:\fm_test\dexed_epiano1_c4.wav
```

此命令调用本机 Dexed/msfa 的 `Dx7Note`，覆盖算子EG、Pitch EG、力度、键位
缩放、LFO、算法路由、反馈和 Note Off。MIDI 音符按 Dexed 音色中的 Transpose
参数处理；默认控制器为中性值，MPE、踏板、Pitch Bend、效果器关闭。旁边生成
`.i32le`内部核心样点和`.json`，后者记录音色名、Bank 哈希和 Dexed 源码哈希。
WAV 使用 Dexed `PluginProcessor` 中核心 int32 到 int16 的同一量化方式，便于
与关闭效果器的 Dexed 插件数字导出做听感/包络比较。参考音不是 FPGA 输出，
也还不表示已完成 FPGA 逐位一致。

## 当前覆盖边界

- 已完成：统一MIDI测试事件、Bank身份记录、32路由源代码审计、直接编译
  Dexed FM核心、PCM WAV自动对齐和分段误差报告。
- 已加入：不做自动对齐/重采样/增益拟合的32位原始整数样点比较器。
- 已完成：Dexed 完整单音色离线渲染（仍是参考，不是 FPGA 输出）。
- 未完成：板端内部样点自动导出、RTL仿真自动运行、FPGA 内部 EG/算子中间值
  的自动导出，以及逐样点硬件差分。
  因此工具不会把目前的“32/32路由一致”误报为“DX7音色完全一致”。

## 以后要对照原版DX7，而不仅是Dexed

- Yamaha原版《DX7 Service Manual》有EGS、OPS及DAC信号链描述：
  <https://og.kervella.org/synth/yamaha_dx7/DX-7%20Service%20Manual.pdf>
- Yamaha原版《DX7 Technical Analysis》扫描件入口；比用户手册详细得多：
  <https://ajxs.me/blog/Yamaha_DX7_Official_Technical_Analysis.html>
- 实物OPS芯片开盖逆向，适合确认正弦/指数ROM、算法和输出数据路径：
  <https://www.righto.com/2021/11/reverse-engineering-yamaha-dx7.html>
- 原版固件ROM注释反汇编，适合确认CPU写入EGS/OPS的参数与演奏控制：
  <https://github.com/ajxs/yamaha_dx7_rom_disassembly>

这些材料和真实DX7录音可作为第二参考轴。Dexed源码是可执行参考，
但它自身不等于原机芯片的逐时钟规格。
