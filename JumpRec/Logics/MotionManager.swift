//
//  MotionManager.swift
//  JumpRec
//

import AVFAudio
import CoreMotion
import Foundation

/// Manages jump detection on iPhone using both local device motion and supported headphone motion.
final class MotionManager: NSObject {
    /// Identifies which local device produced a detected jump.
    enum Source: Equatable {
        /// A jump detected from iPhone motion sensors.
        case iPhone
        /// A jump detected from supported headphone motion sensors.
        case headphones
    }

    // MARK: - Public State

    /// Indicates whether local motion tracking is currently active.
    var isTracking = false

    // MARK: - Motion Managers

    /// Reads motion data from the iPhone sensors.
    private let phoneMotionManager = CMMotionManager()
    /// Reads motion data from supported headphones.
    private let headphoneMotionManager = CMHeadphoneMotionManager()
    /// Serializes motion processing work off the main thread.
    private let queue = OperationQueue()
    /// Defines the motion sampling interval used for local tracking.
    private let updateInterval: TimeInterval = 0.05

    // MARK: - Detection

    // The app keeps separate detector instances because iPhone-in-pocket motion and headphone motion
    // have different signal characteristics and should not share internal state.
    /// Detects jumps from iPhone motion samples.
    private let phoneDetector = JumpDetector(profile: .iPhonePocket)
    /// Detects jumps from headphone motion samples.
    private let headphoneDetector = JumpDetector(profile: .headphones)
    /// Indicates whether raw motion samples should be stored for export.
    private let shouldRecordMotionSamples: Bool
    /// Protects recorded sample access across the motion-processing queue and UI.
    private let recordedSamplesLock = NSLock()

    // MARK: - Callbacks

    /// Reports accepted jumps back to app state.
    private let onJumpDetected: @MainActor (Source) -> Void
    /// Reports active motion-source changes back to app state.
    private let onSourceChanged: @MainActor (Source?) -> Void
    /// Reports motion availability changes back to app state.
    private let onAvailabilityChanged: @MainActor (_ iPhoneAvailable: Bool, _ headphoneAvailable: Bool) -> Void

    // MARK: - Private State

    /// Remembers the last published preferred source to avoid duplicate updates.
    private var lastPreferredSource: Source?
    /// Tracks whether supported headphones are currently connected.
    private var isHeadphoneConnected = false
    /// Stores raw motion samples when recording is enabled.
    private var recordedSamples: [MotionSample] = []

    // MARK: - Initialization

    /// Configures local motion tracking, callbacks, and route-change observation.
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
        // ⭐️Detect headphone is connected by detecting audio route changes
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

    /// Stops route-change observation when the manager is released.
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Availability

    /// Returns whether iPhone device motion is available.
    var isPhoneMotionAvailable: Bool {
        phoneMotionManager.isDeviceMotionAvailable
    }

    /// Returns whether supported headphone motion is currently available.
    var isHeadphoneMotionAvailable: Bool {
        isHeadphoneConnected
    }

    /// Returns the preferred live motion source based on current connectivity and data flow.
    var preferredSource: Source? {
        // Headphone motion wins whenever it is actively producing samples.
        // This avoids mixing two motion streams into one session count.
        if isHeadphoneConnected, headphoneMotionManager.deviceMotion != nil {
            return .headphones
        }
        // Fall back to iPhone motion when headphone data is unavailable.
        if phoneMotionManager.isDeviceMotionActive {
            return .iPhone
        }
        return nil
    }

    /// Refreshes local availability flags and republishes the preferred source.
    func refreshAvailability() {
        isHeadphoneConnected = currentAudioRouteSupportsHeadphoneMotion()
        notifyAvailabilityChanged()
        updatePreferredSourceIfNeeded(force: true)
    }

    // MARK: - Tracking

    /// Starts local motion tracking for both iPhone and headphone sources when available.
    func startTracking() {
        guard !isTracking else { return }

        isTracking = true
        // Reset detector state at session start so old peaks / cadence hints do not bleed into a new workout.
        phoneDetector.reset()
        headphoneDetector.reset()
        resetRecordedSamples()
        isHeadphoneConnected = currentAudioRouteSupportsHeadphoneMotion()

        notifyAvailabilityChanged()
        startPhoneMotionUpdatesIfAvailable()
        startHeadphoneMonitoringIfAvailable()
        updatePreferredSourceIfNeeded()
    }

    /// Stops local motion tracking and clears the active preferred source.
    func stopTracking() {
        guard isTracking else { return }

        isTracking = false
        phoneMotionManager.stopDeviceMotionUpdates()
        headphoneMotionManager.stopDeviceMotionUpdates()
        updatePreferredSourceIfNeeded(force: true)
    }

    /// Returns and clears any recorded motion samples collected during the session.
    func consumeRecordedSamples() -> [MotionSample] {
        guard shouldRecordMotionSamples else { return [] }

        recordedSamplesLock.lock()
        defer { recordedSamplesLock.unlock() }

        let samples = recordedSamples
        recordedSamples.removeAll(keepingCapacity: false)
        return samples
    }

    // MARK: - Motion Updates

    /// Starts iPhone device-motion updates when they are available.
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

            // The shared detector operates on normalized `MotionSample` values, so this manager only
            // adapts Core Motion data into that shared format and forwards accepted jumps to the UI layer.
            if phoneDetector.processMotionSample(sample) {
                Task { @MainActor in
                    self.onJumpDetected(.iPhone)
                }
            }
        }
    }

    /// Starts headphone motion updates when supported hardware is available.
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

            // Headphone motion is treated as a first-class source rather than a tweak on top of phone motion,
            // because real-world false positives and thresholds differ enough to justify a dedicated profile.
            if headphoneDetector.processMotionSample(sample) {
                Task { @MainActor in
                    self.onJumpDetected(.headphones)
                }
            }
        }
    }

    // MARK: - State Publishing

    /// Publishes preferred-source changes only when the effective source changed.
    private func updatePreferredSourceIfNeeded(force: Bool = false) {
        let source = isTracking ? preferredSource : nil
        // Only publish source changes when the effective source actually changes.
        guard force || source != lastPreferredSource else { return }
        lastPreferredSource = source
        Task { @MainActor in
            onSourceChanged(source)
        }
    }

    /// Publishes the latest iPhone and headphone availability flags.
    private func notifyAvailabilityChanged() {
        Task { @MainActor in
            onAvailabilityChanged(isPhoneMotionAvailable, isHeadphoneMotionAvailable)
        }
    }

    // MARK: - Sample Recording

    /// Appends a motion sample to the export buffer when recording is enabled.
    private func record(_ sample: MotionSample) {
        guard shouldRecordMotionSamples else { return }

        recordedSamplesLock.lock()
        recordedSamples.append(sample)
        recordedSamplesLock.unlock()
    }

    /// Clears the motion-sample export buffer for a new session.
    private func resetRecordedSamples() {
        guard shouldRecordMotionSamples else { return }

        recordedSamplesLock.lock()
        recordedSamples.removeAll(keepingCapacity: true)
        recordedSamplesLock.unlock()
    }

    // MARK: - Audio Routing

    /// Returns whether the current audio route supports headphone motion updates.
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

    /// Recomputes availability and preferred source after an audio-route change.
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
    /// Refreshes availability when supported headphones connect.
    func headphoneMotionManagerDidConnect(_: CMHeadphoneMotionManager) {
        // Connection callbacks refresh availability immediately, but actual promotion to
        // headphones still depends on receiving live motion samples.
        isHeadphoneConnected = currentAudioRouteSupportsHeadphoneMotion()
        notifyAvailabilityChanged()
        updatePreferredSourceIfNeeded(force: true)
    }

    /// Refreshes availability when supported headphones disconnect.
    func headphoneMotionManagerDidDisconnect(_: CMHeadphoneMotionManager) {
        // A disconnect invalidates headphone priority, so the preferred source is recomputed.
        isHeadphoneConnected = currentAudioRouteSupportsHeadphoneMotion()
        notifyAvailabilityChanged()
        updatePreferredSourceIfNeeded(force: true)
    }
}
