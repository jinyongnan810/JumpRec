//
//  DeviceSource.swift
//  JumpRec
//

import Foundation

/// Identifies the device currently supplying motion data.
enum DeviceSource: String, CaseIterable {
    /// Uses Apple Watch motion data.
    case watch = "Watch"
    /// Uses supported headphone motion data.
    case airpods = "Headphone"

    // MARK: - Display Metadata

    /// Returns the localized short label shown in the UI.
    var shortName: String {
        switch self {
        case .watch: String(localized: "Watch")
        case .airpods: String(localized: "Headphone")
        }
    }

    /// Returns the SF Symbol associated with the source.
    var iconName: String {
        switch self {
        case .watch: "applewatch"
        case .airpods: "airpodspro"
        }
    }
}
