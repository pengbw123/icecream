# 2026-10-31 AI 菜单入口优化

SETUP 底部同一行从左到右：METERS、AI BACKING（AI 伴奏）、AI MELODY（AI 旋律）、GLIDE MS。三个入口均为176×48像素，滑音时间占同尺寸参数框。原琶音器、音序器及其他设置位置不变。当前字库为英文，因此按钮使用对应英文名称。

AI MELODY 可以从 SETUP 直接进入；AI BACKING 页原 COMPOSE 跳转改名 AI MELODY，作为同级功能的快捷跳转保留。PLAY 页运行状态同步使用新名称。

旋律操作页右侧直接提供232×32像素 GESTURES 按钮，不必先到 SETTINGS；手势页右上角 SURFACE 直接回到操作面。参数页原手势入口仍可使用。EXIT MODE 停止旋律、解除手势控制，返回 SETUP；仅切换顶栏页面仍维持原来的播放行为。

修复导航触摸落入新页面钢琴区域的问题：切页时记录仍按住的 Goodix ID，这些触点在抬起前不能生成琴键事件；独立的新触点仍可演奏。有效空触摸帧释放屏蔽位，I2C 失联恢复也清理该状态。页面切换依旧释放原触屏音符，不改变外部 MIDI 或背景声部的音符归属。

固件81052/81920字节，BSS10808字节。新增入口不增加 RTL 模块、字库、屏幕缓冲或软核规格。完整位流资源和时序以发布记录为准。

复现：先运行 src/ui_firmware/build_firmware.ps1 编译固件，再运行 sim/run_ai_menu_checks.ps1（可传 -IverilogDirectory）。五项真实 RV32I/I2C 回归分别覆盖直接旋律/手势导航和零意外琴键音符、伴奏播放与互斥、旋律主题/节奏录制及退出、滑音时间、全宽琴键/力度/输出选择。

发布状态：完整构建、五项固件回归及全部约束时钟时序验收通过，标准下载文件已更新，未自动烧录。详细记录见 releases/2026-10-31_ai_navigation.json。

## 2026-10-31 AI菜单入口优化（当前下载版）

- 编译源码`36f63ca`；位流北京时间`2026-10-31T00:36:02.305729+08:00`，SHA256 `4F369D5142FAD66536DC8BAAE0B36713AF82540DC23844F73B04174FF183A688`。标准`impl/pnr/fm_138k_rgb_hdmi.fs`已更新，未自动烧录。
- SETUP并列AI BACKING（AI伴奏）与AI MELODY（AI旋律），不必先进入伴奏才能到旋律。旋律操作面直接进入GESTURES，手势页SURFACE直接返回操作面，EXIT MODE回SETUP。入口176×48，实固件800×480预览见assets/ai_menu_navigation/setup_800x480.png。
- 修复按住导航按钮后，新页面钢琴区域误发音：切页触点抬起前不参与琴键映射。外部MIDI不受此触屏状态影响。
- 五项真实RV32I/I2C回归通过：直接旋律/手势导航且零意外琴键音符、AI伴奏、旋律主题/节奏录制、滑音时间、全宽琴键/力度/输出选择。固件81052/81920字节，BSS10808字节。
- RTL、模型、摄像头配置和时序约束与上一灰度版逐文件核对相同；本轮继承灰度CNN回归及局限，不重复声称新的模型准确率或实机验收。RECOGNITION和CONTROL仍默认关闭。
- 完整布局布线通过，全部约束时钟setup/hold TNS为0；逻辑69601/138240、寄存器39089/139095、BSRAM329/340、DSP83/298。
- 说明AI_MENU_NAVIGATION.md；发布记录releases/2026-10-31_ai_navigation.json；回退`impl\pnr\backup\fm_138k_rgb_hdmi_2026-10-31_pre_ai_navigation.fs`。
