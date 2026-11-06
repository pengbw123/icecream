# 构建与验证

所有命令从 `fpga_project_FM_138k` 目录运行。Gowin版本基线为V1.9.12.03，器件GW5AT-LV138PG484AC1/I0版本B。将Gowin IDE/bin、Python3、Icarus加入PATH，或显式传入工具路径。

## FPGA

```powershell
gw_sh build_cli_hdmi.tcl
```

RGB单屏替代入口为 `gw_sh build_cli.tcl`。默认工程使用CH376直接输入MIDI。

输出在工程自己的 `impl/` 中。HDMI位流名为 `fm_138k_rgb_hdmi.fs`。脚本在构建后运行 `tools/check_timing.py`，全部约束时钟的频率、建立和保持检查必须通过。输出位流后继续检查脚本退出码和日志。

若仅检查既有报告，可运行 `python tools/check_timing.py fm_138k_rgb_hdmi`。

## 菜单固件

```powershell
powershell -ExecutionPolicy Bypass -File src/ui_firmware/build_firmware.ps1 -Zig <zig.exe路径>
python tools/check_ui_layout.py
```

固件由 `main.c`、菜单头文件、`start.S` 和 `linker.ld` 生成。`firmware.hex` 与 `firmware_high.hex` 是FPGA初始化所需资源，应一起保留。重新生成固件后需要重新综合。

## 仿真

```powershell
python tools/check_code_integration.py --iverilog-dir <Icarus的bin路径> --gowin-simlib <Gowin的IDE/simlib/gw5a/prim_sim.v>
```

日志与结果在工程 `verification/code_integration/`。`--extended` 增加真实CPU读写及完整板级联合夹具。完整板级夹具仍需完成验证，不能用历史记录代替本次运行结果。

灰度模块回归可从 `sim/run_gray_checks.ps1` 启动，临时产物位于工程 `tmp/`。模型生成工具的Python依赖见 `tools/requirements.txt`。

## App

App构建脚本接受 `-Toolchain <工具链目录>`，也可通过环境变量ANDROID_TOOLCHAIN提供。目录应包含JDK与Android SDK。签名密钥与工具链需由使用者提供。源码版本为0.7.2，versionCode为33。

```powershell
cd ../android_control
./build.ps1 -Toolchain <工具链目录>
./test.ps1 -Toolchain <工具链目录>
./test-score.ps1 -Toolchain <工具链目录>
```

App构建输出在其 `build/` 和 `outputs/` 下。原工具链生成的签名应继续用于覆盖升级。

## IDE层次显示设置

`impl/fpga_project_process_config.json` 保存本工程的IDE配置，应随工程保留。顶层为 `top_138k_hdmi`，语言标准为SystemVerilog 2017，CPU与SSPI作为GPIO开启。CLI与IDE设置需对齐。`impl/temp/` 为可重建的解析缓存，Hierarchy的Update可刷新层次。
