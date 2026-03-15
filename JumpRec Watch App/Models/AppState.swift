//
//  AppState.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/10/05.
//

import AVFoundation
import Foundation
import Observation
import WatchKit

enum JumpState {
    case idle, jumping, finished
}

@Observable
@MainActor
class JumpRecState {
    static let shared = JumpRecState()

    var jumpState: JumpState = .idle
    var startTime: Date?
    var endTime: Date?
    var jumpCount: Int = 0
    var jumps: [TimeInterval] = []
    var heartrate: Int = 0
    @ObservationIgnored
    var heartRateSum: Int = 0
    @ObservationIgnored
    var heartRateSampleCount: Int = 0
    @ObservationIgnored
    var peakHeartRate: Int = 0
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

    @ObservationIgnored
    let dataStore = MyDataStore.shared

    @ObservationIgnored
    let synthesizer = AVSpeechSynthesizer()

    @ObservationIgnored
    var motionManager: MotionManager?
    @ObservationIgnored
    var minuteTimer: Timer?

//    let notificationCenter = UNUserNotificationCenter.current()

    init() {
        motionManager = MotionManager(addJump: { by in
            Task { @MainActor in
                self.addJump(by: by)
            }
        }, updateHeartRate: { with in
            Task { @MainActor in
                self.recordHeartRate(with)
            }
        }, updateEnergyBurned: { with in
            Task { @MainActor in
                self.energyBurned += with
            }
        })
        configureAudioSession()
        warmUpSpeechSynthesizer()
    }

    func warmUpSpeechSynthesizer() {
        // first call to synthesizer.speak can be very heavy
        let utterance = AVSpeechUtterance(string: isJapanesePreferred ? "こんにちは" : "Hello")
        utterance.volume = 0.0
        utterance.voice = AVSpeechSynthesisVoice(language: preferredSpeechLanguageCode)
        synthesizer.speak(utterance)
    }

    func start(goalType: GoalType, goalCount: Int) {
        resetSessionMetrics()
        self.goalType = goalType
        switch goalType {
        case .count:
            goal = goalCount
        case .time:
            goal = goalCount * 60
        @unknown default:
            goal = goalCount
        }
        startTime = Date()
        if let startTime {
            motionManager?.startTracking(startDate: startTime, goalType: goalType, goalValue: goal)
        }
        jumpState = .jumping
        if goalType == .time {
            startMinuteTimer()
        }
        WKInterfaceDevice.current().play(.start)
        speak(text: localizedSessionStartedAnnouncement)
        ConnectivityManager.shared.sendMessage(["watch app": "started"])
    }

    func startFromCompanion() {
        let settings = JumpRecSettings()
        settings.loadSettings()
        start(goalType: settings.goalType, goalCount: settings.goalCount)
    }

    func end() {
        guard jumpState == .jumping else { return }
        invalidateMinuteTimer()

        motionManager?.stopTracking()
        endTime = Date()
        speak(text: localizedSessionFinishedAnnouncement, delay: 0.5)
        WKInterfaceDevice.current().play(.stop)
        ConnectivityManager.shared.sendMessage(["watch app": "finished"])

        jumpState = .finished

        // save data to database
        guard let startTime, let endTime else { return }
        dataStore.saveCompletedSession(
            startedAt: startTime,
            endedAt: endTime,
            jumpCount: jumpCount,
            caloriesBurned: energyBurned,
            jumpOffsets: jumps,
            averageHeartRate: averageHeartRate,
            peakHeartRate: peakHeartRateValue
        )

        ConnectivityManager.shared.sendCompletedSession(
            startedAt: startTime,
            endedAt: endTime,
            jumpCount: jumpCount,
            caloriesBurned: energyBurned,
            jumpOffsets: jumps,
            averageHeartRate: averageHeartRate,
            peakHeartRate: peakHeartRateValue
        )

        print("end finished")
    }

    func reset() {
        invalidateMinuteTimer()
        motionManager?.stopTracking()
        resetSessionMetrics()
        jumpState = .idle
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

    private func recordHeartRate(_ heartRate: Int) {
        heartrate = heartRate
        heartRateSum += heartRate
        heartRateSampleCount += 1
        peakHeartRate = max(peakHeartRate, heartRate)
    }

    private var averageHeartRate: Int? {
        guard heartRateSampleCount > 0 else { return nil }
        return heartRateSum / heartRateSampleCount
    }

    private var peakHeartRateValue: Int? {
        peakHeartRate > 0 ? peakHeartRate : nil
    }

    func addJump(by: Int) {
        guard jumpState == .jumping, let startTime else { return }
        let before = jumpCount
        jumpCount += by
        let jumpOffset = Date().timeIntervalSince(startTime)
        jumps.append(jumpOffset)
        motionManager?.recordJump(jumpCount: jumpCount, jumpOffset: jumpOffset)
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
        WKInterfaceDevice.current().play(.success)
        let hundred = jumpCount / 100 * 100
        speak(text: localizedJumpAnnouncement(for: hundred))
//        scheduleNotification(title: "Reached \(hundred) jumps!", body: "")
    }

    // MARK: - Time goal minute landmarks

    private func startMinuteTimer() {
        invalidateMinuteTimer()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(60), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMinuteLandmark()
            }
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
        speak(text: localizedMinuteAnnouncement(for: minutesElapsed))
        WKInterfaceDevice.current().play(.success)
//        scheduleNotification(title: "Reached \(minuteText)", body: "")
    }

    func speak(text: String, delay: Double = 0.5) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: self.preferredSpeechLanguageCode)
            self.synthesizer.speak(utterance)
        }
    }

    private var isJapanesePreferred: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ja") == true
    }

    private var preferredSpeechLanguageCode: String {
        isJapanesePreferred ? "ja-JP" : "en-US"
    }

    private var localizedSessionStartedAnnouncement: String {
        isJapanesePreferred ? "セッションを開始しました" : "Session Started!"
    }

    private var localizedSessionFinishedAnnouncement: String {
        isJapanesePreferred ? "セッションを終了しました" : "Session Finished!"
    }

    private func localizedJumpAnnouncement(for jumpCount: Int) -> String {
        if isJapanesePreferred {
            return "\(jumpCount) 回"
        }
        return "\(jumpCount) Jumps"
    }

    private func localizedMinuteAnnouncement(for minutesElapsed: Int) -> String {
        if isJapanesePreferred {
            return "\(minutesElapsed) 分"
        }
        return minutesElapsed == 1 ? "1 minute" : "\(minutesElapsed) minutes"
    }

    private func resetSessionMetrics() {
        jumpCount = 0
        jumps.removeAll(keepingCapacity: true)
        heartrate = 0
        heartRateSum = 0
        heartRateSampleCount = 0
        peakHeartRate = 0
        energyBurned = 0
        endTime = nil
        startTime = nil
    }

//    func requestNotificationAuthorization() {
//        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
//            if let error {
//                print("Notification authorization error: \(error)")
//            }
//            print("Notification authorization granted: \(granted)")
//        }
//    }
//
//    func scheduleNotification(title: String, body: String) {
//        clearNotifications()
//
//        let content = UNMutableNotificationContent()
//        content.title = title
//        content.body = body
//        content.sound = .default
//
//        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
//
//        let request = UNNotificationRequest(
//            identifier: "jumprec-milestone",
//            content: content,
//            trigger: trigger
//        )
//
//        notificationCenter.add(request) { error in
//            if let error {
//                print("Failed to schedule notification: \(error)")
//            }
//        }
//    }
//
//    func clearNotifications() {
//        notificationCenter
//            .removePendingNotificationRequests(withIdentifiers: ["jumprec-milestone"])
//        notificationCenter
//            .removeDeliveredNotifications(withIdentifiers: ["jumprec-milestone"])
//    }
}

// Show foreground notifications
// extension JumpRecState: UNUserNotificationCenterDelegate {
//    func userNotificationCenter(_: UNUserNotificationCenter,
//                                willPresent _: UNNotification,
//                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
//    {
//        completionHandler([.banner, .sound, .list]) // or appropriate options on watchOS
//    }
// }
