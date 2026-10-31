# 测试曲谱来源（2026-10-09）

## Mutopia 两首

本次核对两作品页面均明确标注 Public Domain。保留原 MIDI/PDF，可用来测试和核对乐谱；APP 内置 MIDI 与下载文件逐字节一致。

| 文件 | 页面与下载 | 维护者 | APP转换结果 |
|---|---|---|---|
| mutopia/ode_to_joy.mid / .pdf | [欢乐颂 ID528](https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=528)，[MIDI](https://www.mutopiaproject.org/ftp/BeethovenLv/ode/ode.mid)，[A4 PDF](https://www.mutopiaproject.org/ftp/BeethovenLv/ode/ode-a4.pdf) | Peter Chubb | SATB四部合声，468音符事件、38.4秒、峰值4音 |
| mutopia/fur_elise.mid / .pdf | [致爱丽丝 ID931](https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=931)，[MIDI](https://www.mutopiaproject.org/ftp/BeethovenLv/WoO59/fur_Elise_WoO59/fur_Elise_WoO59.mid)，[A4 PDF](https://www.mutopiaproject.org/ftp/BeethovenLv/WoO59/fur_Elise_WoO59/fur_Elise_WoO59-a4.pdf) | Stelios Samelis | 钢琴，1798音符事件、130.417秒、峰值6音 |

原 MIDI SHA256：

- ode_to_joy.mid：FB1604C08C865B275B464D74E5A7C526FF1A8ACCCDF9853CB92F0778DAAED14B
- fur_elise.mid：1C12C21C7BBF4CF163896732672648A69D497636059837ABD153C71ABE50215A

## 晴天旋律本地测试

用户授权用于本机程序测试。来源 [TwilightLemon/SunnyDays](https://github.com/TwilightLemon/SunnyDays)，下载日2026-10-09，保留四个参考文件在 sunny_reference；未发现明确LICENSE，本次未对外发布，不能把GitHub公开当成通用再发行许可。

convert_sunny_reference.py 从 Voice.cpp 的旋律数据和 MIDIHelper 音符映射转换为 sunny_melody_test.mid：省去开头13.1秒等待，速度按原等待时间解释，90%门限生成松键、力度80。不包含伴奏，未保证是完整或准确的商业出版谱；APP 标注“社区旋律测试”。结果686事件、149.941秒、单音。

转换结果 SHA256：E47D713AF800059995D31E65D7DB0BE38AA4CA447266E04F05C2880BE0F886FC。

## 共用处理

Score.java 读取 SMF0/1 PPQ、速度事件及音符，延音CC64转成音符时长，同音跨通道合并，忽略鼓轨和程序号，使用FPGA现有音色。最大2048事件、8个逻辑同时音符；超过上限会拒绝，不能自动把不兼容的曲谱当成可播放。
