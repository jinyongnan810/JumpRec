//
//  JumpRecSettings.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/15.
//
import Foundation
import Observation

/// Defines the kinds of workout goals users can choose from.
public enum GoalType: String, Codable, Sendable {
    /// A jump-count-based goal.
    case count
    /// A time-based goal.
    case time
}

public extension Notification.Name {
    /// Posted when settings synced from the paired device change.
    static let jumpRecSettingsDidUpdate = Notification.Name("JumpRecSettingsDidUpdate")
}

/// Default jump-count goal used for new installs and resets.
public let DefaultJumpCount: Int64 = 1000
/// Default time goal used for new installs and resets.
public let DefaultJumpTime: Int64 = 10
/// Default relative threshold adjustment for jump detection.
public let DefaultJumpDetectorThresholdAdjustmentPercentage = 0.0
/// Lowest supported relative threshold adjustment for jump detection.
public let MinimumJumpDetectorThresholdAdjustmentPercentage = -50.0
/// Highest supported relative threshold adjustment for jump detection.
public let MaximumJumpDetectorThresholdAdjustmentPercentage = 50.0

/// Stores and synchronizes user-selected workout settings across devices.
///
/// Settings are observed directly by SwiftUI, so all reads and mutations are isolated to the
/// main actor. This also gives notification callbacks a single, explicit synchronization point.
@MainActor
@Observable
public class JumpRecSettings {
    // MARK: - Dependencies

    /// The iCloud-backed key-value store used for persistence and sync.
    public let store = NSUbiquitousKeyValueStore.default
    /// Prevents save loops while values are being reloaded from storage.
    @ObservationIgnored
    private var isLoadingFromStore = false

    // MARK: - Persisted Settings

    /// The active goal type selected by the user.
    public var goalType: GoalType {
        didSet {
            guard !isLoadingFromStore else { return }
            store.set(goalType.rawValue, forKey: "goalType")
            store.synchronize()
        }
    }

    /// The saved jump-count goal value.
    public var jumpCount: Int64 {
        didSet {
            guard !isLoadingFromStore else { return }
            store.set(jumpCount, forKey: "jumpCount")
            store.synchronize()
        }
    }

    /// The saved time goal value in minutes.
    public var jumpTime: Int64 {
        didSet {
            guard !isLoadingFromStore else { return }
            store.set(jumpTime, forKey: "jumpTime")
            store.synchronize()
        }
    }

    /// Indicates whether compatible headphones should keep a session on iPhone instead of starting on Apple Watch.
    ///
    /// The default remains `false` to preserve the existing Watch-first behavior for current users.
    /// Users who prefer headphone motion can opt into iPhone sessions from the settings sheet.
    public var preferHeadphonesForIPhoneSessions: Bool {
        didSet {
            guard !isLoadingFromStore else { return }
            store.set(preferHeadphonesForIPhoneSessions, forKey: "preferHeadphonesForIPhoneSessions")
            store.synchronize()
        }
    }

    /// Controls whether the app speaks jump-count milestones during a workout.
    ///
    /// This defaults to `true` for both new and existing installs so current audible
    /// feedback behavior is preserved until the user explicitly turns it off.
    public var shouldSpeakJumpCountAnnouncements: Bool {
        didSet {
            guard !isLoadingFromStore else { return }
            store.set(shouldSpeakJumpCountAnnouncements, forKey: "shouldSpeakJumpCountAnnouncements")
            store.synchronize()
        }
    }

    /// Controls whether the app speaks elapsed-time milestones during a workout.
    ///
    /// Time-goal completion still works when this is disabled; only the spoken minute
    /// cue is muted so the setting does not change workout lifecycle behavior.
    public var shouldSpeakJumpTimeAnnouncements: Bool {
        didSet {
            guard !isLoadingFromStore else { return }
            store.set(shouldSpeakJumpTimeAnnouncements, forKey: "shouldSpeakJumpTimeAnnouncements")
            store.synchronize()
        }
    }

    /// Stores the relative sensitivity adjustment applied to the shared jump detector thresholds.
    ///
    /// This is intentionally a percentage instead of a raw acceleration value. Keeping settings
    /// relative to each detector profile lets the app improve default calibration later without
    /// migrating user data or exposing implementation details in the UI.
    public var jumpDetectorThresholdAdjustmentPercentage: Double {
        didSet {
            let clampedValue = Self.clampedJumpDetectorThresholdAdjustmentPercentage(jumpDetectorThresholdAdjustmentPercentage)
            if jumpDetectorThresholdAdjustmentPercentage != clampedValue {
                jumpDetectorThresholdAdjustmentPercentage = clampedValue
                return
            }

            guard !isLoadingFromStore else { return }
            store.set(jumpDetectorThresholdAdjustmentPercentage, forKey: "jumpDetectorThresholdAdjustmentPercentage")
            store.synchronize()
        }
    }

    // MARK: - Derived Values

    /// Returns the currently active goal value as an `Int`.
    public var goalCount: Int {
        Int(goalType == .count ?
            jumpCount
            : jumpTime
        )
    }

    // MARK: - Initialization

    /// Loads the initial settings and starts observing sync updates.
    public init() {
        store.synchronize()
        goalType = .count
        jumpCount = DefaultJumpCount
        jumpTime = DefaultJumpTime
        preferHeadphonesForIPhoneSessions = false
        shouldSpeakJumpCountAnnouncements = true
        shouldSpeakJumpTimeAnnouncements = true
        jumpDetectorThresholdAdjustmentPercentage = DefaultJumpDetectorThresholdAdjustmentPercentage
        loadSettings()

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            // NotificationCenter's closure is Sendable even when delivery uses the main queue.
            // An explicit task communicates the actor hop to Swift's concurrency checker.
            Task { @MainActor [weak self] in
                self?.loadSettings()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .jumpRecSettingsDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Paired-device updates use the same main-actor reload path as iCloud updates.
            Task { @MainActor [weak self] in
                self?.loadSettings()
            }
        }
    }

    // MARK: - Loading

    /// Reloads settings from the shared store without triggering write-back loops.
    public func loadSettings() {
        store.synchronize()

        let storedGoalType: GoalType = store
            .string(
                forKey: "goalType"
            ) == GoalType.time.rawValue ? .time : .count
        let storedJumpCount = store.longLong(forKey: "jumpCount")
        let storedJumpTime = store.longLong(forKey: "jumpTime")
        let storedPreferHeadphonesForIPhoneSessions = store.bool(forKey: "preferHeadphonesForIPhoneSessions")
        let storedShouldSpeakJumpCountAnnouncements = store.object(forKey: "shouldSpeakJumpCountAnnouncements") as? Bool ?? true
        let storedShouldSpeakJumpTimeAnnouncements = store.object(forKey: "shouldSpeakJumpTimeAnnouncements") as? Bool ?? true
        let storedThresholdAdjustmentPercentage = (store.object(forKey: "jumpDetectorThresholdAdjustmentPercentage") as? NSNumber)?.doubleValue
            ?? DefaultJumpDetectorThresholdAdjustmentPercentage

        isLoadingFromStore = true
        goalType = storedGoalType
        jumpCount = storedJumpCount == 0 ? DefaultJumpCount : storedJumpCount
        jumpTime = storedJumpTime == 0 ? DefaultJumpTime : storedJumpTime
        preferHeadphonesForIPhoneSessions = storedPreferHeadphonesForIPhoneSessions
        shouldSpeakJumpCountAnnouncements = storedShouldSpeakJumpCountAnnouncements
        shouldSpeakJumpTimeAnnouncements = storedShouldSpeakJumpTimeAnnouncements
        jumpDetectorThresholdAdjustmentPercentage = Self.clampedJumpDetectorThresholdAdjustmentPercentage(storedThresholdAdjustmentPercentage)
        isLoadingFromStore = false
    }

    /// Clamps persisted and synced threshold adjustments to the range supported by the settings UI.
    public static func clampedJumpDetectorThresholdAdjustmentPercentage(_ percentage: Double) -> Double {
        min(
            MaximumJumpDetectorThresholdAdjustmentPercentage,
            max(MinimumJumpDetectorThresholdAdjustmentPercentage, percentage)
        )
    }
}
