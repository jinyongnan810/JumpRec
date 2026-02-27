//
//  DeviceSource.swift
//  JumpRec
//

import Foundation

enum DeviceSource: String, CaseIterable {
    case watch = "Apple Watch"
    case iPhone
    case airpods = "AirPods"

    var iconName: String {
        switch self {
        case .watch: "applewatch"
        case .iPhone: "iphone"
        case .airpods: "airpodspro"
        }
    }
}
