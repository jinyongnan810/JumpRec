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

    private struct QueuedUtterance {
        let text: String
        let languageCode: String
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "JumpRec.watch", category: "Speech")

    /// Holds the active synthesizer; replaced when resetting after standby or a wedged utterance.
    private var synthesizer = AVSpeechSynthesizer()
    /// Forwards nonisolated `AVSpeechSynthesizerDelegate` events back into the actor.
    private var delegateProxy: DelegateProxy?
    /// Caches resolved voices by language code to avoid repeated catalog lookups when speaking.
    private var cachedVoices: [String: AVSpeechSynthesisVoice] = [:]
    /// Tracks whether the current synthesizer is executing a silent warmup.
    private var isWarmupInProgress = false
    /// Tracks whether the ducking audio session is currently active.
    private var isAudioSessionActive = false
    /// Identifies the currently active utterance so older cancelled utterances cannot deactivate the session.
    private var activeUtteranceID: ObjectIdentifier?
    /// Holds milestone utterances waiting to play after the active utterance finishes.
    private var pendingUtterances: [QueuedUtterance] = []
    /// Suspends the workout finalizer until the active non-warmup utterance completes or resets.
    private var idleContinuation: CheckedContinuation<Void, Never>?
    /// Guards against a wedged synthesizer leaving background audio ducked indefinitely.
    private var watchdogTask: Task<Void, Never>?
    /// Retries audio session deactivation once when `didFinish` races with audio teardown.
    private var deactivationRetryTask: Task<Void, Never>?

    // MARK: - Public API

    /// Rebuilds the speech synthesizer and warms it up silently without ducking other audio.
    func prepareForWorkout(text: String, languageCode: String) {
        guard activeUtteranceID == nil, pendingUtterances.isEmpty else { return }
        rebuildSynthesizer()
        isWarmupInProgress = true

        // Activate `.mixWithOthers` so the audio route warms up without dipping background music.
        activateAudioSession(options: [.mixWithOthers])

        let utterance = AVSpeechUtterance(string: text)
        utterance.volume = 0
        utterance.rate = AVSpeechUtteranceMaximumSpeechRate
        utterance.voice = voice(for: languageCode)
        let utteranceID = ObjectIdentifier(utterance)
        activeUtteranceID = utteranceID
        scheduleWatchdog(for: utteranceID, timeoutSeconds: 30)
        synthesizer.speak(utterance)
    }

    /// Activates ducking audio and queues or interrupts speech depending on priority.
    func speak(text: String, languageCode: String, interruptsCurrentSpeech: Bool = false) {
        ensureSynthesizerConfigured()

        if interruptsCurrentSpeech {
            pendingUtterances.removeAll()
            watchdogTask?.cancel()
            watchdogTask = nil

            if activeUtteranceID != nil || isWarmupInProgress || synthesizer.isSpeaking || synthesizer.isPaused {
                synthesizer.stopSpeaking(at: .immediate)
                isWarmupInProgress = false
            }

            startUtterance(text: text, languageCode: languageCode)
            return
        }

        if isWarmupInProgress {
            watchdogTask?.cancel()
            watchdogTask = nil
            synthesizer.stopSpeaking(at: .immediate)
            isWarmupInProgress = false
        } else if activeUtteranceID != nil {
            pendingUtterances.append(QueuedUtterance(text: text, languageCode: languageCode))
            return
        }

        startUtterance(text: text, languageCode: languageCode)
    }

    /// Stops any active speech and releases the ducking audio session immediately.
    func stopAndDeactivate() {
        pendingUtterances.removeAll()
        watchdogTask?.cancel()
        watchdogTask = nil
        activeUtteranceID = nil
        isWarmupInProgress = false

        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        deactivateAudioSessionIfNeeded()
        resumeIdleContinuation()
    }

    /// Suspends until the active and queued non-warmup utterances end, cancel, or hit the watchdog.
    func waitForActiveSpeech() async {
        guard (activeUtteranceID != nil && !isWarmupInProgress) || !pendingUtterances.isEmpty else { return }

        resumeIdleContinuation()
        await withCheckedContinuation { continuation in
            guard (activeUtteranceID != nil && !isWarmupInProgress) || !pendingUtterances.isEmpty else {
                continuation.resume()
                return
            }
            idleContinuation = continuation
        }
    }

    // MARK: - Helpers

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

    /// Lazily attaches the delegate proxy on the actor before speaking when warmup was skipped.
    private func ensureSynthesizerConfigured() {
        if delegateProxy == nil {
            setupSynthesizer()
        }
    }

    /// Creates a fresh synthesizer instance and attaches a new delegate proxy.
    private func setupSynthesizer() {
        let newSynthesizer = AVSpeechSynthesizer()
        let proxy = DelegateProxy { [weak self] synthesizerID, utteranceID in
            guard let self else { return }
            Task {
                await self.handleUtteranceEnded(synthesizerID: synthesizerID, utteranceID: utteranceID)
            }
        }
        newSynthesizer.delegate = proxy
        delegateProxy = proxy
        synthesizer = newSynthesizer
    }

    /// Replaces the synthesizer instance to clear stale XPC state after standby or a hung utterance.
    private func rebuildSynthesizer() {
        pendingUtterances.removeAll()
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
        resumeIdleContinuation()
    }

    /// Activates ducking audio and starts a single spoken announcement with a watchdog timer.
    private func startUtterance(text: String, languageCode: String) {
        activateDuckingAudioSession()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: languageCode)
        let utteranceID = ObjectIdentifier(utterance)
        activeUtteranceID = utteranceID
        scheduleWatchdog(for: utteranceID, timeoutSeconds: 15)
        synthesizer.speak(utterance)
    }

    /// Activates `.playback` with `.duckOthers` right before speaking a real workout cue.
    private func activateDuckingAudioSession() {
        activateAudioSession(options: [.duckOthers])
    }

    /// Configures and activates the audio session while cancelling any stale deactivation retry.
    private func activateAudioSession(options: AVAudioSession.CategoryOptions) {
        deactivationRetryTask?.cancel()
        deactivationRetryTask = nil

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: options)
            try session.setActive(true)
            isAudioSessionActive = true
        } catch {
            Self.logger.error("Audio session activation error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Releases the audio session and notifies background music to restore full volume.
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

    /// Cleans up state when the active utterance finishes or cancels, draining any queued utterances first.
    private func handleUtteranceEnded(synthesizerID: ObjectIdentifier, utteranceID: ObjectIdentifier) {
        guard synthesizerID == ObjectIdentifier(synthesizer), activeUtteranceID == utteranceID else { return }
        watchdogTask?.cancel()
        watchdogTask = nil
        activeUtteranceID = nil
        isWarmupInProgress = false

        if !pendingUtterances.isEmpty {
            let next = pendingUtterances.removeFirst()
            startUtterance(text: next.text, languageCode: next.languageCode)
            return
        }

        if synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        deactivateAudioSessionIfNeeded()
        resumeIdleContinuation()
    }

    /// Wakes the task waiting on the current utterance, if any.
    private func resumeIdleContinuation() {
        idleContinuation?.resume()
        idleContinuation = nil
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
    // MARK: - Audio

    /// Rebuilds and warms up the speech synthesizer once per foreground session when idle.
    func prepareSpeechForWorkout() {
        guard needsSpeechWarmup else { return }
        needsSpeechWarmup = false
        cancelPendingSpeech()
        let text = AppLocalization.speechWarmupText(isCompact: true)
        let languageCode = AppLocalization.speechLanguageCode()
        Task { [speechCoordinator] in
            await speechCoordinator.prepareForWorkout(text: text, languageCode: languageCode)
        }
    }

    /// Marks speech for rebuild and warmup on the next foreground activation.
    func markSpeechWarmupNeeded() {
        needsSpeechWarmup = true
    }

    // MARK: - Speech

    /// Speaks a localized prompt on the speech coordinator, queuing or overriding active speech.
    func speak(text: String, interruptsCurrentSpeech: Bool = false) {
        let previousTask = pendingSpeechTask
        if interruptsCurrentSpeech {
            previousTask?.cancel()
            pendingSpeechTask = nil
        }
        let languageCode = AppLocalization.speechLanguageCode()

        pendingSpeechTask = Task { [speechCoordinator] in
            // Wait for prior tasks to settle or cancel so interrupting speech cannot be overtaken.
            await previousTask?.value
            guard !Task.isCancelled else { return }
            await speechCoordinator.speak(
                text: text,
                languageCode: languageCode,
                interruptsCurrentSpeech: interruptsCurrentSpeech
            )
        }
    }

    /// Cancels a speech task before it reaches the speech coordinator.
    func cancelPendingSpeech() {
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

    /// Waits for any queued or active announcement to finish before ending background execution.
    func waitForCurrentSpeech() async {
        await pendingSpeechTask?.value
        await speechCoordinator.waitForActiveSpeech()
    }

    /// Returns the localized spoken phrase for session finish.
    var localizedSessionFinishedAnnouncement: String {
        AppLocalization.sessionFinishedAnnouncement()
    }

    /// Returns the localized spoken phrase for jump milestones.
    func localizedJumpAnnouncement(for jumpCount: Int) -> String {
        AppLocalization.jumpMilestoneAnnouncement(for: jumpCount)
    }

    /// Returns the localized spoken phrase for minute milestones.
    func localizedMinuteAnnouncement(for minutesElapsed: Int) -> String {
        Duration.seconds(Double(minutesElapsed) * 60).formatted(
            .units(allowed: [.minutes], width: .wide)
        )
    }
}
