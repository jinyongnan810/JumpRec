//
//  AppState+Metrics.swift
//  JumpRec
//

import Foundation

extension JumpRecState {
    // MARK: - Metrics

    /// Updates the latest visible heart-rate sample.
    func updateHeartrate(_ heartrate: Int) {
        self.heartrate = heartrate
    }

    /// Records heart-rate data for average and peak tracking.
    func recordHeartRate(_ heartRate: Int) {
        heartrate = heartRate
        heartRateSum += heartRate
        heartRateSampleCount += 1
        peakHeartRate = max(peakHeartRate, heartRate)
    }

    /// Returns the average heart rate for the current session.
    var averageHeartRate: Int? {
        guard heartRateSampleCount > 0 else { return nil }
        return heartRateSum / heartRateSampleCount
    }

    /// Returns the peak heart rate only when one has been recorded.
    var peakHeartRateValue: Int? {
        peakHeartRate > 0 ? peakHeartRate : nil
    }
}
