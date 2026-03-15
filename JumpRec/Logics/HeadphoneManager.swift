//
//  HeadphoneManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2026/02/22.
//
import CoreMotion
import Observation

/// Wraps `CMHeadphoneMotionManager` to track headphone motion availability.
@Observable
final class HeadphoneManager: NSObject, CMHeadphoneMotionManagerDelegate {
    /// The underlying Core Motion manager for headphone updates.
    private let manager = CMHeadphoneMotionManager()

    /// Indicates whether motion access has been authorized.
    var motionAuthorized: Bool = CMHeadphoneMotionManager.authorizationStatus() == .authorized
    /// Indicates whether headphone motion updates are currently active.
    var motionActive: Bool = false

    /// Starts listening for connection and motion updates from supported headphones.
    func start() {
        print("authorization: \(motionAuthorized)")
        guard manager.isDeviceMotionAvailable else {
            print("device motion not available")
            return
        }
        manager.delegate = self
        print("starting device motion updates")
        manager.startConnectionStatusUpdates()
        // sometimes(most of times) not firing
        manager.startDeviceMotionUpdates(to: .main) { motion, error in
            print("getting device motion: motion: \(String(describing: motion)), error: \(String(describing: error))")
//            self?.motionActive = (motion != nil && error == nil)
        }
    }

    /// Stops all headphone connection and motion updates.
    func stop() {
        manager.stopConnectionStatusUpdates()
        manager.stopDeviceMotionUpdates()
    }

    // sometimes(most of times) not firing
    /// Marks motion as active when supported headphones connect.
    func headphoneMotionManagerDidConnect(_: CMHeadphoneMotionManager) {
        print("headphone connected")
        motionActive = true
    }

    /// Marks motion as inactive when supported headphones disconnect.
    func headphoneMotionManagerDidDisconnect(
        _: CMHeadphoneMotionManager
    ) {
        print("headphone disconnected")
        motionActive = false
    }
}
