import SwiftUI

/// Shows earned highlights without locked goals or progress targets.
struct LifetimeMilestonesSection: View {
    let milestones: [LifetimeJumpMilestone]

    /// CloudKit may merge awards made independently on different devices.
    private var distinctMilestones: [LifetimeJumpMilestone] {
        var seenCounts = Set<Int>()
        return milestones.filter { seenCounts.insert($0.jumpCount).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("A Little Adds Up", systemImage: "sparkles")
                .font(AppFonts.bodyLabelStrong)
                .foregroundStyle(AppColors.textPrimary)
            ForEach(distinctMilestones) { milestone in
                HStack {
                    Text("\(milestone.jumpCount.formatted()) lifetime jumps")
                        .font(AppFonts.bodyRegular)
                        .foregroundStyle(AppColors.accent)
                    Spacer()
                    Text(milestone.achievedAt, format: .dateTime.year().month(.abbreviated).day())
                        .font(AppFonts.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.cardSurface, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    LifetimeMilestonesSection(milestones: [
        LifetimeJumpMilestone(jumpCount: 10000, achievedAt: .now),
        LifetimeJumpMilestone(jumpCount: 5000, achievedAt: .now),
    ])
    .padding()
}
