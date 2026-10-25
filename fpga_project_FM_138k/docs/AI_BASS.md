# AI BASS 原型

目标：用户正常弹奏LIVE音色，小型神经网络根据已发生的MIDI与已知和声条件，逐十六分音符产生单轨BACKING低音。
不预测任意曲目的真实和弦，不读取未来旋律，不生成PCM。音频仍由FM引擎实时合成。

## 已实现的模型链路

- 输入48项：16格节奏位置；相对当前根音的12音级近期活动；过去四步起音数量；按住音符数量、力度、密度；
  当前和弦大小调；上一伴奏动作；疏/密模式；换和弦标记；静默时长；最近旋律音相对根音。
- 两层MLP（48→32→8），中间clipped ReLU。历史由因果特征提供，本版不是GRU或大模型。
- 输出八动作：休止、保持、根音、三音、五音、高八度、低五音、根音下半音连接音。
- 稀疏模式把非四分音符拍点上的起音折为保持；换和声时若保持的是无关旧音，调度器改为新根音，避免持续挂着旧和弦外音。
- 输入/激活为无符号Q0.7，权重有符号Q2.5，偏置/输出累加Q*.12。整数argmax，无浮点softmax。
- 软件训练在电脑完成；RTL单乘加核逐项推理，固定3664个50MHz时钟（73.28us，不含48项快照装载与MIDI排队）。

## 数据与限制

POP909：Wang et al., *POP909: A Pop-song Dataset for Music Arrangement Generation*, ISMIR 2020。
仓库 https://github.com/music-x-lab/POP909-Dataset ，固定提交d83e6edba6872a704f5d3b8b32f5cb540088dae6。
仓库根LICENSE为MIT；其原文随模型来源材料保留。没有将原始MIDI曲库纳入本工程Git。
PIANO轨简化为受限单音低声部，不代表完整贝斯编曲；4/4样例47首、歌曲级划分，详见training_report.json。
首版只验证流行伴奏原型，不声明通用风格或乐手水平，仍需实机听感和更多样本验证。

复现：Python需numpy、mido。依次运行：

```
python tools/ai_accompaniment/fetch_pop909.py --songs 48
python tools/ai_accompaniment/train.py --epochs 45
```

## 硬件接口

沿用编译参数辅助命令0x6A：0x3F1/3F2为十六分音符微秒周期低/高16位影子；0x3F0写控制同时提交周期。
控制bit0开、bit1稀疏、bit2固定I-vi-IV-V循环、bit[7:4]根音（0=C，11=B）、bit8静态小三和弦、bit[15:9]力度。
周期范围10ms..1s。修改周期保留当前步，下一步使用新周期。
状态bit0实际运行、bit1有活动/待发音符、bit2推理/装载忙、bit3全局panic锁存；bit[15:4]推理时钟，bit[31:16]错过调度计数。
Panic需显式停止再启动恢复。丢失/忙时计数，不阻塞LIVE；不允许悄悄排队积累延迟。

## 验收

tb_ai_bass_inference：162组特征含留出歌曲、随机、全0/127，全部1296分数与固定点软件一致，忙时写入隔离。
tb_ai_bass_accompaniment：生成事件标签/音域/力度、单音松键、暂停/停止、panic、变速与背压，无调度遗漏。
整机接入、菜单、最终PnR状态见AI_ACCOMPANIMENT_PROGRESS.md；单元通过不等于实机听感通过。

## 当前RV32I软核的计算基线

采用工程现有50MHz RV32I（没有M乘法扩展）和同一模型、同一定点算法，隔离运行标量C推理。
C用-Oz，并专门加入8位移位乘法与跳过零激活，避免只挑通用32位软件乘法较慢的实现作对照。
两组向量的全部16个输出分数与FPGA整数参考一致。

| 输入 | 优化C时钟 | 按50MHz折算 | RTL时钟 / 时间 |
|---|---:|---:|---:|
| 留出测试集第一个真实特征向量 | 109248 | 2.18496ms | 3664 / 73.28us |
| 所有输入为127的数值压力向量 | 413584 | 8.27168ms | 3664 / 73.28us |

在这两组输入上，内核计算时钟之比分别约29.8:1、112.9:1。压力向量不代表正常MIDI特征分布；
这不是桌面CPU、RV32IM或所有CPU实现的性能结论，也不是应用平均值或全系统延迟。
测量来自周期仿真，含C调用开销，均不含特征生成、节拍等待、MIDI排队和模拟音频输出延迟。
RTL的162向量回归还单独验证了固定周期数。常规32位软件乘法基线约17.02ms，仅保留日志供参考。

复现（准备阶段会覆盖tmp中的独立benchmark.hex，不修改生产UI固件）：

```
python tools/ai_accompaniment/prepare_cpu_benchmark.py --optimized --zig PATH_TO_ZIG
iverilog -g2012 -s tb_ai_cpu_benchmark -o tmp/tb_ai_cpu.vvp sim/tb_ai_cpu_benchmark.sv src/usb_midi/rtl/rv32i.v
vvp tmp/tb_ai_cpu.vvp
```

日志：tmp/check_ai_cpu_optimized.log、tmp/check_ai_cpu_benchmark.log。
