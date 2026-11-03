# 手势演奏版时序优化（2026-11-02）

原快照`tmp/gesture_performance_build`已生成候选位流，但未通过时序，不能下载：主50MHz域Fmax48.443MHz、Setup TNS -48.168ns/160端点；RGB 33.333MHz域Fmax33.115MHz、TNS -0.197ns/1端点。其它约束时钟通过。正式FS没有替换。

## 本次修改

1. 最差路径为FX输出→切音移位加法增益→波形XY/电平峰值比较。切音树改为两级系统时钟寄存，分离增益计算与下游统计；增加40ns固定数字管线延迟，不增加音频采样周期。32音演示旁路仍为原样直通。
2. 主MIDI入口的一槽寄存缓冲改为仅按是否占用产生ready，消费后空一拍再接受替换，切断ARP/pad分类→上游ACK→曲谱RAM写使能的组合路径。事件仍按valid/ready完整保存，不去重、不丢弃。
3. 合成器已接受事件的监视输出寄存一拍；板级新增`midi_input_observer`，把原始USB/桥接/触屏已接受事件及来源寄存后送练习的按键匹配逻辑。修复报告中lesson enabled→仲裁→大扇出→tutorial next_valid长路径。二者只改变观察延迟，不参与音频ACK。板级延迟测量起点没有后移。
4. FFT幅度近似结果独立寄存，将RAM读出、绝对值/幅度计算、band_max比较分开。对应增加扫描等待状态，频点地址和实际幅度对齐，数学定义及FFT数据不变。
5. RGB键盘的32位`(x*15)/800`和边界除法改为平衡比较树、固定分界点；对全部800个x逐点验证与原表达式完全一致，键宽、颜色、触屏区域不变。
6. 灯带fill_index从32位integer收窄到现有MAP_INDEX_WIDTH（160灯为8位），避免大计数器/动态位选的冗余译码。灯数、地图、颜色与时序参数不变。

时钟约束、固件镜像、6算子/32声部、原32音测试模块、曲谱8192事件容量、摄像头与AI功能均未删改。没有使用降频、放宽约束或增加false path来隐藏失败。

## 验证

已通过切音流水线有符号满幅、增益平滑及32音旁路测试；FFT校准/负满幅/对数频带回归；512频点与32个真实峰值回归；生产FM32 PCM的32独立谱峰和释放回零；真实FM32+FX的手势切音与六音琶音；MIDI各通道/cable及触屏共17次延迟脉冲逐周期等于计数；三个RGB视图和全800像素琴键边界；MIDI观察器来源/空闲/复位；160灯及1灯边界和完整发送；曲谱/练习32项联合回归。日志`tmp/opt_*.log`。

包含手势模块的32声部生产演示`tmp/opt_poly_gesture.log`亦已PASS。所有回归汇总与精简日志归档在`assets/gesture_timing_optimization`。菜单固件及触摸处理本轮未改，沿用前轮真实RV32I/I2C菜单通过记录。

## 构建状态

最新冻结目录`tmp/gesture_performance_timing_build_v2`；`source_manifest.json`记录548个输入。主构建进程47848，后台检查进程4668，脚本`tools/finish_gesture_timing_build.ps1`。

`tmp/gesture_performance_timing_build`是本轮最初综合快照，已在尚未布局布线时终止，以便一起加入已确认的练习按键观察长路径及灯带计数器修复。不要继续等待它，也不要和18:37完成的原失败版混淆。

最新构建仍需实际STA验证。所有专项回归及全部时钟Setup/Hold TNS=0、源码哈希均通过后才另存`impl/pnr/fm_138k_gesture_performance.fs`，结果`background_result.json`/`test_result.json`，正式标准FS保持原版，不自动烧录。
