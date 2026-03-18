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
        Locale.isJapanesePreferredLanguage ? .japanese : .english
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
        let metrics = session.promptMetrics(language: language)

        switch language {
        case .english:
            return """
            Create a short highlight and a short phrase for this jump rope session.
            The phrase must be either a gentle reflective question or a kind supportive phrase.
            \(metrics.joined(separator: "\n"))
            """
        case .japanese:
            return """
            この縄跳びセッションについて、短い highlight と短い phrase を作成してください。
            phrase は、やさしい振り返りの問いかけ、または思いやりのある一言にしてください。
            \(metrics.joined(separator: "\n"))
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
    /// Returns the prompt metrics, omitting calories and heart rate when they are missing or zero.
    func promptMetrics(language: SessionAICommentGenerator.OutputLanguage) -> [String] {
        var metrics = [
            promptLine(english: "Duration", japanese: "時間", value: durationText, language: language),
            promptLine(english: "Jumps", japanese: "ジャンプ回数", value: "\(jumpCount)", language: language),
            promptLine(
                english: "Average rate",
                japanese: "平均レート",
                value: rateText(from: averageRate, language: language),
                language: language
            ),
            promptLine(
                english: "Peak rate",
                japanese: "最高レート",
                value: rateText(from: peakRate, language: language),
                language: language
            ),
            promptLine(english: "Longest streak", japanese: "最長連続回数", value: "\(longestStreak)", language: language),
            promptLine(english: "Short breaks", japanese: "短い休憩", value: "\(smallBreaksCount)", language: language),
            promptLine(english: "Long breaks", japanese: "長い休憩", value: "\(longBreaksCount)", language: language),
        ]

        if caloriesBurned > 0 {
            metrics.insert(
                promptLine(
                    english: "Calories",
                    japanese: "消費カロリー",
                    value: "\(Int(caloriesBurned.rounded()))",
                    language: language
                ),
                at: 2
            )
        }

        if let averageHeartRate, averageHeartRate > 0 {
            metrics.append(
                promptLine(
                    english: "Average heart rate",
                    japanese: "平均心拍数",
                    value: heartRateText(from: averageHeartRate, language: language),
                    language: language
                )
            )
        }

        if let peakHeartRate, peakHeartRate > 0 {
            metrics.append(
                promptLine(
                    english: "Peak heart rate",
                    japanese: "最高心拍数",
                    value: heartRateText(from: peakHeartRate, language: language),
                    language: language
                )
            )
        }

        return metrics
    }

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

    private func promptLine(
        english: String,
        japanese: String,
        value: String,
        language: SessionAICommentGenerator.OutputLanguage
    ) -> String {
        switch language {
        case .english:
            "\(english): \(value)"
        case .japanese:
            "\(japanese): \(value)"
        }
    }
}
