#if DEBUG && targetEnvironment(simulator)
    import Foundation
    import SwiftData

    /// Deterministic simulator data based on the May 2026 App Store screenshots.
    @MainActor
    public enum ScreenshotFixtures {
        /// Persists the opt-in across launches; disabling restores the regular store.
        public static var isEnabled: Bool {
            let defaults = UserDefaults.standard
            if ProcessInfo.processInfo.arguments.contains("--screenshot-data") {
                defaults.set(true, forKey: "screenshotDataEnabled")
            }
            if ProcessInfo.processInfo.arguments.contains("--disable-screenshot-data") {
                defaults.set(false, forKey: "screenshotDataEnabled")
            }
            return defaults.bool(forKey: "screenshotDataEnabled")
        }

        public static var state: String? {
            guard isEnabled,
                  let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--screenshot-state"),
                  ProcessInfo.processInfo.arguments.indices.contains(index + 1) else { return nil }
            return ProcessInfo.processInfo.arguments[index + 1]
        }

        static func date(day: Int, month: Int = 5, hour: Int = 18, minute: Int = 11) -> Date {
            // Local dates keep the same calendar cells in every simulator time zone.
            Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
        }

        /// Recreates the short workout shown in the completion screenshot without saving it to history.
        public static func makeCompletedSession() -> JumpSession {
            let start = date(day: 30, hour: 16, minute: 5)
            let session = JumpSession(
                startedAt: start, endedAt: start.addingTimeInterval(87),
                jumpCount: 182, peakRate: 156, averageRate: 126,
                caloriesBurned: 7, longestStreak: 182,
                averageHeartRate: 111, peakHeartRate: 128
            )
            session.replaceRateSamples(with: rateSamples(duration: 87, rate: 143, hasBreaks: false))
            return session
        }

        /// Approximates the reference charts; the original per-second measurements are unavailable.
        static func rateSamples(duration: Int, rate: Double, hasBreaks: Bool) -> [RateSamplePoint] {
            stride(from: 0, through: duration, by: 3).map { second in
                let ramp = min(1, Double(second) / 9, Double(duration - second) / 9)
                let isBreak = hasBreaks && ((258 ... 273).contains(second) || (339 ... 354).contains(second))
                let variation = sin(Double(second) * 0.7) * 7 + cos(Double(second) * 0.23) * 4
                return RateSamplePoint(secondOffset: second, rate: Float(isBreak ? 0 : max(0, (rate + variation) * ramp)))
            }
        }
    }

    extension MyDataStore {
        /// Populates only the separate, local screenshot store, once per simulator install.
        func seedScreenshotHistoryIfNeeded() throws {
            guard try modelContext.fetchCount(FetchDescriptor<JumpSession>()) == 0 else { return }

            // Visible counts and totals match the reference; obscured workout details are representative.
            let workouts: [(day: Int, jumps: Int, seconds: Int, calories: Double, peak: Double, streak: Int)] = [
                (4, 1200, 540, 83, 180, 480),
                (9, 1000, 420, 58, 174, 1000),
                (16, 1100, 420, 65, 186, 620),
                (18, 1000, 480, 67, 172, 510),
                (23, 872, 420, 55, 168, 430),
                (26, 1000, 435, 61, 180, 492),
                (30, 1208, 525, 76, 192, 740),
            ]
            for workout in workouts {
                let start = ScreenshotFixtures.date(day: workout.day, minute: workout.day == 26 ? 44 : 11)
                let session = JumpSession(
                    startedAt: start, endedAt: start.addingTimeInterval(Double(workout.seconds)),
                    jumpCount: workout.jumps, peakRate: workout.peak,
                    averageRate: Double(workout.jumps) * 60 / Double(workout.seconds),
                    caloriesBurned: workout.calories, smallBreaksCount: workout.day == 9 ? 0 : 4,
                    longBreaksCount: workout.day == 9 ? 0 : 1, longestStreak: workout.streak
                )
                modelContext.insert(session)
                session.replaceRateSamples(with: ScreenshotFixtures.rateSamples(
                    duration: workout.seconds, rate: workout.day == 26 ? 162 : 165,
                    hasBreaks: workout.day != 9
                ))
                upsertPersonalRecords(for: session)
            }
            // The reference's peak-rate record was achieved outside the visible May history.
            let peakRecord = try modelContext.fetch(FetchDescriptor<PersonalRecord>()).first { $0.kind == .bestJumpRate }
            peakRecord?.metricValue = 204
            peakRecord?.displayValue = localizedRateText(204)
            peakRecord?.achievedAt = ScreenshotFixtures.date(day: 19, month: 6)
            try modelContext.save()
            refreshLocalSessionCount()
            print("[ScreenshotFixtures] Loaded \(localSessionCount) May workouts, 7,380 jumps, 54 minutes")
        }
    }
#endif
