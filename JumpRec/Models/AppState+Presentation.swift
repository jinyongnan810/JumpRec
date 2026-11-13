//
//  AppState+Presentation.swift
//  JumpRec
//

import AVFoundation
import Foundation
import OSLog
import UIKit

/// Serializes iPhone speech synthesis and audio session ducking off the main actor.
actor PhoneSpeechCoordinator {
    // MARK: - Stored Properties

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "JumpRec", category: "Speech")

    /// Synthesizer owned by the actor so audio session work never blocks the main thread.
    private let synthesizer = AVSpeechSynthesizer()
    /// Forwards nonisolated `AVSpeechSynthesizerDelegate` events back into the actor.
    private var delegateProxy: DelegateProxy?
    /// Caches resolved voices by language code to avoid repeated catalog lookups when speaking.
    private var cachedVoices: [String: AVSpeechSynthesisVoice] = [:]
    /// Marks silent warmup speech so a real announcement can interrupt it.
    private var isWarmupInProgress = false
    /// Tracks whether the audio session is currently active for speech.
    private var isAudioSessionActive = false
    /// Identifies the latest utterance so stale delegate callbacks do not release audio early.
    private var activeUtteranceID: ObjectIdentifier?
    /// Retries audio session deactivation once when `didFinish` races with audio teardown.
    private var deactivationRetryTask: Task<Void, Never>?

    // MARK: - Public API

    /// Warms up speech synthesis once with a silent, non-ducking utterance.
    func warmUp(text: String, languageCode: String) {
        ensureSynthesizerConfigured()
        isWarmupInProgress = true

        // Use `.mixWithOthers` so launch warmup does not dip background audio.
        activateAudioSession(options: [.mixWithOthers])

        let utterance = AVSpeechUtterance(string: text)
        utterance.volume = 0
        utterance.voice = voice(for: languageCode)
        activeUtteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    /// Activates ducking audio and speaks a localized workout announcement immediately.
    func speak(text: String, languageCode: String) {
        ensureSynthesizerConfigured()

        // Cancel the silent warmup so real speech can play immediately.
        if isWarmupInProgress {
            synthesizer.stopSpeaking(at: .immediate)
            isWarmupInProgress = false
        }

        activateAudioSession(options: [.duckOthers])

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: languageCode)
        activeUtteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    // MARK: - Helpers

    /// Lazily attaches the delegate proxy on the actor before any speech starts.
    private func ensureSynthesizerConfigured() {
        guard delegateProxy == nil else { return }

        let proxy = DelegateProxy { [weak self] synthesizerID, utteranceID in
            guard let self else { return }
            Task {
                await self.handleUtteranceEnded(synthesizerID: synthesizerID, utteranceID: utteranceID)
            }
        }
        synthesizer.delegate = proxy
        delegateProxy = proxy
    }

    /// Returns the cached synthesis voice for a language code, resolving it on first use.
    private func voice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        if let cachedVoice = cachedVoices[languageCode] {
            return cachedVoice
        }
        if let resolvedVoice = AVSpeechSynthesisVoice(language: languageCode) {
            cachedVoices[languageCode] = resolvedVoice
            return resolvedVoice
        }
        return nil
    }

    /// Configures and activates the audio session off the main thread to avoid UI hangs.
    private func activateAudioSession(options: AVAudioSession.CategoryOptions) {
        deactivationRetryTask?.cancel()
        deactivationRetryTask = nil

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: options)
            try session.setActive(true)
            isAudioSessionActive = true
        } catch {
            Self.logger.error("Audio session config error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deactivates speech audio and restores background-audio volume.
    private func deactivateAudioSessionIfNeeded(allowRetry: Bool = true) {
        guard isAudioSessionActive else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            isAudioSessionActive = false
        } catch {
            Self.logger.error("Audio session deactivation error: \(error.localizedDescription, privacy: .public)")
            guard allowRetry else { return }
            scheduleDeactivationRetry()
        }
    }

    /// Retries deactivation briefly if the synthesizer audio unit was still tearing down on `didFinish`.
    private func scheduleDeactivationRetry() {
        deactivationRetryTask?.cancel()
        deactivationRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            await retryDeactivateAudioSession()
        }
    }

    /// Attempts one deferred deactivation if no newer speech utterance has started.
    private func retryDeactivateAudioSession() {
        deactivationRetryTask = nil
        guard activeUtteranceID == nil else { return }
        deactivateAudioSessionIfNeeded(allowRetry: false)
    }

    /// Cleans up audio ducking after the latest utterance ends.
    private func handleUtteranceEnded(synthesizerID: ObjectIdentifier, utteranceID: ObjectIdentifier) {
        guard synthesizerID == ObjectIdentifier(synthesizer) else { return }
        isWarmupInProgress = false
        guard activeUtteranceID == utteranceID else { return }
        activeUtteranceID = nil
        if synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        deactivateAudioSessionIfNeeded()
    }

    // MARK: - Delegate Proxy

    /// Bridges `AVSpeechSynthesizerDelegate` callbacks to the actor without sending non-Sendable types.
    private final class DelegateProxy: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
        private let onEnded: @Sendable (ObjectIdentifier, ObjectIdentifier) -> Void

        init(onEnded: @escaping @Sendable (ObjectIdentifier, ObjectIdentifier) -> Void) {
            self.onEnded = onEnded
        }

        nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            onEnded(ObjectIdentifier(synthesizer), ObjectIdentifier(utterance))
        }

        nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            onEnded(ObjectIdentifier(synthesizer), ObjectIdentifier(utterance))
        }
    }
}

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

            let csvText = MotionCSVFormatter.makeCSV(from: samples)
            let filename = MotionCSVFormatter.makeFilename(prefix: "motion", startedAt: startedAt, endedAt: endedAt)
            motionCSVShareURL = ConnectivityManager.shared.saveCSVToLocalDocuments(csvText: csvText, filename: filename)
            Task {
                await ConnectivityManager.shared.saveCSVToICloud(csvText: csvText, filename: filename)
            }
        }
    #endif

    // MARK: - Haptics And Speech

    /// Prepares haptic generators used during the session.
    func prepareHaptics() {
        notificationFeedbackGenerator.prepare()
    }

    /// Warms up speech once with a silent utterance; delegate cleanup releases the audio session.
    func warmUpSpeechSynthesizerIfNeeded() {
        guard !hasWarmedUpSpeechSynthesizer else { return }

        hasWarmedUpSpeechSynthesizer = true
        let warmupText = isJapanesePreferred ? "こんにちは" : "Hello"
        let languageCode = preferredSpeechLanguageCode
        enqueueSpeechOperation { [speechCoordinator] in
            await speechCoordinator.warmUp(text: warmupText, languageCode: languageCode)
        }
    }

    // MARK: - Speech

    /// Speaks a localized prompt immediately.
    func speak(text: String) {
        let languageCode = preferredSpeechLanguageCode
        enqueueSpeechOperation { [speechCoordinator] in
            await speechCoordinator.speak(text: text, languageCode: languageCode)
        }
    }

    /// Chains speech operations in order so warmup cannot run after a spoken announcement.
    private func enqueueSpeechOperation(_ operation: @escaping @Sendable () async -> Void) {
        let previousTask = speechTask
        speechTask = Task {
            await previousTask?.value
            await operation()
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
        isJapanesePreferred ? "ワークアウトを開始しました" : "Workout Started!"
    }

    /// Returns the localized spoken phrase for session end.
    var localizedSessionFinishedAnnouncement: String {
        isJapanesePreferred ? "ワークアウトが終了しました" : "Workout Finished!"
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
