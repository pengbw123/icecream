# 手势集成后的时序优化

本轮保留32复音、双Part、音频效果、RGB菜单、HDMI摄像头显示和神经网络手势链路，不降低时钟、不放宽约束。摄像头实机无图的问题仍单独待查。

## 基线与目标

源码`1af0e10`的完整布局布线于2026-10-28 17:16结束。主域要求50 MHz，实际Fmax 45.581 MHz，setup TNS −539.124 ns，823个失败端点；其余四域通过。工具生成了位流，但这份失败位流没有替换正式版本。

验收要求五个受约束时钟域的setup、hold TNS均为0，失败端点均为0；不能只看Gowin退出码、生成.fs或综合通过。检查器为`tools/check_timing.py`。

## 改动与原因

生产源码检查点`9cf7ec2`，构建目录`tmp/gesture_build_9cf7ec2`。

| 基线长路径 | 改动 | 可观察影响 |
|---|---|---|
| NN分数→排序/求差/门限→事件计数/锁存 | 新增四拍`gesture_score_gate`，事件与遥测共用结果；稳定计数器按参数收窄 | 后处理约增加80 ns；分类分数、阈值、连续帧规则不变 |
| 算子索引→力度敏感度读取/乘法/舍入→最终电平 | 在已有`ENGINE_EVENT_GAIN_WAIT`锁存乘积 | 未增加FM事件处理周期；保持原有有符号舍入 |
| 声部索引→年龄数组读取/递增→数组写回 | `ENGINE_PREP`读取年龄，`ENGINE_PREP_RESOLVE`更新同一声部 | 未增加渲染周期；年龄仍饱和递增 |
| MIDI数据→8打击垫匹配/动作优先级→乐句状态 | 仲裁结果寄存后执行 | 触屏/打击垫/手势动作增加1拍，即20 ns |

跨域特征邮箱仍由原始NN完成信号确认，不使用可被关闭识别开关清除的后处理valid。这样在推理完成附近关闭识别时，邮箱不会因等不到确认而卡住。

手势命令继续经过COMPOSER所有权、录入/学习/紧急停止、新鲜帧及手动优先约束；优化不扩大其控制权限。

## 回归证据

| 检查 | 日志 |
|---|---|
| 九组手势检查，含127组连续极值/边界向量、全部1116个NN分数逐位一致、实际样本到COMPOSER联合 | `tmp/gesture_timing_checks.log` |
| 作曲器原有旋律/节奏/主题/快速重启/背压/紧急停止/无漏拍 | `tmp/gesture_timing_composer.log` |
| FM32到I2S实际PCM、LIVE隔离及按来源停止 | `tmp/gesture_timing_audio.log` |
| 32复音、192算子槽、密集事件/渲染期限 | `tmp/gesture_timing_fm32_poly32.log` |
| 单音滑音、相位/包络保持、精确滑音终点 | `tmp/gesture_timing_fm32_legato.log` |
| 双Part精确BACKING PCM、独立声部/延音/ARP与SEQ来源 | `tmp/gesture_timing_parts.log` |
| 实际32复音性能计数 | `tmp/gesture_timing_fm32_metrics.log` |
| 三路并发MIDI、144事件、背压/复位/无丢失重复 | `tmp/gesture_timing_midi.log` |
| 时序优化后的真实RV32I/I2C COMPOSER菜单 | `tmp/gesture_timing_real_ui_composer_restart.log`，已通过 |

其余不变部分沿用最终固件手势菜单/琴键与摄像头诊断/恢复/整链显示的已通过记录。公开CGI测试准确率81.72%不等于实机识别准确率。

## 最终实现

2026-10-28 20:15完成，五域setup/hold TNS均为0、失败端点均为0。

| 时钟域 | 要求MHz | Fmax MHz |
|---|---:|---:|
| 主域 | 50 | 50.069 |
| 摄像头输入 | 50 | 106.012 |
| RGB像素 | 33.333 | 34.835 |
| HDMI像素 | 25 | 73.670 |
| HDMI串行 | 125 | 358.422 |

主域最差setup slack 0.028ns，路径为音频输出到数码管峰值换算；目前通过但余量很小。后续扩展应优先流水化该显示换算，再观察FM增益、ARP及MIDI扇出。

Logic 67652/138240，FF 37189/139095，BSRAM 331/340，DSP 82/298。相比失败基线，Logic减少429、FF增加250，BSRAM/DSP不增加。PnR报告总耗时17分54秒，基线为46分50秒；综合另计。

正式位流`impl/pnr/fm_138k_rgb_hdmi.fs`已更新，SHA256 `A443C69D6247B4A9E44E5DEB3B8CC409970D1B3978F116366F1B56B105E12117`；旧位流已备份，未自动烧录。详细记录[releases/2026-10-28_gesture_integration.json](releases/2026-10-28_gesture_integration.json)。完整构建日志`tmp/build_gesture_9cf7ec2_restart.log`；中断前的`tmp/build_gesture_9cf7ec2.log`只到综合阶段。

发布时同时核对了源码/SDC/CST/固件与快照一致、五域时序、回归日志、文件清单和引脚。最终固件手势菜单测试的已知跨页MIDI为两组57号音符开关与两次滑音控制：SETUP入口按住跨入AI页的琴键所致，旧版已有。本轮严格核对这份既有序列，未声称整个导航过程零音符；该触屏行为留待单独修复。
