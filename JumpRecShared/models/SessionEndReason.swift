//
//  SessionEndReason.swift
//  JumpRecShared
//

/// Describes why an active workout session ended.
public nonisolated enum SessionEndReason: Sendable {
    /// The user stopped the workout manually.
    case manualStop
    /// The workout ended automatically because the configured goal was reached.
    case goalReached
}
