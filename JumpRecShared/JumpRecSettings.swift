//
//  JumpRecSettings.swift
//  JumpRec
//
//  Created by kinn on 2025/09/15.
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

/// Synchronizes workout settings across devices on the main actor.
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

    /// Prefers iPhone headphone tracking over Watch tracking when enabled; defaults to false.
    public var preferHeadphonesForIPhoneSessions: Bool {
        didSet {
            guard !isLoadingFromStore else { return }
            store.set(preferHeadphonesForIPhoneSessions, forKey: "preferHeadphonesForIPhoneSessions")
            store.synchronize()
        }
    }

    /// Enables spoken jump milestones; defaults to true.
    public var shouldSpeakJumpCountAnnouncements: Bool {
        didSet {
            guard !isLoadingFromStore else { return }
            store.set(shouldSpeakJumpCountAnnouncements, forKey: "shouldSpeakJumpCountAnnouncements")
            store.synchronize()
        }
    }

    /// Enables spoken minute cues without affecting time-goal completion.
    public var shouldSpeakJumpTimeAnnouncements: Bool {
        didSet {
            guard !isLoadingFromStore else { return }
            store.set(shouldSpeakJumpTimeAnnouncements, forKey: "shouldSpeakJumpTimeAnnouncements")
            store.synchronize()
        }
    }

    /// Adjusts sensitivity as a percentage of each detector profile's baseline threshold.
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

    /// Free workout quota allowed before requiring a one-time license.
    public static let freeWorkoutQuota = 100
    /// Minimum jump count for a session to qualify toward the 100-workout quota.
    public static let minimumJumpsForQuotaQualification = 100

    /// Indicates whether the user has unlocked the one-time license for unlimited workouts.
    public var hasUnlockedUnlimitedWorkouts: Bool {
        didSet {
            guard !isLoadingFromStore else { return }
            store.set(hasUnlockedUnlimitedWorkouts, forKey: "hasUnlockedUnlimitedWorkouts")
            store.synchronize()
        }
    }

    /// Completed workouts with at least 100 jumps, synced between iPhone and Watch.
    public var qualifiedWorkoutCount: Int {
        didSet {
            guard !isLoadingFromStore else { return }
            store.set(Int64(qualifiedWorkoutCount), forKey: "qualifiedWorkoutCount")
            store.synchronize()
        }
    }

    /// Whether the user has exceeded their free workout quota and needs to unlock the license.
    public var isQuotaExceeded: Bool {
        !hasUnlockedUnlimitedWorkouts && qualifiedWorkoutCount >= Self.freeWorkoutQuota
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

    #if DEBUG
        /// Provides a Watch preview quota with iCloud reads, writes, and sync observers disabled.
        public init(previewQualifiedWorkoutCount: Int) {
            isLoadingFromStore = true
            goalType = .count
            jumpCount = DefaultJumpCount
            jumpTime = DefaultJumpTime
            preferHeadphonesForIPhoneSessions = false
            shouldSpeakJumpCountAnnouncements = true
            shouldSpeakJumpTimeAnnouncements = true
            jumpDetectorThresholdAdjustmentPercentage = DefaultJumpDetectorThresholdAdjustmentPercentage
            hasUnlockedUnlimitedWorkouts = false
            qualifiedWorkoutCount = previewQualifiedWorkoutCount
        }
    #endif

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
        hasUnlockedUnlimitedWorkouts = false
        qualifiedWorkoutCount = 0
        loadSettings()

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            // Notification callbacks are Sendable, so settings updates require a main-actor hop.
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
        let storedHasUnlockedUnlimitedWorkouts = store.bool(forKey: "hasUnlockedUnlimitedWorkouts")
        let storedQualifiedWorkoutCount = Int(store.longLong(forKey: "qualifiedWorkoutCount"))

        isLoadingFromStore = true
        goalType = storedGoalType
        jumpCount = storedJumpCount == 0 ? DefaultJumpCount : storedJumpCount
        jumpTime = storedJumpTime == 0 ? DefaultJumpTime : storedJumpTime
        preferHeadphonesForIPhoneSessions = storedPreferHeadphonesForIPhoneSessions
        shouldSpeakJumpCountAnnouncements = storedShouldSpeakJumpCountAnnouncements
        shouldSpeakJumpTimeAnnouncements = storedShouldSpeakJumpTimeAnnouncements
        jumpDetectorThresholdAdjustmentPercentage = Self.clampedJumpDetectorThresholdAdjustmentPercentage(storedThresholdAdjustmentPercentage)
        hasUnlockedUnlimitedWorkouts = storedHasUnlockedUnlimitedWorkouts
        qualifiedWorkoutCount = storedQualifiedWorkoutCount
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
