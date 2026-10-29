# 2026-10-29 背景补偿与手势拒识

生产控制器采用 `NORMALIZE=1`，摄像头仍为已经实机验证出图的 TFT 800x480 配置、中央裁剪后160x120预览。权重从独立的 `src/generated/gesture_plane/` 读取。旧固定阈值及其模型保留用于回归，不能与新版预处理混搭。

## 实现

摄像头域先传送中央16x16取样点的7位暗度，邮箱跨域保持整帧。50MHz域的 `gesture_normalize` 用四个2x2角落的最小暗度估计背景，按整数双线性插值补偿明暗渐变，再以相对暗度12分割手形。插值两次右移4位，Python与RTL完全相同，无软核图像处理、无整幅摄像头帧RAM。

分割后只有前景7..192格、周边前景不超过24格、水平与垂直跳变总数不超过96时保留面积能量。否则能量置0，继续输出原始网络分数，但不能通过现有识别门槛。它是工程过滤，不是已经训练好的第四类“无手”，不能保证陌生物体都拒识。

新增256x7位原始取样及256x1位轮廓缓存，声明使用分布式RAM；实际资源以本轮综合报告为准。预处理增加约25.6微秒（1282个50MHz周期）的延迟；原MLP仍为12486周期，邮箱持有到MLP真正结束。关闭识别时完成在途处理以释放邮箱，不依赖摄像头时钟持续运行。

HDMI原 CTRL 字段改为 `E:xxxx`（十六进制前景能量）。E=0000可能为空白或形态过滤拒绝；M仍为分差，至少0800才通过分差门槛。RGB页的控制开关与状态仍保留。识别和音乐控制仍默认关闭。

## 训练与离线结果

CPU/NumPy，固定种子720138，2160训练/360序列隔离验证，180轮，按验证集选择第101轮。训练输入为新plane特征，加大小、平移、约±15度旋转增强。256→24→3架构、6216个INT8权重和27个偏置均不增加；验证94.72%，原始公开测试318/372=85.48%。数据仍是白背景CGI，真人准确率未知。

`camera_plane_audit.json`：每组372张统一96x96的合成压力测试，正确且通过门槛的结果为：原图313、曝光87%315、曝光70%320、缩小75%271、旋转15度323、渐变光照318；49张无手探针全部拒绝。这些探针不是完整无手验收集。已查看的公开测试不能再作为新盲测集。

复现：

```
python tools/gesture/train.py --features plane --geometry-augment --epochs 180 --out tmp/gesture_plane
python tools/gesture/benchmark_camera.py --candidate tmp/gesture_plane --output assets/ai/gesture/camera_plane_audit.json
./sim/run_gesture_checks.ps1 -IverilogDirectory <bin> -Python <python>
./sim/run_camera_checks.ps1 -IverilogDirectory <bin> -Python <python>
```

## 使用边界

先开RECOGNITION，保持CONTROL关闭，在亮色背景下将手放入中央方框，四角尽量只含背景。避免手掌覆盖四角、强烈局部阴影、杂乱背景。当前补偿不是手部自动定位，不能保证复杂场景可靠工作。

## 构建验收

源码65e32dd，标准下载文件于2026-10-29 12:36:27更新。所有约束时钟setup/hold TNS均为0；主时钟Fmax50.025MHz，余量较小，摄像头PCLK Fmax117.267MHz。逻辑70378/138240、寄存器40905/139095、BSRAM331/340、DSP85/298；相对TFT版增加2703逻辑、3692寄存器、3 DSP，BSRAM不增加。

12项手势与6项摄像头回归均通过。发布记录见 `releases/2026-10-29_gesture_plane.json`，备份在 `impl/pnr/backup/fm_138k_rgb_hdmi_2026-10-29_pre_gesture_plane.fs`。已更新标准文件，未自动烧录；新手势效果仍待实机验收。
