//
//  DebugMotionCSVStore.swift
//  JumpRec
//

#if DEBUG
    import Foundation
    import Observation

    /// Manages locally stored debug motion CSV files so users can share or clean them up on iPhone.
    @Observable
    @MainActor
    final class DebugMotionCSVStore {
        /// Identifies which device recorded the exported motion CSV.
        enum Source: Sendable {
            case watch
            case iphone

            var localizedTitle: String {
                switch self {
                case .watch:
                    String(localized: "Apple Watch")
                case .iphone:
                    String(localized: "iPhone")
                }
            }

            var systemImageName: String {
                switch self {
                case .watch:
                    "applewatch"
                case .iphone:
                    "iphone"
                }
            }
        }

        /// Represents a single locally saved debug motion CSV file.
        struct ExportItem: Identifiable, Hashable, Sendable {
            let id: String
            let url: URL
            let filename: String
            let createdAt: Date
            let fileSizeBytes: Int64
            let source: Source

            var formattedSize: String {
                ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
            }
        }

        /// Shared store observed by debug export UI.
        static let shared = DebugMotionCSVStore()

        /// Saved CSV files ordered from newest to oldest.
        private(set) var items: [ExportItem] = []

        private init() {
            refresh()
        }

        /// Writes a CSV file to local Documents and refreshes the observable export list.
        @discardableResult
        func save(csvText: String, filename: String) -> URL? {
            do {
                let documentsURL = try documentsDirectoryURL()
                let fileURL = documentsURL.appendingPathComponent(filename)
                try csvText.write(to: fileURL, atomically: true, encoding: .utf8)
                print("[DebugMotionCSVStore] Saved CSV to local Documents at \(fileURL.path)")
                refresh()
                return fileURL
            } catch {
                print("[DebugMotionCSVStore] Error saving CSV to local Documents: \(error.localizedDescription)")
                return nil
            }
        }

        /// Reloads the list of locally saved motion CSV files from Documents.
        func refresh() {
            guard let documentsURL = try? documentsDirectoryURL() else {
                items = []
                return
            }

            let resourceKeys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .fileSizeKey]
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            ) else {
                items = []
                return
            }

            items = urls
                .filter { $0.pathExtension.lowercased() == "csv" }
                .map { url in
                    let values = try? url.resourceValues(forKeys: Set(resourceKeys))
                    let createdAt = values?.contentModificationDate ?? values?.creationDate ?? .distantPast
                    let fileSizeBytes = Int64(values?.fileSize ?? 0)
                    let filename = url.lastPathComponent
                    let source: Source = filename.hasPrefix("watch-motion") ? .watch : .iphone
                    return ExportItem(
                        id: filename,
                        url: url,
                        filename: filename,
                        createdAt: createdAt,
                        fileSizeBytes: fileSizeBytes,
                        source: source
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return lhs.filename > rhs.filename
                }
        }

        /// Deletes one saved CSV file and updates the list.
        func delete(_ item: ExportItem) {
            do {
                if FileManager.default.fileExists(atPath: item.url.path) {
                    try FileManager.default.removeItem(at: item.url)
                }
                refresh()
            } catch {
                print("[DebugMotionCSVStore] Failed to delete CSV \(item.filename): \(error.localizedDescription)")
            }
        }

        /// Deletes all locally saved debug motion CSV files.
        func deleteAll() {
            for item in items {
                do {
                    if FileManager.default.fileExists(atPath: item.url.path) {
                        try FileManager.default.removeItem(at: item.url)
                    }
                } catch {
                    print("[DebugMotionCSVStore] Failed to delete CSV \(item.filename): \(error.localizedDescription)")
                }
            }
            refresh()
        }

        /// Resolves the app's local Documents directory.
        private func documentsDirectoryURL() throws -> URL {
            try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
    }
#endif
