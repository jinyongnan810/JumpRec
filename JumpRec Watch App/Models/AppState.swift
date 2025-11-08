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
import UserNotifications
import WatchKit

enum JumpState {
    case idle, jumping, finished
}

@Observable
class JumpRecState: NSObject {
    var jumpState: JumpState = .idle
    var startTime: Date?
    var endTime: Date?
    var jumpCount: Int = 0
    var heartrate: Int = 0
    var energyBurned: Double = 0
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
    var minuteTimer: Timer?

    let notificationCenter = UNUserNotificationCenter.current()

    override init() {
        super.init()
        requestNotificationAuthorization()
        notificationCenter.getNotificationSettings { settings in
            print("Authorization status: \(settings.authorizationStatus.rawValue)")
            print("Alert setting: \(settings.alertSetting.rawValue)")
        }
        notificationCenter.delegate = self
        motionManager = MotionManager(addJump: { by in
            self.addJump(by: by)
        }, updateHeartRate: { with in
            self.heartrate = with
        }, updateEnergyBurned: { with in
            self.energyBurned = self.energyBurned + with
        })
        configureAudioSession()
        warmUpSpeechSynthesizer()
    }

    func warmUpSpeechSynthesizer() {
        // first call to synthesizer.speak can be very heavy
        let utterance = AVSpeechUtterance(string: "Hello")
        utterance.volume = 0.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
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
        motionManager?.startTracking()
        startTime = Date()
        jumpState = .jumping
        if goalType == .time {
            startMinuteTimer()
        }
//        WKInterfaceDevice.current().play(.start)
        speak(text: "Session Started!")
        ConnectivityManager.shared.sendMessage(["watch app": "started"])
    }

    func end() {
        if jumpState == .finished { return }
        invalidateMinuteTimer()

        motionManager?.stopTracking()
        endTime = Date()
//        print("endTime: \(endTime!)")
        DispatchQueue.main.async {
//            print("end action dispatch started: \(Date())")
//            WKInterfaceDevice.current().play(.stop)
            let duration = self.endTime!.timeIntervalSince(self.startTime!)
            self.speak(text: "Session Finished!", delay: 0.5)
            self.scheduleNotification(
                title: "Session Finished",
                body: "You've jumped \(self.jumpCount) times in \(Int(duration)) seconds!"
            )
            ConnectivityManager.shared.sendMessage(["watch app": "finished"])
//            print("end action dispatch finished: \(Date())")
        }

        jumpState = .finished
        print("end finished")
    }

    func reset() {
        invalidateMinuteTimer()
        jumpState = .idle
        jumpCount = 0
        heartrate = 0
        energyBurned = 0
        endTime = nil
        startTime = nil
    }

    func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session config error: \(error)")
        }
    }

    func updateHeartrate(_ heartrate: Int) {
        self.heartrate = heartrate
    }

    func addJump(by: Int) {
        let before = jumpCount
        jumpCount += by
        checkJumpLandmark(before: before, after: jumpCount)
    }

    func checkJumpLandmark(before: Int, after: Int) {
        if goalType == .time {
            return
        }
        if jumpCount >= goal {
            end()
            return
        }
        if before / 100 != after / 100 {
            handleHundredJumpsLandmark(jumpCount: jumpCount)
        }
    }

    func handleHundredJumpsLandmark(jumpCount: Int) {
//        WKInterfaceDevice.current().play(.success)
        let hundred = jumpCount / 100 * 100
        speak(text: "\(hundred) Jumps")
        scheduleNotification(title: "Reached \(hundred) jumps!", body: "")
    }

    // MARK: - Time goal minute landmarks

    private func startMinuteTimer() {
        invalidateMinuteTimer()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(60), repeats: true) { [weak self] _ in
            self?.handleMinuteLandmark()
        }
        RunLoop.current.add(minuteTimer!, forMode: .common)
    }

    private func invalidateMinuteTimer() {
        minuteTimer?.invalidate()
        minuteTimer = nil
    }

    private func handleMinuteLandmark() {
        guard jumpState == .jumping, goalType == .time, let startTime else { return }
        let minutesElapsed = Int(Date().timeIntervalSince(startTime)) / 60
        if minutesElapsed <= 0 { return }
        // If we've reached or exceeded the time goal in seconds, finish.
        if minutesElapsed * 60 >= goal {
            end()
            return
        }
        let minuteText = minutesElapsed == 1 ? "1 minute" : "\(minutesElapsed) minutes"
        speak(text: minuteText)
        scheduleNotification(title: "Reached \(minuteText)", body: "")
    }

    func speak(text: String, delay: Double = 0.5) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            self.synthesizer.speak(utterance)
        }
    }

    func requestNotificationAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("Notification authorization error: \(error)")
            }
            print("Notification authorization granted: \(granted)")
        }
    }

    func scheduleNotification(title: String, body: String) {
        clearNotifications()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)

        let request = UNNotificationRequest(
            identifier: "jumprec-milestone",
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request) { error in
            if let error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }

    func clearNotifications() {
        notificationCenter
            .removePendingNotificationRequests(withIdentifiers: ["jumprec-milestone"])
        notificationCenter
            .removeDeliveredNotifications(withIdentifiers: ["jumprec-milestone"])
    }
}

// Show foreground notifications
extension JumpRecState: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_: UNUserNotificationCenter,
                                willPresent _: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        completionHandler([.banner, .sound, .list]) // or appropriate options on watchOS
    }
}
