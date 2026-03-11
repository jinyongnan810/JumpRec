//
//  DeviceSource.swift
//  JumpRec
//

import Foundation

enum DeviceSource: String, CaseIterable {
    case watch = "Watch"
    case iPhone
    case airpods = "Headphone"

    var shortName: String {
        rawValue
    }

    var iconName: String {
        switch self {
        case .watch: "applewatch"
        case .iPhone: "iphone"
        case .airpods: "airpodspro"
        }
    }
}
