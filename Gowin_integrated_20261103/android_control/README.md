# 配套Android控制端

源码版本0.7.2，versionCode33。包含MIDI下载与本机曲库、校准管理、蓝牙曲谱上传、灯光手弹以及FM参数编辑。

构建入口为build.ps1，测试入口为test.ps1和test-score.ps1。通过-Toolchain参数或ANDROID_TOOLCHAIN指定JDK/SDK工具链目录。工具链与签名私钥由使用者提供。

本轮整理只调整脚本工具链入口，App业务源码保持原样。构建和安装验证状态见上层README。旧E盘专用的设备UI测试脚本已归档。
