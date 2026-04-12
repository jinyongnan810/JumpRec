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
    /// Monitors compatible headphone connection status outside of an active motion session.
    ///
    /// Apple documents `CMHeadphoneActivityManager.Status.connected` as "A compatible set of headphones is connected."
    /// Apple also documents that `startStatusUpdates` immediately delivers `.connected` when supported headphones
    /// were already connected before monitoring started. That makes this manager the most reliable way to decide
    /// whether the home screen should show headphones as available before the first motion sample arrives.
    private let headphoneActivityManager = CMHeadphoneActivityManager()
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
    /// Reports motion availability changes and the best-known headphone name back to app state.
    private let onAvailabilityChanged: @MainActor (_ iPhoneAvailable: Bool, _ headphoneAvailable: Bool, _ headphoneName: String?) -> Void

    // MARK: - Private State

    /// Remembers the last published preferred source to avoid duplicate updates.
    private var lastPreferredSource: Source?
    /// Tracks whether Core Motion has confirmed a motion-capable headphone connection.
    ///
    /// This is intentionally stricter than "some headphones are connected." The device selector should only
    /// present a headphone model as usable after Core Motion reports a compatible connection or delivers live
    /// motion samples. Audio route information alone is too broad because many regular Bluetooth headphones
    /// appear there even though they never provide motion data.
    private var isHeadphoneConnected = false
    /// Stores the latest route name for the connected headphones so the UI can show a real product name.
    private var connectedHeadphoneName: String?
    /// Stores raw motion samples when recording is enabled.
    private var recordedSamples: [MotionSample] = []

    // MARK: - Initialization

    /// Configures local motion tracking, callbacks, and route-change observation.
    init(
        shouldRecordMotionSamples: Bool = false,
        onJumpDetected: @escaping @MainActor (Source) -> Void,
        onSourceChanged: @escaping @MainActor (Source?) -> Void,
        onAvailabilityChanged: @escaping @MainActor (_ iPhoneAvailable: Bool, _ headphoneAvailable: Bool, _ headphoneName: String?) -> Void
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
        phoneMotionManager.deviceMotionUpdateInterval = updateInterval
    }

    /// Stops route-change observation when the manager is released.
    deinit {
        NotificationCenter.default.removeObserver(self)
        headphoneActivityManager.stopStatusUpdates()
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
        // Route metadata can tell us when no headphones are connected at all, but it cannot prove that the
        // connected accessory supports motion. Preserve the stricter Core Motion-backed flag unless the route
        // clearly shows that all headphones are gone.
        if !hasConnectedHeadphoneRoute() {
            isHeadphoneConnected = false
        }
        connectedHeadphoneName = currentConnectedHeadphoneName()
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
        if !hasConnectedHeadphoneRoute() {
            isHeadphoneConnected = false
        }
        connectedHeadphoneName = currentConnectedHeadphoneName()

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
            // A live sample is definitive proof that the current headphones are motion-capable, so keep this
            // as a fallback confirmation path even though the home screen now usually learns about support from
            // connection-status updates before the user starts a session.
            applyConfirmedHeadphoneAvailability(isConnected: true)

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

    // MARK: - Headphone Status

    /// Starts Core Motion headphone status updates when the platform supports them.
    ///
    /// The status stream is used for pre-session availability because Apple explicitly says it reports
    /// `.connected` immediately when compatible headphones were already connected before monitoring began.
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

    /// Applies a Core Motion-confirmed headphone availability change and republishes the UI state if needed.
    ///
    /// This shared helper keeps the connection-status stream, motion-manager delegate callbacks, and first
    /// live motion sample aligned so the app has one consistent definition of "supported headphones available."
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

    /// Publishes the latest iPhone and headphone availability flags.
    private func notifyAvailabilityChanged() {
        Task { @MainActor in
            // Route names come from AVAudioSession and can be missing or generic depending on the accessory.
            // The UI only uses this when the system exposes something more specific than the fallback label.
            onAvailabilityChanged(isPhoneMotionAvailable, isHeadphoneMotionAvailable, connectedHeadphoneName)
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

    /// Returns whether the current audio route contains any headphone-like output.
    ///
    /// Audio routes alone do not prove motion support. This helper is only used to clear stale state when
    /// the user fully disconnects from headphones, not to positively declare motion availability.
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

    /// Returns the current route's descriptive headphone name when motion-capable headphones are confirmed.
    ///
    /// This guard avoids showing a generic Bluetooth headset model inside the selector when that accessory
    /// cannot actually be used for motion tracking.
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

    /// Centralizes the route types that can represent headphone motion sources so name lookup matches availability checks.
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
        // Connection callbacks refresh availability immediately, but actual promotion to
        // headphones as the active in-session source still depends on receiving live motion samples.
        //
        // This callback is still valuable for foreground attach events, while the activity-manager status
        // stream covers the "already connected before launch" case for the home screen.
        applyConfirmedHeadphoneAvailability(isConnected: hasConnectedHeadphoneRoute())
    }

    /// Refreshes availability when supported headphones disconnect.
    func headphoneMotionManagerDidDisconnect(_: CMHeadphoneMotionManager) {
        // A disconnect invalidates headphone priority, so the preferred source is recomputed.
        applyConfirmedHeadphoneAvailability(isConnected: false)
    }
}
