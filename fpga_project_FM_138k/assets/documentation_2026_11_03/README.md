# 作品报告r7的工程证据

2026年11月3日从11月2日已完成的40Pin候选冻结构建复制，未重新运行综合或布局布线。原始文件未修改，各文件SHA256见`archive_sha256.json`。

- `fm_138k_rgb_hdmi.rpt.txt`：原始PnR资源报告，80559 Logic、45530 Register、337 BSRAM、87 DSP。
- `fm_138k_rgb_hdmi_tr_content.html`：原始静态时序内容报告，打开HTML可查看时钟关系及路径。
- `source_manifest.json`：548项冻结输入哈希，文档修改后逐项比对当前输入一致；不是另一次Git提交。
- `background_result.json` / `test_result.json`：完成收据，构建和回归PASS；工具未自动烧录。
- `acg720_rgb_hdmi.cst` / `.sdc`：该构建约束副本，不供修改后直接覆盖生产约束。
- `opt_*.log`：原回归日志，覆盖32声PCM、数字起音、入口握手、RGB显示、输入观察、FFT及灯带/练习边界。它们是仿真证据，不是现场波形或无线实测。

位流SHA256为`97A853217B176CC843B84EB1C58901323496DCD4F7C3BDD1066EDB67D99F6773`，位流本体未重复复制到此目录。临时目录保存完整冻结源树，本目录保存报告引用的持久证据。完整源码交付仍须同时保留源树或其正式Git提交，只有哈希清单不能重建源码。
