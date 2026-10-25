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
