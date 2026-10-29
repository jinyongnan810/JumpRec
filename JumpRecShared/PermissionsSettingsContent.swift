import CoreMotion
import HealthKit
import OSLog
import SwiftUI

/// Shows local permission status without inferring Health read access from available samples.
struct PermissionsSettingsContent: View {
    @Environment(\.scenePhase) private var scenePhase
    /// The iPhone app opens its own system Settings page from the application context.
    var openAppSettings: (@MainActor () async -> Bool)? = nil
    @State private var workoutStatus = HKAuthorizationStatus.notDetermined
    @State private var energyStatus = HKAuthorizationStatus.notDetermined
    @State private var motionStatus = CMAuthorizationStatus.notDetermined
    @State private var canRequestHealthAccess = false
    @State private var isRequesting = false
    @State private var isShowingHealthHelp = false
    @State private var isShowingError = false

    private let healthStore = HKHealthStore()
    private static let logger = Logger(subsystem: "JumpRec", category: "Permissions")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if HKHealthStore.isHealthDataAvailable() {
                permissionRow(
                    title: "Save Workouts",
                    status: healthStatus(workoutStatus),
                    explanation: "Saves completed workouts to Apple Health."
                )
                #if os(watchOS)
                    permissionRow(
                        title: "Save Active Energy",
                        status: healthStatus(energyStatus),
                        explanation: "Saves calories burned during Watch workouts."
                    )
                #endif
                permissionRow(
                    title: "Read Health Data",
                    status: .reviewInHealth,
                    explanation: "Reads heart rate, active energy, and activity summaries."
                )
                if canRequestHealthAccess {
                    Button("Allow Health Access") {
                        Task { await requestHealthAccess() }
                    }
                    .disabled(isRequesting)
                }
                Button("Review Health Permissions") {
                    isShowingHealthHelp = true
                }
            } else {
                Text("Health data is unavailable on this device.")
                    .foregroundStyle(AppColors.textMuted)
            }
            #if os(iOS)
                Divider()
                    .overlay(AppColors.textMuted.opacity(0.3))

                permissionRow(
                    title: "Headphone Motion",
                    status: motionPermissionStatus,
                    explanation: "Uses supported headphones to count jumps."
                )
                if let openAppSettings {
                    Button("Open App Settings") {
                        Task {
                            if await !openAppSettings() {
                                isShowingError = true
                            }
                        }
                    }
                }
            #endif
        }
        .task { await refreshPermissions() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshPermissions() }
            }
        }
        .alert("Health Permissions", isPresented: $isShowingHealthHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            #if os(watchOS)
                Text("On Apple Watch, open Settings, then Health, and select JumpRec to review access. Health read permissions cannot be checked by the app.")
            #else
                Text("Open Health on iPhone, tap your profile, then Apps under Privacy, and select JumpRec. Health read permissions cannot be checked by the app.")
            #endif
        }
        .alert("Unable to Update Permissions", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again or review JumpRec’s permissions in system settings.")
        }
    }

    private func permissionRow(title: LocalizedStringResource, status: PermissionStatus, explanation: LocalizedStringResource) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: 4)
            Image(systemName: status.systemImage)
                .font(.subheadline)
                .foregroundStyle(status.color)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(status.title))
        .accessibilityHint(Text(explanation))
    }

    private enum PermissionStatus {
        case allowed, denied, notRequested, restricted, reviewInHealth, unknown

        var title: LocalizedStringResource {
            switch self {
            case .allowed: "Allowed"
            case .denied: "Not Allowed"
            case .notRequested: "Not Requested"
            case .restricted: "Restricted"
            case .reviewInHealth: "Review in Health"
            case .unknown: "Unknown"
            }
        }

        var systemImage: String {
            switch self {
            case .allowed: "checkmark.circle.fill"
            case .denied: "xmark.circle.fill"
            case .notRequested: "circle.dashed"
            case .restricted: "lock.circle.fill"
            case .reviewInHealth: "info.circle"
            case .unknown: "questionmark.circle"
            }
        }

        @MainActor
        var color: Color {
            switch self {
            case .allowed: AppColors.accent
            case .denied: .red
            case .restricted: .orange
            case .reviewInHealth: AppColors.accent
            case .notRequested, .unknown: AppColors.textMuted
            }
        }
    }

    private func healthStatus(_ status: HKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .sharingAuthorized: .allowed
        case .sharingDenied: .denied
        case .notDetermined: .notRequested
        @unknown default: .unknown
        }
    }

    #if os(iOS)
        private var motionPermissionStatus: PermissionStatus {
            switch motionStatus {
            case .authorized: .allowed
            case .denied: .denied
            case .restricted: .restricted
            case .notDetermined: .notRequested
            @unknown default: .unknown
            }
        }

    #endif

    @MainActor
    private func refreshPermissions() async {
        #if os(iOS)
            motionStatus = CMHeadphoneMotionManager.authorizationStatus()
        #endif
        guard HKHealthStore.isHealthDataAvailable() else { return }
        workoutStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        energyStatus = healthStore.authorizationStatus(for: HKQuantityType(.activeEnergyBurned))
        do {
            canRequestHealthAccess = try await WorkoutPermissions.requestStatus(using: healthStore) == .shouldRequest
        } catch {
            Self.logger.error("Could not refresh Health permission request status: \(error.localizedDescription)")
            canRequestHealthAccess = false
            isShowingError = true
        }
    }

    @MainActor
    private func requestHealthAccess() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        do {
            try await WorkoutPermissions.requestAuthorization(using: healthStore)
        } catch {
            Self.logger.error("Could not request Health permissions: \(error.localizedDescription)")
            isShowingError = true
        }
        await refreshPermissions()
    }
}

#Preview {
    List {
        Section("Permissions") {
            PermissionsSettingsContent()
        }
    }
}
