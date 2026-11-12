//
//  MotionCSVFormatter.swift
//  JumpRecShared
//

#if DEBUG
    import Foundation

    /// Formats recorded motion samples into CSV text and stable debug filenames.
    public nonisolated enum MotionCSVFormatter {
        /// Converts recorded motion samples into CSV text with relative timestamps.
        public static func makeCSV(from samples: [MotionSample]) -> String {
            let baseTimestamp = samples.first?.timestamp ?? 0
            let header = "time,AX,AY,AZ,RX,RY,RZ"

            let rows = samples.map { sample in
                String(
                    format: "%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f",
                    sample.timestamp - baseTimestamp,
                    sample.userAccelerationX,
                    sample.userAccelerationY,
                    sample.userAccelerationZ,
                    sample.rotationRateX,
                    sample.rotationRateY,
                    sample.rotationRateZ
                )
            }

            return ([header] + rows).joined(separator: "\n")
        }

        /// Builds a stable filename for an exported motion CSV.
        public static func makeFilename(prefix: String = "motion", startedAt: Date, endedAt: Date) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let start = sanitizedFilenameTimestamp(from: formatter.string(from: startedAt))
            let end = sanitizedFilenameTimestamp(from: formatter.string(from: endedAt))
            return "\(prefix)-\(start)-\(end).csv"
        }

        /// Sanitizes a timestamp string for safe filename use.
        private static func sanitizedFilenameTimestamp(from value: String) -> String {
            value.replacingOccurrences(of: ":", with: "-")
        }
    }
#endif
