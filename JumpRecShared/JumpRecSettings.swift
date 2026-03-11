//
//  JumpRecSettings.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/15.
//
import Foundation
import Observation

public enum GoalType: String, Codable {
    case count
    case time
}

public extension Notification.Name {
    static let jumpRecSettingsDidUpdate = Notification.Name("JumpRecSettingsDidUpdate")
}

public let DefaultJumpCount: Int64 = 1000
public let DefaultJumpTime: Int64 = 10

@Observable
public class JumpRecSettings {
    public let store = NSUbiquitousKeyValueStore.default
    @ObservationIgnored
    private var isLoadingFromStore = false

    public var goalType: GoalType {
        didSet {
            guard !isLoadingFromStore else { return }
            store.set(goalType.rawValue, forKey: "goalType")
            store.synchronize()
        }
    }

    public var jumpCount: Int64 {
        didSet {
            guard !isLoadingFromStore else { return }
            store.set(jumpCount, forKey: "jumpCount")
            store.synchronize()
        }
    }

    public var jumpTime: Int64 {
        didSet {
            guard !isLoadingFromStore else { return }
            store.set(jumpTime, forKey: "jumpTime")
            store.synchronize()
        }
    }

    public var goalCount: Int {
        Int(goalType == .count ?
            jumpCount
            : jumpTime
        )
    }

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
