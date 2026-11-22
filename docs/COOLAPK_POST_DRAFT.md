# 【酷安发帖草稿】一加 13（24G+1TB）手搓 OneUI 9.0（Android 17）主力机日用化全记录 + 开源 v1.2.1 一键套件

> **建议标题**：花一半的钱手搓“S26 Ultra 24G+1TB 6000mAh 特别版”！一加 13 刷 OneUI 9.0 v1.2.1 开源套件发布：防 Root/BL 检测隐蔽挂载＋体检面板＋三段式开关＋旁路直驱＋全三网 VoLTE 短信全修平

---

### 📱 硬件对标（真香时刻）
- **一加 13（PJZ110）**：骁龙 8 Elite + **24GB 内存** + **1TB** + **6000mAh** + 100W 快充 + **OneUI 9.0（Android 17 / 港版 TGY）**
- 同期原版三星旗舰 16G+1TB 卖到 1.2W+ 且只有 5000mAh + 45W，这套刷稳之后简直不要太香。

---

### 🛡️ `v1.2.0` 新增防 Root / BL 检测加固 & 极客体验

1. **中性只读隐蔽挂载 + 安全属性加固 + WebUI 一键体检（v1.2.0 新增）**
   - 把 FixPack 原本裸挂在 `/adb/oneui9_mods` 且带 `rw` 属性的挂载全部转入中性路径 `/data/misc/oneui_rt/` 并执行 `remount,ro,bind`（配合 SUSFS 自动 `add_sus_mount`），彻底抹掉模块自身在 `/proc/self/mountinfo` 留下的 `/adb/` 字样与可写标记；
   - 自动修正 `persist.service.debuggable=0` 及缺失的 `ro.boot.vbmeta.device_state=locked` / `ro.boot.veritymode=enforcing` / `warranty_bit=0`，且严守安全底线**不强改 DFE 的 `ro.crypto.state`**；
   - KernelSU WebUI 直接内嵌「环境隐蔽体检卡片」，第三方 `zygisk_lsposed`/`bindhosts` 暴露也能一眼抓出。

2. **物理三段式开关复活 + X 轴马达手感**
   - 用事件驱动 `getevent -l` 监听 `oplus,hall_tri_state_key` (`KEY_F3`)，配合 `/proc/tristatekey/tri_state`，实现上静音 / 中震动 / 下响铃无缝切换，**待机 0% CPU 轮询功耗**，切换瞬间触发线性马达震感反馈。

3. **游戏硬件旁路直驱供电 + 充电上限保护**
   - 直接接管 `/sys/class/oplus_chg/battery/mmi_charging_enable`，支持一键开启旁路直驱不充电池，以及 `80% / 85% / 90%` 充电阈值 + `5%` 迟滞防抖保护电芯寿命。

4. **KernelSU 原生暗黑 WebUI 控制面板**
   - 在 KernelSU 模块页点「打开」就能直观看到电量温度、三段式挡位、旁路直驱开关、环境体检结果和各系统补丁激活状态，全部纯离线原生实现。

5. **TGY 港版 OMC CSC 动态解密与功能增强**
   - 从本机 `framework.jar` 提取 `SemCscFeature` 的 256B `salts/shifts` 解开 OMC 密文，注入**三星原生通话录音、禁用虚假 eSIM、50Hz 防闪烁、快门音开关、实时网速、最近任务锁定**，直接生成明文 XML 挂载。

6. **彻底根治 60fps 录像黑屏断电 & 相机 9:16 崩溃**
   - 保持 **ColorOS 15.0.0.860（ARB 0 安全底包，绝不碰防回滚分区）** + 配套原厂 `6.6.66` 内核，避免跨版本内核导致的 `CAM-ICP DMI_STATUS` 断电。解锁全部 60fps 开关并将 `4000x2252` 修正为 `3840x2160`，**连续录 60fps 102 分钟（13.06 GB）零重启，稳在 41.8°C**。

7. **微信/OneDrive 零闪退 + 双卡管理 + 三网短信 & 电信联通 VoLTE + 时钟显秒**
   - 替换污染的 `kotlin-stdlib` 假库，去除虚假 eSIM，原位修补 `telephony-common.jar`、`imsservice.apk`、`SystemUI.apk`，**电信 IMS 短信（`SIP 202 Accepted`）与双卡 VoLTE 通话稳过 6 秒**。

---

### 📦 开源地址（GitHub Actions 自动打包，零版权夹带）
- **GitHub 仓库**：`https://github.com/YANS311/OneUI9-OnePlus13-FixPack`
- 含 **KernelSU / Magisk v1.2.1 一键模块包（内置 WebUI 隐蔽体检，Release 直接下载）** + **PC 端一键 ADB 原位修补脚本** + **4 套 Agent Skills** + 完整技术原理。
- 欢迎各位一加 13 刷 OneUI 9 的机友 Star / PR，一起把移植包打磨成完美主力机！
