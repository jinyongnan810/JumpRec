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
                Write one short summary of the highlight of the jump rope session.
                Keep it casual, gental, simple, and human.
                Keep it about 40 words total.
                Use at most one emoji, and only if it fits naturally.
                Do not guess or describe the user's emotions.
                Do not repeat raw stats back to the user.
                Do not overpraise or sound overly excited.
                Do not restate the numbers directly unless truly needed.
                Return only the text.
                """
            )

            do {
                let response = try await languageSession.respond(to: prompt(for: session))
                let comment = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
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
        Write a short highlight of the jump session. And a gental reflective question or a kind words of phrase.
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
