//
//  DeviceSource.swift
//  JumpRec
//

import Foundation

/// Identifies the device currently supplying motion data.
enum DeviceSource: String, CaseIterable {
    /// Uses Apple Watch motion data.
    case watch = "Watch"
    /// Uses the iPhone motion sensors.
    case iPhone
    /// Uses supported headphone motion data.
    case airpods = "Headphone"

    // MARK: - Display Metadata

    /// Returns the short label shown in the UI.
    var shortName: String {
        rawValue
    }

    /// Returns the SF Symbol associated with the source.
    var iconName: String {
        switch self {
        case .watch: "applewatch"
        case .iPhone: "iphone"
        case .airpods: "airpodspro"
        }
    }
}
