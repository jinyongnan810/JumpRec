//
//  AppState+Presentation.swift
//  JumpRec
//

import AVFoundation
import Foundation

extension JumpRecState {
    // MARK: - Audio

    /// Activates ducking audio only when a Watch announcement is about to play.
    private func configureSpeechAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session config error: \(error)")
        }
    }

    /// Releases speech audio and restores background-audio volume.
    private func deactivateSpeechAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Audio session deactivation error: \(error)")
        }
    }

    /// Warms up speech silently, then releases the audio session through delegate cleanup.
    func warmUpSpeechSynthesizerIfNeeded() {
        warmUpSpeechSynthesizer(force: false)
    }

    /// Resets speech after long suspension so stale audio routes cannot delay or batch cues.
    func recoverSpeechAudioPipelineAfterExtendedBackground() {
        cancelPendingSpeech()
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeechWarmupInProgress = false
        hasWarmedUpSpeechSynthesizer = false
        deactivateSpeechAudioSession()
        warmUpSpeechSynthesizer(force: true)
    }

    /// Performs the silent speech warmup, optionally forcing it after a stale background resume.
    private func warmUpSpeechSynthesizer(force: Bool) {
        guard force || !hasWarmedUpSpeechSynthesizer else { return }

        hasWarmedUpSpeechSynthesizer = true
        isSpeechWarmupInProgress = true
        configureSpeechAudioSession()

        let utterance = AVSpeechUtterance(string: isJapanesePreferred ? "こんにちは" : "Hello")
        utterance.volume = 0
        utterance.voice = AVSpeechSynthesisVoice(language: preferredSpeechLanguageCode)
        synthesizer.speak(utterance)
    }

    // MARK: - Speech

    /// Speaks a localized prompt after an optional, cancellable delay.
    func speak(text: String, delay: Double = 0.5) {
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

            // Replace queued speech to avoid stale announcements after suspension.
            if isSpeechWarmupInProgress || synthesizer.isSpeaking || synthesizer.isPaused {
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
    /// Releases ducking audio on the main actor after the last announcement finishes.
    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeechWarmupInProgress = false
            guard !self.synthesizer.isSpeaking, !self.synthesizer.isPaused else { return }
            self.deactivateSpeechAudioSession()
        }
    }

    /// Mirrors the normal-finish cleanup path when speech is cancelled early.
    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeechWarmupInProgress = false
            guard !self.synthesizer.isSpeaking, !self.synthesizer.isPaused else { return }
            self.deactivateSpeechAudioSession()
        }
    }
}
