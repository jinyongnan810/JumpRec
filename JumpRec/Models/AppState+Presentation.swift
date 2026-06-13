//
//  AppState+Presentation.swift
//  JumpRec
//

import AVFoundation
import Foundation
import UIKit

extension JumpRecState {
    // MARK: - Live Activity And Idle Timer

    /// Starts, updates, or ends the live activity to match session state.
    ///
    /// Every operation waits for the previous ActivityKit call before proceeding. Metric
    /// updates cancel the superseded task, so rapid jump events collapse to the newest
    /// snapshot while an update already accepted by ActivityKit is still allowed to finish.
    /// Terminal operations use the same chain, ensuring stale content cannot run after end.
    func syncLiveActivity() {
        let previousTask = liveActivitySyncTask
        previousTask?.cancel()

        if sessionState == .idle {
            liveActivitySyncTask = Task { [liveActivityManager] in
                await previousTask?.value
                await liveActivityManager.endIfNeeded()
            }
            return
        }

        if sessionState == .complete {
            guard let endedAt = endTime else { return }

            // Capture final values before suspension so later reset work cannot alter the
            // content that belongs to the completed session.
            let startedAt = startTime
            let goalSummary = liveActivityGoalSummary
            let finalJumpCount = jumpCount
            let finalCaloriesBurned = caloriesBurned
            let finalAverageRate = averageRate
            let finalSourceLabel = liveActivitySourceLabel

            liveActivitySyncTask = Task { [liveActivityManager] in
                await previousTask?.value
                await liveActivityManager.end(
                    startedAt: startedAt,
                    goalSummary: goalSummary,
                    jumpCount: finalJumpCount,
                    caloriesBurned: finalCaloriesBurned,
                    averageRate: finalAverageRate,
                    sourceLabel: finalSourceLabel,
                    endedAt: endedAt
                )
            }
            return
        }

        guard let startedAt = startTime else { return }

        // Snapshot observable state on the main actor. The task may wait behind an in-flight
        // update, and reading these properties later could mix values from another session.
        let goalSummary = liveActivityGoalSummary
        let latestJumpCount = jumpCount
        let latestCaloriesBurned = caloriesBurned
        let latestAverageRate = averageRate
        let latestSourceLabel = liveActivitySourceLabel

        liveActivitySyncTask = Task { [liveActivityManager] in
            await previousTask?.value
            guard !Task.isCancelled else { return }

            await liveActivityManager.startOrUpdate(
                startedAt: startedAt,
                goalSummary: goalSummary,
                jumpCount: latestJumpCount,
                caloriesBurned: latestCaloriesBurned,
                averageRate: latestAverageRate,
                sourceLabel: latestSourceLabel
            )
        }
    }

    /// Keeps the system idle timer aligned with session and scene state.
    func syncIdleTimer() {
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

    // MARK: - Motion Export

    /// Exports recorded motion samples to local storage and iCloud when enabled.
    func exportMotionCSVIfNeeded(samples: [MotionSample], startedAt: Date, endedAt: Date) {
        guard isMotionCSVExportEnabled, !samples.isEmpty else {
            motionCSVShareURL = nil
            return
        }

        let csvText = makeMotionCSV(from: samples)
        let filename = makeMotionCSVFilename(startedAt: startedAt, endedAt: endedAt)
        motionCSVShareURL = ConnectivityManager.shared.saveCSVToLocalDocuments(csvText: csvText, filename: filename)
        Task {
            await ConnectivityManager.shared.saveCSVToICloud(csvText: csvText, filename: filename)
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

    /// Configures the app's speech audio session immediately before an announcement.
    ///
    /// The app intentionally avoids activating this session during launch because
    /// `.duckOthers` lowers Apple Music and other background audio as soon as the
    /// session becomes active. Deferring activation until speech starts preserves
    /// the user's listening volume while the app is merely open on screen.
    private func configureSpeechAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session config error: \(error)")
        }
    }

    /// Releases the app's speech audio session once announcements are finished.
    ///
    /// `notifyOthersOnDeactivation` tells iOS that any ducked background audio can
    /// return to its normal level immediately after JumpRec stops speaking.
    private func deactivateSpeechAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Audio session deactivation error: \(error)")
        }
    }

    /// Prepares haptic generators used during the session.
    func prepareHaptics() {
        notificationFeedbackGenerator.prepare()
    }

    /// Primes `AVSpeechSynthesizer` with a silent utterance so the first real prompt starts quickly.
    ///
    /// Commit `2716b99` removed the old warmup when speech audio activation was deferred
    /// until announcement time. That preserved background-audio volume, but it also
    /// reintroduced the sluggish first spoken prompt because the synthesizer had to do
    /// its one-time voice setup on the first user-visible utterance. This method restores
    /// the warmup while keeping the newer audio-session behavior: we briefly activate the
    /// speech session, speak a zero-volume utterance, and rely on the delegate cleanup to
    /// release the session immediately afterward.
    ///
    /// The method is intentionally idempotent because SwiftUI may call `onAppear` more
    /// than once across the app's lifecycle.
    func warmUpSpeechSynthesizerIfNeeded() {
        guard !hasWarmedUpSpeechSynthesizer else { return }

        hasWarmedUpSpeechSynthesizer = true
        isSpeechWarmupInProgress = true

        configureSpeechAudioSession()

        let warmupText = isJapanesePreferred ? "こんにちは" : "Hello"
        let utterance = AVSpeechUtterance(string: warmupText)
        utterance.volume = 0
        utterance.voice = AVSpeechSynthesisVoice(language: preferredSpeechLanguageCode)
        synthesizer.speak(utterance)
    }

    // MARK: - Speech

    /// Speaks a localized prompt after an optional, cancellable delay.
    func speak(text: String, delay: TimeInterval = 0.2) {
        cancelPendingSpeech()
        let requestID = pendingSpeechRequestID

        pendingSpeechTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch is CancellationError {
                return
            } catch {
                print("[JumpRecState] Speech delay failed: \(error.localizedDescription)")
                return
            }

            guard let self,
                  !Task.isCancelled,
                  pendingSpeechRequestID == requestID
            else {
                return
            }

            pendingSpeechTask = nil

            // If the user acts before the silent warmup completes, discard it so the
            // real announcement is not queued behind invisible setup work.
            if isSpeechWarmupInProgress {
                synthesizer.stopSpeaking(at: .immediate)
                isSpeechWarmupInProgress = false
            }

            configureSpeechAudioSession()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: preferredSpeechLanguageCode)
            synthesizer.speak(utterance)
        }
    }

    /// Cancels a speech cue that has not reached the synthesizer yet.
    func cancelPendingSpeech() {
        pendingSpeechRequestID = UUID()
        pendingSpeechTask?.cancel()
        pendingSpeechTask = nil
    }

    /// Returns whether Japanese is the preferred system language.
    private var isJapanesePreferred: Bool {
        Locale.isJapanesePreferredLanguage
    }

    /// Returns the language code used for speech synthesis.
    private var preferredSpeechLanguageCode: String {
        isJapanesePreferred ? "ja-JP" : "en-US"
    }

    /// Returns the localized spoken phrase for session start.
    var localizedSessionStartedAnnouncement: String {
        isJapanesePreferred ? "セッションを開始しました" : "Session Started!"
    }

    /// Returns the localized spoken phrase for session end.
    var localizedSessionFinishedAnnouncement: String {
        isJapanesePreferred ? "セッションを終了しました" : "Session Finished!"
    }

    /// Returns the localized spoken phrase for jump milestones.
    func localizedJumpAnnouncement(for jumpCount: Int) -> String {
        if isJapanesePreferred {
            return "\(jumpCount) 回"
        }
        return "\(jumpCount) Jumps"
    }

    /// Returns the localized spoken phrase for minute milestones.
    func localizedMinuteAnnouncement(for minutesElapsed: Int) -> String {
        Duration.seconds(Double(minutesElapsed) * 60).formatted(
            .units(allowed: [.minutes], width: .wide)
        )
    }
}

extension JumpRecState: AVSpeechSynthesizerDelegate {
    /// Releases the ducking audio session after the last queued announcement ends.
    ///
    /// The delegate callback is not main-actor isolated, so the audio-session
    /// cleanup hops back to the main actor before touching app state helpers.
    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeechWarmupInProgress = false
            guard !self.synthesizer.isSpeaking, !self.synthesizer.isPaused else { return }
            deactivateSpeechAudioSession()
        }
    }

    /// Mirrors the normal-finish cleanup path when speech is cancelled early.
    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeechWarmupInProgress = false
            guard !self.synthesizer.isSpeaking, !self.synthesizer.isPaused else { return }
            deactivateSpeechAudioSession()
        }
    }
}
