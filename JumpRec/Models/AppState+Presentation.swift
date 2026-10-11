//
//  AppState+Presentation.swift
//  JumpRec
//

import AVFoundation
import Foundation
import UIKit

extension JumpRecState {
    // MARK: - Live Activity And Idle Timer

    /// Serializes ActivityKit calls, coalesces metric updates, and orders end after pending updates.
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

            // Capture final metrics before suspension so reset cannot alter the completed session.
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

        // Snapshot metrics before waiting to avoid reading values from a later session.
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
            return String(localized: "Workout in progress")
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

    #if DEBUG
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
    #endif

    // MARK: - Audio And Haptics

    /// Activates the ducking audio session only when an announcement is about to play.
    private func configureSpeechAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session config error: \(error)")
        }
    }

    /// Deactivates speech audio and restores background-audio volume.
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

    /// Warms up speech once with a silent utterance; delegate cleanup releases the audio session.
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

            // Cancel the silent warmup so real speech can play immediately.
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
        isJapanesePreferred ? "ワークアウトを開始しました" : "Workout Started!"
    }

    /// Returns the localized spoken phrase for session end.
    var localizedSessionFinishedAnnouncement: String {
        isJapanesePreferred ? "ワークアウトを終了しました" : "Workout Finished!"
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
    /// Releases ducking audio on the main actor after the last announcement ends.
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
