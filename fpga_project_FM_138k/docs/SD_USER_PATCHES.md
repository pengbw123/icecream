# SD 用户音色库

## 使用

1. 使用 FAT32 格式的 SDHC 卡；SDXC 卡须已有 FAT32 分区。本版不支持 exFAT、FAT16、SDSC、GPT。
2. 将卡接电脑，在工程目录运行：

   ```powershell
   python tools/prepare_sd_user_bank.py E:/
   ```

   将 `E:/` 换成卡的盘符。工具只创建根目录 `FMUSER.BIN`（8704 字节），不会格式化卡；已有同名文件时拒绝覆盖。
   也可直接将工程 `assets/sd/FMUSER.BIN` 空白模板复制到卡根目录；已有音色库时先备份，勿用空白模板覆盖。
3. 安全弹出卡，插入板载 microSD 卡槽。进入 PATCH。
4. **STORE SD**：选中用户槽，确认后将当前正在编辑的音色保存到该 SD 槽；成功后同步更新这个 RAM 槽。会显示 `SLOT SAVED + VERIFIED`。
5. **READ SD**：确认后将 SD 的八槽整体读入 RAM。全部检查成功后才替换 RAM 槽；选槽再按 **LOAD RAM** 应用到音源。读取本身不改变当前演奏音色。
6. **STORE RAM / LOAD RAM** 保留原来操作；只 STORE RAM 仍不能掉电保存。已有音色库可在电脑上直接复制备份。

没有卡、格式错误、文件缺失、校验失败都会在 PATCH 标题下面显示错误，不会自动格式化或重建文件。
读写期间触摸菜单暂时等待，RTL 音频、USB 输入和已运行的伴奏继续工作。等待状态结束再拔卡；中途断电恢复不等于对卡内部控制器断电行为的绝对保证。

## 硬件与实现

- 板载卡槽，SPI 模式：CS#=SD_DATA3/K6、CLK=N3、MOSI=SD_CMD/N4、MISO=SD_DATA0/R1，LVCMOS33。
- 引脚来源：开发板资料 `04_引脚功能信息/高云 ACG720-138&60K通用管脚分配表.xlsx`，SD 行。
- `sd_spi_byte.v`：50 MHz 域，模式 0；初始化 200 kHz，后续 5 MHz。MISO 两级同步。
- MMIO `0x26000000`：word0 CS#[0]/fast[1]/abort[2]，word1 busy[0]/RX[15:8]，word2 写字节开始传输。
- UI 软核完成 SDHC 初始化、CMD17/CMD24、CRC16、FAT32 根目录及簇链定位；不增加处理器。
- 支持 MBR 中第一个 0B/0C 分区或无分区表 FAT32 卷、512 字节扇区、每簇 1..128 扇区、活动 FAT 选择、碎片文件。根目录搜索限制为 128 个扇区。
- 只覆写已存在且头部校验通过的文件内容，不分配簇，不写 FAT、目录、FSInfo 或其他文件。首次须用电脑创建库文件。
- 协议参考：[SD Association 简化规范](https://www.sdcard.org/downloads/pls/)，[Analog Devices AN-1443](https://www.analog.com/en/resources/app-notes/an-1443.html)。

## 格式 v1

所有数值小端，文件 17 个 512 字节逻辑扇区：头部一扇区，八个槽各两扇区。

头部：`FMUSER1\0`，offset8/version=1、offset12/slots=8、offset16/payload_bytes=260。offset508 为前508字节的标准 CRC32。

每条记录：offset0=`FMP1`、offset4/u16 version=1、offset6/u16 slot=0..7、offset8/u32 generation、offset12/u32 payload_bytes=260，offset16 为参数快照，offset508 为 CRC32。

参数快照沿用现有 `slot_t`：magic、10字符音色名和结束符、9个全局参数、6×17算子参数、12个 Pitch EG 字，共260字节。保存音源参数，不保存 FX、主音量、配色、ARP/SEQ Pattern。

写入读取两副本，保留最新有效副本，覆写另一份，generation+1，随后整扇区读回比对。读入选择最新有效副本；两份全零表示空槽；两份都损坏则报错，不部分替换 RAM 槽。generation 按32位环绕比较。

## 资源与验证

UI 固件超过原64 KiB，本版指令 ROM 分为64+16 KiB，同步读延迟保持一拍；16 KiB扩展最多需要8块18-Kbit RAM，当前未使用的常量区域会被综合器裁剪，实际占用以构建报告为准。数据 RAM 仍128 KiB。编译改为 `-Oz`。
`firmware.hex` 是128 KiB 数据初始化文件，`firmware_high.hex` 是新增16 KiB指令段；两者必须由同一次构建产生。

验证：`tb_sd_spi_byte.sv` 检查两档 SPI、边沿、字节与 abort；`test_sd_patch_store.c` 运行生产 C 协议及文件系统代码，模型覆盖碎片簇链、多扇区簇、活动 FAT、无分区卷、八槽往返、双副本、写入中断、坏链/坏头/CRC/无卡。实卡读写速度、兼容性与断电行为须上板确认。

```powershell
./sim/run_sd_checks.ps1 -Zig <zig.exe> -IverilogDirectory <iverilog的bin目录>
```
