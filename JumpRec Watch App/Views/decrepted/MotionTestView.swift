//
//  MotionTestView.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/14.
//

import Charts
import SwiftUI
#if os(watchOS)
    import WatchKit
#endif
import Observation

/// View for testing and visualizing motion detection
struct MotionTestView: View {
    @State private var motionManager = MotionManager(addJump: { _ in })
    @State private var calibrationManager = CalibrationManager()
    @State private var showingCalibration = false
    @State private var showingSettings = false
    @State private var accelerationHistory: [AccelerationPoint] = []
    @State private var maxHistoryPoints = 100

    var body: some View {
        #if os(watchOS)
            watchView
        #else
            iPhoneView
        #endif
    }

    // MARK: - Watch View

    #if os(watchOS)
        var watchView: some View {
            NavigationView {
                ScrollView {
                    VStack(spacing: 10) {
                        // Jump Counter
                        jumpCounterView

                        // Control Buttons
                        controlButtonsView

                        // Real-time Acceleration
                        accelerationView

                        // Settings Button
                        settingsButtonView
                    }
                    .padding()
                }
                .navigationTitle("Jump Counter")
                .navigationBarTitleDisplayMode(.inline)
            }
            .sheet(isPresented: $showingCalibration) {
                CalibrationView(calibrationManager: $calibrationManager)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(motionManager: $motionManager)
            }
            // TODO:
//        .onReceive(motionManager.$currentAcceleration) { acceleration in
//            updateAccelerationHistory(acceleration)
//        }
        }
    #endif

    // MARK: - iPhone View

    #if !os(watchOS)
        var iPhoneView: some View {
            NavigationView {
                VStack(spacing: 20) {
                    // Jump Counter Card
                    jumpCounterCard

                    // Acceleration Chart
                    accelerationChart

                    // Statistics
                    statisticsView

                    // Control Buttons
                    HStack(spacing: 20) {
                        controlButton(
                            title: motionManager.isTracking ? "Stop" : "Start",
                            color: motionManager.isTracking ? .red : .green,
                            action: toggleTracking
                        )

                        controlButton(
                            title: "Reset",
                            color: .orange,
                            action: { motionManager.resetSession() }
                        )
                    }
                    .padding(.horizontal)

                    // Bottom Buttons
                    HStack(spacing: 20) {
                        Button("Calibrate") {
                            showingCalibration = true
                        }
                        .buttonStyle(.bordered)

                        Button("Settings") {
                            showingSettings = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top)
                .navigationTitle("Motion Test")
                .sheet(isPresented: $showingCalibration) {
                    CalibrationView(calibrationManager: calibrationManager)
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView(motionManager: motionManager)
                }
            }
            .onReceive(motionManager.$currentAcceleration) { acceleration in
                updateAccelerationHistory(acceleration)
            }
        }
    #endif

    // MARK: - Shared Components

    var jumpCounterView: some View {
        VStack(spacing: 5) {
            Text("\(motionManager.jumpCount)")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("JUMPS")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(15)
    }

    var jumpCounterCard: some View {
        VStack(spacing: 10) {
            Text("\(motionManager.jumpCount)")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("JUMPS")
                .font(.title3)
                .foregroundColor(.secondary)

            if motionManager.isTracking {
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                    Text("Recording")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.blue.opacity(0.1))
        )
        .padding(.horizontal)
    }

    var accelerationView: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Acceleration")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text(String(format: "%.2fg", motionManager.currentAcceleration))
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                // Visual indicator
                accelerationIndicator
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }

    var accelerationIndicator: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                .frame(width: 30, height: 30)

            Circle()
                .fill(accelerationColor)
                .frame(width: 20, height: 20)
                .scaleEffect(motionManager.currentAcceleration > motionManager.detectionSensitivity ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: motionManager.currentAcceleration)
        }
    }

    var accelerationColor: Color {
        let accel = motionManager.currentAcceleration
        if accel > motionManager.detectionSensitivity {
            return .green
        } else if accel > motionManager.detectionSensitivity * 0.7 {
            return .yellow
        } else {
            return .gray
        }
    }

    var controlButtonsView: some View {
        HStack(spacing: 15) {
            Button(action: toggleTracking) {
                Label(
                    motionManager.isTracking ? "Stop" : "Start",
                    systemImage: motionManager.isTracking ? "stop.fill" : "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(motionManager.isTracking ? .red : .green)

            Button(action: { motionManager.resetSession() }) {
                Label("Reset", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(!motionManager.isTracking)
        }
    }

    var settingsButtonView: some View {
        HStack(spacing: 15) {
            Button("Calibrate") {
                showingCalibration = true
            }
            .buttonStyle(.bordered)

            Button("Settings") {
                showingSettings = true
            }
            .buttonStyle(.bordered)
        }
    }

    #if !os(watchOS)
        var accelerationChart: some View {
            VStack(alignment: .leading) {
                Text("Real-time Acceleration")
                    .font(.headline)
                    .padding(.horizontal)

                Chart(accelerationHistory) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Acceleration", point.acceleration)
                    )
                    .foregroundStyle(.blue)

                    // Threshold line
                    RuleMark(y: .value("Threshold", motionManager.detectionSensitivity))
                        .foregroundStyle(.red.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
                .frame(height: 200)
                .padding(.horizontal)
                .chartYScale(domain: 0 ... 4)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisTick()
                    }
                }
            }
            .padding(.vertical)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.gray.opacity(0.05))
            )
            .padding(.horizontal)
        }

        var statisticsView: some View {
            HStack(spacing: 20) {
                StatisticCard(
                    title: "Rate",
                    value: String(format: "%.0f", motionManager.getCurrentJumpRate()),
                    unit: "per min"
                )

                StatisticCard(
                    title: "Interval",
                    value: String(format: "%.2f", motionManager.getAverageJumpInterval()),
                    unit: "seconds"
                )

                StatisticCard(
                    title: "Sensitivity",
                    value: String(format: "%.1f", motionManager.detectionSensitivity),
                    unit: "G"
                )
            }
            .padding(.horizontal)
        }
    #endif

    // MARK: - Helper Methods

    private func toggleTracking() {
        if motionManager.isTracking {
            motionManager.stopTracking()
        } else {
            // Load calibration profile if exists
            if let profile = CalibrationManager.loadProfile() {
                calibrationManager.applyProfile(profile, to: motionManager)
            }
            motionManager.startTracking()
        }
    }

    // TODO:
//    private func updateAccelerationHistory(_ acceleration: Double) {
//        let point = AccelerationPoint(
//            timestamp: Date(),
//            acceleration: acceleration
//        )
//
//        accelerationHistory.append(point)
//
//        // Keep only recent points
//        if accelerationHistory.count > maxHistoryPoints {
//            accelerationHistory.removeFirst()
//        }
//    }

    private func controlButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(color)
                .cornerRadius(10)
        }
    }
}

// MARK: - Supporting Views

struct CalibrationView: View {
    @Binding var calibrationManager: CalibrationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Progress
                ProgressView(value: calibrationManager.progress)
                    .padding(.horizontal)

                // State Icon
                stateIcon

                // Instructions
                Text(calibrationManager.instructions)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Action Buttons
                actionButtons

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        calibrationManager.cancelCalibration()
                        dismiss()
                    }
                }
            }
        }
    }

    var stateIcon: some View {
        Group {
            switch calibrationManager.state {
            case .idle:
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
            case .collectingBaseline:
                Image(systemName: "figure.stand")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
            case .collectingJumps:
                Image(systemName: "figure.jumprope")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
            case .analyzingData:
                ProgressView()
                    .scaleEffect(1.5)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
            }
        }
        .frame(height: 80)
    }

    var actionButtons: some View {
        VStack(spacing: 15) {
            if calibrationManager.state == CalibrationState.idle {
                Button(action: {
                    calibrationManager.startCalibration()
                }) {
                    Label("Start Calibration", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if calibrationManager.state == .completed {
                Button(action: {
                    dismiss()
                }) {
                    Label("Done", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if let profile = calibrationManager.calibrationProfile {
                    Text(profile.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal)
    }
}

struct SettingsView: View {
    @Binding var motionManager: MotionManager
    @Environment(\.dismiss) private var dismiss
    @State private var sensitivity: Double = 1.5
    @State private var minJumpInterval: Double = 0.3

    var body: some View {
        NavigationView {
            Form {
                Section("Detection Settings") {
                    VStack(alignment: .leading) {
                        Text("Sensitivity: \(String(format: "%.1f", sensitivity))G")
                        Slider(value: $sensitivity, in: 1.0 ... 3.0, step: 0.1)
                    }

                    VStack(alignment: .leading) {
                        Text("Min Jump Interval: \(String(format: "%.1f", minJumpInterval))s")
                        Slider(value: $minJumpInterval, in: 0.2 ... 1.0, step: 0.1)
                    }
                }

                Section("Information") {
                    LabeledContent("Current Acceleration", value: String(format: "%.2fg", motionManager.currentAcceleration))
                    LabeledContent("Jump Count", value: "\(motionManager.jumpCount)")
                    LabeledContent("Jump Rate", value: String(format: "%.0f/min", motionManager.getCurrentJumpRate()))
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        motionManager.setSensitivity(sensitivity)
                        motionManager.setMinTimeBetweenJumps(minJumpInterval)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            sensitivity = motionManager.detectionSensitivity
            minJumpInterval = 0.3 // Default value
        }
    }
}

struct StatisticCard: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
}

// MARK: - Data Models

struct AccelerationPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let acceleration: Double
}
