import SwiftData
import SwiftUI

/// Toggles a saved workout's favorite status independently of its performance.
struct SessionFavoriteButton: View {
    @Environment(\.modelContext) private var modelContext
    let session: JumpSession
    @State private var hasSaveError = false

    var body: some View {
        Button(action: toggleFavorite) {
            Label {
                if session.isFavorite {
                    Text("Remove from favorites")
                } else {
                    Text("Save as a favorite")
                }
            } icon: {
                Image(systemName: session.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 20))
            }
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(session.isFavorite ? AppColors.accent : AppColors.textPrimary)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityValue(session.isFavorite ? Text("Favorite session") : Text("Not a favorite"))
        .alert("Unable to save favorite", isPresented: $hasSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    private func toggleFavorite() {
        let previousValue = session.isFavorite
        session.isFavorite.toggle()
        do {
            try modelContext.save()
        } catch {
            session.isFavorite = previousValue
            hasSaveError = true
            print("[Favorites] Failed to save favorite: \(error)")
        }
    }
}

#Preview("Favorite") {
    let session = JumpSession(startedAt: .now, endedAt: .now, jumpCount: 250, peakRate: 120, caloriesBurned: 20)
    session.isFavorite = true
    return SessionFavoriteButton(session: session)
        .modelContainer(for: JumpSession.self, inMemory: true)
}

#Preview("Not a favorite") {
    let session = JumpSession(startedAt: .now, endedAt: .now, jumpCount: 250, peakRate: 120, caloriesBurned: 20)
    return SessionFavoriteButton(session: session)
        .modelContainer(for: JumpSession.self, inMemory: true)
}
