//
//  AppState.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/10/05.
//

import AVFoundation
import Foundation
import JumpRecShared
import Observation
import WatchKit

enum JumpState {
    case idle, jumping, finished
}

@Observable
class JumpRecState {
    var jumpState: JumpState = .idle
    var startTime: Date?
    var endTime: Date?
    var jumpCount: Int = 0
    var heartrate: Int = 0
    var energyBurned: Int = 0
    var goalType: GoalType = .count
    var goal: Int = 0
    var totalTime: String {
        guard let startTime, let endTime else { return "00:00" }
        let timeInterval: TimeInterval = endTime.timeIntervalSince(startTime)
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval).remainderReportingOverflow(dividingBy: 60).partialValue
        return String(format: "%02d:%02d", minutes, seconds)
    }

    let synthesizer = AVSpeechSynthesizer()

    var motionManager: MotionManager?

    init() {
        motionManager = MotionManager(addJump: { by in
            self.addJump(by: by)
        }, updateHeartRate: { with in
            self.heartrate = with
        }, updateEnergyBurned: { with in
            self.energyBurned = with
        })
    }

    func start(goalType: GoalType, goalCount: Int) {
        self.goalType = goalType
        switch goalType {
        case .count:
            goal = goalCount
        case .time:
            goal = goalCount * 60
        default:
            fatalError("Unhandled GoalType")
        }
        startTime = Date()
        jumpState = .jumping
        motionManager?.startTracking()
        WKInterfaceDevice.current().play(.start)
        ConnectivityManager.shared.sendMessage(["watch app": "started"])
    }

    func end() {
        motionManager?.stopTracking()
        endTime = Date()
        jumpState = .finished
        WKInterfaceDevice.current().play(.stop)
        ConnectivityManager.shared.sendMessage(["watch app": "finished"])
    }

    func reset() {
        jumpState = .idle
        jumpCount = 0
        heartrate = 0
        energyBurned = 0
        endTime = nil
        startTime = nil
    }

    func updateHeartrate(_ heartrate: Int) {
        self.heartrate = heartrate
    }

    func addJump(by: Int) {
        let before = jumpCount
        jumpCount += by
        checkLandmark(before: before, after: jumpCount)
    }

    func checkLandmark(before: Int, after: Int) {
        if before / 100 != after / 100 {
            handleHundredJumpsLandmark(jumpCount: jumpCount)
        }
        switch goalType {
        case .count:
            if jumpCount >= goal {
                end()
            }
        case .time:
            if let startTime, let endTime {
                let duration: TimeInterval = endTime.timeIntervalSince(startTime)
                if Int(duration) >= goal {
                    end()
                }
            }
        default:
            fatalError("Unhandled GoalType")
        }
    }

    func handleHundredJumpsLandmark(jumpCount: Int) {
        WKInterfaceDevice.current().play(.success)
        speak(text: (jumpCount / 100 * 100).description)
    }

    func speak(text: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let utterance = AVSpeechUtterance(string: text)
            self.synthesizer.speak(utterance)
        }
    }
}
