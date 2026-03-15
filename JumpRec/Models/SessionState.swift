//
//  SessionState.swift
//  JumpRec
//

/// Represents the lifecycle state of a workout session.
enum SessionState {
    /// No session is running.
    case idle
    /// A session is currently active.
    case active
    /// The latest session has finished and is showing results.
    case complete
}
