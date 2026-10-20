# 给后续 AI 的工程交接说明

更新时间：2026-10-20（字库/波形修复轮）。目标是让接手者从当前代码和硬件状态继续，不要把计划、候选代码或仿真结果误写成已交付功能。

## 1. 工程位置与当前状态

- 当前工程：`D:\a_My_projects\Gowin_publish\fpga_project_FM_138k`
- Gowin 工程：`fpga_project.gprj`，综合顶层：`top_138k`
- 可复现命令（在工程根目录运行）：

  ```powershell
  & 'D:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' build_cli.tcl
  ```

- 当前可烧录文件：`impl/pnr/fm_138k_rgb.fs`。它是在 2026-10-20 15:48 生成的“像素时钟相位修复”版（见 9.2）。旧位流在 `impl/pnr/backup/`，IDE 工程目录中可能有旧的 `fpga_project.fs`，不要误烧旧文件。
- 提交历史：`31de69e`（字库/波形修复）在当前分支；`590569d` 是修复前工作树快照，标签 `pre-display-fix-20261020`。更早的正式基线是 `2d60072`。工作区已无未提交改动（2026-10-20）。
- 最近一次回归 `sim/run_checks.ps1` 全通过；完整 Gowin 综合、布局布线和位流生成成功。2026-10-20 15:48 报告：50 MHz 主时钟 Fmax 60.443 MHz；33.333 MHz 像素时钟 Fmax 46.535 MHz；两时钟 setup/hold TNS 都为 0。资源：Logic 17683、Register 10401、CLS 13496、BSRAM 116/340、DSP 23.5/298。以 `impl/pnr` 最新报告为准，不要引用旧文档中的旧 Fmax。
- 真实 ACG720 + TFT 屏幕本轮已上板：背光、扫描、触摸、WAVE/XY 均工作，但文字笔画随机丢点；根因是转发像素时钟反相 180°，已于 2026-10-20 修复（9.2）。触摸/显示仍建议继续实板观察。

## 2. 产品目标与用户优先级

目标是以 GW5AT-LV138 为平台的六算子 FM 乐器，重点是音色向 Dexed/DX7 靠拢，同时让作品具备现场可演奏的输入、直观的演奏反馈和设备上的参数操作。

用户反复强调的优先次序：

1. 音色合成质量和演奏稳定性；不得为了界面功能破坏 FM 数值路径。
2. 题目要求的 RTL 视觉反馈（波形、XY/李萨如、电平、琴键/力度等）。显示图形必须是 RTL 实时生成，不依赖软核画帧。
3. 设备上的菜单/音色与效果器编辑；菜单控制可由软核处理，之后希望做专业 FM 合成器式多页参数页面、六算子算法连线图、效果器类型与数值、配色等。
4. 可选的八位数码管状态反馈、效果器等。

曾讨论过的延伸包括滤波、失真、移相、合唱、混响、SD 卡预设保存，以及在138K接串口屏/触摸屏。都不是当前已经完成的功能。用户还希望最终继续做 FM 与 Dexed 源码的差分还原，并明确不想只满足“听起来大致相似”。

用户会要求“继续”时，通常是接着当前工程问题推进，而不是重开项目。已经确认的当前显示目标是修复文字、复杂波形断线、XY起音越界；这三项现在代码已改、仿真与实现通过，等待实屏验证。

## 3. 工程之间的边界

不要把旁边的工程混为一个：

- `fpga_project_FM_138k`：本交接文档对应的138K主工程。
- `../fpga_project_FM`：Primer25K FM工程，里面有 USB-MIDI host 和 FM 算法的历史主线。存在用户未提交的更改；不要从138K随手复制旧版本覆盖。
- `../fpga_midi_bridge_25k`：单独的25K MIDI中转工程，不是原25K主工程。用于接 USB-MIDI 键盘并通过 UART 将 MIDI 事件送到138K。用户明确要求中转板的改动独立，不要直接改原25K工程。
- `../piano1`：Zynq TFT/GT触摸屏参考工程。触摸复位、INT 选地址及GT9147轮询逻辑曾经花较多时间调通。只移植验证过的接触时序/协议，不复制 Zynq 的帧缓冲显示架构到138K。
- 用户给过小梅哥 ACG720 资料目录：`D:\a_files\小梅哥ACG720国产高云FPGA教学开发板资料`。板级约束、例程和引脚定位优先查该资料以及本工程 CST，不要凭相似板卡猜引脚。
- TFT/触控资料：`D:\a_files\xinluheng_TFT_V3.0`，另有历程。用户的屏幕在 Zynq 上曾能显示/触控，所以遇到问题先区分排线、屏幕供电/背光、接口时序和RTL；不要反复仅凭I2C地址确认“触控正常”。

## 4. 总体硬件结构

```text
USB MIDI 键盘
    │ USB Host
独立 Primer25K 中转工程 ──UART 1 Mbaud──> ACG720 138K MIDI 桥接接收
                                              │
电脑串口演奏/配置 115200 ────────────────────┤
屏幕 GT9147/GT911 触摸 ─ RV32I + I2C 控制 ───┤ MIDI事件/菜单状态
                                              ▼
                                16复音 × 6算子 FM 引擎
                                              │ PCM / sample tick
                           ┌──────────────────┴─────────────────┐
                           ▼                                    ▼
                     I2S -> MAX98357                    RTL RGB 800×480
                           │                         波形 / 延迟XY / UI叠加
                       扬声器
                           └──────── WS2812 25键力度灯反馈
```

138K 工程本身没有启用 USB Host：`top_138k` 实例化 `top` 时 `USB_HOST_ENABLED(0)`。MIDI键盘由独立25K中转板处理；138K USB接头/CH340不是 MIDI Host。不要把PC串口助手的115200线路接到两板之间的1 Mbaud输入。

板级连接以 `README.md` 为准：J1 40pin FPC 是 LCD RGB565 与触摸；MAX98357 接 P7-1/2/3（BCLK/LRCLK/DIN = A13/A14/A15）；25K TX 到 P7-4 A16；WS2812 数据 P7-6 A19，建议 74AHCT125 电平转换；公共 GND；S4 为低有效复位。138K 与25K各自供电，仅共地和UART信号，不要互接5V。灯条单独供电并共地。

约束文件是 `src/acg720_rgb.cst` / `.sdc`。RGB像素PLL来自 `src/video_pll.v`，目标约33.333 MHz；当前时序报告已通过。FPC方向、触点朝向、屏幕版本和排线规格属于真实硬件风险，必须按屏幕/板卡资料确认。

## 5. 关键源码地图

### 顶层与音频

- `src/top_138k.v`：138K板级组合。建立复位延时；实例化 MIDI UART 桥、触摸UI、FM顶层、LED和RGB视觉；把监视 PCM、采样tick、当前预设/算法/声部数/算子EG送到显示。
- `src/top.v`：FM/音频共用核心顶层。138K 通过参数关闭USB Host并启用音频专用构建；另有电脑串口、触摸产生的MIDI事件、I2S和监视端口。
- `src/fm_poly_synth.v`：核心 16 复音、六算子 FM 合成器。算法、算子路由、EG/LFO/力度等 DX7 兼容逻辑在此。音色ROM和FM算法改动要参考 `docs/DX7_COMPATIBILITY.md`，不要只听一次或凭截图判断“对齐 Dexed”。
- `src/fm_uart_control.v`：串口参数/音色/事件协议与合成器控制。改协议前要同时核对桌面端编辑器和 MIDI 演奏器，不要破坏现存上位机。
- `src/midi_performance_control.v`：踏板、弯音、调制等演奏控制。
- `src/audio_output_stage.v`、`src/audio_effects.v`、`src/i2s_tx.v`：音频输出与老效果器。**本次138K顶层用 `FM_AUDIO_ONLY(1)`，现阶段为方便音色验证，效果器/附加输出链路旁路。**
- `src/midi_bridge_rx.v`：接25K中转发送的串口MIDI帧；有 `valid/ready` 背压和丢事件计数，顶层要保留流控。
- `src/ws2812_keys.v`：C3起始的25键事件灯。物理按键状态以Note On/Off事件为准，延音踏板的尾音不应让物理键灯一直亮。

### 触摸与设备菜单

- `src/touch_ui_controller.v`：小型 RV32I 软核外壳，负责GT触摸轮询、I2C开漏、UART诊断、菜单控制寄存器、触摸虚拟琴键MIDI事件。它不绘制画面，也不在音频采样路径上运行。
- `src/gt9147_reset.v`：GT9147/GT911上电复位和INT地址选择时序。参考 `piano1` 已验证做法。
- `src/ui_firmware/main.c` + `start.S` + `linker.ld` + `build_firmware.ps1`：软核固件及构建。改了C必须重新运行构建脚本生成 `firmware.hex`，再做FPGA实现。综合仅读hex，不会替你编译C。
- 当前UI是基础演奏/性能菜单：音色±、主音量±、屏幕琴键八度±、PANIC、WAVE/XY、XY延时、AUTO。不是用户要求的专业六算子参数编辑器。
- `touch_ui_controller.v` 有command/text/fx/numeric等准备接口；`top_138k.v` 当前将 `.fx_write()`、`.numeric_display()` 等未集成功能悬空，`rgb_visualizer` 的 `ENABLE_MENU_TEXT=0`。这些端口是扩展预留，不代表功能可用。

软核寄存器细节：UI内存区域大致为 `0x230000xx`，UART诊断为 `0x200000xx`，未来候选FX区为 `0x250000xx`。`ui_state` 位域见 `touch_ui_controller.v`：bit0触摸在线、[11:8]八度、bit12显示模式、[22:16] XY delay、bit31关闭自动视觉增益、[27:24]菜单页。清零/复位默认视觉自动增益开。

### RTL屏幕与视觉

- `src/rgb_visualizer.v`：800×480 RGB565扫描、颜色及文字/琴键叠加。当前没有整屏帧缓存，pixel clock约33.333 MHz；底图、波形、XY轨迹和状态文字在光栅扫描时实时合成。图形反馈必须保留RTL实现。
- `src/audio_wave_scope.v`：以音频 `sample_tick` 收集512点快照，使用整帧峰值确定显示倍率，再把相邻点变成每列纵向范围；解决复杂波形断点。绘图用了两组bank及垂直空白期切换。
- `src/audio_xy_scope.v`：采集512组 `(s[n],s[n-delay])`，使用同一个快照增益缩放X/Y，用Bresenham连接邻点到像素RAM；全快照填好后才在VBlank切换显示bank。这个“李萨如”是单声道延迟XY轨迹，不是立体声XY或FFT频谱。
- `src/rtl_performance_text.v` 与 `src/generated/font8x16.mem`：当前固定性能标签用8×16字形。标题、字段是硬编码位置，当前修复了4×6小字在屏幕上容易乱码/难辨的问题。
- `src/rtl_menu_text.v`：候选多页菜单文本栅格化，**不可直接打开**。之前启用/尝试时字符存储被推成大量FF，导致实现/时序问题。应先改成真正的BSRAM/双口RAM（必要时显式SDPB），再评估资源时序；当前稳定版使用 `ENABLE_MENU_TEXT=0`。
- `src/generated/fm_rom1a_names.mem`：32个ROM1A音色名称。

视觉自动增益规则：自动档 1/2/4…256 倍，根据完整快照选择倍率，且额外留1/8绘图区余量。AUTO关闭时不自动放大，但仍保留余量。它只改变图，不影响PCM、音量或FM。极低底噪也可能被放大；真实电平条读真实PCM。详见 `docs/VISUAL_AUTO_GAIN.md`。

**BRAM推断的关键坑（本轮刚修）**：`samples[index]` 一边异步写、一边同一 always 块无条件读同一个index，Gowin把波形/XY RAM推成 `SP WRITE_MODE=2'b10`，布局布线报 `PA2122 Not support`。现在读口使用独立的 `read_index`，将读写地址分开，从而推为受支持的RAM结构。未来改RAM时不要把读地址重新合并成当前写地址；综合若出现PA2122，先看RAM端口和WRITE_MODE。

### 候选专业功能（尚未交付）

- `src/pro_audio_effects.v`：后置滤波/失真/合唱/混响候选实现，尚未接入 `top_138k` 的有效音频链。
- `src/seg8_status.v`：8位数码管移位驱动候选；尚未顶层接入，也没有完成引脚约束核对。板厂HC595参考引脚记录在 `docs/PRO_UI_WORK_IN_PROGRESS.md`，集成前要查例程/CST确认。
- `src/rtl_menu_text.v`, `src/ui_firmware/pro_tables.h`, `tools/generators/generate_pro_ui.py`：专业菜单准备代码/数据，不是完整功能。
- HDMI已排除当前活动设计。用户现在要求采用板载J1 RGB屏幕。FFT未实现；目前是波形与延迟XY。

## 6. 触摸排查经验（非常重要）

1. “找到GT9147地址0x14/读到芯片ID”只证明I2C有响应，**不证明触点数据在更新**。之前日志多次出现 GT found、配置正确、运行状态全0，但手指按下仍无新帧。
2. 已在独立触摸测试工程证明屏幕控制器可以识别触摸后，才回到琴键工程；根因排查中使用了上电复位/INT选地址、读 `0x814E` ready/status、读取所有触点、最后清状态的流程。
3. 不要在没有资料支持时向GT写猜测配置。曾经写了假配置后，虽然回读表面正确，触摸仍不工作。优先沿用 `piano1` 的复位与I2C访问顺序。
4. 无新触摸帧时应保留按键状态，不要把“没有新数据”解释成所有琴键松开。多点触摸同一音符要做引用/合并，松开一个手指不应让仍被另一个手指按住的同键发Note Off。
5. RGB PLL失锁后，像素域与音频域快照bank所有权都要复位并重新同步；否则可能出现首帧黑屏或读写同一bank。`rgb_visualizer.v` 已有复位同步和恢复路径，修改后保持回归。
6. 真机完全黑屏时先按顺序检查FPC线型/触点朝向/1脚、屏幕供电和BL引脚、时钟/同步/DE、复位。以前曾误以为背光只要接FPC就必然亮，实际不一定；板载调试USB线也不一定能给TFT背光供电。

## 7. 上位机、UART与FPGA交互

- PC板载 CH340：115200 / 8N1。既有串口工具和演奏工具曾出现COM冲突、运动时USB线松动、串口挂起等现象。Windows上同一COM不能同时由两个程序打开；音符和音色参数验证时只留一个客户端。
- 25K到138K桥接 UART：1 Mbaud，独立接收口。桥接数据是MIDI事件，必须遵守 `valid/ready`，不能用PC常规115200设置代替。
- MIDI键盘直接USB接138K不可用；138K Host未启用。当前结构由Primer25K Host做键盘枚举，再串口桥接。
- 更换键盘/控制器时重点核对MIDI channel、Note On velocity=0松键、Note Off、CC64踏板和控制器编号。25键器件的旋钮/滑条映射在历史交谈中约定过，但不是全部都已在本138K菜单里实现。
- UART演奏失败排查从LED/串口逐层确认：中转枚举、MIDI包解析、桥接TX、138K RX、`valid/ready`、音符分配、FM输出、I2S。不要仅凭电脑能连COM口就推断MIDI链通。

## 8. Dexed / DX7音色还原主线

目标是比较数字PCM，不是只调到“像”。目前已做的内容和明确未完成的项都写在 `docs/DX7_COMPATIBILITY.md`；其中包括EG块推进/块内插值、LFO/AMS、反馈历史、固定频率、pitch bend、Portamento和Q精度差异。接手前完整读该文档以及 `../fpga_project_FM/docs/DX7_COMPATIBILITY.md`，两份文件可能因复制/近期修改存在内容时差。

工作原则：

- FM算法核心集中于 `fm_poly_synth.v`。每次算法改动要有一个Dexed固定音色、音高、力度、按住/释放条件的对照；最好做板内PCM捕获或内部信号差分。当前已经有Dexed参考生成/波形分析工具，但**没有完成FPGA对Dexed逐样本PCM的端到端差分**，不允许说“仿真证明百分之百/bit级一致”。
- 仿真正弦查表误差、算法路由一致、Dexed参考音频和 FPGA PCM 是不同验证层级，不可混为一谈。
- 当前138K显示/菜单移植没有改FM数值路径，音频改动应在独立任务和明确证据下做。
- 关闭或恢复效果器前，确认与PCM采集点的位置一致；比较干净FM时在效果器之前取样，比较产品输出时统一效果器状态。

## 9. 本轮显示修复的已知可复现结果

- `sim/run_checks.ps1`：visual gain、XY快照/攻击、波形连续与满幅边界、TMDS、WS2812、UART/MIDI桥、触摸固件I2C、RGB光栅/PLL失锁全部通过。
- RGB模拟预览位于 `tmp/rgb_quiet_preview.png`、`tmp/rgb_wave_preview.png`，仅仿真截图，不是真机照片。
- 本轮加 `read_index` 时修正了Gowin不支持的RAM模式并重新完整实现。不要误引用此前PA2122失败的中间报告。
- 控制台仍会见到一条非致命警告：`rv32i.v` 的 firmware.hex 比指令ROM `[0:16383]` 范围长。不要为消警告直接截断hex；先判定hex布局和存储映射。
- 已修复当前屏幕标题字段长度造成的首字母丢失。
- 工作树变动未提交。当前位流是可重复构建的，但只完成仿真/工具实现，实屏排线和实机交互确认仍待做。

## 9.1 2026-10-20 实板反馈后的字库/波形修复

实机首次给出显示反馈：文字可读但有大量断续杂点；复杂波形有断点；XY 正常。定位结论与改动：

- 旧 `font8x16.mem` 由 12 px TTF 二值化生成，字形只占 16 行单元的上 8 行，细笔画被阈值打碎成孤立像素。新增 `tools/generators/generate_font8x16.py`：Consolas 15 px、二值化阈值 90、基线固定第 12 行，大写高 10 行、笔画约 2 px，只有超宽字形才横向压缩。`generate_pro_ui.py` 已改为调用同一生成器，避免重跑脚本把旧字体写回。
- 波形轨迹原来只有 1 像素宽，而 XY 是 2×2 块，所以在实板上只有波形显得断续。`rgb_visualizer.v` 把每列 span 上下各扩 1 行（最小 3 行），几何连续性和实板可见度都更好。
- `sim/tb_rgb_visualizer.sv` 新增 `+messy` 复合波形，并新增**显示级**断言：按最终 RGB565 波形颜色逐列检查无竖向空洞、相邻列区间必须重叠。`sim/run_checks.ps1` 已加入该用例。
- 回退保障：本轮开始前的工作树已快照为提交 `590569d`，标签 `pre-display-fix-20261020`；旧位流备份在 `impl/pnr/backup/fm_138k_rgb_20261019_2154_before_font_wave.fs`。回退源码用 `git reset --hard pre-display-fix-20261020`。
- 旧文档（ACG720_138K_SUMMARY / 138K_CAPACITY_ROADMAP / XY_VISUAL_UPDATE / 138K_USER_GUIDE 第10节）已加过期注记或更正为最新报告数字。

## 9.2 2026-10-20 文字断笔的真正根因：像素时钟相位

字体改成清晰字型后用户反馈“稍微好点但笔画仍断续”，说明根因不在字库形状。定位过程与结论：

- 仿真中文字/波形完全连续，说明 RTL 绘制和 ROM 内容正确；问题出在“像素数据到屏”这一段，仿真无法反映。
- 本设计用 `ODDR(D0=0,D1=1)` 转发 `lcd_pclk`。查 Gowin GW5A 原语模型 `IDE/simlib/gw5a/prim_sim.v`：`Q0 = CLK ? d0_reg_2 : d1_reg_2`，因此该配置输出的是**反相 180°** 的像素时钟。
- 同板同屏的厂方例程（`小梅哥ACG720.../02_例程源码/GW5AT138K/第28章 TFT显示屏驱动`）PLL 相位为 0，且直接 `assign Disp_PCLK = ClkDisp;`（0°）。数据、DE、同步都在 posedge 寄存。屏在该配置下工作，说明屏在其**另一时钟沿**采样；反相后采样沿正好落在数据翻转处，细笔画（文字、1 像素线）就出现随机丢点。
- 修复：`rgb_visualizer.v` 改为 `assign lcd_pclk = pclk;`（0°，与厂方例程一致），保留 `PIXEL_CLK_INVERT` 参数作为万一需要反相的备选。**除非实板证明 0° 不行，不要改回 ODDR 反相。**
- 顺带修复菜单 ± 图标：原 4×6 点阵竖笔在第 3 格、横笔占满 4 格，放大 3 倍后加号横杠右侧比左侧短 3 像素。现改为直接几何绘制（12 px 横杠、4 px 竖笔居中，左右各 4 px）。

## 10. 安全修改与交付建议

1. 先读本文件、`README.md`、`docs/PRO_UI_WORK_IN_PROGRESS.md`、`docs/138K_USER_GUIDE.md`、`docs/DX7_COMPATIBILITY.md`，再检查当前Git工作树。若文件与本说明冲突，以源码和最新工具报告为准，并回写文档。
2. 不要假定未提交修改属于“垃圾”。不运行 `git clean`、`git reset --hard` 或大范围 checkout。用户之前明确不希望GitHub推送大量MIDI音乐、AIFF音符样本等大文件；提交时只挑与当前变更有关的源码/小型生成ROM/文档。
3. 改软核C后先构建固件，再综合FPGA。改Verilog后先做局部检查，最终报告和.fs必须在同一次当前源码构建中产生。
4. 保留音频采样tick（音频样点域）和50 MHz系统时钟的职责边界。像素域CDC状态要两级同步，跨域整组参数在帧边界锁存。不要让I2C或软核stall音频或视频时序。
5. 新RAM先检查推断类型、读延迟、bank所有权和跨时钟读写模式；报告如有PA2122立即修，不要只看仿真过就交付。
6. 新菜单先做一两个实际可用页面，再接完整参数；检查新增ROM/RAM是真BSRAM而非大规模寄存器。效果器逐项加入并提供真旁路，核对旁路下逐样点音频完全一致。
7. 交付总结区分：RTL/固件已实现、仿真已验证、综合/布局布线通过、烧录上板已验证、仅计划/候选代码。它们是不同状态。

## 11. 推荐下一步

本轮修复后最实用的下一步是：烧录最新 `impl/pnr/fm_138k_rgb.fs`，确认文字笔画是否清晰、复杂波形是否连续；若仍有杂点，用串口日志和屏幕照片判断是字形/绘制问题还是像素采样余量问题（若平底色块也出现杂点，优先怀疑像素时钟相位、FPC 信号完整性和输出驱动强度）。

之后再按 `docs/PRO_UI_WORK_IN_PROGRESS.md` 分阶段启用专业菜单、效果器和数码管。文本RAM需先改为BSRAM结构并评估资源；每次只增加一类功能并重新布局布线。Dexed PCM差分主线继续保留，不要被菜单工作遗忘。

