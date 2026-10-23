import SwiftUI

/// Offers named color choices with a visible and accessible selection indicator.
struct AccentColorSettingsView: View {
    @Bindable private var appearance = AppAppearance.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accent Color")
                .font(AppFonts.cardTitle)
                .foregroundStyle(AppColors.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76))], spacing: 12) {
                ForEach(AppAccentColor.allCases) { accent in
                    Button {
                        appearance.accent = accent
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if appearance.accent == accent {
                                        Image(systemName: "checkmark")
                                            .font(.headline.bold())
                                            .foregroundStyle(AppColors.accentForeground)
                                    }
                                }
                            Text(accent.name)
                                .font(AppFonts.bodySmall)
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(accent.name))
                    .accessibilityAddTraits(appearance.accent == accent ? .isSelected : [])
                }
            }

            Text("Also applies to your paired Apple Watch.")
                .font(AppFonts.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(16)
        .background(AppColors.bgPrimary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private extension AppAccentColor {
    var name: LocalizedStringResource {
        switch self {
        case .cyan: "Cyan"
        case .mint: "Mint"
        case .blue: "Blue"
        case .lavender: "Lavender"
        case .pink: "Pink"
        case .amber: "Amber"
        }
    }
}

#Preview {
    AccentColorSettingsView()
        .padding()
        .background(AppColors.cardSurface)
        .preferredColorScheme(.dark)
}
