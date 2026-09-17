import AVKit
import QuickLook
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
    @State private var selectedPreview: ChatAttachmentPreviewItem?

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
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 3),
                                count: 3
                            ),
                            spacing: 3
                        ) {
                            ForEach(messages) { message in
                                Button { handleTap(message) } label: {
                                    Group {
                                        if message.attachmentType?.hasPrefix("video/") == true {
                                            ChatVideoThumbnailView(
                                                url: message.mediaUrl.flatMap(URL.init(string:))
                                            )
                                        } else {
                                            Rectangle()
                                                .fill(AppConstants.Colors.raised)
                                                .overlay {
                                                    AsyncImage(url: message.mediaUrl.flatMap(URL.init(string:))) { image in
                                                        image
                                                            .resizable()
                                                            .scaledToFill()
                                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                            .clipped()
                                                    } placeholder: {
                                                        ProgressView()
                                                    }
                                                }
                                        }
                                    }
                                    .aspectRatio(1, contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .contentShape(Rectangle())
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
            .sheet(item: $selectedPreview) { item in
                ChatAttachmentPreviewView(item: item, roomId: room.id)
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
        selectedPreview = ChatAttachmentPreviewItem(
            messageId: message.id,
            remoteURL: url,
            category: category,
            contentType: message.attachmentType,
            fileName: message.attachmentName ?? defaultExportName(for: message)
        )
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

struct ChatAttachmentPreviewItem: Identifiable {
    let messageId: UUID
    let remoteURL: URL
    let category: ChatAttachmentCategory
    let contentType: String?
    let fileName: String

    var id: UUID { messageId }
    var isVideo: Bool { contentType?.hasPrefix("video/") == true }
}

struct ChatAttachmentPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let item: ChatAttachmentPreviewItem
    let roomId: UUID

    @State private var localURL: URL?
    @State private var temporaryDirectory: URL?
    @State private var player: AVPlayer?
    @State private var isPlayingAudio = false
    @State private var isStored = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingShareSheet = false
    @State private var showingRemoveConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if let localURL {
                    preview(localURL)
                } else if isLoading {
                    ProgressView("Preparing preview…")
                } else {
                    ContentUnavailableView(
                        "Preview Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage ?? "This attachment could not be downloaded.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppConstants.Colors.background)
            .navigationTitle(item.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if localURL != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            if isStored {
                                Button(role: .destructive) {
                                    showingRemoveConfirmation = true
                                } label: {
                                    Label("Remove App Download", systemImage: "trash")
                                }
                            } else {
                                Button { keepInApp() } label: {
                                    Label("Keep in App", systemImage: "arrow.down.circle")
                                }
                            }

                            if item.category == .photos {
                                Button { saveToPhotos() } label: {
                                    Label("Save to Photos", systemImage: "photo.badge.arrow.down")
                                }
                            }

                            Button { showingShareSheet = true } label: {
                                Label("Share or Save to Files", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: isStored ? "checkmark.circle.fill" : "ellipsis.circle")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isStored {
                    Label("Downloaded to this app", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.secondaryText)
                        .padding(.vertical, 8)
                }
            }
            .task { await preparePreview() }
            .onDisappear { cleanupTemporaryPreview() }
            .sheet(isPresented: $showingShareSheet) {
                if let localURL { AttachmentActivityView(items: [localURL]) }
            }
            .confirmationDialog(
                "Remove this downloaded copy from the app?",
                isPresented: $showingRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove Download", role: .destructive) { removeFromApp() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func preview(_ url: URL) -> some View {
        if item.category == .photos, item.isVideo {
            VideoPlayer(player: player)
                .onAppear {
                    let previewPlayer = AVPlayer(url: url)
                    player = previewPlayer
                    previewPlayer.play()
                }
                .onDisappear { player?.pause() }
        } else if item.category == .photos {
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                ContentUnavailableView("Photo Unavailable", systemImage: "photo.badge.exclamationmark")
            }
        } else if item.category == .audio {
            VStack(spacing: 22) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 88))
                    .foregroundColor(AppConstants.Colors.primaryAction)
                Text(item.fileName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button {
                    toggleAudio(url)
                } label: {
                    Label(isPlayingAudio ? "Pause" : "Play", systemImage: isPlayingAudio ? "pause.fill" : "play.fill")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        } else {
            ChatQuickLookPreview(url: url)
        }
    }

    @MainActor
    private func preparePreview() async {
        isLoading = true
        errorMessage = nil
        do {
            if let storedURL = try ChatAttachmentLocalStore.storedURL(
                roomId: roomId,
                messageId: item.messageId
            ) {
                localURL = storedURL
                isStored = true
            } else {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("FireflyAttachmentPreview-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let (downloadedURL, _) = try await URLSession.shared.download(from: item.remoteURL)
                let destination = directory.appendingPathComponent(item.fileName.safeFilename)
                try FileManager.default.moveItem(at: downloadedURL, to: destination)
                temporaryDirectory = directory
                localURL = destination
            }
        } catch where AppErrorMessage.isCancellation(error) {
            // The preview was dismissed while loading.
        } catch {
            errorMessage = AppErrorMessage.school("Could not prepare attachment", error)
        }
        isLoading = false
    }

    private func toggleAudio(_ url: URL) {
        if let player {
            if isPlayingAudio { player.pause() } else { player.play() }
            isPlayingAudio.toggle()
        } else {
            do {
                try AudioPlaybackSession.activate()
                let audioPlayer = AVPlayer(url: url)
                player = audioPlayer
                audioPlayer.play()
                isPlayingAudio = true
            } catch {
                errorMessage = AppErrorMessage.school("Could not play audio", error)
            }
        }
    }

    private func keepInApp() {
        guard let localURL else { return }
        do {
            let storedURL = try ChatAttachmentLocalStore.store(
                localURL: localURL,
                roomId: roomId,
                messageId: item.messageId,
                fileName: item.fileName
            )
            self.localURL = storedURL
            isStored = true
            cleanupTemporaryPreview()
        } catch {
            errorMessage = AppErrorMessage.school("Could not keep attachment in the app", error)
        }
    }

    private func removeFromApp() {
        do {
            try ChatAttachmentLocalStore.remove(roomId: roomId, messageId: item.messageId)
            isStored = false
            localURL = nil
            Task { await preparePreview() }
        } catch {
            errorMessage = AppErrorMessage.school("Could not remove app download", error)
        }
    }

    private func saveToPhotos() {
        Task {
            do {
                try await MediaLibrarySaver.save(
                    remoteURL: item.remoteURL,
                    contentType: item.contentType,
                    fileName: item.fileName
                )
            } catch {
                errorMessage = AppErrorMessage.school("Could not save media to Photos", error)
            }
        }
    }

    private func cleanupTemporaryPreview() {
        player?.pause()
        player = nil
        isPlayingAudio = false
        guard let temporaryDirectory else { return }
        try? FileManager.default.removeItem(at: temporaryDirectory)
        self.temporaryDirectory = nil
    }
}

private struct ChatQuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

enum ChatAttachmentLocalStore {
    static func storedURL(roomId: UUID, messageId: UUID) throws -> URL? {
        let directory = try messageDirectory(roomId: roomId, messageId: messageId, create: false)
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).first
    }

    static func store(localURL: URL, roomId: UUID, messageId: UUID, fileName: String) throws -> URL {
        let directory = try messageDirectory(roomId: roomId, messageId: messageId, create: true)
        let destination = directory.appendingPathComponent(fileName.safeFilename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: localURL, to: destination)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDestination = destination
        try mutableDestination.setResourceValues(resourceValues)
        return destination
    }

    static func remove(roomId: UUID, messageId: UUID) throws {
        let directory = try messageDirectory(roomId: roomId, messageId: messageId, create: false)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    static func removeAll() throws {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let directory = applicationSupport
            .appendingPathComponent("FireflyFM", isDirectory: true)
            .appendingPathComponent("Chat Downloads", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private static func messageDirectory(roomId: UUID, messageId: UUID, create: Bool) throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        let directory = applicationSupport
            .appendingPathComponent("FireflyFM", isDirectory: true)
            .appendingPathComponent("Chat Downloads", isDirectory: true)
            .appendingPathComponent(roomId.uuidString, isDirectory: true)
            .appendingPathComponent(messageId.uuidString, isDirectory: true)
        if create {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableDirectory = directory
            try mutableDirectory.setResourceValues(resourceValues)
        }
        return directory
    }
}
