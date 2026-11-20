# Permissions & Privacy Architecture

This document describes how JumpRec requests and checks HealthKit and Core Motion permissions across iPhone and Apple Watch, along with the TCC and Watch-companion pitfalls to keep in mind when modifying workout or sensor startup flows.

---

## Permission Matrix

### HealthKit (`WorkoutPermissions`)

[`WorkoutPermissions`](../JumpRecShared/WorkoutPermissions.swift) defines the single source of truth for HealthKit access shared by iOS and watchOS:

| Access | Types | Purpose |
| :--- | :--- | :--- |
| **Share (Write)** | `HKObjectType.workoutType()`, `HKQuantityType(.activeEnergyBurned)` | Saves completed workouts (`HKLiveWorkoutBuilder`) and active calorie samples on both devices. |
| **Read** | `HKQuantityType(.activeEnergyBurned)`, `HKQuantityType(.heartRate)` | Displays live and summary calorie and heart-rate metrics. |

* **Intentional omission:** `HKObjectType.workoutType()` is **not** included in `typesToRead`. JumpRec stores workout history in its own SwiftData store (`MyDataStore`) and receives live Watch workouts via `HKHealthStore.workoutSessionMirroringStartHandler`, so it never queries saved `HKWorkout` records from Apple Health.

### Core Motion

Watch and iPhone use different Core Motion frameworks and TCC services:

| Platform | Sensor API | TCC Service | Prompt Required |
| :--- | :--- | :--- | :--- |
| **watchOS** | `CMMotionManager` (`JumpRec Watch App/Logics/MotionManager.swift`) | `kTCCServiceMotionSensors` | No **Motion & Fitness** prompt; device-motion updates operate even when Motion & Fitness is toggled off in watchOS Settings. |
| **iOS** | `CMHeadphoneMotionManager` & `CMHeadphoneActivityManager` (`JumpRec/Logics/MotionManager.swift`) | `kTCCServiceMotion` ("Motion & Fitness") | Prompted only before starting a headphone workout on iPhone (`requestMotion: true`). |

Both app targets declare `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, and `NSMotionUsageDescription` (with localized strings in `InfoPlist.xcstrings`).

---

## Authorization Timing & Settings UI

1. **Watch Launch:** [`StartView.requestInitialHealthPermissionsIfNeeded()`](../JumpRec%20Watch%20App/Views/StartView.swift) calls `WorkoutPermissions.requestAuthorization(using:)` once per launch so the multi-step HealthKit sheet is resolved before the user taps **START**.
2. **Pre-Countdown Gate:**
   * **iPhone ([`HomeView`](../JumpRec/Views/HomeView.swift)):** Calls `WorkoutPermissions.prepareForWorkout(requestMotion: !usesWatch)` before starting a countdown or launching the Watch app. Motion & Fitness is requested only when starting locally on headphones (`!usesWatch`).
   * **Apple Watch ([`AppState+SessionLifecycle`](../JumpRec%20Watch%20App/Models/AppState+SessionLifecycle.swift)):** Calls `WorkoutPermissions.prepareForWorkout()` (HealthKit only) before preparing sensors or starting the 3-second countdown.
3. **Deduplication:** `WorkoutPermissions.requestAuthorization(using:)` deduplicates concurrent prompts through a single `authorizationTask` on `@MainActor`.
4. **Settings UI ([`PermissionsSettingsContent`](../JumpRecShared/PermissionsSettingsContent.swift)):** Displays **Save Workouts**, **Save Active Energy**, and **Read Health Data** on both platforms, and **Headphone Motion** (`CMHeadphoneMotionManager.authorizationStatus()`) plus **Open App Settings** on iOS.

---

## Pitfalls & Guardrails

### 1. Calling `CMHeadphoneMotionManager.stopDeviceMotionUpdates()` Without an Active Stream Triggers `tccd` Kills on Watch

Calling `CMHeadphoneMotionManager.stopDeviceMotionUpdates()` on iPhone (even with no headphones connected and no stream started) triggers a non-preflight `TCCAccessRequest` for `kTCCServiceMotion` (`preflight=no`) in iOS `tccd`.

When Watch starts a workout, Watch's `startMirroringToCompanionDevice()` wakes the companion iPhone app, and [`beginMirroredSession(_:)`](../JumpRec/Models/AppState+MirroredWorkout.swift) calls `motionManager?.cancelPreparation()` right as the countdown reaches `0`. If iPhone's Motion & Fitness status is `.notDetermined`, an unguarded `stopDeviceMotionUpdates()` inside `cancelPreparation()` pops the Motion & Fitness prompt on iPhone and emits a `TCCDEvent` (`type=Create, service=kTCCServiceMotion`) synced to Apple Watch — causing watchOS `tccd` to immediately terminate (`SIGKILL`) the running Watch app.

**Required invariants in [`JumpRec/Logics/MotionManager.swift`](../JumpRec/Logics/MotionManager.swift):**

* Never instantiate `CMHeadphoneMotionManager` or `CMHeadphoneActivityManager` eagerly during `init()`. Use `ensureHeadphoneMotionManager()` and `ensureHeadphoneActivityManager()` only after `CMHeadphoneMotionManager.authorizationStatus() == .authorized`.
* Only call preflight-safe checks when unauthorized (`CMHeadphoneMotionManager.authorizationStatus()` and `AVAudioSession` route inspection via `hasConnectedAudioHeadphoneRoute`).
* Guard `stopDeviceMotionUpdates()` with `hasStartedDeviceMotionUpdates` via `stopHeadphoneDeviceMotionIfStarted()` across `cancelPreparation()`, `stopTracking()`, and `isolated deinit`.

### 2. Mismatched HealthKit Type Sets Cause Prompts on Both Devices

`HKHealthStore.getRequestStatusForAuthorization(toShare:read:)` checks whether every requested share/read type has already been presented across the iPhone/Watch pair. If iOS and watchOS pass different `typesToShare` or `typesToRead` sets (for example, requesting `read: workoutType` only on iOS or `share: activeEnergyBurned` only on watchOS), granting permissions on the first device still triggers a second HealthKit sheet on the other device.

**Guardrail:** Keep `WorkoutPermissions.typesToShare` and `WorkoutPermissions.typesToRead` identical across iOS and watchOS unless an extra type is strictly required and platform-exclusive.

### 3. Do Not Gate Watch Workouts on iPhone Motion & Fitness (`kTCCServiceMotion`)

On watchOS, `CMMotionManager` uses `kTCCServiceMotionSensors`, not `kTCCServiceMotion`. Checking `CMHeadphoneMotionManager.authorizationStatus()` or triggering a Watch-side Motion & Fitness prompt couples Watch workouts to a permission Watch does not need, and calling `CMMotionManager.authorizationStatus` does not reflect the iOS Motion & Fitness toggle in Watch Settings.

### 4. Companion Dependency (`WKRunsIndependentlyOfCompanionApp = NO`)

`JumpRec Watch App` keeps `INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = NO` in [project.pbxproj](../JumpRec.xcodeproj/project.pbxproj):

* Users **can** still start and complete Watch workouts offline without their iPhone nearby; workouts save locally to HealthKit and transfer to iPhone once reconnected.
* Keeping `NO` reflects that the Watch app pairs with the iPhone app for workout history, CSV export, and unlocking unlimited workouts, rather than supporting Watch-only installs with no iPhone app present.

---

## Debugging TCC Terminations

* TCC terminations (`SIGKILL` triggered when `kTCCServiceMotion` authorization changes while a companion process is active) leave **no** `.ips` crash log for `JumpRec Watch App`.
* To diagnose unexpected Watch exits during startup or mirroring, monitor **`tccd` logs on the paired iPhone** in Console.app filtered by `kTCCServiceMotion` or `AUTHREQ_PROMPTING`. A `preflight=no` `TCCAccessRequest` from `com.kinn.JumpRec` indicates a Core Motion call touched a protected API while authorization was `.notDetermined`.
