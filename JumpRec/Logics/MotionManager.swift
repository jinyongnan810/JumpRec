//
//  MotionManager.swift
//  JumpRec
//

import AVFAudio
import CoreMotion
import Foundation

/// Manages jump detection on iPhone using supported headphone motion.
final class MotionManager: NSObject {
    /// Identifies which local device produced a detected jump.
    enum Source: Equatable {
        /// A jump detected from supported headphone motion sensors.
        case headphones
    }

    // MARK: - Public State

    /// Indicates whether local motion tracking is currently active.
    var isTracking = false

    // MARK: - Motion Managers

    /// Reads motion data from supported headphones.
    private let headphoneMotionManager = CMHeadphoneMotionManager()
    /// Reports compatible headphone connections before motion tracking starts.
    private let headphoneActivityManager = CMHeadphoneActivityManager()
    /// Serializes motion processing work off the main thread.
    private let queue = OperationQueue()

    // MARK: - Detection

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
    /// Reports headphone availability changes and the best-known headphone name back to app state.
    private let onAvailabilityChanged: @MainActor (_ headphoneAvailable: Bool, _ headphoneName: String?) -> Void

    // MARK: - Private State

    /// Remembers the last published preferred source to avoid duplicate updates.
    private var lastPreferredSource: Source?
    /// Headphone motion support confirmed by Core Motion, not by the audio route alone.
    private var isHeadphoneConnected = false
    /// Stores the latest route name for the connected headphones so the UI can show a real product name.
    private var connectedHeadphoneName: String?
    /// Stores raw motion samples when recording is enabled.
    private var recordedSamples: [MotionSample] = []

    // MARK: - Initialization

    /// Configures headphone motion tracking, callbacks, and route-change observation.
    init(
        shouldRecordMotionSamples: Bool = false,
        onJumpDetected: @escaping @MainActor (Source) -> Void,
        onSourceChanged: @escaping @MainActor (Source?) -> Void,
        onAvailabilityChanged: @escaping @MainActor (_ headphoneAvailable: Bool, _ headphoneName: String?) -> Void
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
        isHeadphoneConnected = false
        connectedHeadphoneName = nil
        startHeadphoneStatusUpdatesIfAvailable()
        headphoneMotionManager.startConnectionStatusUpdates()
        queue.maxConcurrentOperationCount = 1
        queue.name = "JumpRec.iPhoneMotionManager"
    }

    /// Stops route-change observation and Core Motion callbacks when the manager is released.
    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        headphoneActivityManager.stopStatusUpdates()
        headphoneMotionManager.stopDeviceMotionUpdates()
        headphoneMotionManager.stopConnectionStatusUpdates()
        headphoneMotionManager.delegate = nil
        // Cancel queued Core Motion callbacks before disconnecting observers and delegates.
        queue.cancelAllOperations()
    }

    // MARK: - Availability

    /// Returns whether supported headphone motion is currently available.
    var isHeadphoneMotionAvailable: Bool {
        headphoneMotionManager.isDeviceMotionAvailable && isHeadphoneConnected && hasConnectedHeadphoneRoute()
    }

    /// Returns the most recently resolved connected headphone route name.
    var currentHeadphoneName: String? {
        connectedHeadphoneName
    }

    /// Returns the preferred live motion source based on current connectivity.
    var preferredSource: Source? {
        isHeadphoneMotionAvailable ? .headphones : nil
    }

    /// Refreshes local availability flags and republishes the preferred source.
    func refreshAvailability() {
        // Clear availability when headphones disconnect; an audio route alone cannot confirm support.
        if !hasConnectedHeadphoneRoute() {
            isHeadphoneConnected = false
        }
        connectedHeadphoneName = currentConnectedHeadphoneName()
        notifyAvailabilityChanged()
        updatePreferredSourceIfNeeded(force: true)
    }

    // MARK: - Tracking

    /// Warms up headphone motion streams during the countdown without recording jumps.
    func prepareForWorkout(thresholdAdjustmentPercentage: Double = DefaultJumpDetectorThresholdAdjustmentPercentage) {
        guard !isTracking else { return }

        if !hasConnectedHeadphoneRoute() {
            isHeadphoneConnected = false
        }
        connectedHeadphoneName = currentConnectedHeadphoneName()
        notifyAvailabilityChanged()

        queue.addOperation { [weak self] in
            guard let self, !isTracking else { return }
            headphoneDetector.updateThresholdAdjustmentPercentage(thresholdAdjustmentPercentage)
            headphoneDetector.reset()
            resetRecordedSamples()
        }

        startHeadphoneMonitoringIfAvailable()
    }

    /// Starts headphone tracking with the configured relative sensitivity adjustment.
    func startTracking(thresholdAdjustmentPercentage: Double = DefaultJumpDetectorThresholdAdjustmentPercentage) {
        guard !isTracking else { return }

        isTracking = true
        if !hasConnectedHeadphoneRoute() {
            isHeadphoneConnected = false
        }
        connectedHeadphoneName = currentConnectedHeadphoneName()

        queue.addOperation { [weak self] in
            guard let self else { return }
            // Apply sensitivity and clear motion history before processing active workout samples.
            headphoneDetector.updateThresholdAdjustmentPercentage(thresholdAdjustmentPercentage)
            headphoneDetector.reset()
            resetRecordedSamples()
        }

        notifyAvailabilityChanged()
        startHeadphoneMonitoringIfAvailable()
        updatePreferredSourceIfNeeded()
    }

    /// Stops pre-warmed motion streams when the countdown is cancelled before the workout starts.
    func cancelPreparation() {
        guard !isTracking else { return }

        headphoneMotionManager.stopDeviceMotionUpdates()
        queue.addOperation { [weak self] in
            guard let self, !isTracking else { return }
            headphoneDetector.reset()
            resetRecordedSamples()
        }
        updatePreferredSourceIfNeeded(force: true)
    }

    /// Changes sensitivity without clearing jumps, recorded samples, or refractory timing.
    func updateThresholdAdjustmentPercentage(_ percentage: Double) {
        queue.addOperation { [weak self] in
            guard let self else { return }
            headphoneDetector.updateThresholdAdjustmentPercentage(percentage)
        }
    }

    /// Stops local motion tracking and clears the active preferred source.
    func stopTracking() {
        guard isTracking else { return }

        isTracking = false
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

    /// Starts headphone motion updates when supported hardware is available.
    private func startHeadphoneMonitoringIfAvailable() {
        guard headphoneMotionManager.isDeviceMotionAvailable,
              !headphoneMotionManager.isDeviceMotionActive
        else { return }

        headphoneMotionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // A live motion sample confirms compatible headphones if status updates are unavailable.
            applyConfirmedHeadphoneAvailability(isConnected: true)
            guard isTracking else { return }

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

            // Use the headphone detector's separate profile and state.
            if headphoneDetector.processMotionSample(sample) {
                Task { @MainActor in
                    self.onJumpDetected(.headphones)
                }
            }
        }
    }

    // MARK: - Headphone Status

    /// Monitors headphone status, including compatible headphones connected before startup.
    private func startHeadphoneStatusUpdatesIfAvailable() {
        guard headphoneActivityManager.isStatusAvailable else { return }

        headphoneActivityManager.startStatusUpdates(to: queue) { [weak self] status, _ in
            guard let self else { return }

            switch status {
            case .connected:
                applyConfirmedHeadphoneAvailability(isConnected: true)
            case .disconnected:
                applyConfirmedHeadphoneAvailability(isConnected: false)
            @unknown default:
                break
            }
        }
    }

    /// Applies confirmed headphone availability from status, delegate, or motion callbacks.
    private func applyConfirmedHeadphoneAvailability(isConnected: Bool) {
        let previousConnection = isHeadphoneConnected
        let previousHeadphoneName = connectedHeadphoneName

        isHeadphoneConnected = isConnected
        connectedHeadphoneName = currentConnectedHeadphoneName()

        guard isHeadphoneConnected != previousConnection || connectedHeadphoneName != previousHeadphoneName else {
            return
        }

        notifyAvailabilityChanged()
        updatePreferredSourceIfNeeded(force: true)
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

    /// Publishes the latest headphone availability flag and route name.
    private func notifyAvailabilityChanged() {
        Task { @MainActor in
            // Use the audio-route name only when it is more specific than the fallback label.
            onAvailabilityChanged(isHeadphoneMotionAvailable, connectedHeadphoneName)
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

    /// Checks for a headphone audio route to clear stale availability, not confirm motion support.
    private func hasConnectedHeadphoneRoute() -> Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains { output in
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                true
            default:
                false
            }
        }
    }

    /// Returns the route name only for confirmed motion-capable headphones.
    private func currentConnectedHeadphoneName() -> String? {
        guard isHeadphoneConnected else {
            return nil
        }

        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard let headphoneOutput = outputs.first(where: isSupportedHeadphonePort) else {
            return nil
        }

        // `portName` is the system-provided human-readable route label, such as "AirPods Pro".
        let trimmedName = headphoneOutput.portName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    /// Audio-route types used by headphone availability checks and name lookup.
    private func isSupportedHeadphonePort(_ output: AVAudioSessionPortDescription) -> Bool {
        switch output.portType {
        case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            true
        default:
            false
        }
    }

    /// Recomputes availability and preferred source after an audio-route change.
    @objc
    private func handleAudioRouteChange(_: Notification) {
        let wasConnected = isHeadphoneConnected
        if !hasConnectedHeadphoneRoute() {
            isHeadphoneConnected = false
        }
        let previousHeadphoneName = connectedHeadphoneName
        connectedHeadphoneName = currentConnectedHeadphoneName()
        guard isHeadphoneConnected != wasConnected || connectedHeadphoneName != previousHeadphoneName else { return }
        notifyAvailabilityChanged()
        updatePreferredSourceIfNeeded(force: true)
    }
}

extension MotionManager: CMHeadphoneMotionManagerDelegate {
    /// Refreshes availability when supported headphones connect.
    func headphoneMotionManagerDidConnect(_: CMHeadphoneMotionManager) {
        // Refresh availability on connection; select headphones for tracking only after live samples arrive.
        applyConfirmedHeadphoneAvailability(isConnected: hasConnectedHeadphoneRoute())
    }

    /// Refreshes availability when supported headphones disconnect.
    func headphoneMotionManagerDidDisconnect(_: CMHeadphoneMotionManager) {
        // A disconnect invalidates headphone priority, so the preferred source is recomputed.
        applyConfirmedHeadphoneAvailability(isConnected: false)
    }
}
