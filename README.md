# 高云 ACG720 实时多音色电子乐器

当前唯一维护入口为 [Gowin_integrated_20261103](Gowin_integrated_20261103/README.md)，采用2026年11月4日R3基线。工程为 `Gowin_integrated_20261103/fpga_project_FM_138k/fpga_project.gprj`，顶层 `top_138k_hdmi`。

系统包含六算子FM、32复音、128组预置、双Part、硬件效果器、触屏和USB MIDI、手势表情、蓝牙曲谱及灯带指引。

- [构建说明](Gowin_integrated_20261103/docs/BUILD.md)
- [当前功能](Gowin_integrated_20261103/docs/FUNCTIONS.md)
- [维护交接](Gowin_integrated_20261103/docs/AI_HANDOFF.md)
- [项目规则](Gowin_integrated_20261103/AGENTS.md)
- [功能待办](Gowin_integrated_20261103/docs/FEATURE_BACKLOG.md)

提交范围包括RTL、固件源码与初始化ROM、约束、构建/测试工具、Android源码和R3验证报告。工具链、签名密钥、构建缓存、历史归档、个人曲库及比赛报告不纳入源码仓库。位流可由源码构建，本地发布位流不随Git提交。

整理后本地工作区为 `D:\Gowin_Project\Gowin_publish`。旧工程和报告位于上一级；移出的重复副本、历史归档和展示产物保存在上一级 `publish_local_20261106`。

R3已有时序通过记录：50 MHz，最小建立裕量0.016 ns，BSRAM 339/340。完整板级联合仿真和实板验收仍待完成。此次整理未重新构建或烧录。

第三方USB Host许可见工程 `src/usb_midi/LICENSE.third-party.txt`；其他第三方说明随对应目录保留。
