//
//  MotionManager.swift
//  JumpRec
//

import AVFAudio
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

    private let phoneDetector = JumpDetector(profile: .iPhonePocket)
    private let headphoneDetector = JumpDetector(profile: .headphones)
    private let shouldRecordMotionSamples: Bool
    private let recordedSamplesLock = NSLock()

    private let onJumpDetected: @MainActor (Source) -> Void
    private let onSourceChanged: @MainActor (Source?) -> Void
    private let onAvailabilityChanged: @MainActor (_ iPhoneAvailable: Bool, _ headphoneAvailable: Bool) -> Void

    private var lastPreferredSource: Source?
    private var isHeadphoneConnected = false
    private var recordedSamples: [MotionSample] = []

    init(
        shouldRecordMotionSamples: Bool = false,
        onJumpDetected: @escaping @MainActor (Source) -> Void,
        onSourceChanged: @escaping @MainActor (Source?) -> Void,
        onAvailabilityChanged: @escaping @MainActor (_ iPhoneAvailable: Bool, _ headphoneAvailable: Bool) -> Void
    ) {
        self.shouldRecordMotionSamples = shouldRecordMotionSamples
        self.onJumpDetected = onJumpDetected
        self.onSourceChanged = onSourceChanged
        self.onAvailabilityChanged = onAvailabilityChanged
        super.init()
        headphoneMotionManager.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        headphoneMotionManager.startConnectionStatusUpdates()
        isHeadphoneConnected = currentAudioRouteSupportsHeadphoneMotion()
        queue.maxConcurrentOperationCount = 1
        queue.name = "JumpRec.iPhoneMotionManager"
        phoneMotionManager.deviceMotionUpdateInterval = updateInterval
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var isPhoneMotionAvailable: Bool {
        phoneMotionManager.isDeviceMotionAvailable
    }

    var isHeadphoneMotionAvailable: Bool {
        isHeadphoneConnected
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
        isHeadphoneConnected = currentAudioRouteSupportsHeadphoneMotion()
        notifyAvailabilityChanged()
        updatePreferredSourceIfNeeded(force: true)
    }

    func startTracking() {
        guard !isTracking else { return }

        isTracking = true
        phoneDetector.reset()
        headphoneDetector.reset()
        resetRecordedSamples()
        isHeadphoneConnected = currentAudioRouteSupportsHeadphoneMotion()

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
        updatePreferredSourceIfNeeded(force: true)
    }

    func consumeRecordedSamples() -> [MotionSample] {
        guard shouldRecordMotionSamples else { return [] }

        recordedSamplesLock.lock()
        defer { recordedSamplesLock.unlock() }

        let samples = recordedSamples
        recordedSamples.removeAll(keepingCapacity: false)
        return samples
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
            record(sample)

            if phoneDetector.processMotionSample(sample) {
                Task { @MainActor in
                    self.onJumpDetected(.iPhone)
                }
            }
        }
    }

    private func startHeadphoneMonitoringIfAvailable() {
        guard headphoneMotionManager.isDeviceMotionAvailable else { return }

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
            record(sample)

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

    private func record(_ sample: MotionSample) {
        guard shouldRecordMotionSamples else { return }

        recordedSamplesLock.lock()
        recordedSamples.append(sample)
        recordedSamplesLock.unlock()
    }

    private func resetRecordedSamples() {
        guard shouldRecordMotionSamples else { return }

        recordedSamplesLock.lock()
        recordedSamples.removeAll(keepingCapacity: true)
        recordedSamplesLock.unlock()
    }

    private func currentAudioRouteSupportsHeadphoneMotion() -> Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let hasHeadphoneRoute = outputs.contains { output in
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                true
            default:
                false
            }
        }
        return hasHeadphoneRoute && headphoneMotionManager.isDeviceMotionAvailable
    }

    @objc
    private func handleAudioRouteChange(_: Notification) {
        let wasConnected = isHeadphoneConnected
        isHeadphoneConnected = currentAudioRouteSupportsHeadphoneMotion()
        guard isHeadphoneConnected != wasConnected else { return }
        notifyAvailabilityChanged()
        updatePreferredSourceIfNeeded(force: true)
    }
}

extension MotionManager: CMHeadphoneMotionManagerDelegate {
    func headphoneMotionManagerDidConnect(_: CMHeadphoneMotionManager) {
        // Connection callbacks refresh availability immediately, but actual promotion to
        // headphones still depends on receiving live motion samples.
        isHeadphoneConnected = currentAudioRouteSupportsHeadphoneMotion()
        notifyAvailabilityChanged()
        updatePreferredSourceIfNeeded(force: true)
    }

    func headphoneMotionManagerDidDisconnect(_: CMHeadphoneMotionManager) {
        // A disconnect invalidates headphone priority, so the preferred source is recomputed.
        isHeadphoneConnected = currentAudioRouteSupportsHeadphoneMotion()
        notifyAvailabilityChanged()
        updatePreferredSourceIfNeeded(force: true)
    }
}
