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
        guard !hasWarmedUpSpeechSynthesizer else { return }

        hasWarmedUpSpeechSynthesizer = true
        isSpeechWarmupInProgress = true
        configureSpeechAudioSession()

        let utterance = AVSpeechUtterance(string: isJapanesePreferred ? "こんにちは" : "Hello")
        utterance.volume = 0
        utterance.voice = AVSpeechSynthesisVoice(language: preferredSpeechLanguageCode)
        synthesizer.speak(utterance)
    }

    // MARK: - Speech

    /// Speaks a localized prompt after an optional delay.
    func speak(text: String, delay: Double = 0.5) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Cancel the silent warmup if it is still running so the spoken workout cue
            // can start immediately instead of being queued behind setup work.
            if self.isSpeechWarmupInProgress {
                self.synthesizer.stopSpeaking(at: .immediate)
                self.isSpeechWarmupInProgress = false
            }

            self.configureSpeechAudioSession()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: self.preferredSpeechLanguageCode)
            self.synthesizer.speak(utterance)
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
