//
//  HeadphoneManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2026/02/22.
//
import CoreMotion
import Observation

@Observable
final class HeadphoneManager: NSObject, CMHeadphoneMotionManagerDelegate {
    private let manager = CMHeadphoneMotionManager()

    var motionAuthorized: Bool = CMHeadphoneMotionManager.authorizationStatus() == .authorized
    var motionActive: Bool = false

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
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            print("getting device motion: motion: \(String(describing: motion)), error: \(String(describing: error))")
//            self?.motionActive = (motion != nil && error == nil)
        }
    }

    func stop() {
        manager.stopConnectionStatusUpdates()
        manager.stopDeviceMotionUpdates()
    }

    // sometimes(most of times) not firing
    func headphoneMotionManagerDidConnect(_: CMHeadphoneMotionManager) {
        print("headphone connected")
        motionActive = true
    }

    func headphoneMotionManagerDidDisconnect(
        _: CMHeadphoneMotionManager
    ) {
        print("headphone disconnected")
        motionActive = false
    }
}
