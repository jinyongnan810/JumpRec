import SwiftData
import SwiftUI

private enum FavoriteSessionTag: String, CaseIterable, Identifiable {
    case feltGood, clearedMyHead, hadFun

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .feltGood: "Felt good"
        case .clearedMyHead: "Cleared my head"
        case .hadFun: "Had fun"
        }
    }
}

/// Keeps personal reflections separate from performance records.
struct SessionFavoriteCard: View {
    @Environment(\.modelContext) private var modelContext
    let session: JumpSession
    @State private var isEditing = false
    @State private var hasSaveError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggleFavorite) {
                Label {
                    if session.isFavorite {
                        Text("Favorite session")
                    } else {
                        Text("Save as a favorite")
                    }
                } icon: {
                    Image(systemName: session.isFavorite ? "heart.fill" : "heart")
                }
                .font(AppFonts.bodyLabelStrong)
                .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityHint(session.isFavorite ? Text("Removes this workout from favorites.") : Text("Adds this workout to favorites."))

            if session.isFavorite {
                ForEach(FavoriteSessionTag.allCases) { tag in
                    if session.favoriteTagRawValues.contains(tag.rawValue) {
                        Text(tag.title)
                            .font(AppFonts.bodySmall)
                    }
                }
                if let note = session.favoriteNote, !note.isEmpty {
                    Text(note)
                        .font(AppFonts.bodyRegular)
                }
                Button("Edit tags and note") { isEditing = true }
                    .font(AppFonts.bodySmall)
            }
        }
        .foregroundStyle(AppColors.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.cardSurface, in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $isEditing) {
            FavoriteSessionEditor(session: session)
        }
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

private struct FavoriteSessionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let session: JumpSession
    @State private var tags: Set<String>
    @State private var note: String
    @State private var hasSaveError = false

    init(session: JumpSession) {
        self.session = session
        _tags = State(initialValue: Set(session.favoriteTagRawValues))
        _note = State(initialValue: session.favoriteNote ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What made it special? (Optional)") {
                    ForEach(FavoriteSessionTag.allCases) { tag in
                        Toggle(isOn: Binding(
                            get: { tags.contains(tag.rawValue) },
                            set: { isSelected in
                                if isSelected { tags.insert(tag.rawValue) }
                                else { tags.remove(tag.rawValue) }
                            }
                        )) {
                            Text(tag.title)
                        }
                    }
                }
                Section("Note (Optional)") {
                    TextField("A thought to remember", text: $note, axis: .vertical)
                        .lineLimit(3 ... 8)
                }
            }
            .navigationTitle("Favorite session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .alert("Unable to save favorite", isPresented: $hasSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please try again.")
            }
        }
    }

    private func save() {
        let previousTags = session.favoriteTagRawValues
        let previousNote = session.favoriteNote
        session.favoriteTagRawValues = tags.sorted()
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        session.favoriteNote = trimmedNote.isEmpty ? nil : trimmedNote
        do {
            try modelContext.save()
            dismiss()
        } catch {
            session.favoriteTagRawValues = previousTags
            session.favoriteNote = previousNote
            hasSaveError = true
            print("[Favorites] Failed to save reflection: \(error)")
        }
    }
}

#Preview {
    let session = JumpSession(startedAt: .now, endedAt: .now, jumpCount: 250, peakRate: 120, caloriesBurned: 20)
    session.isFavorite = true
    session.favoriteTagRawValues = ["feltGood"]
    session.favoriteNote = "A relaxing break outside."
    return SessionFavoriteCard(session: session)
        .padding()
        .modelContainer(for: JumpSession.self, inMemory: true)
}
