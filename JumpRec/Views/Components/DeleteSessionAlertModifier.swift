//
//  DeleteSessionAlertModifier.swift
//  JumpRec
//

import SwiftUI

struct DeleteSessionAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let sessionCount: Int
    let onDelete: () -> Void

    private var title: String {
        sessionCount == 1 ? String(localized: "Delete this session?") : String(localized: "Delete these sessions?")
    }

    private var deleteButtonTitle: String {
        sessionCount == 1 ? String(localized: "Delete Session") : String(localized: "Delete Sessions")
    }

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
