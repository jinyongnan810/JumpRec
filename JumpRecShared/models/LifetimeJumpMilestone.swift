import Foundation
import SwiftData

/// An earned lifetime highlight retained independently of workout history.
@Model
public final class LifetimeJumpMilestone {
    public var jumpCount: Int = 0
    public var achievedAt: Date = Date()

    public init(jumpCount: Int, achievedAt: Date) {
        self.jumpCount = jumpCount
        self.achievedAt = achievedAt
    }

    /// Includes only thresholds crossed by this workout, without replaying history.
    public static func crossedThresholds(previousTotal: Int, newTotal: Int) -> [Int] {
        guard newTotal > previousTotal else { return [] }
        let earlyThresholds = [1000, 5000, 10000, 25000, 50000]
        var thresholds = earlyThresholds.filter { $0 > previousTotal && $0 <= newTotal }
        let firstStep = max(1, previousTotal / 100_000 + 1)
        let lastStep = newTotal / 100_000
        if firstStep <= lastStep {
            thresholds.append(contentsOf: (firstStep ... lastStep).map { $0 * 100_000 })
        }
        return thresholds
    }
}
