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

public let DefaultJumpCount: Int64 = 1000
public let DefaultJumpTime: Int64 = 10

@Observable
public class JumpRecSettings {
    public let store = NSUbiquitousKeyValueStore.default

    public var goalType: GoalType {
        didSet {
            store.set(goalType.rawValue, forKey: "goalType")
            store.synchronize()
        }
    }

    public var jumpCount: Int64 {
        didSet {
            goalType = .count
            store.set(jumpCount, forKey: "jumpCount")
            store.synchronize()
        }
    }

    public var jumpTime: Int64 {
        didSet {
            goalType = .time
            store.set(jumpTime, forKey: "jumpTime")
            store.synchronize()
        }
    }

    public init() {
        goalType = store.string(forKey: "goalType") == GoalType.time.rawValue ? .time : .count
        jumpCount = store.longLong(forKey: "jumpCount") == 0 ? DefaultJumpCount : store.longLong(forKey: "jumpCount")
        jumpTime = store.longLong(forKey: "jumpTime") == 0 ? DefaultJumpTime : store.longLong(forKey: "jumpTime")

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.loadSettings()
        }
    }

    public func loadSettings() {
        goalType = store
            .string(
                forKey: "goalType"
            ) == GoalType.time.rawValue ? .time : .count
        jumpCount = store.longLong(forKey: "jumpCount")
        jumpCount = jumpCount == 0 ? DefaultJumpCount : jumpCount
        jumpTime = store.longLong(forKey: "jumpTime")
        jumpTime = jumpTime == 0 ? DefaultJumpTime : jumpTime
    }
}
