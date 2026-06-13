//
//  CloudCSVExporter.swift
//  JumpRec
//

import Foundation

/// Serializes iCloud CSV exports and waits for container availability without blocking a thread.
actor CloudCSVExporter {
    /// The number of delayed availability checks made after the initial immediate check.
    private let maximumRetryCount = 5
    /// The delay between iCloud availability checks.
    private let retryDelay: Duration = .milliseconds(500)

    /// Saves CSV text in the requested iCloud container's Documents directory.
    ///
    /// iCloud identity and container discovery can briefly return `nil` during app startup
    /// or account transitions. Suspending between checks leaves the underlying thread free
    /// and also makes cancellation responsive when the owning task no longer needs the export.
    func save(csvText: String, filename: String, containerIdentifier: String) async {
        guard await waitForUbiquityIdentity() else {
            print("[CloudCSVExporter] iCloud not available or user not logged in")
            return
        }

        guard let containerURL = await waitForContainerURL(identifier: containerIdentifier) else {
            print("[CloudCSVExporter] Could not resolve iCloud container URL")
            return
        }

        guard !Task.isCancelled else { return }

        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)

        do {
            if !FileManager.default.fileExists(atPath: documentsURL.path) {
                try FileManager.default.createDirectory(
                    at: documentsURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                print("[CloudCSVExporter] Created Documents directory in iCloud container")
            }

            let fileURL = documentsURL.appendingPathComponent(filename)
            try csvText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("[CloudCSVExporter] Saved CSV to iCloud at \(fileURL.path)")
        } catch {
            print("[CloudCSVExporter] Error saving CSV to iCloud: \(error.localizedDescription)")
        }
    }

    /// Waits briefly for the signed-in iCloud identity token to become available.
    private func waitForUbiquityIdentity() async -> Bool {
        if FileManager.default.ubiquityIdentityToken != nil {
            return true
        }

        for _ in 0 ..< maximumRetryCount {
            print("[CloudCSVExporter] Waiting for iCloud ubiquity identity token...")
            guard await waitBeforeRetry() else { return false }

            if FileManager.default.ubiquityIdentityToken != nil {
                return true
            }
        }

        return false
    }

    /// Waits briefly for FileManager to resolve the requested ubiquitous container.
    private func waitForContainerURL(identifier: String) async -> URL? {
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: identifier) {
            return containerURL
        }

        for _ in 0 ..< maximumRetryCount {
            print("[CloudCSVExporter] Waiting for iCloud container URL...")
            guard await waitBeforeRetry() else { return nil }

            if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: identifier) {
                return containerURL
            }
        }

        return nil
    }

    /// Suspends between retries and reports cancellation without treating it as an export error.
    private func waitBeforeRetry() async -> Bool {
        do {
            try await Task.sleep(for: retryDelay)
            return true
        } catch is CancellationError {
            return false
        } catch {
            print("[CloudCSVExporter] Retry delay failed: \(error.localizedDescription)")
            return false
        }
    }
}
