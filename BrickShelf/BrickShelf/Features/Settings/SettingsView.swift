import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var boxes: [SetBox]
    @Query private var bulk: [BulkPieceRecord]
    @Query private var missing: [MissingPieceRecord]

    @State private var exportDocument = BackupDocument(snapshot: .empty)
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Offline database", systemImage: "iphone.and.arrow.forward")
                    Text("Your collection is stored with SwiftData and remains available without a connection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Storage")
                }

                Section {
                    Button {
                        createBackup()
                    } label: {
                        Label("Export backup", systemImage: "arrow.up.doc.fill")
                    }
                    Button {
                        isImporting = true
                    } label: {
                        Label("Restore from backup", systemImage: "arrow.down.doc.fill")
                    }

                    if let statusMessage {
                        Label(statusMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.teal)
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.coral)
                    }
                } header: {
                    Text("Deletion-safe backup")
                } footer: {
                    Text("Save the .brickshelf file to iCloud Drive, Files, or another provider. It survives app deletion and restores by merging records—never by erasing the current collection. Automatic CloudKit sync can be added after a production Apple developer container is configured.")
                }

                Section("Backup includes") {
                    LabeledContent("Physical boxes", value: boxes.count.formatted())
                    LabeledContent("Bulk records", value: bulk.count.formatted())
                    LabeledContent("Missing-piece records", value: missing.count.formatted())
                    Text("Photos and receipt images are included, so backup files may be large.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    rule("Sets and boxes", "Archive first; keep purchase and provenance data.")
                    rule("Missing pieces", "Mark found or reopen; do not erase normal history.")
                    rule("Bulk pieces", "Adjust counts; archive only duplicate or invalid lines.")
                    rule("Catalog data", "Reference definitions are not deleted by collection actions.")
                } header: {
                    Text("Deletion rules")
                }

                Section("About") {
                    Text("BrickShelf prototype 0.1")
                    Text("Not affiliated with, authorized, sponsored, or endorsed by the LEGO Group.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings & Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .brickShelfBackup,
                defaultFilename: "BrickShelf-\(Date.now.formatted(.iso8601.year().month().day()))"
            ) { result in
                switch result {
                case .success:
                    statusMessage = "Backup exported"
                    errorMessage = nil
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.brickShelfBackup, .json]) { result in
                restore(result)
            }
        }
    }

    @ViewBuilder
    private func rule(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func createBackup() {
        do {
            exportDocument = BackupDocument(snapshot: try BackupSnapshot.make(from: modelContext))
            errorMessage = nil
            isExporting = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(BackupSnapshot.self, from: data)
            let count = try snapshot.merge(into: modelContext)
            statusMessage = "Restored \(count) new records"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
