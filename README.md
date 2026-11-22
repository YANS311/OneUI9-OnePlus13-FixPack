# OneUI 9.0 FixPack for OnePlus 13 (`PJZ110` / `dodge`)

[![CI & Release](https://github.com/YANS311/OneUI9-OnePlus13-FixPack/actions/workflows/ci-release.yml/badge.svg)](https://github.com/YANS311/OneUI9-OnePlus13-FixPack/actions/workflows/ci-release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

一套面向 **一加 13（`PJZ110` / `dodge`）刷入 OneUI 9.0（Android 17 / `SM-S9480` 移植包，如 `v199`）** 的无侵入式 KernelSU / Magisk 修复套件、硬件直驱适配、**防 Root/BL 环境检测隐蔽挂载加固**与原位二进制修补工具链（含原生离线 KernelSU WebUI 与极客技能库）。

> **设计原则**：零系统分区改动、零三星版权二进制分发（所有修补均基于用户本机 ROM 文件动态原位生成）、全套脚本经过 ShellCheck + Python 单元测试 CI/CD 验证。

---

## ✨ `v1.2.2` 修复、硬件增强与隐蔽加固清单（真机实测验证）

| 模块 | 解决的痛点 / 新增能力 | 技术根因与修复方案 |
| :--- | :--- | :--- |
| **1. 微信 / OneDrive 等 App 秒闪退** | Kotlin / R8 混淆应用启动即崩（`NoSuchMethodError`） | 一加 `/odm/framework/androidx.camera.extensions.impl.fake.jar` 混入未混淆的 `kotlin-stdlib` 污染父 ClassLoader。`post-fs-data` 使用 `/system/framework/sec_camerax_impl.jar` 只读 bind-mount 替换根治。 |
| **2. 双实体 SIM 管理器** | 隐藏卡槽 2、错显 eSIM 或去掉 eSIM 后显示无卡 | 移除 `privapp-permissions-com.samsung.euicc*.xml` 的 `euicc` 声明与 `floating_feature.xml` 的 `tsds2`，按 `gsm.sim.state` 自动补齐 `ril.ICC_TYPE0/1`。 |
| **3. 三网双卡发短信修复** | 电信/联通/移动发短信报 `RADIO_NOT_AVAILABLE` | 原位修补 `telephony-common.jar`（保持 `STORED` 对齐）：`mSemCi` → `mCi`、`secSendSMS*` → `sendSMS*`，并将 `mIsSmsOverImsOnly` → `mIsRegistered` 打通纯 VoLTE IMS 短信（实测 `SIP 202 Accepted`）。 |
| **4. 电信 / 联通 VoLTE 6 秒断线** | 原移植包漏修电信（`CTC_CN`）和联通（`CU_CN`） | 修补 `imsservice.apk` 内 `res/raw/imsprofile.json`，补齐 `dbr_timer = 0` 与 `use_precondition = false`。 |
| **5. 通话 RTP 搭桥加固** | 接通前 1 秒无声、连续拨号偶发端口冲突 | `callbridge_auto.sh` 轮询缩至 `0.3s`（起音提速 3 倍），同步清理旧 `RtpRelay` + `BridgeService` 防端口竞态。 |
| **6. 相机 60fps + 9:16 闪光灯** | 隐藏 60fps 档位；9:16 开闪光灯连拍崩溃 | 解锁 `camera-feature.xml` 全部 12 项 60fps 开关，并将 `4000x2252` 修正为一加 13 LYT-808 HAL 原生三流支持的 `3840x2160`。 |
| **7. 状态栏 & 下拉栏时钟显秒** | 移植包无 Good Lock，重启或刷新后时钟秒数失效 | `patchers/patch_systemui_seconds.py` 动态扫表并幂等修补 `SlimIndicatorPluginMediator`、`QSClockQuickStarHelper`、`QSClockIndicatorView` 三处 DEX 字节码并重算 ZIP/DEX 校验和。 |
| **8. 一加 13 事件驱动三段式开关 + X 轴马达** | OneUI 无一加实体三段式开关原生响应 | `module/scripts/alert_slider.sh` 基于 `getevent -l` 监听 `oplus,hall_tri_state_key` (`KEY_F3`)，空闲 **0% CPU**；联动 `/proc/tristatekey/tri_state` 通过 `service call audio 53` 切换静音/震动/响铃并触发 `cmd vibrator_manager synced` X 轴振动反馈。 |
| **9. 硬件旁路直驱供电 + 充电上限保护** | 游戏插电发热、长期满充伤电池 | `module/scripts/power_guard.sh` 控制 `/sys/class/oplus_chg/battery/mmi_charging_enable`（`0` 直驱 / `1` 恢复），支持旁路供电开关及 `80%/85%/90%` 上限 + `5%` 迟滞回充防抖。 |
| **10. Root / BL 隐蔽挂载与安全属性加固（`v1.2.0` 新增）** | `/proc/self/mountinfo` 暴露 `/adb/oneui9_mods` 且为 `rw`；`persist.service.debuggable=1` 及空 AVB/vbmeta 属性易被检测 | `module/scripts/stealth_lib.sh` 将覆盖文件转储至中性只读目录 `/data/misc/oneui_rt/` 后执行 `mount -o remount,ro,bind`，若存在 SUSFS 自动追加 `add_sus_mount`；安全修正 `vbmeta`/`verity`/`warranty_bit`/`persist.service.debuggable`（**严格不全局伪造 DFE 的 `ro.crypto.state`，避免锁屏/启动异常**）。 |
| **11. KernelSU 离线 WebUI 控制台 + 隐蔽体检（`v1.2.0` 升级）** | 修改配置与排查 Root 暴露门槛高 | 纯离线暗黑风 `module/webroot/index.html`，支持旁路供电/充电阈值/三段式一键开关，**新增 Root/BL 环境隐蔽体检卡片**（检测 `mountinfo` `/adb` 暴露、只读状态、`debuggable` 泄露、第三方 `zygisk_lsposed`/`bindhosts` 暴露与 SUSFS 状态）。 |
| **12. TGY OMC CSC 动态解码与明文增强** | 港版 `cscfeature.xml` 为 OMC 位旋转+XOR+Gzip 密文 | `patchers/patch_cscfeature.py` 自动从本机 `framework.jar` 提取 `SemCscFeature` 256B `salts`/`shifts` 解密 `cscfeature.xml`，注入通话录音、禁用假 eSIM、50Hz 防闪烁、快门音开关、实时网速、最近任务锁。 |
| **13. 60fps 录像黑屏根治（底层建议）** | 跨版本内核（如 `6.6.104`）录 60fps 触发 `CAM-ICP DMI_STATUS` | **保持 ColorOS `15.0.0.860`（ARB 0）原厂底层 + 配套 `6.6.66-android15-8` 内核**，实测 60fps 连续录制 **102 分钟（13 GB+）零死机、温度稳定 41.8°C**。 |

---

## 🛠️ 安装与使用

### 方式一：KernelSU 刷入模块（日常用户）
1. 前往 [Releases](https://github.com/YANS311/OneUI9-OnePlus13-FixPack/releases) 下载 `OneUI9-OnePlus13-FixPack-v1.2.2.zip`；
2. 若已在 PC 运行过补丁（或已暂存到 `/sdcard/Download/OneUI9_v1.2.2/`），直接在 **KernelSU Manager**（或 Magisk）中刷入该模块，安装脚本会自动原子导入暂存补丁并清理早期旧热修复脚本；
3. 重启手机，在 KernelSU 模块页点击本模块 **「打开」** 即可使用 WebUI 控制与隐蔽体检面板。

### 方式二：PC 端一键原位修补脚本（含 Binary + TGY CSC）
> 本仓库不含任何三星版权二进制，脚本会从你自己的手机拉取原包，在本地完成全部修补与校验；若 ADB 具备 root（`uid=0`）将直接部署到 `/data/adb/oneui9_mods/`，若受 Play Integrity 伪装限制为非 root（`uid=2000`）则自动暂存至 `/sdcard/Download/OneUI9_v1.2.2/` 供 KernelSU 安装器接管。

```bash
python patchers/apply_via_adb.py --reboot
```

也可独立调用各个修补器：
```bash
python patchers/patch_telephony_sms.py telephony-common.jar telephony-common-patched.jar
python patchers/patch_imsservice.py imsservice.apk imsservice-patched.apk
python patchers/patch_systemui_seconds.py SystemUI.apk SystemUI-patched.apk
python patchers/patch_cscfeature.py cscfeature.bin cscfeature.xml --framework-jar framework.jar
```

---

## 🧠 极客技能库（`skills/`）

本次排查与工程实践沉淀了 4 套可复用的 Antigravity Agent Skills（位于仓库 [`skills/`](skills/) 目录）：
- `android-rom-port-debugger`: 移植系统卡一屏/App 闪退/双卡与短信 VoLTE/相机 HAL/CallBridge 全链路排障指南；
- `dex-inplace-patcher`: `apk/jar` 内 `STORED classes*.dex` 零重打包原位字节码修改规范与模板脚本；
- `oneplus-arb-safe-flasher`: 一加骁龙 8 Elite / SM8750 防回滚（ARB）底包安全刷机检查规范；
- `android-root-bl-stealth`: **防 Root / Bootloader 检测排查与隐蔽架构规范**（涵盖 `mountinfo` 隐蔽挂载、AVB/Debug 属性安全修正、DFE 安全红线、Zygisk/LSPosed/HMA/TrickyStore/SUSFS 分层排障）。

---

## ⚠️ 重要安全须知（一加 13 防回滚 ARB 警告）
- **切勿随意刷入 ColorOS 16+ 高版本底包固件**，以免触发高通 ARB 熔断导致无法降级甚至 9008 变砖；
- 始终保留 **ColorOS `15.0.0.860`（ARB 0）** 安全基线固件（`abl`/`xbl`/`tz`/`modem`/`dsp` 等关键分区保持不动）；
- 若刷入 OneUI 9 移植包遇到一屏卡死，通常为 `/vendor/etc/fstab.qcom` 中残留 `my_*` 挂载项或 `vold` 等待 `ISehKeyMintExtension` 导致的加密死锁，需清理 `my_*` 并应用 DFE。

---

## 🧪 本地运行测试（与 GitHub Actions CI 一致）

```bash
python -m unittest discover -s tests -v
```

## 📄 License
[MIT License](LICENSE)
