# JumpRec 隱私權政策

**最後更新日期：** 2026年9月20日

*語言：[English](PRIVACY_POLICY.md) | [日本語](PRIVACY_POLICY_ja.md) | [简体中文](PRIVACY_POLICY_zh-Hans.md) | [繁體中文](PRIVACY_POLICY_zh-Hant.md) | [한국어](PRIVACY_POLICY_ko.md)*

---

感謝您使用 **JumpRec**（以下簡稱「本 App」）。JumpRec 旨在協助您透過 Apple Watch 與 iPhone 記錄跳繩運動。

我們深信，您的個人健康與運動資料屬於您本人。JumpRec 從設計之初便遵循**「隱私優先設計」（Privacy by Design）**原則：我們不會在外部伺服器上收集、儲存、販售或分享您的個人資料。

---

## 1. 核心重點

- **無需註冊帳號：** 使用 JumpRec 無需註冊帳號、登入，也無需提供姓名、電子郵件地址或電話號碼等個人資訊。
- **本機與裝置端處理：** 透過動作感測器偵測跳躍及計算各項運動數據均直接在您的裝置上完成。
- **無第三方追蹤或廣告：** 我們未整合任何第三方分析 SDK、追蹤工具或廣告聯播網。
- **HealthKit 隱私保護：** 僅在獲得您的明確授權後，您的運動資料才會同步至 Apple「健康」，且 HealthKit 資料絕不會用於行銷、廣告或資料探勘。
- **私人 iCloud 同步：** 如果您使用 iCloud，您的運動歷史與設定會透過 Apple 的私人 iCloud 資料庫（CloudKit）在您自己的 Apple 裝置間同步。我們無法存取這些資料。

---

## 2. 我們存取與處理的資訊

### A. 動作與感測器資料（CoreMotion）
- **存取內容：** 來自您的 Apple Watch 或相容耳機（例如支援耳機動作感測的 AirPods）的加速度計與動作感測器資料。
- **使用目的：** 即時偵測跳繩次數、節奏與跳躍頻率。
- **保留期限：** 動作感測器資料會由裝置端的跳躍偵測演算法即時分析。原始感測器波形資料在分析後立即捨棄，絕不會儲存或傳輸。

### B. 健康與體能資料（Apple HealthKit）
在獲得您的明確許可後，JumpRec 會與 Apple HealthKit 整合：
- **讀取權限：** JumpRec 會讀取體能訓練階段資料，以便在 iPhone 上即時同步顯示進行中的 Apple Watch 運動指標。
- **寫入權限：** JumpRec 會將已完成的跳繩運動（包含開始／結束時間、時長與估算的活動消耗卡路里）直接儲存至 Apple「健康」資料庫，並計入您的每日活動圓圈。
- **HealthKit 保護：** 嚴格遵守 Apple 開發者準則，HealthKit 資料安全儲存在 Apple 的加密健康資料庫中。我們絕不會將 HealthKit 資料分享、販售或用於廣告、行銷，或提供 JumpRec 核心運動追蹤功能以外的任何用途。

### C. 運動歷史與個人紀錄（SwiftData）
- **儲存內容：** 運動日期、跳躍次數、經過時間、最長連續跳躍、平均／最高節奏，以及估算消耗卡路里。
- **儲存位置：** 運動歷史與個人紀錄本機儲存在您裝置上的安全 App Group 容器中。

### D. iCloud 同步（CloudKit 與 NSUbiquitousKeyValueStore）
- **運動紀錄同步：** 如果您已登入啟用 iCloud 的 Apple ID，JumpRec 會使用 Apple 的 **CloudKit**，在您的 iPhone、Apple Watch 與即時動態（Live Activity）延伸功能之間自動同步運動紀錄。
- **設定同步：** 使用者偏好設定（例如跳躍目標、語音播報偏好與偵測靈敏度）會透過 Apple 的 `NSUbiquitousKeyValueStore` 在您的裝置間同步。
- **隱私保證：** 所有 iCloud 同步作業均嚴格在您個人的私人 iCloud 容器中進行。我們（開發者）不架設伺服器，亦無法檢視、解密或存取您的 iCloud 資料。

### E. App 內購買（StoreKit）
- JumpRec 透過 Apple 的 **StoreKit** 提供單次買斷，以終身解鎖無限次運動記錄。
- 所有交易與付款處理皆由 Apple 透過您的 Apple ID 帳號全權負責。JumpRec 不會收集、處理，亦無法存取您的信用卡號碼、帳單地址或付款詳情。
- 購買權限狀態會使用 Apple 官方 StoreKit 2 API 在您的裝置本機檢查。

### F. 語音播報與裝置端智慧功能
- **語音播報：** JumpRec 可使用 Apple 內建的 `AVSpeechSynthesizer` 播報運動里程碑（例如每跳滿 100 下或每經過 1 分鐘）。語音合成在裝置本機進行。
- **Siri 捷徑與 App Intents：** JumpRec 支援 Siri 捷徑與裝置端 Apple Intelligence 基礎模型，讓您查詢最近的運動與個人紀錄。所有查詢皆於本機針對您裝置上的資料庫處理，不會將任何運動資料傳送至外部 AI 伺服器。

---

## 3. 我們不會收集的資訊

我們不會收集：
- **個人識別資訊（PII）：** 不收集姓名、電子郵件地址、電話號碼或實體地址。
- **位置資料：** JumpRec 不會要求 GPS 或位置追蹤權限。
- **第三方分析：** 我們不使用 Google Analytics、Firebase、Meta SDK、Mixpanel 或任何其他第三方追蹤架構。
- **廣告識別碼：** 我們不會跨 App 或網站追蹤您，亦不會存取 IDFA（廣告識別碼）。
- **資料仲介：** 我們絕不會販售、出租或將您的個人或運動資訊變現。

---

## 4. 第三方服務與系統框架

JumpRec 僅依賴 Apple 原生系統框架：
- **Apple HealthKit：** [Apple 隱私權政策](https://www.apple.com/tw/legal/privacy/)
- **Apple iCloud（CloudKit）：** [iCloud 安全性概覽](https://support.apple.com/zh-tw/102651)
- **Apple App 內購買（StoreKit）：** [StoreKit 與隱私權](https://www.apple.com/legal/privacy/data/zh-tw/apple-pay/)

---

## 5. 使用者控制與資料刪除

您隨時對自己的資料擁有完整控制權：
- **刪除運動紀錄：** 您可直接從 JumpRec 內的「歷史」畫面刪除單一運動紀錄或全部紀錄。
- **撤銷 HealthKit 權限：** 您可隨時在 iPhone「設定」中修改或撤銷 JumpRec 對 Apple「健康」的存取權限：
  `設定` &rarr; `健康` &rarr; `資料存取權限與裝置` &rarr; `JumpRec`。
- **撤銷動作權限：** 您可隨時在 iPhone「設定」中停用動作存取權限：
  `設定` &rarr; `隱私權與安全性` &rarr; `動作與健身` &rarr; `JumpRec`。
- **移除所有 App 資料：** 從裝置解除安裝本 App 將會刪除所有本機儲存的資料。若要刪除已同步至 iCloud 的資料，您可以透過以下路徑刪除 App 資料：
  `設定` &rarr; `[您的姓名]` &rarr; `iCloud` &rarr; `管理儲存空間`。

---

## 6. 兒童隱私權

JumpRec 不會故意收集或向 13 歲以下（或適用當地法律規定的最低年齡）的兒童索取任何個人資訊。由於本 App 無需帳號且不會將個人資料傳送至外部伺服器，兒童可在家長或監護人的監督下安全使用跳繩計數功能。

---

## 7. 安全性

我們高度重視資料保護。JumpRec 仰賴 iOS、watchOS 與 Apple iCloud 內建的沙盒機制、硬體級加密與安全防護來保護您的資料。您的運動紀錄受到裝置密碼、Face ID / Touch ID 與 Apple ID 安全設定的保護。

---

## 8. 本隱私權政策的變更

我們可能會不時更新本隱私權政策，以反映 App 功能、作業系統或法律規範的變更。任何更新都會發佈於本儲存庫並修訂「最後更新日期」。建議您定期檢閱本政策。

---

## 9. 聯絡我們

如果您對本隱私權政策或 JumpRec 的隱私權作法有任何疑問、建議或顧慮，歡迎在我們的 GitHub 儲存庫建立 Issue：

- **GitHub Issues：** [https://github.com/jinyongnan810/JumpRec/issues](https://github.com/jinyongnan810/JumpRec/issues)
- **專案儲存庫：** [https://github.com/jinyongnan810/JumpRec](https://github.com/jinyongnan810/JumpRec)
