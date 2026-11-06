# 高云 ACG720 实时多音色电子乐器

当前维护入口为本目录。整理日期为2026年11月6日。

## 打开工程

在 Gowin Designer 打开 `fpga_project_FM_138k/fpga_project.gprj`，顶层为 `top_138k_hdmi`，器件为 GW5AT-LV138PG484AC1/I0，版本B。

本目录已同步2026年11月4日通过时序的R3源码，包括手势表情寄存、CNN乘法流水级、琶音器控制寄存及校准提示计数器优化。功能源码按字节与通过版核对。

## 目录

- `fpga_project_FM_138k/src/` 包含RTL、菜单C固件、约束、IP和ROM资源。
- `fpga_project_FM_138k/tools/` 包含构建检查、资源生成、模型训练和音色工具。
- `fpga_project_FM_138k/sim/` 包含模块和联合仿真。
- `android_control/` 包含配套App 0.7.2源码、资源与测试。
- `pc_control/` 包含PC协议参考。
- `scores/` 包含演示曲谱。
- `docs/` 包含构建、功能与交接说明。
- `releases/r3_20261104/` 保留R3时序报告、资源报告与源码SHA256清单；位流仅在本地保留，不随Git提交。
- 展示产物已移至仓库外 `../publish_local_20261106/Gowin_integrated_20261103_output/`（相对仓库根目录）。
- 历史归档已移至仓库外 `../publish_local_20261106/Gowin_integrated_20261103_archive/`（相对仓库根目录）。

## 验证状态

R3主时钟要求50 MHz，报告Fmax为50.039 MHz，最小建立裕量0.016 ns。全部有数据路径的约束时钟建立/保持TNS为0。camera_xclk_24m由工具报告无数据时序路径。逻辑资源85225/138240，寄存器47956/138240，BSRAM为339/340。

15项工程检查通过。灰度CNN的552张测试图、2208个输出分数逐位一致，固定推理35909周期。完整板级App/USB/灯带联合仿真和R3实板验收仍待完成。时序裕量较小，后续代码修改应重新构建。

构建操作见 `docs/BUILD.md`，功能入口见 `docs/FUNCTIONS.md`，后续事项见 `docs/AI_HANDOFF.md`。
