import Foundation
import SwiftData

extension MyDataStore {
    /// Evaluate before inserting the new session so existing history supplies the baseline.
    func awardLifetimeJumpMilestones(for session: JumpSession) -> Int? {
        do {
            let sessions = try modelContext.fetch(FetchDescriptor<JumpSession>())
            let previousTotal = sessions.reduce(0) { $0 + max(0, $1.jumpCount) }
            let thresholds = LifetimeJumpMilestone.crossedThresholds(
                previousTotal: previousTotal,
                newTotal: previousTotal + max(0, session.jumpCount)
            )
            guard !thresholds.isEmpty else { return nil }
            let earnedMilestones = try modelContext.fetch(FetchDescriptor<LifetimeJumpMilestone>())
            let earnedCounts = Set(earnedMilestones.map(\.jumpCount))
            let newThresholds = thresholds.filter { !earnedCounts.contains($0) }
            for threshold in newThresholds {
                modelContext.insert(LifetimeJumpMilestone(jumpCount: threshold, achievedAt: session.endedAt))
            }
            return newThresholds.max()
        } catch {
            // A failed history fetch must not invent a lifetime total or prevent saving the workout.
            print("[Milestones] Failed to evaluate lifetime jumps: \(error)")
            return nil
        }
    }
}
