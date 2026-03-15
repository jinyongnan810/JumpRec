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
    /// No workout is running.
    case idle, jumping, finished
}

/// Owns the watch app's session lifecycle, motion tracking, and mirrored workout updates.
@Observable
@MainActor
class JumpRecState {
    // MARK: - Shared Instance

    /// Provides the single shared app state used across watch views.
    static let shared = JumpRecState()

    // MARK: - Session State

    /// Tracks the current watch-side session state.
    var jumpState: JumpState = .idle
    /// Stores when the current or last session started.
    var startTime: Date?
    /// Stores when the current or last session ended.
    var endTime: Date?
    /// Stores the total jump count for the session.
    var jumpCount: Int = 0
    /// Stores jump offsets relative to `startTime`.
    var jumps: [TimeInterval] = []
    /// Stores the latest heart-rate sample.
    var heartrate: Int = 0
    /// Accumulates heart-rate samples for average calculation.
    @ObservationIgnored
    var heartRateSum: Int = 0
    /// Counts heart-rate samples used for averaging.
    @ObservationIgnored
    var heartRateSampleCount: Int = 0
    /// Stores the highest observed heart rate.
    @ObservationIgnored
    var peakHeartRate: Int = 0
    /// Stores the latest calorie estimate from HealthKit.
    var energyBurned: Double = 0
    /// Stores the active goal type for the session.
    var goalType: GoalType = .count
    /// Stores the active goal value, in jumps or seconds depending on `goalType`.
    var goal: Int = 0
    /// Returns the finished session duration formatted as `mm:ss`.
    var totalTime: String {
        guard let startTime, let endTime else { return "00:00" }
        let timeInterval: TimeInterval = endTime.timeIntervalSince(startTime)
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval).remainderReportingOverflow(dividingBy: 60).partialValue
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Provides shared persistence helpers.
    @ObservationIgnored
    let dataStore = MyDataStore.shared

    /// Speaks workout announcements on Apple Watch.
    @ObservationIgnored
    let synthesizer = AVSpeechSynthesizer()

    /// Detects watch motion and jump events.
    @ObservationIgnored
    var motionManager: MotionManager?
    /// Announces minute milestones during time-based sessions.
    @ObservationIgnored
    var minuteTimer: Timer?

//    let notificationCenter = UNUserNotificationCenter.current()

    // MARK: - Initialization

    /// Configures motion tracking and speech for the watch app.
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

    // MARK: - Session Lifecycle

    /// Pre-warms speech synthesis to avoid a heavy first utterance.
    func warmUpSpeechSynthesizer() {
        // first call to synthesizer.speak can be very heavy
        let utterance = AVSpeechUtterance(string: isJapanesePreferred ? "こんにちは" : "Hello")
        utterance.volume = 0.0
        utterance.voice = AVSpeechSynthesisVoice(language: preferredSpeechLanguageCode)
        synthesizer.speak(utterance)
    }

    /// Starts a new watch-tracked workout session.
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

    /// Starts a workout using settings received from the companion iPhone app.
    func startFromCompanion() {
        let settings = JumpRecSettings()
        settings.loadSettings()
        start(goalType: settings.goalType, goalCount: settings.goalCount)
    }

    /// Ends the current watch workout, saves it, and sends results to the phone.
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

    /// Resets the watch app back to the idle state.
    func reset() {
        invalidateMinuteTimer()
        motionManager?.stopTracking()
        resetSessionMetrics()
        jumpState = .idle
    }

    // MARK: - Audio

    /// Configures audio so speech prompts can play during the session.
    func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session config error: \(error)")
        }
    }

    // MARK: - Metrics

    /// Updates the latest visible heart-rate sample.
    func updateHeartrate(_ heartrate: Int) {
        self.heartrate = heartrate
    }

    /// Records heart-rate data for average and peak tracking.
    private func recordHeartRate(_ heartRate: Int) {
        heartrate = heartRate
        heartRateSum += heartRate
        heartRateSampleCount += 1
        peakHeartRate = max(peakHeartRate, heartRate)
    }

    /// Returns the average heart rate for the current session.
    private var averageHeartRate: Int? {
        guard heartRateSampleCount > 0 else { return nil }
        return heartRateSum / heartRateSampleCount
    }

    /// Returns the peak heart rate only when one has been recorded.
    private var peakHeartRateValue: Int? {
        peakHeartRate > 0 ? peakHeartRate : nil
    }

    /// Adds newly detected jumps to the active session.
    func addJump(by: Int) {
        guard jumpState == .jumping, let startTime else { return }
        let before = jumpCount
        jumpCount += by
        let jumpOffset = Date().timeIntervalSince(startTime)
        jumps.append(jumpOffset)
        motionManager?.recordJump(jumpCount: jumpCount, jumpOffset: jumpOffset)
        checkJumpLandmark(before: before, after: jumpCount)
    }

    /// Handles count-based milestones and goal completion.
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

    /// Announces each 100-jump landmark during count-based sessions.
    func handleHundredJumpsLandmark(jumpCount: Int) {
        WKInterfaceDevice.current().play(.success)
        let hundred = jumpCount / 100 * 100
        speak(text: localizedJumpAnnouncement(for: hundred))
//        scheduleNotification(title: "Reached \(hundred) jumps!", body: "")
    }

    // MARK: - Time goal minute landmarks

    /// Starts the timer used for minute-based announcements.
    private func startMinuteTimer() {
        invalidateMinuteTimer()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(60), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMinuteLandmark()
            }
        }
        RunLoop.current.add(minuteTimer!, forMode: .common)
    }

    /// Invalidates the active minute timer.
    private func invalidateMinuteTimer() {
        minuteTimer?.invalidate()
        minuteTimer = nil
    }

    /// Announces elapsed minutes and ends the session when the time goal is met.
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

    // MARK: - Speech

    /// Speaks a localized prompt after an optional delay.
    func speak(text: String, delay: Double = 0.5) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: self.preferredSpeechLanguageCode)
            self.synthesizer.speak(utterance)
        }
    }

    /// Returns whether Japanese is the preferred language.
    private var isJapanesePreferred: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ja") == true
    }

    /// Returns the speech language code used for announcements.
    private var preferredSpeechLanguageCode: String {
        isJapanesePreferred ? "ja-JP" : "en-US"
    }

    /// Returns the localized spoken phrase for session start.
    private var localizedSessionStartedAnnouncement: String {
        isJapanesePreferred ? "セッションを開始しました" : "Session Started!"
    }

    /// Returns the localized spoken phrase for session finish.
    private var localizedSessionFinishedAnnouncement: String {
        isJapanesePreferred ? "セッションを終了しました" : "Session Finished!"
    }

    /// Returns the localized spoken phrase for jump milestones.
    private func localizedJumpAnnouncement(for jumpCount: Int) -> String {
        if isJapanesePreferred {
            return "\(jumpCount) 回"
        }
        return "\(jumpCount) Jumps"
    }

    /// Returns the localized spoken phrase for minute milestones.
    private func localizedMinuteAnnouncement(for minutesElapsed: Int) -> String {
        if isJapanesePreferred {
            return "\(minutesElapsed) 分"
        }
        return minutesElapsed == 1 ? "1 minute" : "\(minutesElapsed) minutes"
    }

    // MARK: - Reset

    /// Clears the live metrics stored for the current session.
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
