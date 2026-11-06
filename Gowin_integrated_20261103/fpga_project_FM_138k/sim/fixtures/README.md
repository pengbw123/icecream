# Android 曲谱上传字节夹具

`android_truth_part2_words.mem` 来自队友同一提交的 MIDI `the_truth_that_you_leave_part2.mid`，通过 `android_control/tests/ScoreFixture.java` 和实际 `Score.fromMidi/uploadFrames` 导出，共 1574 个音符事件、1577 帧。每行 12 字节按整数小端存放，UART 测试从低字节发送，线上首字节为 A5，第二字节为 5A。它不是音频或模型权重。

MIDI SHA256：`88d9f4b77672ae3b548b3dd624fddcdf976414a4078c61072b62150a0206eb57`

MEM SHA256：`8d1f090246413aba120820bd6706021e51dc5fb9398efee15dd124f883bbc2a0`

重新生成：先按 Android `test-score.ps1 -JdkDirectory <JDK目录>` 编译测试类，再运行 `com.gowin.instrument.ScoreFixture <输出目录> <该MIDI路径>`。把导出的 `.hex` 每行用 `bytes.fromhex(line)[::-1].hex()` 转换为 MEM 行；不能直接把以 A55A 开头的线上字节串作为 `$readmemh` 整数，否则字节顺序反转。

`sim/run_bluetooth_score.ps1` 自动跑完整 1574 事件加速字节链路，以及实际 50MHz/115200（每位434时钟）的32事件窗口压力测试。两者检查回包、每个 RAM 事件、坏 CRC 和漏包拒绝；播放与容量边界由其他用例覆盖。该夹具不代表 BLE 无线链路已经实测。
