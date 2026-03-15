//
//  SessionAICommentGenerator.swift
//  JumpRecShared
//

import Foundation
import SwiftData

#if os(iOS) && canImport(FoundationModels)
    import FoundationModels
#endif

@MainActor
public enum SessionAICommentGenerator {
    // MARK: - Output Language

    /// Defines the language used for generated AI recap text.
    enum OutputLanguage {
        /// Generates English output.
        case english
        /// Generates Japanese output.
        case japanese
    }

    // MARK: - Availability

    /// Returns whether the given session qualifies for AI comment generation.
    public static func shouldGenerate(for session: JumpSession) -> Bool {
        session.jumpCount >= 100
    }

    /// Returns whether on-device AI generation is currently available.
    public static var isAvailable: Bool {
        #if os(iOS) && canImport(FoundationModels)
            guard #available(iOS 26.0, *) else { return false }

            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return false }
            return model.supportsLocale()
        #else
            return false
        #endif
    }

    // MARK: - Generation

    /// Generates and persists an AI comment when the session qualifies and no comment exists yet.
    @discardableResult
    public static func generateIfNeeded(
        for session: JumpSession,
        in modelContext: ModelContext
    ) async -> String? {
        if let existingComment = session.aiComment?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existingComment.isEmpty
        {
            return existingComment
        }

        guard shouldGenerate(for: session) else { return nil }
        guard isAvailable else { return nil }

        #if os(iOS) && canImport(FoundationModels)
            guard #available(iOS 26.0, *) else { return nil }

            let model = SystemLanguageModel.default
            let outputLanguage = preferredOutputLanguage
            let languageSession = LanguageModelSession(
                model: model,
                instructions: instructions(for: outputLanguage)
            )

            do {
                let response = try await languageSession.respond(
                    to: prompt(for: session, language: outputLanguage),
                    generating: SessionAICommentResponse.self
                )
                let comment = response.content.formattedComment
                guard !comment.isEmpty else { return nil }

                session.aiComment = comment
                try? modelContext.save()
                return comment
            } catch {
                return nil
            }
        #else
            return nil
        #endif
    }

    // MARK: - Prompt Construction

    /// Returns the preferred output language based on the current locale.
    private static var preferredOutputLanguage: OutputLanguage {
        Locale.preferredLanguages.first?.hasPrefix("ja") == true ? .japanese : .english
    }

    /// Returns the system instructions used for AI comment generation.
    private static func instructions(for language: OutputLanguage) -> String {
        switch language {
        case .english:
            """
            Generate two short fields for a jump rope session recap.
            Keep the tone casual, gentle, simple, and human.
            The highlight should be one short sentence about the session's most notable point.
            The phrase should be either a gentle reflective question or a kind supportive phrase.
            Keep the combined output around 40 words total.
            Use at most one emoji across both fields, and only if it fits naturally.
            Do not guess or describe the user's emotions.
            Do not repeat raw stats back to the user.
            Do not overpraise or sound overly excited.
            Do not use markdown.
            Do not assume this is the best record.
            Write the response in English.
            """
        case .japanese:
            """
            縄跳びセッションの振り返りとして、短い highlight と phrase の2項目を生成してください。
            トーンはやさしく、自然で、シンプルにしてください。
            highlight はそのセッションの特徴を一文で短く伝えてください。
            phrase はやさしい振り返りの問いかけ、または思いやりのある一言にしてください。
            合計は40語相当以内の短さに収めてください。
            絵文字は両方合わせて最大1つまで、自然な場合のみ使ってください。
            ユーザーの感情を決めつけないでください。
            数字や統計をそのまま並べ直さないでください。
            大げさに褒めすぎたり、過度に興奮した口調にしないでください。
            Markdown は使わないでください。
            自己ベストだと決めつけないでください。
            出力は日本語で書いてください。
            """
        }
    }

    /// Builds the per-session prompt passed to the language model.
    private static func prompt(for session: JumpSession, language: OutputLanguage) -> String {
        switch language {
        case .english:
            """
            Create a short highlight and a short phrase for this jump rope session.
            The phrase must be either a gentle reflective question or a kind supportive phrase.
            Duration: \(session.durationText)
            Jumps: \(session.jumpCount)
            Calories: \(Int(session.caloriesBurned.rounded()))
            Average rate: \(session.rateText(from: session.averageRate, language: language))
            Peak rate: \(session.rateText(from: session.peakRate, language: language))
            Longest streak: \(session.longestStreak)
            Short breaks: \(session.smallBreaksCount)
            Long breaks: \(session.longBreaksCount)
            Average heart rate: \(session.heartRateText(from: session.averageHeartRate, language: language))
            Peak heart rate: \(session.heartRateText(from: session.peakHeartRate, language: language))
            """
        case .japanese:
            """
            この縄跳びセッションについて、短い highlight と短い phrase を作成してください。
            phrase は、やさしい振り返りの問いかけ、または思いやりのある一言にしてください。
            時間: \(session.durationText)
            ジャンプ回数: \(session.jumpCount)
            消費カロリー: \(Int(session.caloriesBurned.rounded()))
            平均レート: \(session.rateText(from: session.averageRate, language: language))
            最高レート: \(session.rateText(from: session.peakRate, language: language))
            最長連続回数: \(session.longestStreak)
            短い休憩: \(session.smallBreaksCount)
            長い休憩: \(session.longBreaksCount)
            平均心拍数: \(session.heartRateText(from: session.averageHeartRate, language: language))
            最高心拍数: \(session.heartRateText(from: session.peakHeartRate, language: language))
            """
        }
    }
}

#if os(iOS) && canImport(FoundationModels)
    /// Structured response generated by the on-device language model.
    @available(iOS 26.0, *)
    @Generable(description: "A short recap of a jump rope session with a highlight and a phrase.")
    private struct SessionAICommentResponse {
        /// The primary summary sentence for the session.
        @Guide(description: "One short sentence describing the session highlight.")
        let highlight: String

        /// A reflective or supportive follow-up phrase.
        @Guide(description: "One short reflective question or kind supportive phrase.")
        let phrase: String

        /// Combines the structured response into the final display string.
        var formattedComment: String {
            [highlight, phrase]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }
    }
#endif

private extension JumpSession {
    /// Returns the session duration formatted as `mm:ss`.
    var durationText: String {
        let seconds = max(durationSeconds, 0)
        let minutes = seconds / 60
        let remainderSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainderSeconds)
    }

    /// Formats an optional jump-rate value for the requested output language.
    func rateText(from value: Double?, language: SessionAICommentGenerator.OutputLanguage) -> String {
        guard let value else { return "--" }
        switch language {
        case .english:
            return "\(Int(value.rounded()))/min"
        case .japanese:
            return "\(Int(value.rounded()))/分"
        }
    }

    /// Formats an optional heart-rate value for the requested output language.
    func heartRateText(from value: Int?, language: SessionAICommentGenerator.OutputLanguage) -> String {
        guard let value else { return "--" }
        switch language {
        case .english:
            return "\(value) bpm"
        case .japanese:
            return "\(value) bpm"
        }
    }
}
