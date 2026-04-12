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
    func syncLiveActivity() {
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
                    goalSummary: liveActivityGoalSummary,
                    jumpCount: jumpCount,
                    caloriesBurned: caloriesBurned,
                    averageRate: averageRate,
                    sourceLabel: liveActivitySourceLabel,
                    endedAt: endedAt
                )
            }
            return
        }

        guard let startTime else { return }
        Task {
            await liveActivityManager.startOrUpdate(
                startedAt: startTime,
                goalSummary: liveActivityGoalSummary,
                jumpCount: jumpCount,
                caloriesBurned: caloriesBurned,
                averageRate: averageRate,
                sourceLabel: liveActivitySourceLabel
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

    // MARK: - Speech

    /// Speaks a localized prompt after an optional delay.
    func speak(text: String, delay: TimeInterval = 0.2) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.configureSpeechAudioSession()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: self.preferredSpeechLanguageCode)
            self.synthesizer.speak(utterance)
        }
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
            guard !self.synthesizer.isSpeaking, !self.synthesizer.isPaused else { return }
            deactivateSpeechAudioSession()
        }
    }

    /// Mirrors the normal-finish cleanup path when speech is cancelled early.
    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.synthesizer.isSpeaking, !self.synthesizer.isPaused else { return }
            deactivateSpeechAudioSession()
        }
    }
}
