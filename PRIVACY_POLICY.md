# Privacy Policy for JumpRec

**Last Updated:** September 20, 2026

*Language: [English](PRIVACY_POLICY.md) | [日本語 (Japanese)](PRIVACY_POLICY_ja.md)*

---

Welcome to **JumpRec** ("we", "our", or "the app"). JumpRec is designed to help you track your rope jumping workouts using your Apple Watch and iPhone. 

We strongly believe that your personal health and workout data belongs to you. JumpRec was built from the ground up following a **privacy-by-design** approach: we do not collect, store, sell, or share your personal data on external servers.

---

## 1. Summary of Key Points

- **No User Accounts:** You do not need to register an account, sign in, or provide personal details (such as your name, email address, or phone number) to use JumpRec.
- **Local & On-Device Processing:** Jump detection using motion sensors and workout calculations occurs directly on your device.
- **No Third-Party Trackers or Advertising:** We do not integrate any third-party analytics SDKs, tracking tools, or advertising networks.
- **HealthKit Privacy:** Your workout data is synced with Apple Health only with your explicit permission, and HealthKit data is never used for marketing, advertising, or data mining.
- **Private iCloud Sync:** If you use iCloud, your workout history and settings sync across your own Apple devices using Apple's private iCloud database (CloudKit). We have no access to this data.

---

## 2. Information We Access and Process

### A. Motion and Sensor Data (CoreMotion)
- **What is accessed:** Accelerometer and motion sensor data from your Apple Watch or compatible headphones (such as AirPods via Headphone Motion).
- **Purpose:** To detect rope jump repetitions, cadence, and jump frequency in real time.
- **Retention:** Motion sensor data is analyzed on-device in real time by our jump detection algorithm. Raw sensor waveforms are discarded immediately and are never stored or transmitted.

### B. Health and Fitness Data (Apple HealthKit)
With your explicit consent, JumpRec integrates with Apple HealthKit:
- **Read Access:** JumpRec reads workout session data to mirror active Apple Watch workout metrics on your iPhone.
- **Write Access:** JumpRec saves completed jump rope workouts (including session start/end time, duration, and estimated active calories burned) directly to your Apple Health database so it counts toward your daily Activity rings.
- **HealthKit Protection:** In compliance with Apple developer guidelines, HealthKit data is stored securely in Apple's encrypted health database. We will never share, sell, or use HealthKit data for advertising, marketing, or any purpose other than providing the core fitness tracking functionality of JumpRec.

### C. Workout History and Personal Records (SwiftData)
- **What is stored:** Session dates, jump counts, elapsed durations, streaks, average/peak jump rates, and estimated calories burned.
- **Storage Location:** Workout history and personal records are saved locally on your device within the secure App Group container.

### D. iCloud Synchronization (CloudKit & NSUbiquitousKeyValueStore)
- **Workout Synchronization:** If you are signed in to an Apple ID with iCloud enabled, JumpRec uses Apple's **CloudKit** to automatically sync workout records between your iPhone, Apple Watch, and Live Activity extensions.
- **Settings Synchronization:** User preferences (such as target jump goals, audio announcement preferences, and detector sensitivity) are synchronized across your devices using Apple's `NSUbiquitousKeyValueStore`.
- **Privacy Guarantee:** All iCloud sync operations take place strictly within your private iCloud container. We (the developers) do not host servers and cannot view, decrypt, or access your iCloud data.

### E. In-App Purchases (StoreKit)
- JumpRec offers a one-time lifetime unlock for unlimited workouts via Apple's **StoreKit**.
- Transactions and payment processing are handled entirely by Apple through your Apple ID account. JumpRec does not collect, process, or have access to your credit card number, billing address, or payment details.
- Purchase entitlement status is checked locally on your device using Apple's official StoreKit 2 APIs.

### F. Voice Announcements and On-Device Intelligence
- **Audio Announcements:** JumpRec can announce workout milestones (e.g., every 100 jumps or elapsed minutes) using Apple's built-in `AVSpeechSynthesizer`. Voice synthesis is processed on-device.
- **Siri Shortcuts & App Intents:** JumpRec supports Siri Shortcuts and on-device Apple Intelligence Foundation Models to allow you to inquire about recent workouts and personal records. All queries are resolved locally against your on-device database; no workout data is sent to external AI servers.

---

## 3. Information We Do NOT Collect

We do not collect:
- **No Personally Identifiable Information (PII):** No names, email addresses, phone numbers, or physical addresses.
- **No Location Data:** JumpRec does not request GPS or location tracking permissions.
- **No Third-Party Analytics:** We do not use Google Analytics, Firebase, Meta SDK, Mixpanel, or any other third-party tracking frameworks.
- **No Advertising Identifiers:** We do not track you across apps or websites and do not access IDFA (Identifier for Advertisers).
- **No Data Brokerage:** We will never sell, lease, or monetize your personal or workout information.

---

## 4. Third-Party Services and System Frameworks

JumpRec relies solely on native Apple system frameworks:
- **Apple HealthKit:** [Apple's Privacy Policy](https://www.apple.com/legal/privacy/)
- **Apple iCloud (CloudKit):** [Apple iCloud Security Overview](https://support.apple.com/en-us/102651)
- **Apple In-App Purchases (StoreKit):** [StoreKit & Privacy](https://www.apple.com/legal/privacy/data/en/apple-pay/)

---

## 5. User Control and Data Deletion

You are always in full control of your data:
- **Delete Workouts:** You can delete any individual workout session or all sessions directly from the History screen inside JumpRec.
- **Revoke HealthKit Access:** You can modify or revoke JumpRec's access to Apple Health at any time in your iPhone Settings:
  `Settings` &rarr; `Health` &rarr; `Data Access & Devices` &rarr; `JumpRec`.
- **Revoke Motion Access:** You can disable motion access at any time in iPhone Settings:
  `Settings` &rarr; `Privacy & Security` &rarr; `Motion & Fitness` &rarr; `JumpRec`.
- **Remove All App Data:** Uninstalling the app from your devices deletes all locally stored data. To delete iCloud-synced data, you may delete the app data via:
  `Settings` &rarr; `[Your Name]` &rarr; `iCloud` &rarr; `Manage Storage`.

---

## 6. Children's Privacy

JumpRec does not knowingly collect or solicit any personal information from children under the age of 13 (or the equivalent minimum age under applicable local law). Because the app operates without user accounts and does not transmit personal data to external servers, children can use the jump counting features safely under the supervision of a parent or guardian.

---

## 7. Security

We take data protection seriously. JumpRec relies on the robust sandboxing, hardware-level encryption, and security mechanisms built into iOS, watchOS, and Apple iCloud. Your workout records are protected by your device passcode, Face ID / Touch ID, and Apple ID security settings.

---

## 8. Changes to This Privacy Policy

We may update this Privacy Policy from time to time to reflect changes in our app features, operating systems, or legal requirements. Any updates will be published in this repository with a revised "Last Updated" date. We encourage you to review this policy periodically.

---

## 9. Contact Us

If you have any questions, suggestions, or concerns regarding this Privacy Policy or JumpRec's privacy practices, please open an issue in our GitHub repository:

- **GitHub Issues:** [https://github.com/jinyongnan810/JumpRec/issues](https://github.com/jinyongnan810/JumpRec/issues)
- **Project Repository:** [https://github.com/jinyongnan810/JumpRec](https://github.com/jinyongnan810/JumpRec)
