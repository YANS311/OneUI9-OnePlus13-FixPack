# 【酷安发帖草稿】一加 13（24G+1TB）手搓 OneUI 9.0（Android 17）主力机日用化全记录 + 开源一键修复包

> **建议标题**：花一半的钱手搓“S26 Ultra 24G+1TB 6000mAh 特别版”！一加 13 刷 OneUI 9.0 彻底修平微信闪退/双卡/发短信/电信联通通话/60fps 录像，附开源模块

---

### 📱 硬件对标（真香时刻）
- **一加 13（PJZ110）**：骁龙 8 Elite + **24GB 内存** + **1TB** + **6000mAh** + 100W 快充 + **OneUI 9.0（Android 17 / 港版 TGY）**
- 同期原版三星旗舰 16G+1TB 卖到 1.2W+ 且只有 5000mAh + 45W，这套刷稳之后简直不要太香。

---

### 🔧 实测踩坑 & 我们顺手修平的 7 个底层问题（已全部开源）

1. **彻底根治 60fps 录像黑屏断电**
   - 保持 **ColorOS 15.0.0.860（ARB 0 安全底包，绝不碰防回滚分区）** + 配套原厂 `6.6.66` 内核，避免跨版本内核导致的 `CAM-ICP DMI_STATUS` 硬件级断电。
   - **极限实测**：解锁三星原生相机全部 60fps 档位后，**连续不间断录制 102 分钟（单文件 13.06 GB），全程零死机、零重启、电池温度稳在 41.8°C**！

2. **根治微信 / OneDrive 等 Kotlin App 秒闪退**
   - 解压微信崩溃快照抓到真凶：一加底包 `/odm/framework/androidx.camera.extensions.impl.fake.jar` 里打进了一整套未混淆的 `kotlin-stdlib`，覆盖了微信混淆后的 `kotlin.coroutines.Continuation`。
   - 用三星纯净的 `/system/framework/sec_camerax_impl.jar` 挂载覆盖，瞬间零闪退。

3. **修复 SIM 管理器隐藏卡 2 & 虚假 eSIM**
   - 去除 S26 Ultra 的 `euicc` / `euicc.mep` 特性声明与 `floating_feature.xml` 里的 `tsds2`，自动补齐 `ril.ICC_TYPE0/1`，双实体卡（电信 5G + 联通 5G）完整显示、自由切换。

4. **彻底修好三网双卡发短信**
   - 反编译 `telephony-common.jar` 发现 `GsmSMSDispatcher.sendSms()` 仍在调本机不存在的 `ISehRadioMessaging`（导致 `RADIO_NOT_AVAILABLE`），且 `ImsSmsDispatcher.isAvailable()` 卡在 `mIsSmsOverImsOnly` 导致中国电信纯 VoLTE 发不出短信。
   - 原位修补后，**电信 IMS 短信（`SIP 202 Accepted`）与联通短信全部秒发秒回、0 报错**。

5. **补齐电信 / 联通 VoLTE 6 秒断线修复**
   - 拆开 `imsservice.apk` 发现作者只修了中国移动的 `dbr_timer=0` 和 `use_precondition=false`，漏掉了电信（`CTC_CN`）和联通（`CU_CN`）。补齐后双卡 VoLTE 通话稳稳超过 6 秒不掉线，同时把 `callbridge_auto.sh` 轮询从 `1.0s` 提到 `0.3s`，接听起音快 3 倍。

6. **修复三星相机 9:16 闪光灯连拍崩溃**
   - 原包 `camera-feature.xml` 写了 S26 Ultra 的 `4000x2252`，一加 13 LYT-808 HAL 不支持，改为原生三流支持的 `3840x2160` 即可。

7. **状态栏 + 下拉栏时钟显秒永久常驻**
   - 无需 Good Lock，开机 `post-fs-data` 挂载生效，重启不掉。

---

### 📦 开源地址（GitHub Actions 自动打包，零版权夹带）
- **GitHub 仓库**：`https://github.com/YANS311/OneUI9-OnePlus13-FixPack`
- 含 **KernelSU 一键模块包（Release 直接下载）** + **PC 端一键 ADB 原位修补脚本** + 完整技术原理。
- 欢迎各位一加 13 刷 OneUI 9 的机友 Star / PR，一起把移植包打磨成完美主力机！
