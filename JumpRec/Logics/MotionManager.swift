//
//  MotionManager.swift
//  JumpRec
//

import CoreMotion
import Foundation
import JumpRecShared

/// Manages jump detection on iPhone using both local device motion and supported headphone motion.
final class MotionManager: NSObject {
    enum Source: Equatable {
        case iPhone
        case headphones
    }

    var isTracking = false

    private let phoneMotionManager = CMMotionManager()
    private let headphoneMotionManager = CMHeadphoneMotionManager()
    private let queue = OperationQueue()
    private let updateInterval: TimeInterval = 0.05

    private let phoneDetector = JumpDetector()
    private let headphoneDetector = JumpDetector()

    private let onJumpDetected: @MainActor (Source) -> Void
    private let onSourceChanged: @MainActor (Source?) -> Void
    private let onAvailabilityChanged: @MainActor (_ iPhoneAvailable: Bool, _ headphoneAvailable: Bool) -> Void

    private var lastPreferredSource: Source?
    private var isHeadphoneConnected = false

    init(
        onJumpDetected: @escaping @MainActor (Source) -> Void,
        onSourceChanged: @escaping @MainActor (Source?) -> Void,
        onAvailabilityChanged: @escaping @MainActor (_ iPhoneAvailable: Bool, _ headphoneAvailable: Bool) -> Void
    ) {
        self.onJumpDetected = onJumpDetected
        self.onSourceChanged = onSourceChanged
        self.onAvailabilityChanged = onAvailabilityChanged
        super.init()
        headphoneMotionManager.delegate = self
        isHeadphoneConnected = headphoneMotionManager.isDeviceMotionAvailable
        queue.maxConcurrentOperationCount = 1
        queue.name = "JumpRec.iPhoneMotionManager"
        phoneMotionManager.deviceMotionUpdateInterval = updateInterval
    }

    var isPhoneMotionAvailable: Bool {
        phoneMotionManager.isDeviceMotionAvailable
    }

    var isHeadphoneMotionAvailable: Bool {
        headphoneMotionManager.isDeviceMotionAvailable
    }

    var preferredSource: Source? {
        // Headphone motion wins whenever it is actively producing samples.
        if isHeadphoneConnected, headphoneMotionManager.deviceMotion != nil {
            return .headphones
        }
        // Fall back to iPhone motion when headphone data is unavailable.
        if phoneMotionManager.isDeviceMotionActive {
            return .iPhone
        }
        return nil
    }

    func refreshAvailability() {
        isHeadphoneConnected = headphoneMotionManager.isDeviceMotionAvailable
        notifyAvailabilityChanged()
        updatePreferredSourceIfNeeded(force: true)
    }

    func startTracking() {
        guard !isTracking else { return }

        isTracking = true
        phoneDetector.reset()
        headphoneDetector.reset()
        isHeadphoneConnected = headphoneMotionManager.isDeviceMotionAvailable

        notifyAvailabilityChanged()
        startPhoneMotionUpdatesIfAvailable()
        startHeadphoneMonitoringIfAvailable()
        updatePreferredSourceIfNeeded()
    }

    func stopTracking() {
        guard isTracking else { return }

        isTracking = false
        phoneMotionManager.stopDeviceMotionUpdates()
        headphoneMotionManager.stopDeviceMotionUpdates()
        headphoneMotionManager.stopConnectionStatusUpdates()
        updatePreferredSourceIfNeeded(force: true)
    }

    private func startPhoneMotionUpdatesIfAvailable() {
        guard phoneMotionManager.isDeviceMotionAvailable else { return }

        phoneMotionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion, isTracking else { return }

            // Initialize the active source once the first local motion sample arrives.
            if lastPreferredSource == nil {
                updatePreferredSourceIfNeeded()
            }

            // Ignore iPhone samples as soon as headphone motion becomes the preferred source.
            if preferredSource == .headphones {
                return
            }

            let sample = MotionSample(
                userAccelerationX: motion.userAcceleration.x,
                userAccelerationY: motion.userAcceleration.y,
                userAccelerationZ: motion.userAcceleration.z,
                rotationRateX: motion.rotationRate.x,
                rotationRateY: motion.rotationRate.y,
                rotationRateZ: motion.rotationRate.z,
                timestamp: motion.timestamp
            )

            if phoneDetector.processMotionSample(sample) {
                Task { @MainActor in
                    self.onJumpDetected(.iPhone)
                }
            }
        }
    }

    private func startHeadphoneMonitoringIfAvailable() {
        guard headphoneMotionManager.isDeviceMotionAvailable else { return }

        headphoneMotionManager.startConnectionStatusUpdates()
        headphoneMotionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion, isTracking else { return }
            isHeadphoneConnected = true

            // Promote headphones immediately on the first live headphone sample.
            if lastPreferredSource != .headphones {
                updatePreferredSourceIfNeeded(force: true)
            }

            let sample = MotionSample(
                userAccelerationX: motion.userAcceleration.x,
                userAccelerationY: motion.userAcceleration.y,
                userAccelerationZ: motion.userAcceleration.z,
                rotationRateX: motion.rotationRate.x,
                rotationRateY: motion.rotationRate.y,
                rotationRateZ: motion.rotationRate.z,
                timestamp: motion.timestamp
            )

            if headphoneDetector.processMotionSample(sample) {
                Task { @MainActor in
                    self.onJumpDetected(.headphones)
                }
            }
        }
    }

    private func updatePreferredSourceIfNeeded(force: Bool = false) {
        let source = isTracking ? preferredSource : nil
        // Only publish source changes when the effective source actually changes.
        guard force || source != lastPreferredSource else { return }
        lastPreferredSource = source
        Task { @MainActor in
            onSourceChanged(source)
        }
    }

    private func notifyAvailabilityChanged() {
        Task { @MainActor in
            onAvailabilityChanged(isPhoneMotionAvailable, isHeadphoneMotionAvailable)
        }
    }
}

extension MotionManager: CMHeadphoneMotionManagerDelegate {
    func headphoneMotionManagerDidConnect(_: CMHeadphoneMotionManager) {
        // Connection callbacks refresh availability immediately, but actual promotion to
        // headphones still depends on receiving live motion samples.
        isHeadphoneConnected = true
        notifyAvailabilityChanged()
        updatePreferredSourceIfNeeded(force: true)
    }

    func headphoneMotionManagerDidDisconnect(_: CMHeadphoneMotionManager) {
        // A disconnect invalidates headphone priority, so the preferred source is recomputed.
        isHeadphoneConnected = false
        notifyAvailabilityChanged()
        updatePreferredSourceIfNeeded(force: true)
    }
}
