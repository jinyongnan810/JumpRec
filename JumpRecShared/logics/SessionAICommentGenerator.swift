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
    public static func shouldGenerate(for session: JumpSession) -> Bool {
        session.jumpCount >= 100
    }

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
            let languageSession = LanguageModelSession(
                model: model,
                instructions: """
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
                """
            )

            do {
                let response = try await languageSession.respond(
                    to: prompt(for: session),
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

    private static func prompt(for session: JumpSession) -> String {
        """
        Create a short highlight and a short phrase for this jump rope session.
        The phrase must be either a gentle reflective question or a kind supportive phrase.
        Duration: \(session.durationText)
        Jumps: \(session.jumpCount)
        Calories: \(Int(session.caloriesBurned.rounded()))
        Average rate: \(session.rateText(from: session.averageRate))
        Peak rate: \(session.rateText(from: session.peakRate))
        Longest streak: \(session.longestStreak)
        Short breaks: \(session.smallBreaksCount)
        Long breaks: \(session.longBreaksCount)
        Average heart rate: \(session.heartRateText(from: session.averageHeartRate))
        Peak heart rate: \(session.heartRateText(from: session.peakHeartRate))
        """
    }
}

#if os(iOS) && canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable(description: "A short recap of a jump rope session with a highlight and a phrase.")
    private struct SessionAICommentResponse {
        @Guide(description: "One short sentence describing the session highlight.")
        let highlight: String

        @Guide(description: "One short reflective question or kind supportive phrase.")
        let phrase: String

        var formattedComment: String {
            [highlight, phrase]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }
    }
#endif

private extension JumpSession {
    var durationText: String {
        let seconds = max(durationSeconds, 0)
        let minutes = seconds / 60
        let remainderSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainderSeconds)
    }

    func rateText(from value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))/min"
    }

    func heartRateText(from value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value) bpm"
    }
}
