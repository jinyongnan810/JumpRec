//
//  AppState+Presentation.swift
//  JumpRec
//

import AVFoundation
import Foundation

extension JumpRecState {
    // MARK: - Audio

    /// Configures the watch app's speech audio session immediately before an announcement.
    ///
    /// The watch app avoids keeping this session active all the time because `.duckOthers`
    /// lowers background audio as soon as activation happens. Deferring activation until
    /// speech starts preserves the user's audio unless JumpRec is actively talking.
    private func configureSpeechAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session config error: \(error)")
        }
    }

    /// Releases the watch app's speech audio session once announcements are finished.
    ///
    /// `notifyOthersOnDeactivation` tells watchOS that any ducked audio can return to
    /// normal volume as soon as JumpRec stops speaking.
    private func deactivateSpeechAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Audio session deactivation error: \(error)")
        }
    }

    /// Primes `AVSpeechSynthesizer` with a silent utterance so the first real prompt starts quickly.
    ///
    /// The warmup still needs the speech audio session, but only briefly. This keeps the
    /// watch behavior aligned with the iPhone app: fast first speech without holding the
    /// ducking audio session open for the rest of the app lifetime.
    func warmUpSpeechSynthesizerIfNeeded() {
        warmUpSpeechSynthesizer(force: false)
    }

    /// Clears stale speech state after the watch app has been suspended for a long time.
    ///
    /// watchOS may keep the Swift process alive while tearing down the underlying audio
    /// route. When that happens, `AVSpeechSynthesizer` can still appear initialized even
    /// though queued utterances will not play until much later. Resetting before the next
    /// workout prevents old prompts from bursting out together and gives the first real
    /// cue a fresh audio session.
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

            // Workout cues should represent the latest session state. Replacing anything
            // still queued in AVSpeechSynthesizer prevents stale announcements from piling
            // up while watchOS is waking the audio route after a long suspension.
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
        isJapanesePreferred ? "セッションを開始しました" : "Session Started!"
    }

    /// Returns the localized spoken phrase for session finish.
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
    /// Releases the ducking audio session after the last queued announcement finishes.
    ///
    /// Delegate callbacks are not main-actor isolated, so cleanup hops back to the main
    /// actor before touching state shared with the rest of the watch UI.
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
