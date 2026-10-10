# JumpRec 🪢

> **A jump rope workout tracker for Apple Watch, AirPods, and iPhone.**

*Languages: [English](readme.md) | [日本語](readme_ja.md)*

---

**JumpRec** tracks your rope jumping sessions using your Apple Watch, compatible headphones, or your iPhone in your pocket. It counts your jumps, logs your workout duration and heart rate, and keeps your exercise history on your device.

---

## Features

### 🪢 Jump Counting Options
- **Apple Watch:** Counts jumps from wrist motion while wearing your watch.
- **AirPods & Beats:** Counts jumps from head motion using compatible headphones (AirPods Pro, AirPods Max, Beats Fit Pro).
- **iPhone in Pocket:** Counts jumps using motion sensors when your iPhone is in your pocket.

### ⌚📱 Apple Watch & iPhone Sync
- **Live Display:** Shows your ongoing Apple Watch workout metrics (jumps, elapsed time, heart rate, calories) directly on your iPhone.
- **Controls:** Start or stop your session from either device.

### 🏝️ Live Activities
- View your current jump count and workout time on the Lock Screen or Dynamic Island while working out.

### 📊 Workout History & Stats
- **Session Details:** Review jump counts, duration, pace (jumps per minute), heart rate, and estimated calories.
- **Calendar & History:** Browse past workouts by month or year.
- **Personal Milestones:** Tracks milestones like highest jump count, longest session, and longest streak.

### 🗣️ Audio Announcements
- Spoken updates during workouts (such as every 100 jumps or every minute) using the built-in speech synthesizer.

### 🎙️ Siri & Shortcuts
- Check your latest workout, today's total jumps, or start a session using Siri and the Shortcuts app.
- Optional local session recaps generated on-device.

### 🔒 Privacy-Focused
- **No Accounts Required:** No registration, login, or personal profile needed.
- **On-Device Counting:** Motion data is processed in real time on your device and not uploaded.
- **iCloud Sync:** Workout history syncs across your devices using your private iCloud account.
- **No Ads or Third-Party Trackers:** No analytics SDKs or advertising networks.

### 💰 Pricing
- **100 Free Workouts:** First 100 sessions are free with full functionality.
- **One-Time Purchase:** A single in-app purchase unlocks unlimited workouts. No subscriptions.

---

## Tech Stack

| Component | Usage |
| :--- | :--- |
| **SwiftUI & Swift 5** | User interface across iOS and watchOS |
| **CoreMotion** | Jump detection using device and headphone motion sensors |
| **HealthKit** | Workout session tracking and Apple Health sync |
| **SwiftData & CloudKit** | Local storage and private iCloud synchronization |
| **ActivityKit** | Lock Screen and Dynamic Island Live Activities |
| **AppIntents** | Siri and Shortcuts integration |
| **StoreKit 2** | One-time in-app purchase handling |

---

## Compatibility

- **iOS 18.0+** / **watchOS 11.0+**
- **Jump Detection:**
  - Apple Watch (Series 4 or later, Ultra, SE)
  - AirPods Pro, AirPods Max, AirPods (3rd generation or later), Beats Fit Pro
  - iPhone (placed in pocket)

---

## Privacy Policy

- [Privacy Policy (English)](PRIVACY_POLICY.md)
- [プライバシーポリシー (日本語)](PRIVACY_POLICY_ja.md)

---

## License

This repository is available under the [PolyForm Noncommercial License 1.0.0](LICENSE). You may use, study, modify, and share the software for purposes permitted by that license, including personal learning and noncommercial projects. Commercial use, such as selling a derivative app, adding paid features or advertising to a fork, or incorporating this code into a commercial product, requires separate permission from the relevant copyright holders.

JumpRec is source-available with restrictions on commercial use. The repository license does not restrict the copyright holders from selling the official app. The official App Store release is distributed under its applicable App Store terms and end-user license agreement; this repository license does not replace those terms.

Retain the license and required copyright notices when sharing copies. Any third-party material remains subject to its own license. The full [LICENSE](LICENSE) text governs; this section is only a summary.
