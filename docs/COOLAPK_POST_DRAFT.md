# 【酷安发帖草稿】一加 13（24G+1TB）手搓 OneUI 9.0（Android 17）主力机日用化全记录 + 开源 v1.1.0 一键套件

> **建议标题**：花一半的钱手搓“S26 Ultra 24G+1TB 6000mAh 特别版”！一加 13 刷 OneUI 9.0 v1.1.0 开源套件发布：三段式开关/旁路直驱供电/WebUI 面板/CSC 动态解密/全三网 VoLTE 短信全修平

---

### 📱 硬件对标（真香时刻）
- **一加 13（PJZ110）**：骁龙 8 Elite + **24GB 内存** + **1TB** + **6000mAh** + 100W 快充 + **OneUI 9.0（Android 17 / 港版 TGY）**
- 同期原版三星旗舰 16G+1TB 卖到 1.2W+ 且只有 5000mAh + 45W，这套刷稳之后简直不要太香。

---

### 🔧 `v1.1.0` 新增一加硬件适配 & 已修平的底层痛点（已全部开源）

1. **物理三段式开关复活 + X 轴马达手感（v1.1.0 新增）**
   - 用事件驱动 `getevent -l` 监听 `oplus,hall_tri_state_key` (`KEY_F3`)，配合 `/proc/tristatekey/tri_state`，实现上静音 / 中震动 / 下响铃无缝切换，**待机 0% CPU 轮询功耗**，切换瞬间触发线性马达震感反馈。

2. **游戏硬件旁路直驱供电 + 充电上限保护（v1.1.0 新增）**
   - 直接接管 `/sys/class/oplus_chg/battery/mmi_charging_enable`，支持一键开启旁路直驱不充电池，以及 `80% / 85% / 90%` 充电阈值 + `5%` 迟滞防抖保护电芯寿命。

3. **KernelSU 原生暗黑 WebUI 控制面板（v1.1.0 新增）**
   - 在 KernelSU 模块页点「打开」就能直观看到电量温度、三段式挡位、旁路直驱开关和各系统补丁激活状态，全部纯离线原生实现。

4. **TGY 港版 OMC CSC 动态解密与功能增强（v1.1.0 新增）**
   - 自己写了解密脚本从本机 `framework.jar` 提取 `SemCscFeature` 的 256B `salts/shifts` 解开 OMC 密文，注入**三星原生通话录音、禁用虚假 eSIM、50Hz 防闪烁、快门音开关、实时网速、最近任务锁定**，直接生成明文 XML 挂载。

5. **彻底根治 60fps 录像黑屏断电 & 相机 9:16 崩溃**
   - 保持 **ColorOS 15.0.0.860（ARB 0 安全底包，绝不碰防回滚分区）** + 配套原厂 `6.6.66` 内核，避免跨版本内核导致的 `CAM-ICP DMI_STATUS` 断电。解锁全部 60fps 开关并将 `4000x2252` 修正为 `3840x2160`，**连续录 60fps 102 分钟（13.06 GB）零重启，稳在 41.8°C**。

6. **根治微信 / OneDrive 等 Kotlin App 秒闪退**
   - 替换一加 `/odm/framework/androidx.camera.extensions.impl.fake.jar` 里的污染 `kotlin-stdlib`，瞬间零闪退。

7. **双实体 SIM 管理器 + 三网短信 + 电信/联通 VoLTE 6 秒断线 + 0.3s CallBridge**
   - 去除虚假 eSIM，自动补齐 `ril.ICC_TYPE0/1`；原位修补 `telephony-common.jar` 与 `imsservice.apk`，实测中国电信纯 VoLTE 短信（`SIP 202 Accepted`）与联通通话全部秒发秒通、稳过 6 秒。

8. **状态栏 + 下拉栏时钟显秒永久常驻（已纳入 v1.1.0 自动化修补器）**
   - 无需 Good Lock，幂等原位修补 `SystemUI.apk` 保持 APK 对齐，`post-fs-data` 挂载重启不掉。

---

### 📦 开源地址（GitHub Actions 自动打包，零版权夹带）
- **GitHub 仓库**：`https://github.com/YANS311/OneUI9-OnePlus13-FixPack`
- 含 **KernelSU v1.1.0 一键模块包（内置 WebUI，Release 直接下载）** + **PC 端一键 ADB 原位修补脚本** + **3 套 Agent Skills** + 完整技术原理。
- 欢迎各位一加 13 刷 OneUI 9 的机友 Star / PR，一起把移植包打磨成完美主力机！
