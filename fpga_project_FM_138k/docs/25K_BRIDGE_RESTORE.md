# 2026-11-02 恢复 25K MIDI 中转

键盘连接 Primer25K Dock USB-A，25K 解析 USB MIDI 后以专用 1 Mbaud / 8N1 串口发送给 138K。138K 的 RGB+HDMI 和单 RGB 顶层默认 `LEGACY_BRIDGE_ENABLED=1`、`CH376_ENABLED=0`，CH376 SPI 引脚保持空闲，不再作为默认键盘入口。PC CH340 控制、蓝牙、触屏、效果器、AI、摄像头以及新增复音可视化等功能保留。

## 接线

先断电接线，两板 GPIO 使用 3.3V 电平。

| 起点 | 终点 | 用途 |
| --- | --- | --- |
| MIDI 键盘 USB 线 | Primer25K Dock USB-A | 键盘输入 |
| Primer25K Dock J3-15，FPGA F1 | ACG720-138K P7-4，FPGA A16 | 1 Mbaud 专用 MIDI 事件 TX → RX |
| Primer25K 标注 GND 的引脚 | ACG720-138K P7-12，GND | 两板公共地 |

两板分别可靠供电，不互接两板 5V；不需要反向 UART 线。25K 的 C3 是 115200 调试 TX，不能替代 F1。CH376 模块可断开。已有屏幕、音频、摄像头、SD 等接线不变。

## 下载文件

- 25K：`../fpga_midi_bridge_25k/impl/pnr/midi_bridge_25k.fs`。沿用 2026-10-23 21:51 的桥接位流，SHA256 `1F9E610D25C44E7509FB1B18A60217B0FA0B741D80AA68A1563EB3B6C1689A6F`。通道0力度在25K按原始0–80映射到0–127，138K接收不重复缩放。
- 138K：本次构建完成并通过时序后，发布 `impl/pnr/fm_138k_25k_bridge.fs`，同时备份旧文件并更新标准 `impl/pnr/fm_138k_rgb_hdmi.fs`。构建未完成前标准文件仍是旧版，不应提前下载当作新版本。

25K 选择 GW5A-LV25MG121NC1/I0，138K 选择 GW5AT-LV138PG484AC1/I0。可先 SRAM 下载联调，确认后再固化。没有自动烧录。

## 验证与构建

`sim/run_midi_ingress_checks.ps1` 已通过真实 UART 发射/接收→板级仲裁→队列→曲谱仲裁→生产 top / FM32 / 效果器链路：一条 NoteOn 一个声部、触屏一个声部、两个通道的 NoteOn 两个声部。协议回归覆盖弯音、CC、背压和半帧超时恢复。不能将仿真通过当作实板已经验收。

冻结构建目录 `tmp/bridge25k_restore_build`，进程号见 `build.pid`，日志 `build.log`，源码清单 `source_manifest.json`。构建已于16:23完成，全部约束时钟 setup/hold TNS=0。原后台发布脚本在哈希校验阶段失败，标准位流未替换。用户随后明确要求本次不发布，MIDI排查已终止。

修复后的脚本为 `tools/finish_bridge25k_build.ps1`；临时入口 `tmp/finish_bridge25k_build.ps1` 转调它。默认只校验完成标记、冻结源码、当前源码和位流哈希，输出 `validation_result.json`，不复制位流；只有显式 `-Publish` 才备份并发布。构建未完成时立即拒绝，不再隐式等待或续发。当前没有后台发布任务。

出错原因已复现：PowerShell 7 使用 Start-Process 启动 Windows PowerShell 5.1 时继承了混合模块路径，子进程可调用 ConvertFrom-Json，但找不到 Get-FileHash；显式加载5.1自带Utility模块可恢复。正式修复使用.NET流式SHA-256并释放流和算法对象，不依赖该命令。验证模式使用独立记录，不覆盖历史失败记录；发布异常记录区分是否尝试或已经替换正式文件。

`tools/test_finish_bridge25k_build.ps1` 在同一5.1后台启动方式下通过临时目录测试：默认不发布、沙盒发布和旧版备份、时序失败拒绝、冻结/当前源码改变拒绝。对真实构建仅运行了默认校验，415个清单文件通过，构建位流SHA256 `4B1A141826AD37A10A79F3E133E81196CD28E0952CA4A7026ED77C2A2E36CFF3`。正式位流和原失败记录哈希均保持不变。测试日志 `tmp/publish_script_tests.log`、`tmp/publish_real_validate.log`。

本次启动的是 RGB+HDMI 正式版综合布局布线，普通菜单固件，不是 MIDI probe 诊断菜单。先前 CH376 诊断构建已取消，双发根因未确认；恢复 25K 是切换已存在的输入路径，不能据此宣称 CH376 故障已修复。
