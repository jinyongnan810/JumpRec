//
//  AppState+Presentation.swift
//  JumpRec
//

import AVFoundation
import Foundation
import OSLog

/// Serializes Watch speech synthesis and ducking audio session management off the main actor.
actor WatchSpeechCoordinator {
    // MARK: - Stored Properties

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "JumpRec.watch", category: "Speech")

    /// Holds the active synthesizer; replaced when resetting after standby or a wedged utterance.
    private var synthesizer = AVSpeechSynthesizer()
    /// Forwards nonisolated `AVSpeechSynthesizerDelegate` events back into the actor.
    private var delegateProxy: DelegateProxy?
    /// Tracks whether the current synthesizer is executing a silent warmup.
    private var isWarmupInProgress = false
    /// Tracks whether the ducking audio session is currently active.
    private var isAudioSessionActive = false
    /// Identifies the currently active utterance so older cancelled utterances cannot deactivate the session.
    private var activeUtteranceID: ObjectIdentifier?
    /// Guards against a wedged synthesizer leaving background audio ducked indefinitely.
    private var watchdogTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        setupSynthesizer()
    }

    // MARK: - Public API

    /// Rebuilds the speech synthesizer and warms it up silently without ducking other audio.
    func prepareForWorkout(text: String, languageCode: String) {
        rebuildSynthesizer()
        isWarmupInProgress = true

        // Warm up with `.mixWithOthers` so background music never dips during silent preparation.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        } catch {
            Self.logger.error("Warmup audio category error: \(error.localizedDescription, privacy: .public)")
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.volume = 0
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        activeUtteranceID = ObjectIdentifier(utterance)
        scheduleWatchdog(for: ObjectIdentifier(utterance), timeoutSeconds: 5)
        synthesizer.speak(utterance)
    }

    /// Activates ducking audio and speaks a workout announcement, recovering if a prior cue wedged.
    func speak(text: String, languageCode: String) {
        watchdogTask?.cancel()
        watchdogTask = nil

        // If a previous utterance is still marked active, stop it cleanly before starting the new cue.
        if activeUtteranceID != nil || isWarmupInProgress || synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
            isWarmupInProgress = false
        }

        activateDuckingAudioSession()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        let utteranceID = ObjectIdentifier(utterance)
        activeUtteranceID = utteranceID
        scheduleWatchdog(for: utteranceID, timeoutSeconds: 15)
        synthesizer.speak(utterance)
    }

    /// Stops any active speech and releases the ducking audio session immediately.
    func stopAndDeactivate() {
        watchdogTask?.cancel()
        watchdogTask = nil
        activeUtteranceID = nil
        isWarmupInProgress = false

        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        deactivateAudioSessionIfNeeded()
    }

    // MARK: - Helpers

    /// Creates a fresh synthesizer instance and attaches a new delegate proxy.
    private func setupSynthesizer() {
        let newSynthesizer = AVSpeechSynthesizer()
        let proxy = DelegateProxy { [weak self] synthesizer, utterance in
            guard let self else { return }
            Task {
                await self.handleUtteranceEnded(synthesizer: synthesizer, utteranceID: ObjectIdentifier(utterance))
            }
        }
        newSynthesizer.delegate = proxy
        delegateProxy = proxy
        synthesizer = newSynthesizer
    }

    /// Replaces the synthesizer instance to clear stale XPC state after standby or a hung utterance.
    private func rebuildSynthesizer() {
        watchdogTask?.cancel()
        watchdogTask = nil
        activeUtteranceID = nil
        isWarmupInProgress = false

        synthesizer.delegate = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        deactivateAudioSessionIfNeeded()
        setupSynthesizer()
    }

    /// Activates `.playback` with `.duckOthers` right before speaking a real workout cue.
    private func activateDuckingAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.duckOthers])
            try session.setActive(true)
            isAudioSessionActive = true
        } catch {
            Self.logger.error("Audio session activation error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Releases the audio session and notifies background music to restore full volume.
    private func deactivateAudioSessionIfNeeded() {
        guard isAudioSessionActive else { return }
        isAudioSessionActive = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            Self.logger.error("Audio session deactivation error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Cleans up state when the active utterance finishes or cancels, ignoring stale callbacks.
    private func handleUtteranceEnded(synthesizer sourceSynthesizer: AVSpeechSynthesizer, utteranceID: ObjectIdentifier) {
        guard sourceSynthesizer === synthesizer, activeUtteranceID == utteranceID else { return }
        watchdogTask?.cancel()
        watchdogTask = nil
        activeUtteranceID = nil
        isWarmupInProgress = false
        deactivateAudioSessionIfNeeded()
    }

    /// Rebuilds the synthesizer and restores audio volume if the TTS daemon fails to report completion.
    private func scheduleWatchdog(for utteranceID: ObjectIdentifier, timeoutSeconds: Double) {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(timeoutSeconds))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            await handleWatchdogTimeout(for: utteranceID)
        }
    }

    /// Recovers from a wedged utterance that never called `didFinish` or `didCancel`.
    private func handleWatchdogTimeout(for utteranceID: ObjectIdentifier) {
        guard activeUtteranceID == utteranceID else { return }
        Self.logger.warning("Speech utterance timed out; rebuilding synthesizer and releasing audio session")
        rebuildSynthesizer()
    }

    // MARK: - Delegate Proxy

    /// Bridges `AVSpeechSynthesizerDelegate` callbacks to the actor without main-actor hops.
    private final class DelegateProxy: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
        private let onEnded: @Sendable (AVSpeechSynthesizer, AVSpeechUtterance) -> Void

        init(onEnded: @escaping @Sendable (AVSpeechSynthesizer, AVSpeechUtterance) -> Void) {
            self.onEnded = onEnded
        }

        nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            onEnded(synthesizer, utterance)
        }

        nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            onEnded(synthesizer, utterance)
        }
    }
}

extension JumpRecState {
    // MARK: - Audio

    /// Rebuilds and warms up the speech synthesizer during the pre-workout countdown.
    func prepareSpeechForWorkout() {
        cancelPendingSpeech()
        let text = isJapanesePreferred ? "こんにちは" : "Hello"
        let languageCode = preferredSpeechLanguageCode
        Task { [speechCoordinator] in
            await speechCoordinator.prepareForWorkout(text: text, languageCode: languageCode)
        }
    }

    // MARK: - Speech

    /// Speaks a localized prompt after an optional, cancellable delay.
    func speak(text: String, delay: Double = 0) {
        cancelPendingSpeech()
        let requestID = pendingSpeechRequestID
        let languageCode = preferredSpeechLanguageCode

        pendingSpeechTask = Task { [weak self, speechCoordinator] in
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
            await speechCoordinator.speak(text: text, languageCode: languageCode)
        }
    }

    /// Cancels a speech cue that has not reached the synthesizer yet.
    func cancelPendingSpeech() {
        pendingSpeechRequestID = UUID()
        pendingSpeechTask?.cancel()
        pendingSpeechTask = nil
    }

    /// Stops any active speech and releases audio ducking.
    func stopSpeechAndDeactivateAudio() {
        cancelPendingSpeech()
        Task { [speechCoordinator] in
            await speechCoordinator.stopAndDeactivate()
        }
    }

    /// Returns whether Japanese is the preferred language.
    private var isJapanesePreferred: Bool {
        Locale.isJapanesePreferredLanguage
    }

    /// Returns the speech language code used for announcements.
    private var preferredSpeechLanguageCode: String {
        isJapanesePreferred ? "ja-JP" : "en-US"
    }

    /// Returns the localized spoken phrase for session start.
    var localizedSessionStartedAnnouncement: String {
        isJapanesePreferred ? "ワークアウトを開始しました" : "Workout Started!"
    }

    /// Returns the localized spoken phrase for session finish.
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
