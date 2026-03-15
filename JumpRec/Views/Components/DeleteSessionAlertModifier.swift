//
//  DeleteSessionAlertModifier.swift
//  JumpRec
//

import SwiftUI

/// Presents a reusable confirmation alert before deleting one or more sessions.
struct DeleteSessionAlertModifier: ViewModifier {
    /// Controls whether the alert is visible.
    @Binding var isPresented: Bool
    /// Indicates how many sessions are about to be deleted.
    let sessionCount: Int
    /// Runs after the user confirms deletion.
    let onDelete: () -> Void

    // MARK: - Copy

    /// Returns the alert title for the current deletion scope.
    private var title: String {
        sessionCount == 1 ? String(localized: "Delete this session?") : String(localized: "Delete these sessions?")
    }

    /// Returns the destructive button label for the current deletion scope.
    private var deleteButtonTitle: String {
        sessionCount == 1 ? String(localized: "Delete Session") : String(localized: "Delete Sessions")
    }

    // MARK: - View

    /// Wraps content with the deletion confirmation alert.
    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            Button(deleteButtonTitle, role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

extension View {
    /// Applies the shared session-deletion alert behavior to a view.
    func deleteSessionAlert(
        isPresented: Binding<Bool>,
        sessionCount: Int = 1,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(
            DeleteSessionAlertModifier(
                isPresented: isPresented,
                sessionCount: sessionCount,
                onDelete: onDelete
            )
        )
    }
}
