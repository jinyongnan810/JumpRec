# Swift Concurrency Policy

This document defines the concurrency rules used across the JumpRec iPhone
app, Watch app, shared framework, tests, and Live Activity extension.

The goal is to make asynchronous work explicit, cancellable, ordered, and
safe under complete strict-concurrency checking.

## Compiler Policy

All Swift targets use:

```text
SWIFT_STRICT_CONCURRENCY = complete
```

New code must compile without concurrency warnings. Do not suppress a warning
until the ownership and isolation model is understood. Warnings in Swift 5
mode can become errors in Swift 6 mode.

## 1. Keep UI-Owned State on MainActor

Types that own observable UI state, SwiftData contexts, or system objects used
by presentation flows should be isolated to `MainActor`.

Project examples include `AppState`, `DataStore`, `JumpRecSettings`,
connectivity managers, workout managers, and `LiveActivityManager`.

### Good

```swift
@MainActor
@Observable
final class SessionViewModel {
    var jumpCount = 0
    var errorMessage: String?

    func applyJump() {
        jumpCount += 1
    }
}
```

The compiler now enforces one executor for every read and mutation.

### Bad

```swift
@Observable
final class SessionViewModel {
    var jumpCount = 0

    func applyJump() {
        DispatchQueue.main.async {
            self.jumpCount += 1
        }
    }
}
```

Dispatching one mutation to the main queue does not protect other access to
the same state.

## 2. Use Actors for Independent Mutable Services

Use an `actor` when a service owns mutable state or operations that must be
serialized but do not belong to the UI actor.

`CloudCSVExporter` follows this policy because delayed iCloud discovery and
file writes should be serialized independently from UI state.

### Good

```swift
actor ExportService {
    private var pendingFilenames: Set<String> = []

    func export(_ text: String, filename: String) async throws {
        guard pendingFilenames.insert(filename).inserted else { return }
        defer { pendingFilenames.remove(filename) }

        try Task.checkCancellation()
        try text.write(
            to: destinationURL(for: filename),
            atomically: true,
            encoding: .utf8
        )
    }
}
```

### Bad

```swift
final class ExportService {
    private var pendingFilenames: Set<String> = []

    func export(_ text: String, filename: String) {
        DispatchQueue.global().async {
            self.pendingFilenames.insert(filename)
        }
    }
}
```

A background queue is not an ownership model. Multiple jobs can still race on
the set and filesystem.

## 3. Suspend Instead of Blocking

Prefer async Apple APIs. Delays and retries must suspend with `Task.sleep`
instead of blocking a thread with `Thread.sleep` or a semaphore.

### Good

```swift
func waitBeforeRetry() async -> Bool {
    do {
        try await Task.sleep(for: .milliseconds(500))
        return true
    } catch is CancellationError {
        return false
    } catch {
        print("Retry delay failed: \(error.localizedDescription)")
        return false
    }
}
```

### Bad

```swift
func waitBeforeRetry() {
    Thread.sleep(forTimeInterval: 0.5)
}
```

Blocking wastes an executor thread and cannot respond promptly to task
cancellation.

## 4. Own Every Long-Lived Task

A task that can outlive its method call must have an owner. Store it in the
type responsible for the operation, cancel the previous task before replacing
it, and cancel it during teardown.

JumpRec applies this rule to workout lifecycles, delayed speech, minute
announcements, countdowns, Live Activity synchronization, authorization, and
cloud restoration.

### Good

```swift
@MainActor
final class AnnouncementController {
    private var announcementTask: Task<Void, Never>?

    func scheduleAnnouncement() {
        announcementTask?.cancel()
        announcementTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(60))
                try Task.checkCancellation()
                self?.announceElapsedMinute()
            } catch is CancellationError {
                return
            } catch {
                self?.log(error)
            }
        }
    }

    func stop() {
        announcementTask?.cancel()
        announcementTask = nil
    }
}
```

### Bad

```swift
func scheduleAnnouncement() {
    Task {
        try? await Task.sleep(for: .seconds(60))
        announceElapsedMinute()
    }
}
```

The unowned task can announce after a session ends. `try?` also hides whether
the delay completed or was cancelled.

## 5. Validate Results After Suspension

Cancellation is cooperative. A framework operation may still return after its
task is cancelled. Verify that a result still belongs to the active workflow
before committing state.

Workout flows use generation UUIDs and object identity checks so an old
completion cannot mutate a newer session.

### Good

```swift
@MainActor
final class WorkoutController {
    private var generation = UUID()
    private var lifecycleTask: Task<Void, Never>?

    func start() {
        generation = UUID()
        let expectedGeneration = generation
        lifecycleTask?.cancel()

        lifecycleTask = Task { [weak self] in
            guard let self else { return }

            await prepareWorkout()

            guard !Task.isCancelled,
                  generation == expectedGeneration
            else {
                return
            }

            publishWorkoutStarted()
        }
    }

    func invalidate() {
        generation = UUID()
        lifecycleTask?.cancel()
        lifecycleTask = nil
    }
}
```

### Bad

```swift
func start() {
    Task {
        await prepareWorkout()
        isWorkoutActive = true
    }
}
```

An old completion can reactivate state after teardown.

## 6. Treat Framework Delegates as Nonisolated Entry Points

Apple framework delegates may run on arbitrary queues. When the owning type is
`@MainActor`, declare delegate requirements `nonisolated`, read Sendable value
snapshots on the callback thread, and then hop to the main actor.

This pattern is used for WatchConnectivity, HealthKit, speech synthesis, and
workout mirroring delegates.

### Good

```swift
@MainActor
final class ConnectivityManager: NSObject, WCSessionDelegate {
    var isReachable = false

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable

        Task { @MainActor [weak self] in
            self?.isReachable = reachable
        }
    }
}
```

The non-Sendable framework object remains on its callback thread. Only a copied
`Bool` crosses the actor boundary.

### Bad

```swift
nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    Task { @MainActor in
        isReachable = session.isReachable
    }
}
```

This captures and sends the framework-owned `WCSession` reference into another
isolation domain.

## 7. Parse Loosely Typed Payloads Before Actor Hops

WatchConnectivity dictionaries contain `[String: Any]`, which is not
Sendable. Parse and validate the dictionary in the delegate callback, convert
it into Sendable values, and only then cross to the owning actor.

### Good

```swift
nonisolated func didReceive(_ payload: [String: Any]) {
    guard let count = NumberParser.int(payload["jumpCount"]),
          let timestamp = NumberParser.double(payload["startedAt"])
    else {
        return
    }

    let startedAt = Date(timeIntervalSince1970: timestamp)

    Task { @MainActor [weak self] in
        self?.applySession(jumpCount: count, startedAt: startedAt)
    }
}
```

### Bad

```swift
nonisolated func didReceive(_ payload: [String: Any]) {
    Task { @MainActor in
        let count = payload["jumpCount"] as? Int
        applySession(jumpCount: count ?? 0)
    }
}
```

The entire non-Sendable dictionary crosses the actor boundary.

## 8. Copy Ephemeral Callback Data Before Suspending

Some framework callback values are valid only during the callback. Copy their
contents before creating a task or awaiting anything.

WatchConnectivity transferred-file URLs are one example.

### Good

```swift
nonisolated func didReceive(file: WCSessionFile) {
    do {
        let filename = file.fileURL.lastPathComponent
        let data = try Data(contentsOf: file.fileURL)
        guard let text = String(data: data, encoding: .utf8) else { return }

        Task { @MainActor [weak self] in
            await self?.save(text: text, filename: filename)
        }
    } catch {
        print("Failed to copy transferred file: \(error)")
    }
}
```

### Bad

```swift
nonisolated func didReceive(file: WCSessionFile) {
    Task {
        let data = try Data(contentsOf: file.fileURL)
    }
}
```

The system may have removed the temporary file before the task executes.

## 9. Use Nonisolated Only for Independent Code

App targets default unannotated declarations to `MainActor`. Mark pure value
types, calculations, formatting helpers, and immutable protocol conformances
`nonisolated` when they must remain usable from any executor.

Project examples include `SessionMetricsCalculator`, `RateSamplePoint`,
number parsing helpers, formatting functions, and Live Activity attributes.

### Good

```swift
public nonisolated enum MetricsCalculator {
    public static func averageRate(
        jumps: Int,
        seconds: Int
    ) -> Double? {
        guard seconds > 0 else { return nil }
        return Double(jumps) * 60 / Double(seconds)
    }
}
```

### Bad

```swift
@MainActor
final class MetricsCalculator {
    static func averageRate(jumps: Int, seconds: Int) -> Double? {
        Double(jumps) * 60 / Double(seconds)
    }
}
```

Pure arithmetic should not unnecessarily require the main actor. Conversely,
never use `nonisolated` for code that reads or mutates actor-owned state.

## 10. Prefer Sendable Value Snapshots

Data crossing task or actor boundaries should be immutable value types that
conform to `Sendable`. Prefer structs, enums, numbers, strings, dates, UUIDs,
and copied arrays of Sendable elements.

### Good

```swift
struct WorkoutSnapshot: Sendable {
    let id: UUID
    let jumpCount: Int
    let caloriesBurned: Double
}

let snapshot = WorkoutSnapshot(
    id: sessionID,
    jumpCount: jumpCount,
    caloriesBurned: calories
)

await historyActor.save(snapshot)
```

### Bad

```swift
await historyActor.save(appState)
```

Passing a mutable UI object across actors creates unclear ownership.

Do not add `@unchecked Sendable` merely to remove a warning. It is allowed only
after proving and documenting the type's synchronization invariants.

## 11. Bridge Callbacks With Checked Continuations

When no async Apple API exists, wrap a single completion-handler operation
with `withCheckedContinuation` or `withCheckedThrowingContinuation`. Resume
exactly once on every callback path.

### Good

```swift
func finishWorkout(
    _ builder: HKLiveWorkoutBuilder
) async throws -> HKWorkout? {
    try await withCheckedThrowingContinuation { continuation in
        builder.finishWorkout { workout, error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: workout)
            }
        }
    }
}
```

### Bad

```swift
func finishWorkout(
    _ builder: HKLiveWorkoutBuilder
) async -> HKWorkout? {
    var result: HKWorkout?

    builder.finishWorkout { workout, _ in
        result = workout
    }

    return result
}
```

This returns before the callback executes and introduces unsynchronized
mutation.

## 12. Deduplicate Shared Async Operations

Authorization and other one-at-a-time operations should retain their in-flight
task. Concurrent callers await the same task instead of starting duplicate
system prompts or requests.

### Good

```swift
@MainActor
final class AuthorizationController {
    private var authorizationTask: Task<Void, Error>?

    func ensureAuthorization() async throws {
        if let authorizationTask {
            try await authorizationTask.value
            return
        }

        let task = Task {
            try await requestAuthorization()
        }
        authorizationTask = task

        do {
            try await task.value
        } catch {
            authorizationTask = nil
            throw error
        }
    }
}
```

### Bad

```swift
func ensureAuthorization() async throws {
    try await requestAuthorization()
}
```

Several callers can start overlapping permission requests.

## 13. Serialize Operations When Ordering Matters

When an external system must receive updates in order, retain the latest task
and await the previous task before sending the next operation.

JumpRec uses this policy for Live Activity start, update, and end operations.

### Good

```swift
let previousTask = synchronizationTask

synchronizationTask = Task { [service] in
    await previousTask?.value
    guard !Task.isCancelled else { return }
    await service.send(latestSnapshot)
}
```

### Bad

```swift
Task { await service.send(startSnapshot) }
Task { await service.send(endSnapshot) }
```

Independent tasks can complete out of order.

## 14. Use SwiftUI Task Lifetimes

Use `.task` when asynchronous view work should automatically cancel as the
view disappears. Retain a task in `@State` only when an interaction requires
explicit replacement or cancellation beyond the normal view lifetime.

### Good

```swift
struct CountdownView: View {
    @State private var remaining = 3

    var body: some View {
        Text("\(remaining)")
            .task {
                while remaining > 0 {
                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch is CancellationError {
                        return
                    } catch {
                        return
                    }

                    remaining -= 1
                }
            }
    }
}
```

### Bad

```swift
struct CountdownView: View {
    var body: some View {
        Text("Starting")
            .onAppear {
                Task {
                    while true {
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
            }
    }
}
```

Avoid creating tasks during every render or from computed view properties.

## 15. Keep Compatibility Suppressions Narrow

Use `@preconcurrency import` only when a framework API is safe by contract but
lacks the sendability annotations required by strict checking. Add a comment
explaining the exact limitation.

The ActivityKit import in `LiveActivityManager` is intentionally scoped this
way because `Activity` supports async updates and endings but its reference
type does not currently carry the required Sendable metadata.

### Good

```swift
// Activity supports async updates, but the reference lacks Sendable metadata.
@preconcurrency import ActivityKit
```

### Bad

```swift
@preconcurrency import Foundation
@preconcurrency import HealthKit
@preconcurrency import WatchConnectivity
```

Broad suppression hides unrelated problems and weakens complete checking.

## 16. Clean Up Framework Objects on Their Actor

When a type owns non-Sendable framework objects, cleanup must respect the same
isolation as normal use. Use `isolated deinit` when deinitialization needs to
access those properties.

### Good

```swift
@MainActor
final class MotionController {
    private let activityManager = CMHeadphoneActivityManager()

    isolated deinit {
        activityManager.stopStatusUpdates()
    }
}
```

### Bad

```swift
@MainActor
final class MotionController {
    private let activityManager = CMHeadphoneActivityManager()

    deinit {
        activityManager.stopStatusUpdates()
    }
}
```

A normal deinitializer is nonisolated and cannot safely access a non-Sendable
actor-owned object under complete checking.

## Review Checklist

Before merging concurrency-related code, verify:

- The target builds with complete checking and no concurrency warnings.
- Mutable UI, SwiftData, and presentation state has a clear `MainActor` owner.
- Independent mutable services use an actor or documented synchronization.
- Every long-lived task has ownership, replacement, cancellation, and teardown.
- Results are validated after suspension when work can become stale.
- Delegate callbacks do not send framework references across actors.
- `[String: Any]` payloads are converted to Sendable values before actor hops.
- Ephemeral callback resources are copied before suspension.
- Cross-actor data is immutable and Sendable where practical.
- Continuations resume exactly once on all paths.
- `@preconcurrency` and `@unchecked Sendable` are not blanket suppressions.
- Non-trivial calculations and lifecycle regressions have focused tests.

