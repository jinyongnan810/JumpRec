# JumpRec 隐私政策

**最后更新日期：** 2026年9月20日

*语言：[English](PRIVACY_POLICY.md) | [日本語](PRIVACY_POLICY_ja.md) | [简体中文](PRIVACY_POLICY_zh-Hans.md) | [繁體中文](PRIVACY_POLICY_zh-Hant.md) | [한국어](PRIVACY_POLICY_ko.md)*

---

感谢您使用 **JumpRec**（以下简称“本应用”）。JumpRec 旨在帮助您通过 Apple Watch 和 iPhone 记录跳绳运动。

我们坚信，您的个人健康和运动数据归您本人所有。JumpRec 从设计之初就遵循**“隐私优先设计”（Privacy by Design）**原则：我们不会在外部服务器上收集、存储、出售或共享您的个人数据。

---

## 1. 核心要点

- **无需注册账户：** 使用 JumpRec 无需注册账户、登录，也无需提供姓名、电子邮箱或电话号码等个人信息。
- **本地与设备端处理：** 使用动作传感器检测跳跃及计算各项运动数据均直接在您的设备上完成。
- **无第三方追踪或广告：** 我们未集成任何第三方分析 SDK、追踪工具或广告网络。
- **HealthKit 隐私保护：** 仅在获得您的明确授权后，您的运动数据才会同步至 Apple“健康”，且 HealthKit 数据绝不会用于营销、广告或数据挖掘。
- **私人 iCloud 同步：** 如果您启用了 iCloud，您的运动历史与设置会通过 Apple 提供的私人 iCloud 数据库（CloudKit）在您自己的 Apple 设备间同步。我们无法访问这些数据。

---

## 2. 我们访问和处理的信息

### A. 动作与传感器数据（CoreMotion）
- **访问内容：** 来自您的 Apple Watch 或兼容耳机（如支持耳机动作感应的 AirPods）的加速度计和动作传感器数据。
- **使用目的：** 实时检测跳绳次数、节奏和跳跃频率。
- **保留期限：** 动作传感器数据由设备端的跳跃检测算法进行实时分析。原始传感器波形数据在分析后立即丢弃，绝不会存储或传输。

### B. 健康与健身数据（Apple HealthKit）
在获得您的明确许可后，JumpRec 会与 Apple HealthKit 集成：
- **读取权限：** JumpRec 读取体能训练会话数据，以便在 iPhone 上实时同步显示当前 Apple Watch 运动的各项指标。
- **写入权限：** JumpRec 会将已完成的跳绳运动（包括开始/结束时间、时长及估算的活动消耗热量）直接保存至 Apple“健康”数据库，以计入您的每日健身记录圆环。
- **HealthKit 保护：** 严格遵守 Apple 开发者准则，HealthKit 数据安全存储在 Apple 的加密健康数据库中。我们绝不会将 HealthKit 数据共享、出售或用于广告、营销及提供 JumpRec 核心运动追踪功能以外的任何用途。

### C. 运动历史与个人纪录（SwiftData）
- **存储内容：** 运动日期、跳跃次数、耗时、最长连续跳跃、平均/最高节奏以及估算消耗热量。
- **存储位置：** 运动历史与个人纪录本地保存在您设备上的安全 App Group 容器中。

### D. iCloud 同步（CloudKit 与 NSUbiquitousKeyValueStore）
- **运动记录同步：** 如果您登录了支持 iCloud 的 Apple ID 并开启了 iCloud，JumpRec 会使用 Apple 的 **CloudKit** 在您的 iPhone、Apple Watch 与实时活动（Live Activity）扩展之间自动同步运动记录。
- **设置同步：** 用户偏好设置（如跳跃目标、语音播报设置与检测灵敏度）通过 Apple 的 `NSUbiquitousKeyValueStore` 在您的设备间同步。
- **隐私保障：** 所有 iCloud 同步均严格在您个人的私人 iCloud 容器中完成。我们（开发者）不架设服务器，也无法查看、解密或访问您的 iCloud 数据。

### E. 应用内购买（StoreKit）
- JumpRec 通过 Apple 的 **StoreKit** 提供一次性买断，以永久解锁无限次运动记录。
- 所有交易和付款流程均由 Apple 通过您的 Apple ID 账户全权处理。JumpRec 不会收集、处理也无法访问您的信用卡号、账单地址或付款详情。
- 购买权益状态通过 Apple 官方 StoreKit 2 API 在您的设备本地进行验证。

### F. 语音播报与设备端智能
- **语音播报：** JumpRec 可通过 Apple 内置的 `AVSpeechSynthesizer` 播报运动里程碑（例如每跳满 100 次或每经过 1 分钟）。语音合成在设备本地完成。
- **Siri 快捷指令与 App Intents：** JumpRec 支持 Siri 快捷指令与设备端 Apple Intelligence 基础模型，方便您查询近期运动和个人纪录。所有查询均在本地针对您设备上的数据库处理，不会将任何运动数据发送至外部 AI 服务器。

---

## 3. 我们不会收集的信息

我们不会收集：
- **个人身份信息（PII）：** 不收集姓名、电子邮箱、电话号码或通讯地址。
- **位置数据：** JumpRec 不会请求 GPS 或位置追踪权限。
- **第三方分析：** 我们不使用 Google Analytics、Firebase、Meta SDK、Mixpanel 或任何其他第三方追踪框架。
- **广告标识符：** 我们不会跨应用或跨网站追踪您，也不访问 IDFA（广告标识符）。
- **数据交易：** 我们绝不会出售、出租或将您的个人或运动信息用于商业变现。

---

## 4. 第三方服务与系统框架

JumpRec 仅使用 Apple 原生系统框架：
- **Apple HealthKit：** [Apple 隐私政策](https://www.apple.com/legal/privacy/cn/)
- **Apple iCloud（CloudKit）：** [iCloud 安全性概览](https://support.apple.com/zh-cn/102651)
- **Apple 应用内购买（StoreKit）：** [StoreKit 与隐私](https://www.apple.com/legal/privacy/data/zh-cn/apple-pay/)

---

## 5. 用户控制与数据删除

您始终对自己的数据拥有完全控制权：
- **删除运动记录：** 您可以直接在 JumpRec 的“历史”页面中删除单条运动记录或全部记录。
- **撤销 HealthKit 权限：** 您可随时在 iPhone“设置”中修改或撤销 JumpRec 对 Apple“健康”的访问权限：
  `设置` &rarr; `健康` &rarr; `数据访问权限与设备` &rarr; `JumpRec`。
- **撤销动作权限：** 您可随时在 iPhone“设置”中关闭动作访问权限：
  `设置` &rarr; `隐私与安全性` &rarr; `运动与健身` &rarr; `JumpRec`。
- **删除所有应用数据：** 从设备卸载本应用将删除所有本地存储的数据。如需删除已同步至 iCloud 的数据，您可通过以下路径删除应用数据：
  `设置` &rarr; `[您的姓名]` &rarr; `iCloud` &rarr; `管理存储空间`。

---

## 6. 儿童隐私

JumpRec 不会故意收集或向 13 周岁以下（或适用当地法律规定的最低年龄）的儿童索取任何个人信息。由于本应用无需账户且不向外部服务器传输个人数据，儿童可以在家长或监护人的监护下安全使用跳绳计数功能。

---

## 7. 安全性

我们高度重视数据保护。JumpRec 依托 iOS、watchOS 和 Apple iCloud 内置的沙盒机制、硬件级加密和安全防护措施来保障您的数据安全。您的运动记录受设备密码、面容 ID / 触控 ID 及 Apple ID 安全设置的保护。

---

## 8. 本隐私政策的变更

我们可能会不时更新本隐私政策，以反映应用功能、操作系统或法律法规的变化。所有更新都会在本仓库中发布，并修改“最后更新日期”。建议您定期查阅本政策。

---

## 9. 联系我们

如果您对本隐私政策或 JumpRec 的隐私实践有任何疑问、建议或顾虑，请在我们的 GitHub 仓库提交 Issue：

- **GitHub Issues：** [https://github.com/jinyongnan810/JumpRec/issues](https://github.com/jinyongnan810/JumpRec/issues)
- **项目仓库：** [https://github.com/jinyongnan810/JumpRec](https://github.com/jinyongnan810/JumpRec)
