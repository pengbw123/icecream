# E盘便携编译环境记录

2026-10-08：用户同意下载便携JDK和Google Android SDK，接受SDK许可；明确要求不安装C盘。本次所有下载、解压、构建临时目录、产物和调试密钥在E盘，不修改系统PATH、用户JAVA_HOME，不安装模拟器/Android Studio。

工具位置：`E:\gaoyun111111\android_toolchain`（Git忽略）。

| 内容 | 官方下载源 | 已验证校验值 |
| --- | --- | --- |
| Microsoft OpenJDK 17.0.20.1 Windows x64 ZIP | Microsoft Learn链接到`aka.ms/download-jdk/microsoft-jdk-17.0.20.1-windows-x64.zip` | 与对应官方`.sha256sum.txt`一致 |
| Android SDK Platform35 revision2 | `https://dl.google.com/android/repository/platform-35_r02.zip` | SHA1 `0bb560a90a7a2cbd0dd8348224d518b638fe7949` |
| Android SDK Build Tools35.0.0 Windows | `https://dl.google.com/android/repository/build-tools_r35_windows.zip` | SHA1 `af059bb67cf7786f45ee0db85e2d24985df1b4b6` |

SDK校验值来自Google官方`repository2-1.xml`，下载副本及JDK校验文件保留在工具链downloads目录。最初Adoptium/GitHub下载停滞，未使用该不完整包，改用Microsoft官方便携ZIP并校验成功。

SDK归档原始文件夹名：`sdk/platforms/android-35`、`sdk/build-tools/android-15`（后者归档目录名不是API兼容版本）。JDK在`jdk/jdk-17.0.20.1+1`。

构建直接使用Java和SDK工具，避免Gradle在用户C盘生成默认缓存；Java临时目录指向E盘工具链tmp，Android用户目录指向android-home。Android运行时APP本身安装到手机，不会安装到电脑系统。

调试签名密钥是本机生成的非发行用途密钥，路径`signing/instrument-debug.jks`。密码采用标准Android调试密码；不应用于正式发行。保存这个文件便于以后APK覆盖升级，不上传Git。

参考：[Microsoft官方JDK下载](https://learn.microsoft.com/en-us/java/openjdk/download)、[Google SDK条款](https://developer.android.com/studio/terms)。
