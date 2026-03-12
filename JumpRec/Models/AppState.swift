//
//  AppState.swift
//  JumpRec
//

import AVFoundation
import Foundation
import JumpRecShared
import Observation
import UIKit

@Observable
@MainActor
final class JumpRecState {
    private let isMotionCSVExportEnabled = false

    var sessionState: SessionState = .idle
    var startTime: Date?
    var endTime: Date?
    var jumpCount = 0
    var jumps: [TimeInterval] = []
    var caloriesBurned = 0.0
    var averageHeartRate: Int?
    var peakHeartRate: Int?
    var sessionGoalType: GoalType?
    var sessionGoalValue: Int?
    var isMirroredWatchSession = false
    var completedSession: JumpSession?

    var activeMotionSource: DeviceSource?
    var isPhoneMotionAvailable = false
    var isHeadphoneMotionAvailable = false
    var motionCSVShareURL: URL?

    @ObservationIgnored
    let dataStore = MyDataStore.shared
    @ObservationIgnored
    private var pendingMirroredStart = false

    @ObservationIgnored
    private var motionManager: MotionManager?
    @ObservationIgnored
    private let workoutMirrorManager = WorkoutMirrorManager.shared
    @ObservationIgnored
    private let connectivityManager = ConnectivityManager.shared
    @ObservationIgnored
    private let liveActivityManager = LiveActivityManager.shared
    @ObservationIgnored
    private let synthesizer = AVSpeechSynthesizer()
    // @ObservationIgnored
    // private let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored
    private let notificationFeedbackGenerator = UINotificationFeedbackGenerator()
    @ObservationIgnored
    private var minuteTimer: Timer?

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

    var durationSeconds: Int {
        guard let startTime else { return 0 }
        let end = endTime ?? Date()
        return max(0, Int(end.timeIntervalSince(startTime)))
    }

    var elapsedFormatted: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var averageRate: Int {
        guard durationSeconds > 0 else { return 0 }
        return Int((Double(jumpCount) * 60.0 / Double(durationSeconds)).rounded())
    }

    var breakMetrics: (small: Int, long: Int, longestStreak: Int) {
        SessionMetricsCalculator.breakMetrics(from: jumps)
    }

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

    private func startLocalSession(goalType: GoalType, goalValue: Int) {
        invalidateMinuteTimer()
        resetLiveMetrics()
        completedSession = nil
        startTime = Date()
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
        notificationFeedbackGenerator.notificationOccurred(.success)
        speak(text: "Session Started!")
        syncLiveActivity()
    }

    func finish() {
        guard sessionState == .active, let startTime else { return }
        guard !isMirroredWatchSession else { return }

        invalidateMinuteTimer()
        motionManager?.stopTracking()
        let motionSamples = motionManager?.consumeRecordedSamples() ?? []
        endTime = Date()
        sessionState = .complete
        notificationFeedbackGenerator.notificationOccurred(.success)
        speak(text: "Session Finished!")
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

    func reset() {
        invalidateMinuteTimer()
        motionManager?.stopTracking()
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
        Task {
            await liveActivityManager.endIfNeeded()
        }
    }

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

    private func resetLiveMetrics() {
        jumpCount = 0
        jumps.removeAll(keepingCapacity: true)
        caloriesBurned = 0
        startTime = nil
        endTime = nil
    }

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
        syncLiveActivity()
    }

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
        syncLiveActivity()
    }

    private func handleMirroredSessionEnded() {
        guard isMirroredWatchSession, sessionState == .active else { return }
        invalidateMinuteTimer()
        endTime = endTime ?? Date()
        sessionState = .complete
        syncLiveActivity()
    }

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
        syncLiveActivity()
    }

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

    private var liveActivityGoalSummary: String {
        guard let goalType = sessionGoalType, let goalValue = sessionGoalValue else {
            return "Session in progress"
        }

        if goalType == .count {
            return "\(goalValue.formatted()) jumps"
        }

        return "\(goalValue) min"
    }

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

    private func makeMotionCSVFilename(startedAt: Date, endedAt: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let start = sanitizedFilenameTimestamp(from: formatter.string(from: startedAt))
        let end = sanitizedFilenameTimestamp(from: formatter.string(from: endedAt))
        return "motion-\(start)-\(end).csv"
    }

    private func sanitizedFilenameTimestamp(from value: String) -> String {
        value.replacingOccurrences(of: ":", with: "-")
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session config error: \(error)")
        }
    }

    private func warmUpSpeechSynthesizer() {
        let utterance = AVSpeechUtterance(string: "Hello")
        utterance.volume = 0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    private func prepareHaptics() {
        // impactFeedbackGenerator.prepare()
        notificationFeedbackGenerator.prepare()
    }

    private func checkFeedbackLandmarks() {
        guard !isMirroredWatchSession else { return }

        if sessionGoalType == .count, jumpCount > 0, jumpCount.isMultiple(of: 100) {
            notificationFeedbackGenerator.notificationOccurred(.success)
            notificationFeedbackGenerator.prepare()
            speak(text: "\(jumpCount) Jumps")
        }
    }

    private func startMinuteTimer() {
        invalidateMinuteTimer()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMinuteLandmark()
            }
        }
    }

    private func invalidateMinuteTimer() {
        minuteTimer?.invalidate()
        minuteTimer = nil
    }

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

        let minuteText = minutesElapsed == 1 ? "1 minute" : "\(minutesElapsed) minutes"
        notificationFeedbackGenerator.notificationOccurred(.success)
        notificationFeedbackGenerator.prepare()
        speak(text: minuteText)
    }

    private func finishIfGoalReached() {
        guard isGoalReached(referenceDate: Date()) else { return }
        finish()
    }

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

    private func speak(text: String, delay: TimeInterval = 0.2) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            self.synthesizer.speak(utterance)
        }
    }
}
