# AI COMPOSER：互动主旋律，第一阶段

这是独立于AI BASS的主旋律创作模式。现有32复音FM音源负责发声，神经网络在50MHz RTL中运行，软核负责菜单和参数发布。

## 操作

1. PATCH选择希望AI使用的音色。SETUP → AI BASS → COMPOSE >，进入时将音色抓取到BACKING；START开始主旋律。
2. 返回PATCH可另选LIVE音色即兴，AI音色保持。需要重新抓取AI音色时，在COMPOSER SETTINGS按EXIT MODE，再选音色并进入。
3. 中央触摸区域：向上让后续音符趋向高音，向下回落；向右增加起音密度，向左减少。修改影响新音符，不强行移动正在发声的音。
4. THEME开始录入并暂停AI。用底部琴键或外部MIDI键盘输入1～8个音，再按THEME结束输入，START演奏。空主题会在START时恢复内置C-E-G-E。
5. VARIATION改变允许位置的音程选择；REPEAT在本轮四小节完成后复播一遍；CONTRAST让接下来的一小节更跳跃；NEW重新开始生成。
6. LOCK在本轮四小节生成完整后锁定并循环。音高、力度、节奏都按记录复播，BPM可调；XY、调性和形式的变化在解锁后影响新生成内容。
7. END等待当前四小节的最后一拍，奏出主音后释放门控并停止。STOP直接停止，已锁定乐句可用START继续；EXIT MODE同时释放模式所有权并恢复原滑音开关。

形式有LONG PHRASE、SHORT NOTES、PENTATONIC；可设置BPM30～240、KEY、大小调、VARIATION和STRENGTH。主音量和FX仍由现有全局控制。

乐句结构是两小节主题、一小节对比、一小节回归。主题锚点、音阶约束、方向/疏密映射、重复与收尾是明确的RTL规则；模型选择局部起音、音程、时长和力度，不宣称所有结构由网络自行学得。

## 打击垫和节奏

SETTINGS → LEARN 8 PADS，依次敲8个不同的打击垫。记录音符和MIDI通道，依序分配：

| 垫 | 功能 |
|---|---|
| 1 | START/STOP |
| 2 | VARIATION |
| 3 | REPEAT |
| 4 | CONTRAST |
| 5 | END |
| 6 | LOCK/UNLOCK |
| 7 | REC RHYTHM |
| 8 | CLEAR RHYTHM |

默认MIDI通道10，音符依次36、38、42、46、49、51、45、41；推荐实际使用前执行学习。
若键盘和打击垫使用同一通道及同一音符，MIDI事件本身无法区分，宜把垫设置为通道10。

REC RHYTHM有一小节预备拍，之后录两小节。期间敲任一打击垫，或点屏幕TAP，起音量化到十六分音符；垫的普通控制功能临时停用。
录制结束后保留32格节奏。若之前正在演奏，则恢复演奏；否则按START。没有敲击时不锁定空节奏。
RHYTHM LOCKED时严格使用录入的起音位置，XY横向疏密暂由该节奏覆盖；CLEAR RHYTHM恢复自由节奏。

主旋律音域限定为MIDI48～84，主题会映射到该范围和所选音阶。

第一阶段的数据均为易失状态。学习映射、主题、锁定乐句、节奏在断电后恢复默认；最近八小节回听、撤销和SD乐句保存属于第二阶段，不使用现有音色文件冒充乐句文件。

与AI BASS、ARP、SEQ、PRACTICE共用BACKING，启动这些模式会退出COMPOSER。总复音仍为32，手动LIVE与AI可同时发声。

## 训练与模型

- 原始资料为已有固定版本的POP909下载，使用实际MELODY轨。清单和许可在`assets/ai/POP909_subset_manifest.json`及`assets/ai/POP909_LICENSE.txt`。
- 按歌曲划分训练、验证、测试；种子720138，35轮，Python/NumPy在电脑CPU训练，板上不训练。
- 128→48→36，7872个INT8权重，84个INT32偏置，两个时序层共享MAC。模型仅在新十六分拍点需要生成时运行。
- 有效模型输入：拍点与小节位置、最近两小节音高历史/近期起音状态、给定最多8音主题、KEY/形式/方向/密度、上一音等。
- 节奏锁定、对比和变化量由RTL规则处理。未训练的节奏/对比输入权重导出为零；训练中恒定的变化量64精确折入偏置，防止手势触发随机初始化权重。128个实际数据向量的输出逐位保持一致，见assets/ai/composer_export_validation.json。
- 四头：REST/HOLD/ATTACK；-12～+12半音音程；1/2/4/8个十六分音符门控；48/72/96/120力度。
- 数据预处理以首个支持的和弦作为调性提示，将旋律映射到对应音阶并增强五声音阶形式；这不等于准确还原每首原曲的真实全局调性。
- 给定主题来自训练片段的前8个起音，作为用户已经提供的条件；历史只使用当前拍点之前的事件。密度和方向条件由片段统计生成。
- 测试为teacher-forced下一步指标，不能当作连续生成的主观音质。实际闭环MIDI差异、无挂音、乐句重复、完整音频与实机试听需要分别检查。

源码：`tools/ai_composer/train.py`、`composer_model.py`；RTL：`src/ai_melody_inference.v`、`src/ai_melody_composer.v`。
权重、测试向量和完整指标在`src/generated/ai_composer/`，训练日志保存在`assets/ai/composer_training.log`。

```powershell
python tools/ai_composer/train.py --epochs 35
python tools/ai_composer/check_export.py
# 运行sim/run_checks.ps1中的melody测试；不要只凭训练指标发布硬件。
python tools/ai_composer/demo.py
```

## 接口与未来传感器

普通0x6A辅助命令可以发布同一组参数，未来IMU或摄像头无需改写音符调度器。

| 辅助地址 | 内容 |
|---|---|
| 3C0 | bit0模式所有权；原子提交3C1/2周期影子，重复写入不重启 |
| 3C1/3C2 | 十六分音符微秒周期低/高16位 |
| 3C3 | KEY[3:0]、minor4、form[6:5] |
| 3C4 | density[6:0]、direction[14:8]，中心64 |
| 3C5 | 一次性动作：1切换播放、2开始、3停止、4变奏、5重复、6对比、7收尾、8锁定、9主题录入、10录节奏、11清节奏、12学习垫、13默认主题、14重新生成 |
| 3C6 | variation[6:0]、strength[14:8] |

UI[61]：session0、running1、活动/待发MIDI2、网络/构建busy3、themeREC4、rhythmREC5、padLEARN6、locked7、lockPending8、ending9、rhythmValid10、panic11、seedCount[15:12]、step[21:16]（录节奏时为预备/录入拍点）、note[28:22]、learnIndex[31:29]。
UI[62]：misses[15:0]、density[22:16]、direction[29:23]、录音状态[31:30]（0无，1预备，2录入）。
全局CC120/123会停机；START可在清理后重新启动。停止/重新启动用8位生成编号丢弃旧推理结果，输出握手受背压时保持数据稳定。

## UI存储安排

仍为80KiB指令ROM及96KiB数据RAM。既有CPU的两个物理存储独立，数据口仅译码低17位：BSS放到0x10020000别名，物理上复用数据RAM内原指令副本的低地址区；不会写到独立指令ROM。
只读常量和初始化数据仍在主窗口高处，栈从0x10018000向下增长。链接器和`tools/check_ui_layout.py`检查BSS不覆盖常量、镜像不超80KiB、栈仍至少12KiB。
不是扩充RAM，也没有关闭原有栈检查。地址别名属于有意使用的既有硬件行为，修改软核地址译码或内存模型时必须保留这一约定或同步改回布局。

## 五阶段进度

| 阶段 | 范围 | 状态 |
|---|---|---|
| 1 | 触屏旋律雕刻、主题、变奏/重复/对比/收尾、打击垫与节奏输入 | 实现与针对性仿真中；物理发布待验收 |
| 2 | 最近八小节、回听、撤销、保存 | 待做 |
| 3 | IMU动作输入 | 待做 |
| 4 | 摄像头标记追踪，再增加自然手势 | 待做 |
| 5 | 增加低音/和声声部 | 待做 |

完整位流需要65文件清单和四时钟域setup/hold验收。当前标准位流仍为AI BASS V2，尚未自动烧录COMPOSER。
