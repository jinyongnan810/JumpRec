import Foundation
import Observation
import SwiftUI

/// Bright accents with readable contrast on the app's dark surfaces and under dark labels.
public enum AppAccentColor: String, CaseIterable, Identifiable, Sendable {
    case cyan, mint, blue, lavender, pink, amber

    public var id: String { rawValue }

    public var color: Color {
        Color(hex: hexValue)
    }

    private var hexValue: UInt {
        switch self {
        case .cyan: 0x22D3EE
        case .mint: 0x6EE7B7
        case .blue: 0x60A5FA
        case .lavender: 0xC4B5FD
        case .pink: 0xF9A8D4
        case .amber: 0xFCD34D
        }
    }
}

/// Keeps the accent observable across screens and persists it between launches.
@MainActor
@Observable
public final class AppAppearance {
    public static let shared = AppAppearance()

    public var accent: AppAccentColor {
        didSet {
            guard accent != oldValue else { return }
            store.set(accent.rawValue, forKey: "accentColor")
            store.synchronize()
        }
    }

    @ObservationIgnored private let store = NSUbiquitousKeyValueStore.default

    private init() {
        accent = AppAccentColor(rawValue: store.string(forKey: "accentColor") ?? "") ?? .cyan
        store.synchronize()
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let storedAccent = AppAccentColor(rawValue: store.string(forKey: "accentColor") ?? "") ?? .cyan
                if accent != storedAccent {
                    accent = storedAccent
                }
            }
        }
    }
}
