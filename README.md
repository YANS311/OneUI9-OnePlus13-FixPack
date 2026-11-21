# OneUI 9.0 FixPack for OnePlus 13 (`PJZ110` / `dodge`)

[![CI & Release](https://github.com/YANS311/OneUI9-OnePlus13-FixPack/actions/workflows/ci-release.yml/badge.svg)](https://github.com/YANS311/OneUI9-OnePlus13-FixPack/actions/workflows/ci-release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

一套面向 **一加 13（`PJZ110` / `dodge`）刷入 OneUI 9.0（Android 17 / `SM-S9480` 移植包，如 `v199`）** 的无侵入式 KernelSU / Magisk 修复套件与原位修补工具链。

> **设计原则**：零系统分区改动、零三星版权二进制分发（所有修补均基于用户本机 ROM 文件动态原位生成）、全套脚本经过 ShellCheck + Python 单元测试 CI/CD 验证。

---

## ✨ 修复清单（真机实测验证）

| 模块 | 解决的痛点 | 技术根因与修复方案 |
| :--- | :--- | :--- |
| **1. 微信 / OneDrive 等 App 秒闪退** | 微信、OneDrive 等使用 R8 混淆 Kotlin 的应用启动即崩（`NoSuchMethodError` / `NoSuchFieldError`） | 一加底包 `/odm/framework/androidx.camera.extensions.impl.fake.jar` 错误打包了未混淆的 `kotlin-stdlib`，注入父 ClassLoader 污染了应用自身的 Kotlin 类。`post-fs-data` 阶段用纯净的 `/system/framework/sec_camerax_impl.jar` bind-mount 替换即可彻底根治。 |
| **2. 双实体 SIM 管理器** | SIM 管理器隐藏卡槽 2，错显示「添加 eSIM」；去掉 eSIM 后显示「无 SIM 卡」 | 移除 `privapp-permissions-com.samsung.euicc*.xml` 的 `euicc` / `euicc.mep` 特性声明与 `floating_feature.xml` 的 `EMBEDDED_SIM_SLOTSWITCH=tsds2`，并在开机后根据 `gsm.sim.state` 自动补齐三星专属属性 `ril.ICC_TYPE0` / `ril.ICC_TYPE1`。 |
| **3. 三网双卡发短信修复** | 联通 / 电信 / 移动发短信报 `RADIO_NOT_AVAILABLE` 或 `SMS_FAIL_RETRY` | 原位修补 `telephony-common.jar`（保持 `STORED` 对齐）：<br>① `GsmSMSDispatcher.sendSms()` 将 `mSemCi` → `mCi`、`secSendSMS*` → `sendSMS*`，走高通标准 `IRadioMessaging`；<br>② `ImsSmsDispatcher.isAvailable()` 将 `mIsSmsOverImsOnly` → `mIsRegistered`，并开启 `sms_over_ip_indication=1`，打通中国电信纯 VoLTE IMS 短信（实测 `SIP 202 Accepted`）。 |
| **4. 电信 / 联通 VoLTE 6 秒断线** | 原移植包仅修补了中国移动（`CMCC_CN`），电信和联通通话仍触发 6 秒断线或卡 `183 Session Progress` | 修补 `imsservice.apk` 内 `res/raw/imsprofile.json`，为 `CTC Mobile (CTC_CN)` 与 `CU Mobile VoLTE (CU_CN)` 补齐 `dbr_timer = 0` 与 `use_precondition = false`。 |
| **5. 通话 RTP 搭桥加固** | 接通前 1 秒无声、连续拨号偶发端口 `19001` 冲突无声 | `callbridge_auto.sh` 轮询间隔由 `1.0s` 优化至 `0.3s`（起音提速 3 倍），改为同步清理旧 `RtpRelay` + `BridgeService` 后重建，并限制 `rtprelay.out` 单次日志体积。 |
| **6. 相机 60fps 解锁 + 9:16 闪光灯修复** | 原包隐藏所有 60fps 档位；9:16 拍照开闪光灯连拍崩溃 | 解锁 `camera-feature.xml` 全部 12 项前/后置 60fps 开关，并将一加 13 LYT-808 HAL 不支持的 `4000x2252` 修正为原生三流（YUV IN/OUT + JPEG OUT）支持的 `3840x2160`。 |
| **7. 60fps 录像黑屏断电根治（配套建议）** | 跨版本内核（如 `6.6.104`）录 60fps 触发 `CAM-ICP DMI_STATUS` 黑屏死机 | **保持 ColorOS `15.0.0.860`（ARB 0）原厂底层固件 + 配套原厂 `6.6.66-android15-8` 内核与 `vendor_dlkm`**，实测 60fps 连续录制 **102 分钟（13 GB+）零死机、零重启、电池稳定 41.8°C**。 |

---

## 🛠️ 安装方式

### 第一步：刷入 KernelSU / Magisk 模块（处理全部 XML、挂载与脚本修复）
1. 前往 [Releases](https://github.com/YANS311/OneUI9-OnePlus13-FixPack/releases) 下载最新的 `OneUI9-OnePlus13-FixPack-v*.zip`；
2. 在 **KernelSU Manager**（或 Magisk）中刷入该模块。

### 第二步：在电脑上运行一键原位修补脚本（处理 `telephony-common.jar` 与 `imsservice.apk`）
> 本仓库不含任何三星版权二进制，脚本会从你自己的手机拉取原包文件、在本地完成字节码/JSON 原位修补并校验 ZIP 完整性后推回 `/data/adb/oneui9_mods/`。

```bash
# 连接手机（已开启 ADB root 调试）
python patchers/apply_via_adb.py --reboot
```

也可以单独运行各个修补器：
```bash
python patchers/patch_telephony_sms.py telephony-common.jar telephony-common-patched.jar
python patchers/patch_imsservice.py imsservice.apk imsservice-patched.apk
```

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
