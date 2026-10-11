import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Exports portable history and imports it into the current build's iCloud environment.
struct SessionBackupSection: View {
    @Environment(MyDataStore.self) private var dataStore
    @State private var document: SessionBackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isBusy = false
    @State private var pendingBackup: SessionBackup?
    @State private var isConfirmingImport = false
    @State private var isShowingFeedback = false
    @State private var feedback = ""
    @State private var exportedSessionCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Session Backup")
                .font(AppFonts.badgeLabel)
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)

            VStack(alignment: .leading, spacing: 18) {
                Text("Export downloaded sessions before changing builds. Import saves to the current build’s iCloud environment. Wait for iCloud sync to finish first.")
                    .font(AppFonts.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)

                Button(action: exportBackup) {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
                Button {
                    isImporting = true
                } label: {
                    Label("Import Backup", systemImage: "square.and.arrow.down")
                }
                if isBusy {
                    ProgressView()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.bgPrimary.opacity(0.35))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.accent.opacity(0.18), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .tint(AppColors.accent)
            .disabled(isBusy || dataStore.isCloudSyncActive)
        }
        .fileExporter(
            isPresented: $isExporting, document: document, contentType: .json,
            defaultFilename: "JumpRec-Backup-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))"
        ) { result in
            switch result {
            case .success:
                showFeedback(String(localized: "Saved a backup of \(exportedSessionCount) sessions."))
            case let .failure(error):
                report(error, message: String(localized: "Could not save the backup. Please try again."))
            }
            document = nil
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case let .success(url):
                readBackup(at: url)
            case let .failure(error):
                report(error, message: String(localized: "Could not open the backup. Please try again."))
            }
        }
        .confirmationDialog("Import Backup?", isPresented: $isConfirmingImport, titleVisibility: .visible) {
            Button("Import Backup", action: importBackup)
            Button("Cancel", role: .cancel) { pendingBackup = nil }
        } message: {
            Text("This backup contains \(pendingBackup?.sessions.count ?? 0) sessions. Existing session IDs will be skipped. Better personal records will be kept.")
        }
        .alert("Session Backup", isPresented: $isShowingFeedback) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(feedback)
        }
    }

    private func exportBackup() {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try dataStore.modelContext.save()
                let backup = try SessionBackup.capture(from: dataStore.modelContainer)
                let data = try await Task.detached { try backup.encoded() }.value
                document = SessionBackupDocument(data: data)
                exportedSessionCount = backup.sessions.count
                isExporting = true
            } catch {
                report(error, message: String(localized: "Could not create the backup. Please try again."))
            }
        }
    }

    private func readBackup(at url: URL) {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                pendingBackup = try await Task.detached {
                    let hasAccess = url.startAccessingSecurityScopedResource()
                    defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                    var coordinationError: NSError?
                    var readResult: Result<Data, Error>?
                    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
                        readResult = Result { try Data(contentsOf: coordinatedURL) }
                    }
                    if let coordinationError { throw coordinationError }
                    guard let readResult else { throw SessionBackup.BackupError.invalidData }
                    return try SessionBackup.decode(readResult.get())
                }.value
                isConfirmingImport = true
            } catch {
                report(error, message: String(localized: "This file could not be read as a supported JumpRec backup. Choose an unmodified backup exported by JumpRec."))
            }
        }
    }

    private func importBackup() {
        guard let backup = pendingBackup else { return }
        pendingBackup = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try dataStore.modelContext.save()
                let result = try backup.restore(into: dataStore.modelContainer)
                dataStore.refreshLocalSessionCount()
                showFeedback(String(localized: "Imported \(result.imported) sessions; skipped \(result.skipped) existing sessions. iCloud upload will continue automatically when available."))
            } catch {
                report(error, message: String(localized: "Could not import the backup. No backup changes were saved. Please try again."))
            }
        }
    }

    private func report(_ error: Error, message: String) {
        print("[SessionBackup] \(error)")
        showFeedback(message)
    }

    private func showFeedback(_ message: String) {
        feedback = message
        isShowingFeedback = true
    }
}

/// JSON data passed to the system file exporter.
nonisolated struct SessionBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
