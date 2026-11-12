//
//  MotionManager.swift
//  JumpRec
//

import AVFAudio
import CoreMotion
import Foundation
import Synchronization

/// Manages jump detection on iPhone using supported headphone motion.
final class MotionManager: NSObject {
    /// Holds lock-protected motion detection state shared between the main actor and Core Motion queue.
    private final nonisolated class SampleProcessor: Sendable {
        struct LiveMotionEvents {
            let needsAvailabilityConfirmation: Bool
            let didDetectJump: Bool
        }

        private struct State {
            var isTracking = false
            var isHeadphoneConnected = false
            var isAvailabilityConfirmationInFlight = false
            let headphoneDetector = JumpDetector(profile: .headphones)
            var recordedSamples: [MotionSample] = []
        }

        private let shouldRecordMotionSamples: Bool
        private let state = Mutex(State())

        init(shouldRecordMotionSamples: Bool) {
            self.shouldRecordMotionSamples = shouldRecordMotionSamples
        }

        var isTracking: Bool {
            state.withLock { $0.isTracking }
        }

        func prepareIfNotTracking(thresholdAdjustmentPercentage: Double) {
            state.withLock { state in
                guard !state.isTracking else { return }
                state.headphoneDetector.updateThresholdAdjustmentPercentage(thresholdAdjustmentPercentage)
                state.headphoneDetector.reset()
                if shouldRecordMotionSamples {
                    state.recordedSamples.removeAll(keepingCapacity: true)
                }
            }
        }

        func startTracking(thresholdAdjustmentPercentage: Double) {
            state.withLock { state in
                state.isTracking = true
                state.headphoneDetector.updateThresholdAdjustmentPercentage(thresholdAdjustmentPercentage)
                state.headphoneDetector.reset()
                if shouldRecordMotionSamples {
                    state.recordedSamples.removeAll(keepingCapacity: true)
                }
            }
        }

        func resetIfNotTracking() {
            state.withLock { state in
                guard !state.isTracking else { return }
                state.headphoneDetector.reset()
                if shouldRecordMotionSamples {
                    state.recordedSamples.removeAll(keepingCapacity: true)
                }
            }
        }

        func updateThresholdAdjustmentPercentage(_ percentage: Double) {
            state.withLock { state in
                state.headphoneDetector.updateThresholdAdjustmentPercentage(percentage)
            }
        }

        func stopTracking() {
            state.withLock { state in
                state.isTracking = false
            }
        }

        func syncAvailability(isHeadphoneConnected: Bool) {
            state.withLock { state in
                state.isHeadphoneConnected = isHeadphoneConnected
            }
        }

        func finishAvailabilityConfirmation(isHeadphoneConnected: Bool) {
            state.withLock { state in
                state.isHeadphoneConnected = isHeadphoneConnected
                state.isAvailabilityConfirmationInFlight = false
            }
        }

        func consumeRecordedSamples() -> [MotionSample] {
            guard shouldRecordMotionSamples else { return [] }
            return state.withLock { state in
                let samples = state.recordedSamples
                state.recordedSamples.removeAll(keepingCapacity: false)
                return samples
            }
        }

        func processSample(_ sample: MotionSample) -> LiveMotionEvents {
            state.withLock { state in
                let needsAvailabilityConfirmation = !state.isHeadphoneConnected && !state.isAvailabilityConfirmationInFlight
                if needsAvailabilityConfirmation {
                    state.isAvailabilityConfirmationInFlight = true
                }

                guard state.isTracking else {
                    return LiveMotionEvents(
                        needsAvailabilityConfirmation: needsAvailabilityConfirmation,
                        didDetectJump: false
                    )
                }

                if shouldRecordMotionSamples {
                    state.recordedSamples.append(sample)
                }

                let didDetectJump = state.headphoneDetector.processMotionSample(sample)
                return LiveMotionEvents(
                    needsAvailabilityConfirmation: needsAvailabilityConfirmation,
                    didDetectJump: didDetectJump
                )
            }
        }
    }

    /// Identifies which local device produced a detected jump.
    enum Source: Equatable {
        /// A jump detected from supported headphone motion sensors.
        case headphones
    }

    // MARK: - Public State

    /// Indicates whether local motion tracking is currently active.
    var isTracking: Bool {
        sampleProcessor.isTracking
    }

    // MARK: - Motion Managers

    /// Reads motion data from supported headphones.
    private let headphoneMotionManager = CMHeadphoneMotionManager()
    /// Reports compatible headphone connections before motion tracking starts.
    private let headphoneActivityManager = CMHeadphoneActivityManager()
    /// Serializes motion processing work off the main thread.
    private let queue = OperationQueue()

    // MARK: - Detection

    /// Synchronizes tracking state, jump detection, and debug samples across actors and the motion queue.
    private let sampleProcessor: SampleProcessor

    // MARK: - Callbacks

    /// Reports accepted jumps back to app state.
    private let onJumpDetected: @MainActor (Source) -> Void
    /// Reports headphone availability changes and the best-known headphone name back to app state.
    private let onAvailabilityChanged: @MainActor (_ headphoneAvailable: Bool, _ headphoneName: String?) -> Void

    // MARK: - Private State

    /// Headphone motion support confirmed by Core Motion, not by the audio route alone.
    private var isHeadphoneConnected = false
    /// Stores the latest route name for the connected headphones so the UI can show a real product name.
    private var connectedHeadphoneName: String?
    /// Tracks whether Core Motion headphone status/connection observers have been started.
    private var hasStartedConnectionMonitoring = false

    // MARK: - Initialization

    /// Configures headphone motion tracking, callbacks, and route-change observation.
    init(
        shouldRecordMotionSamples: Bool = false,
        onJumpDetected: @escaping @MainActor (Source) -> Void,
        onAvailabilityChanged: @escaping @MainActor (_ headphoneAvailable: Bool, _ headphoneName: String?) -> Void
    ) {
        sampleProcessor = SampleProcessor(shouldRecordMotionSamples: shouldRecordMotionSamples)
        self.onJumpDetected = onJumpDetected
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
        startHeadphoneConnectionMonitoringIfAuthorized()
        queue.maxConcurrentOperationCount = 1
        queue.name = "JumpRec.iPhoneMotionManager"
    }

    /// Stops route-change observation and Core Motion callbacks when the manager is released.
    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        if hasStartedConnectionMonitoring {
            headphoneActivityManager.stopStatusUpdates()
            headphoneMotionManager.stopConnectionStatusUpdates()
        }
        headphoneMotionManager.stopDeviceMotionUpdates()
        headphoneMotionManager.delegate = nil
        // Cancel queued Core Motion callbacks before disconnecting observers and delegates.
        queue.cancelAllOperations()
    }

    // MARK: - Availability

    /// Returns whether supported headphone motion is currently available.
    var isHeadphoneMotionAvailable: Bool {
        headphoneMotionManager.isDeviceMotionAvailable && isHeadphoneConnected && hasConnectedHeadphoneRoute()
    }

    /// Returns whether an audio headphone route is connected without touching Core Motion permissions.
    var hasConnectedAudioHeadphoneRoute: Bool {
        hasConnectedHeadphoneRoute()
    }

    /// Returns the most recently resolved connected headphone route name.
    var currentHeadphoneName: String? {
        connectedHeadphoneName
    }

    /// Refreshes local availability flags and publishes headphone availability.
    func refreshAvailability() {
        startHeadphoneConnectionMonitoringIfAuthorized()
        // Clear availability when headphones disconnect; an audio route alone cannot confirm support.
        clearHeadphoneConnectionIfRouteMissing()
        connectedHeadphoneName = currentConnectedHeadphoneName()
        notifyAvailabilityChanged()
    }

    // MARK: - Tracking

    /// Warms up headphone motion streams during the countdown without recording jumps.
    func prepareForWorkout(thresholdAdjustmentPercentage: Double = DefaultJumpDetectorThresholdAdjustmentPercentage) {
        guard !isTracking else { return }

        clearHeadphoneConnectionIfRouteMissing()
        connectedHeadphoneName = currentConnectedHeadphoneName()
        notifyAvailabilityChanged()

        sampleProcessor.prepareIfNotTracking(thresholdAdjustmentPercentage: thresholdAdjustmentPercentage)

        startHeadphoneConnectionMonitoringIfAuthorized()
        startHeadphoneMonitoringIfAvailable()
    }

    /// Starts headphone tracking with the configured relative sensitivity adjustment.
    func startTracking(thresholdAdjustmentPercentage: Double = DefaultJumpDetectorThresholdAdjustmentPercentage) {
        guard !isTracking else { return }

        clearHeadphoneConnectionIfRouteMissing()
        connectedHeadphoneName = currentConnectedHeadphoneName()

        // Apply sensitivity and clear motion history before processing active workout samples.
        sampleProcessor.startTracking(thresholdAdjustmentPercentage: thresholdAdjustmentPercentage)

        notifyAvailabilityChanged()
        startHeadphoneConnectionMonitoringIfAuthorized()
        startHeadphoneMonitoringIfAvailable()
    }

    /// Stops pre-warmed motion streams when the countdown is cancelled before the workout starts.
    func cancelPreparation() {
        guard !isTracking else { return }

        headphoneMotionManager.stopDeviceMotionUpdates()
        sampleProcessor.resetIfNotTracking()
    }

    /// Changes sensitivity without clearing jumps, recorded samples, or refractory timing.
    func updateThresholdAdjustmentPercentage(_ percentage: Double) {
        sampleProcessor.updateThresholdAdjustmentPercentage(percentage)
    }

    /// Stops local motion tracking.
    func stopTracking() {
        guard isTracking else { return }

        sampleProcessor.stopTracking()
        headphoneMotionManager.stopDeviceMotionUpdates()
    }

    /// Returns and clears any recorded motion samples collected during the session.
    func consumeRecordedSamples() -> [MotionSample] {
        sampleProcessor.consumeRecordedSamples()
    }

    // MARK: - Motion Updates

    /// Starts headphone motion updates when supported hardware is available.
    private func startHeadphoneMonitoringIfAvailable() {
        guard headphoneMotionManager.isDeviceMotionAvailable,
              !headphoneMotionManager.isDeviceMotionActive
        else { return }

        let sampleProcessor = sampleProcessor
        headphoneMotionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let motion else { return }

            let sample = MotionSample(
                userAccelerationX: motion.userAcceleration.x,
                userAccelerationY: motion.userAcceleration.y,
                userAccelerationZ: motion.userAcceleration.z,
                rotationRateX: motion.rotationRate.x,
                rotationRateY: motion.rotationRate.y,
                rotationRateZ: motion.rotationRate.z,
                timestamp: motion.timestamp
            )
            let events = sampleProcessor.processSample(sample)
            guard events.needsAvailabilityConfirmation || events.didDetectJump else {
                return
            }

            Task { @MainActor [weak self] in
                self?.handleLiveMotionEvents(
                    needsAvailabilityConfirmation: events.needsAvailabilityConfirmation,
                    didDetectJump: events.didDetectJump
                )
            }
        }
    }

    // MARK: - Headphone Status

    /// Starts Core Motion headphone observers only after Motion & Fitness access is granted so launch never prompts.
    private func startHeadphoneConnectionMonitoringIfAuthorized() {
        guard !hasStartedConnectionMonitoring,
              CMHeadphoneMotionManager.authorizationStatus() == .authorized
        else {
            return
        }

        hasStartedConnectionMonitoring = true
        startHeadphoneStatusUpdatesIfAvailable()
        headphoneMotionManager.startConnectionStatusUpdates()
    }

    /// Monitors headphone status, including compatible headphones connected before startup.
    private func startHeadphoneStatusUpdatesIfAvailable() {
        guard headphoneActivityManager.isStatusAvailable else { return }

        headphoneActivityManager.startStatusUpdates(to: queue) { [weak self] status, _ in
            let isConnected: Bool
            switch status {
            case .connected:
                isConnected = true
            case .disconnected:
                isConnected = false
            @unknown default:
                return
            }

            Task { @MainActor [weak self] in
                self?.applyConfirmedHeadphoneAvailability(isConnected: isConnected)
            }
        }
    }

    /// Commits availability confirmation and detected jumps signaled from the motion queue.
    private func handleLiveMotionEvents(
        needsAvailabilityConfirmation: Bool,
        didDetectJump: Bool
    ) {
        if needsAvailabilityConfirmation {
            applyConfirmedHeadphoneAvailability(isConnected: true)
            sampleProcessor.finishAvailabilityConfirmation(isHeadphoneConnected: isHeadphoneConnected)
        }
        if didDetectJump, isTracking {
            onJumpDetected(.headphones)
        }
    }

    /// Applies confirmed headphone availability from status, delegate, or motion callbacks.
    private func applyConfirmedHeadphoneAvailability(isConnected: Bool) {
        sampleProcessor.syncAvailability(isHeadphoneConnected: isConnected)
        let previousConnection = isHeadphoneConnected
        let previousHeadphoneName = connectedHeadphoneName

        isHeadphoneConnected = isConnected
        connectedHeadphoneName = currentConnectedHeadphoneName()

        guard isHeadphoneConnected != previousConnection || connectedHeadphoneName != previousHeadphoneName else {
            return
        }

        notifyAvailabilityChanged()
    }

    // MARK: - State Publishing

    /// Publishes the latest headphone availability flag and route name.
    private func notifyAvailabilityChanged() {
        Task { @MainActor in
            // Use the audio-route name only when it is more specific than the fallback label.
            onAvailabilityChanged(isHeadphoneMotionAvailable, connectedHeadphoneName)
        }
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

    /// Recomputes availability after an audio-route change.
    @objc
    private nonisolated func handleAudioRouteChange(_: Notification) {
        Task { @MainActor [weak self] in
            self?.refreshAvailabilityAfterAudioRouteChange()
        }
    }

    /// Clears confirmed availability when no headphone audio route is connected.
    private func clearHeadphoneConnectionIfRouteMissing() {
        guard !hasConnectedHeadphoneRoute() else { return }
        isHeadphoneConnected = false
        sampleProcessor.syncAvailability(isHeadphoneConnected: false)
    }

    /// Applies audio-route changes on the main actor.
    private func refreshAvailabilityAfterAudioRouteChange() {
        startHeadphoneConnectionMonitoringIfAuthorized()
        let wasConnected = isHeadphoneConnected
        clearHeadphoneConnectionIfRouteMissing()
        let previousHeadphoneName = connectedHeadphoneName
        connectedHeadphoneName = currentConnectedHeadphoneName()
        guard isHeadphoneConnected != wasConnected || connectedHeadphoneName != previousHeadphoneName else { return }
        notifyAvailabilityChanged()
    }
}

extension MotionManager: CMHeadphoneMotionManagerDelegate {
    /// Refreshes availability when supported headphones connect.
    nonisolated func headphoneMotionManagerDidConnect(_: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            applyConfirmedHeadphoneAvailability(isConnected: hasConnectedHeadphoneRoute())
        }
    }

    /// Refreshes availability when supported headphones disconnect.
    nonisolated func headphoneMotionManagerDidDisconnect(_: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            applyConfirmedHeadphoneAvailability(isConnected: false)
        }
    }
}
