//
//  AppState.swift
//  JumpRec
//

import AVFoundation
import Foundation
import HealthKit
import Observation
import UIKit

/// Owns the iPhone app's session lifecycle, live metrics, and companion-device coordination.
@Observable
@MainActor
final class JumpRecState {
    // MARK: - Configuration

    /// Enables CSV motion export for debug builds.
    private let isMotionCSVExportEnabled = {
        #if DEBUG
            true
        #else
            false
        #endif
    }()

    // MARK: - Session State

    /// Tracks the current lifecycle state of the session UI.
    var sessionState: SessionState = .idle
    /// Stores when the current or last session started.
    var startTime: Date?
    /// Stores when the current or last session ended.
    var endTime: Date?
    /// Stores the total number of detected jumps in the active session.
    var jumpCount = 0
    /// Stores jump offsets relative to `startTime`.
    var jumps: [TimeInterval] = []
    /// Stores the latest calorie estimate for the session.
    var caloriesBurned = 0.0
    /// Stores the average heart rate for the completed session when available.
    var averageHeartRate: Int?
    /// Stores the peak heart rate for the completed session when available.
    var peakHeartRate: Int?
    /// Stores the selected goal type for the active session.
    var sessionGoalType: GoalType?
    /// Stores the selected goal value for the active session.
    var sessionGoalValue: Int?
    /// Indicates whether the current session is being mirrored from Apple Watch.
    var isMirroredWatchSession = false
    /// Stores the saved session shown on the completion screen.
    var completedSession: JumpSession?

    // MARK: - Motion State

    /// Indicates which device is currently providing motion data.
    var activeMotionSource: DeviceSource?
    /// Indicates whether iPhone motion is currently available.
    var isPhoneMotionAvailable = false
    /// Indicates whether headphone motion is currently available.
    var isHeadphoneMotionAvailable = false
    /// Stores the exported motion CSV URL when debug export is enabled.
    var motionCSVShareURL: URL?

    /// Provides shared persistence and session-generation helpers.
    @ObservationIgnored
    let dataStore = MyDataStore.shared
    /// Tracks whether the scene is active for idle-timer management.
    @ObservationIgnored
    private var isSceneActive = false
    /// Remembers when a mirrored start request is waiting for watch confirmation.
    @ObservationIgnored
    private var pendingMirroredStart = false

    // MARK: - Dependencies

    /// Detects local motion data and jump events.
    @ObservationIgnored
    private var motionManager: MotionManager?
    /// Coordinates HealthKit workout mirroring from Apple Watch.
    @ObservationIgnored
    private let workoutMirrorManager = WorkoutMirrorManager.shared
    /// Manages iPhone HealthKit workouts.
    @ObservationIgnored
    private let phoneWorkoutManager = PhoneWorkoutManager.shared
    /// Manages watch connectivity and file transfer.
    @ObservationIgnored
    private let connectivityManager = ConnectivityManager.shared
    /// Manages live-activity presentation and updates.
    @ObservationIgnored
    private let liveActivityManager = LiveActivityManager.shared
    /// Speaks audible session prompts and milestones.
    @ObservationIgnored
    private let synthesizer = AVSpeechSynthesizer()
    // @ObservationIgnored
    // private let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    /// Emits haptic feedback for session events.
    @ObservationIgnored
    private let notificationFeedbackGenerator = UINotificationFeedbackGenerator()
    /// Announces minute milestones during time-based sessions.
    @ObservationIgnored
    private var minuteTimer: Timer?

    // MARK: - Initialization

    /// Configures managers, callback wiring, audio, and haptics.
    init() {
        motionManager = MotionManager(
            shouldRecordMotionSamples: isMotionCSVExportEnabled,
            onJumpDetected: { [weak self] source in
                self?.addJump(from: source)
            },
            onSourceChanged: { [weak self] source in
                self?.activeMotionSource = Self.deviceSource(from: source)
            },
            onAvailabilityChanged: { [weak self] isPhoneAvailable, isHeadphoneAvailable in
                self?.isPhoneMotionAvailable = isPhoneAvailable
                self?.isHeadphoneMotionAvailable = isHeadphoneAvailable
            }
        )
        motionManager?.refreshAvailability()
        workoutMirrorManager.onPayloadReceived = { [weak self] payload in
            self?.handleMirroredWorkoutPayload(payload)
        }
        workoutMirrorManager.onMirroredSessionEnded = { [weak self] in
            self?.handleMirroredSessionEnded()
        }
        connectivityManager.onCompletedSessionReceived = { [weak self] startedAt, endedAt, jumpCount, caloriesBurned, jumpOffsets, averageHeartRate, peakHeartRate, session in
            self?.applyCompletedWatchSession(
                startedAt: startedAt,
                endedAt: endedAt,
                jumpCount: jumpCount,
                caloriesBurned: caloriesBurned,
                jumpOffsets: jumpOffsets,
                averageHeartRate: averageHeartRate,
                peakHeartRate: peakHeartRate,
                session: session
            )
        }
        configureAudioSession()
        warmUpSpeechSynthesizer()
        prepareHaptics()
    }

    // MARK: - Derived Values

    /// Returns the current session duration in seconds.
    var durationSeconds: Int {
        guard let startTime else { return 0 }
        let end = endTime ?? Date()
        return max(0, Int(end.timeIntervalSince(startTime)))
    }

    /// Returns the current session duration formatted as `mm:ss`.
    var elapsedFormatted: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Returns the current average jump rate in jumps per minute.
    var averageRate: Int {
        guard durationSeconds > 0 else { return 0 }
        return Int((Double(jumpCount) * 60.0 / Double(durationSeconds)).rounded())
    }

    /// Returns the derived break metrics for the current session.
    var breakMetrics: (small: Int, long: Int, longestStreak: Int) {
        SessionMetricsCalculator.breakMetrics(from: jumps)
    }

    // MARK: - Session Lifecycle

    /// Starts a session locally or requests a mirrored watch session when available.
    func start(goalType: GoalType, goalValue: Int) {
        sessionGoalType = goalType
        sessionGoalValue = goalValue

        if connectivityManager.isPaired, connectivityManager.isWatchAppInstalled {
            pendingMirroredStart = true
            connectivityManager.syncSettings(
                goalType: goalType,
                jumpCount: Int64(goalType == .count ? goalValue : 0),
                jumpTime: Int64(goalType == .time ? goalValue : 0)
            )

            Task {
                do {
                    try await workoutMirrorManager.startCompanionWorkout()
                } catch {
                    await MainActor.run {
                        self.pendingMirroredStart = false
                        self.startLocalSession(goalType: goalType, goalValue: goalValue)
                    }
                }
            }
            return
        }

        startLocalSession(goalType: goalType, goalValue: goalValue)
    }

    /// Starts a session that is tracked directly on the iPhone.
    private func startLocalSession(goalType: GoalType, goalValue: Int) {
        let sessionStartDate = Date()
        invalidateMinuteTimer()
        resetLiveMetrics()
        completedSession = nil
        startTime = sessionStartDate
        endTime = nil
        averageHeartRate = nil
        peakHeartRate = nil
        sessionGoalType = goalType
        sessionGoalValue = goalValue
        isMirroredWatchSession = false
        pendingMirroredStart = false
        sessionState = .active
        motionManager?.startTracking()
        if goalType == .time {
            startMinuteTimer()
        }
        syncIdleTimer()
        notificationFeedbackGenerator.notificationOccurred(.success)
        speak(text: localizedSessionStartedAnnouncement)
        syncLiveActivity()
        Task {
            do {
                try await phoneWorkoutManager.startWorkout(at: sessionStartDate)
            } catch {
                print("[JumpRecState] Failed to start iPhone workout session: \(error)")
            }
        }
    }

    /// Finishes the active local session and persists its results.
    func finish() {
        guard sessionState == .active, let startTime else { return }
        guard !isMirroredWatchSession else { return }

        invalidateMinuteTimer()
        motionManager?.stopTracking()
        let motionSamples = motionManager?.consumeRecordedSamples() ?? []
        endTime = Date()
        if let endTime {
            Task {
                await phoneWorkoutManager.endWorkout(at: endTime)
            }
        }
        sessionState = .complete
        syncIdleTimer()
        notificationFeedbackGenerator.notificationOccurred(.success)
        speak(text: localizedSessionFinishedAnnouncement)
        syncLiveActivity()

        if let endTime {
            completedSession = dataStore.saveCompletedSession(
                startedAt: startTime,
                endedAt: endTime,
                jumpCount: jumpCount,
                caloriesBurned: caloriesBurned,
                jumpOffsets: jumps
            )
            exportMotionCSVIfNeeded(samples: motionSamples, startedAt: startTime, endedAt: endTime)
        }
    }

    /// Updates scene activity to keep the idle timer in sync.
    func updateSceneActive(_ isActive: Bool) {
        isSceneActive = isActive
        syncIdleTimer()
    }

    /// Resets the app back to its idle state and clears active session data.
    func reset() {
        invalidateMinuteTimer()
        motionManager?.stopTracking()
        phoneWorkoutManager.discardWorkout()
        sessionState = .idle
        resetLiveMetrics()
        activeMotionSource = nil
        motionCSVShareURL = nil
        averageHeartRate = nil
        peakHeartRate = nil
        sessionGoalType = nil
        sessionGoalValue = nil
        isMirroredWatchSession = false
        completedSession = nil
        pendingMirroredStart = false
        syncIdleTimer()
        Task {
            await liveActivityManager.endIfNeeded()
        }
    }

    // MARK: - Live Metrics

    /// Applies a newly detected jump from the local motion manager.
    private func addJump(from source: MotionManager.Source) {
        guard sessionState == .active, let startTime else { return }

        let resolvedSource = Self.deviceSource(from: source)
        if activeMotionSource == .airpods, resolvedSource == .iPhone {
            return
        }

        activeMotionSource = resolvedSource
        // impactFeedbackGenerator.impactOccurred(intensity: 0.9)
        // impactFeedbackGenerator.prepare()
        jumpCount += 1
        jumps.append(Date().timeIntervalSince(startTime))
        checkFeedbackLandmarks()
        syncLiveActivity()
        finishIfGoalReached()
    }

    /// Clears the live metrics used by the active session UI.
    private func resetLiveMetrics() {
        jumpCount = 0
        jumps.removeAll(keepingCapacity: true)
        caloriesBurned = 0
        startTime = nil
        endTime = nil
    }

    // MARK: - Mirrored Workout Handling

    /// Routes an incoming mirrored payload to the correct handler.
    private func handleMirroredWorkoutPayload(_ payload: MirroredWorkoutPayload) {
        switch payload.kind {
        case .started:
            beginMirroredSession(payload)
        case .jump:
            applyMirroredJump(payload)
        case .metrics:
            applyMirroredMetrics(payload)
        case .ended:
            applyMirroredEnding(payload)
        @unknown default:
            break
        }
    }

    /// Initializes local mirrored-session state from a watch payload.
    private func beginMirroredSession(_ payload: MirroredWorkoutPayload) {
        invalidateMinuteTimer()
        pendingMirroredStart = false
        resetLiveMetrics()
        averageHeartRate = nil
        peakHeartRate = nil
        completedSession = nil
        startTime = payload.startTime ?? Date()
        endTime = nil
        jumpCount = payload.jumpCount ?? 0
        sessionGoalType = payload.goalType
        sessionGoalValue = normalizedGoalValue(payload.goalValue, for: payload.goalType)
        sessionState = .active
        isMirroredWatchSession = true
        activeMotionSource = .watch
        syncIdleTimer()
        syncLiveActivity()
    }

    /// Applies mirrored jump updates from Apple Watch.
    private func applyMirroredJump(_ payload: MirroredWorkoutPayload) {
        guard isMirroredWatchSession else { return }

        activeMotionSource = .watch
        if let jumpCount = payload.jumpCount {
            self.jumpCount = max(self.jumpCount, jumpCount)
        }
        if let jumpOffset = payload.jumpOffset {
            let shouldAppend = jumps.last.map { jumpOffset > $0 } ?? true
            if shouldAppend {
                jumps.append(jumpOffset)
            }
        }
        syncLiveActivity()
    }

    /// Applies mirrored heart-rate and calorie updates from Apple Watch.
    private func applyMirroredMetrics(_ payload: MirroredWorkoutPayload) {
        guard isMirroredWatchSession else { return }

        if let energyBurned = payload.energyBurned {
            caloriesBurned = energyBurned
        }
        if let averageHeartRate = payload.averageHeartRate {
            self.averageHeartRate = averageHeartRate
        }
        if let peakHeartRate = payload.peakHeartRate {
            self.peakHeartRate = peakHeartRate
        }
        syncLiveActivity()
    }

    /// Applies the mirrored workout end state from Apple Watch.
    private func applyMirroredEnding(_ payload: MirroredWorkoutPayload) {
        guard isMirroredWatchSession else { return }

        invalidateMinuteTimer()
        endTime = payload.endTime ?? Date()
        if let energyBurned = payload.energyBurned {
            caloriesBurned = energyBurned
        }
        if let averageHeartRate = payload.averageHeartRate {
            self.averageHeartRate = averageHeartRate
        }
        if let peakHeartRate = payload.peakHeartRate {
            self.peakHeartRate = peakHeartRate
        }
        sessionState = .complete
        syncIdleTimer()
        syncLiveActivity()
    }

    /// Handles the mirrored session ending without a final payload.
    private func handleMirroredSessionEnded() {
        guard isMirroredWatchSession, sessionState == .active else { return }
        invalidateMinuteTimer()
        endTime = endTime ?? Date()
        sessionState = .complete
        syncIdleTimer()
        syncLiveActivity()
    }

    /// Applies a fully completed session received from the watch app.
    private func applyCompletedWatchSession(
        startedAt: Date,
        endedAt: Date,
        jumpCount: Int,
        caloriesBurned: Double,
        jumpOffsets: [TimeInterval],
        averageHeartRate: Int?,
        peakHeartRate: Int?,
        session: JumpSession
    ) {
        guard isMirroredWatchSession else { return }

        invalidateMinuteTimer()
        startTime = startedAt
        endTime = endedAt
        self.jumpCount = jumpCount
        jumps = jumpOffsets
        self.caloriesBurned = caloriesBurned
        self.averageHeartRate = averageHeartRate
        self.peakHeartRate = peakHeartRate
        completedSession = session
        sessionState = .complete
        syncIdleTimer()
        syncLiveActivity()
    }

    // MARK: - Live Activity And Idle Timer

    /// Starts, updates, or ends the live activity to match session state.
    private func syncLiveActivity() {
        let goalSummary = liveActivityGoalSummary
        let sourceLabel = liveActivitySourceLabel

        if sessionState == .idle {
            Task {
                await liveActivityManager.endIfNeeded()
            }
            return
        }

        if sessionState == .complete {
            guard let endedAt = endTime else { return }
            Task {
                await liveActivityManager.end(
                    startedAt: startTime,
                    goalSummary: goalSummary,
                    jumpCount: jumpCount,
                    caloriesBurned: caloriesBurned,
                    averageRate: averageRate,
                    sourceLabel: sourceLabel,
                    endedAt: endedAt
                )
            }
            return
        }

        guard let startTime else { return }
        Task {
            await liveActivityManager.startOrUpdate(
                startedAt: startTime,
                goalSummary: goalSummary,
                jumpCount: jumpCount,
                caloriesBurned: caloriesBurned,
                averageRate: averageRate,
                sourceLabel: sourceLabel
            )
        }
    }

    /// Keeps the system idle timer aligned with session and scene state.
    private func syncIdleTimer() {
        let shouldDisableIdleTimer = sessionState == .active && isSceneActive
        if UIApplication.shared.isIdleTimerDisabled != shouldDisableIdleTimer {
            UIApplication.shared.isIdleTimerDisabled = shouldDisableIdleTimer
        }
    }

    /// Returns the goal summary shown in the live activity.
    private var liveActivityGoalSummary: String {
        guard let goalType = sessionGoalType, let goalValue = sessionGoalValue else {
            return String(localized: "Session in progress")
        }

        if goalType == .count {
            return String(
                format: String(localized: "%@ jumps"),
                goalValue.formatted()
            )
        }

        return String(
            format: String(localized: "%lld min"),
            goalValue
        )
    }

    /// Returns the source label shown in the live activity.
    private var liveActivitySourceLabel: String {
        switch activeMotionSource {
        case .watch:
            DeviceSource.watch.shortName
        case .iPhone:
            DeviceSource.iPhone.shortName
        case .airpods:
            DeviceSource.airpods.shortName
        case nil:
            "--"
        }
    }

    /// Converts a motion-manager source into a shared display source.
    private static func deviceSource(from source: MotionManager.Source?) -> DeviceSource? {
        switch source {
        case .iPhone:
            .iPhone
        case .headphones:
            .airpods
        case nil:
            nil
        }
    }

    // MARK: - Motion Export

    /// Exports recorded motion samples to local storage and iCloud when enabled.
    private func exportMotionCSVIfNeeded(samples: [MotionSample], startedAt: Date, endedAt: Date) {
        guard isMotionCSVExportEnabled, !samples.isEmpty else {
            motionCSVShareURL = nil
            return
        }

        let csvText = makeMotionCSV(from: samples)
        let filename = makeMotionCSVFilename(startedAt: startedAt, endedAt: endedAt)
        motionCSVShareURL = ConnectivityManager.shared.saveCSVToLocalDocuments(csvText: csvText, filename: filename)
        DispatchQueue.global(qos: .utility).async {
            ConnectivityManager.shared.saveCSVtoICloud(csvText: csvText, filename: filename)
        }
    }

    /// Converts recorded motion samples into CSV text.
    private func makeMotionCSV(from samples: [MotionSample]) -> String {
        let baseTimestamp = samples.first?.timestamp ?? 0
        let header = "time,AX,AY,AZ,RX,RY,RZ"

        let rows = samples.map { sample in
            String(
                format: "%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f",
                sample.timestamp - baseTimestamp,
                sample.userAccelerationX,
                sample.userAccelerationY,
                sample.userAccelerationZ,
                sample.rotationRateX,
                sample.rotationRateY,
                sample.rotationRateZ
            )
        }

        return ([header] + rows).joined(separator: "\n")
    }

    /// Builds a stable filename for an exported motion CSV.
    private func makeMotionCSVFilename(startedAt: Date, endedAt: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let start = sanitizedFilenameTimestamp(from: formatter.string(from: startedAt))
        let end = sanitizedFilenameTimestamp(from: formatter.string(from: endedAt))
        return "motion-\(start)-\(end).csv"
    }

    /// Sanitizes a timestamp string for safe filename use.
    private func sanitizedFilenameTimestamp(from value: String) -> String {
        value.replacingOccurrences(of: ":", with: "-")
    }

    // MARK: - Audio And Haptics

    /// Configures audio so spoken feedback can play over other audio.
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session config error: \(error)")
        }
    }

    /// Pre-warms speech synthesis to avoid a long first utterance.
    private func warmUpSpeechSynthesizer() {
        let utterance = AVSpeechUtterance(string: isJapanesePreferred ? "こんにちは" : "Hello")
        utterance.volume = 0
        utterance.voice = AVSpeechSynthesisVoice(language: preferredSpeechLanguageCode)
        synthesizer.speak(utterance)
    }

    /// Prepares haptic generators used during the session.
    private func prepareHaptics() {
        // impactFeedbackGenerator.prepare()
        notificationFeedbackGenerator.prepare()
    }

    // MARK: - Goal Feedback

    /// Announces major jump milestones for local sessions.
    private func checkFeedbackLandmarks() {
        guard !isMirroredWatchSession else { return }

        if sessionGoalType == .count, jumpCount > 0, jumpCount.isMultiple(of: 100) {
            notificationFeedbackGenerator.notificationOccurred(.success)
            notificationFeedbackGenerator.prepare()
            speak(text: localizedJumpAnnouncement(for: jumpCount))
        }
    }

    /// Starts the timer used for time-based goal announcements.
    private func startMinuteTimer() {
        invalidateMinuteTimer()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMinuteLandmark()
            }
        }
    }

    /// Invalidates the active minute timer.
    private func invalidateMinuteTimer() {
        minuteTimer?.invalidate()
        minuteTimer = nil
    }

    /// Announces a minute milestone and ends the session if the time goal is reached.
    private func handleMinuteLandmark() {
        guard sessionState == .active, !isMirroredWatchSession, sessionGoalType == .time, let startTime else {
            return
        }

        let minutesElapsed = Int(Date().timeIntervalSince(startTime)) / 60
        guard minutesElapsed > 0 else { return }

        if isGoalReached(referenceDate: Date()) {
            finish()
            return
        }

        notificationFeedbackGenerator.notificationOccurred(.success)
        notificationFeedbackGenerator.prepare()
        speak(text: localizedMinuteAnnouncement(for: minutesElapsed))
    }

    /// Finishes the session immediately when the goal is satisfied.
    private func finishIfGoalReached() {
        guard isGoalReached(referenceDate: Date()) else { return }
        finish()
    }

    /// Returns whether the active goal has been reached at the given time.
    private func isGoalReached(referenceDate: Date) -> Bool {
        guard sessionState == .active,
              !isMirroredWatchSession,
              let goalType = sessionGoalType,
              let goalValue = sessionGoalValue
        else {
            return false
        }

        switch goalType {
        case .count:
            return jumpCount >= goalValue
        case .time:
            guard let startTime else { return false }
            return Int(referenceDate.timeIntervalSince(startTime)) >= goalValue * 60
        @unknown default:
            return false
        }
    }

    /// Converts mirrored goal values into the units expected by the iPhone UI.
    private func normalizedGoalValue(_ goalValue: Int?, for goalType: GoalType?) -> Int? {
        guard let goalValue, let goalType else { return goalValue }

        switch goalType {
        case .count:
            return goalValue
        case .time:
            return goalValue / 60
        @unknown default:
            return goalValue
        }
    }

    // MARK: - Speech

    /// Speaks a localized prompt after an optional delay.
    private func speak(text: String, delay: TimeInterval = 0.2) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: self.preferredSpeechLanguageCode)
            self.synthesizer.speak(utterance)
        }
    }

    /// Returns whether Japanese is the preferred system language.
    private var isJapanesePreferred: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ja") == true
    }

    /// Returns the language code used for speech synthesis.
    private var preferredSpeechLanguageCode: String {
        isJapanesePreferred ? "ja-JP" : "en-US"
    }

    /// Returns the localized spoken phrase for session start.
    private var localizedSessionStartedAnnouncement: String {
        isJapanesePreferred ? "セッションを開始しました" : "Session Started!"
    }

    /// Returns the localized spoken phrase for session end.
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
}
