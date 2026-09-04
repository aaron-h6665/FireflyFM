import SwiftUI
import UIKit

struct ChatAttachmentGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let room: ChatRoom
    let initialCategory: ChatAttachmentCategory

    @State private var model = ChatAttachmentGalleryModel()
    @State private var category: ChatAttachmentCategory
    @State private var exportError: String?
    @State private var isSelecting = false
    @State private var selectedMessageIds: Set<UUID> = []
    @State private var isPreparingExport = false
    @State private var exportURLs: [URL] = []
    @State private var exportDirectory: URL?
    @State private var showingExportSheet = false

    init(room: ChatRoom, initialCategory: ChatAttachmentCategory) {
        self.room = room
        self.initialCategory = initialCategory
        _category = State(initialValue: initialCategory)
    }

    private var messages: [ChatMessageModel] { model.messages }
    private var isLoading: Bool { model.phase.isLoading }
    private var errorMessage: String? { exportError ?? model.errorMessage }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Attachment type", selection: $category) {
                    ForEach(ChatAttachmentCategory.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if isLoading {
                    Spacer(); ProgressView(); Spacer()
                } else if messages.isEmpty {
                    ContentUnavailableView(
                        "No \(category.title.lowercased()) yet",
                        systemImage: category.symbol
                    )
                } else if category == .photos {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                            ForEach(messages) { message in
                                Button { handleTap(message) } label: {
                                    Group {
                                        if message.attachmentType?.hasPrefix("video/") == true {
                                            Rectangle()
                                                .fill(AppConstants.Colors.wingMist.opacity(0.5))
                                                .overlay {
                                                    Image(systemName: "play.rectangle.fill")
                                                        .font(.largeTitle)
                                                        .foregroundColor(AppConstants.Colors.primaryAction)
                                                }
                                        } else {
                                            AsyncImage(url: message.mediaUrl.flatMap(URL.init(string:))) { image in
                                                image.resizable().scaledToFill()
                                            } placeholder: {
                                                Rectangle().fill(AppConstants.Colors.raised)
                                                    .overlay { ProgressView() }
                                            }
                                        }
                                    }
                                    .frame(minHeight: 110)
                                    .clipped()
                                    .overlay(alignment: .topTrailing) {
                                        if isSelecting {
                                            Image(systemName: selectedMessageIds.contains(message.id) ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(
                                                    selectedMessageIds.contains(message.id) ? AppConstants.Colors.brandNavy : .white,
                                                    selectedMessageIds.contains(message.id) ? AppConstants.Colors.accessibleYellow : .black.opacity(0.35)
                                                )
                                                .padding(6)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if isSavableMedia(message) {
                                        Button {
                                            saveToPhotos(message)
                                        } label: {
                                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    List(messages) { message in
                        Button { handleTap(message) } label: {
                            HStack(spacing: 12) {
                                if isSelecting {
                                    Image(systemName: selectedMessageIds.contains(message.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(AppConstants.Colors.accessibleYellow)
                                }
                                Image(systemName: category.symbol)
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(message.attachmentName ?? (category == .audio ? "Voice message" : "Attachment"))
                                        .foregroundColor(AppConstants.Colors.primaryText)
                                    Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundColor(AppConstants.Colors.secondaryText)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundColor(.red).padding()
                }
            }
            .background(AppConstants.Colors.background)
            .navigationTitle("Chat Attachments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if !messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                prepareExport(messages)
                            } label: {
                                Label("Export All", systemImage: "square.and.arrow.up.on.square")
                            }

                            Button {
                                isSelecting.toggle()
                                if !isSelecting { selectedMessageIds.removeAll() }
                            } label: {
                                Label(
                                    isSelecting ? "Cancel Selection" : "Choose Attachments",
                                    systemImage: isSelecting ? "xmark.circle" : "checkmark.circle"
                                )
                            }

                            if isSelecting {
                                Button {
                                    prepareExport(messages.filter { selectedMessageIds.contains($0.id) })
                                } label: {
                                    Label("Export Selected (\(selectedMessageIds.count))", systemImage: "square.and.arrow.up")
                                }
                                .disabled(selectedMessageIds.isEmpty)
                            }
                        } label: {
                            if isPreparingExport {
                                ProgressView()
                            } else {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                        }
                        .disabled(isPreparingExport)
                    }
                }
            }
            .sheet(isPresented: $showingExportSheet, onDismiss: cleanupExport) {
                AttachmentActivityView(items: exportURLs)
            }
            .task(id: category) { await load() }
            .onChange(of: category) { _, _ in
                isSelecting = false
                selectedMessageIds.removeAll()
            }
            .onDisappear(perform: cleanupExport)
        }
    }

    @MainActor
    private func load() async {
        await model.load(roomId: room.id, category: category)
    }

    private func open(_ message: ChatMessageModel) {
        guard let url = attachmentURL(for: message) else { return }
        UIApplication.shared.open(url)
    }

    private func handleTap(_ message: ChatMessageModel) {
        if isSelecting {
            if selectedMessageIds.contains(message.id) { selectedMessageIds.remove(message.id) }
            else { selectedMessageIds.insert(message.id) }
        } else {
            open(message)
        }
    }

    private func attachmentURL(for message: ChatMessageModel) -> URL? {
        let value: String?
        switch category {
        case .photos: value = message.mediaUrl
        case .files: value = message.fileUrl
        case .audio: value = message.audioUrl
        }
        return value.flatMap(URL.init(string:))
    }

    private func isSavableMedia(_ message: ChatMessageModel) -> Bool {
        guard category == .photos else { return false }
        return message.attachmentType?.hasPrefix("image/") == true
            || message.attachmentType?.hasPrefix("video/") == true
    }

    private func saveToPhotos(_ message: ChatMessageModel) {
        guard isSavableMedia(message), let url = attachmentURL(for: message) else { return }
        Task {
            do {
                try await MediaLibrarySaver.save(
                    remoteURL: url,
                    contentType: message.attachmentType,
                    fileName: message.attachmentName
                )
            } catch {
                await MainActor.run {
                    exportError = AppErrorMessage.school("Could not save media to Photos", error)
                }
            }
        }
    }

    private func prepareExport(_ selectedMessages: [ChatMessageModel]) {
        guard !selectedMessages.isEmpty else { return }
        isPreparingExport = true
        exportError = nil

        Task {
            do {
                cleanupExport()
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("FireflyChatExport-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

                var downloadedURLs: [URL] = []
                for (index, message) in selectedMessages.enumerated() {
                    guard let remoteURL = attachmentURL(for: message) else { continue }
                    let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
                    let suggestedName = message.attachmentName ?? response.suggestedFilename ?? defaultExportName(for: message)
                    let destination = directory.appendingPathComponent("\(index + 1)-\(suggestedName.safeFilename)")
                    try FileManager.default.moveItem(at: temporaryURL, to: destination)
                    downloadedURLs.append(destination)
                }

                guard !downloadedURLs.isEmpty else {
                    try? FileManager.default.removeItem(at: directory)
                    throw ChatAttachmentExportError.noDownloadableAttachments
                }

                exportDirectory = directory
                exportURLs = downloadedURLs
                isPreparingExport = false
                showingExportSheet = true
            } catch {
                isPreparingExport = false
                exportError = AppErrorMessage.school("Could not prepare attachments", error)
            }
        }
    }

    private func defaultExportName(for message: ChatMessageModel) -> String {
        switch category {
        case .photos:
            message.attachmentType?.hasPrefix("video/") == true
                ? "Video-\(message.id.uuidString).mov"
                : "Photo-\(message.id.uuidString).jpg"
        case .files: "File-\(message.id.uuidString)"
        case .audio: "Voice-Message-\(message.id.uuidString).m4a"
        }
    }

    private func cleanupExport() {
        if let exportDirectory {
            try? FileManager.default.removeItem(at: exportDirectory)
        }
        exportDirectory = nil
        exportURLs = []
    }
}
private enum ChatAttachmentExportError: LocalizedError {
    case noDownloadableAttachments

    var errorDescription: String? {
        "No downloadable attachments were available."
    }
}

private struct AttachmentActivityView: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
