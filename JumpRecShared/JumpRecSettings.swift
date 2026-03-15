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

/// Stores and synchronizes user-selected workout settings across devices.
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
        loadSettings()

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.loadSettings()
        }

        NotificationCenter.default.addObserver(
            forName: .jumpRecSettingsDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadSettings()
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

        isLoadingFromStore = true
        goalType = storedGoalType
        jumpCount = storedJumpCount == 0 ? DefaultJumpCount : storedJumpCount
        jumpTime = storedJumpTime == 0 ? DefaultJumpTime : storedJumpTime
        isLoadingFromStore = false
    }
}
