# 灰度 CNN 自检位流

自检位流与正常位流分开。设置顶层 `GESTURE_SELF_TEST=1` 后综合；默认工程为 0。自检位流仍需要摄像头正常输出帧及启用 RECOGNITION，以驱动完整采集、预处理和 CNN 流水线。屏幕小图标题为 `SELFTEST`。

- CONTROL OFF：CNN 收到 1024 个 255，预览全白。预期 R:O、M:3BAB、原因 OTHER。软件参考四类分数依次为 24944、-41371、-14405、40219。
- CONTROL ON：CNN 收到摄像头经光照自适应处理后的灰度，预览显示同一数据的 16×16 抽样。观察手和背景改变时 R 和 M 是否变化。预览是抽样，不能证明其余像素全部正确。
- 两种状态均禁止手势动作与投票接受，不用于演奏。白图参考仅用赢家和分差检验，不能证明四个原始分数全部正确。

白图不符合预期：优先查综合后的 CNN、RAM、权重或结果显示；白图正确而实时图不变化：优先查输入采样/预处理；实时图变化而 R/M 不变：继续查 CNN 读取和模型。白图正确且 R/M 随输入变化仍不代表实拍识别准确。

回归 `sim/run_gray_checks.ps1` 包括 `tb_gray_selftest`，在 RTL 校验固定白图四分数、实时输入参考分数、预览与动作禁止。与板上综合后测试是两层不同证据。

## 2026-10-31 诊断构建

诊断位流 `impl/pnr/fm_138k_gray_selftest.fs`，SHA-256 `E56D2A8581E99E1FBD00AA498BB91DC3A030CD51D65172A6C63BDD3A7F172FD2`。独立源码和哈希清单在 `tmp/gray_selftest_switch_build/source_manifest.json`；顶层 SELF_TEST 默认值仅在该构建快照设为 1。正式位流未替换。

Gowin 布线和全部约束时钟 setup/hold TNS=0；50 MHz 时钟 Fmax 50.048 MHz（裕量较小），摄像头 85 MHz 时钟 Fmax 95.672 MHz。诊断构建使用 Logic 79995/138240，BSRAM 335/340，DSP 90/298。综合网表包含 CNN 图像 SDPB RAM；这不等于已证明门级行为或实机通过。

摄像头帧仍须正常且 RECOGNITION 开启。等待画面中 SELFTEST 和 R/M 稳定。CONTROL 关闭时核对白色小图、R:O、M:3BAB；CONTROL 开启时改变画面，记录小图、R/M 变化。CONTROL 切换后等待至少数帧。白图为固定输入；右侧大画面仍是摄像头画面。实时模式即使识别到手势也不会触发动作，UNKNOWN 属于测试版预期。
