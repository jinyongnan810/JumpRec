//
//  NumberParser.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/23.
//

import Foundation

/// Converts loosely typed payload values into strongly typed numbers.
enum NumberParser {
    nonisolated static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    nonisolated static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
