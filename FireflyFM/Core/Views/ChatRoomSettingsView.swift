import SwiftUI

struct ChatRoomSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    let room: ChatRoom
    var onRoomUpdated: (ChatRoom) -> Void
    var onRoomClosed: () -> Void

    @State private var roomName: String
    @State private var roomDescription: String
    @State private var members: [ChatParticipant] = []
    @State private var directory: [SchoolDirectoryEntry] = []
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var memberSearch = ""
    @State private var notificationsEnabled = true
    @State private var isArchived: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var showingLeaveConfirmation = false
    @State private var selectedAttachmentCategory: ChatAttachmentCategory?

    init(room: ChatRoom, onRoomUpdated: @escaping (ChatRoom) -> Void, onRoomClosed: @escaping () -> Void) {
        self.room = room
        self.onRoomUpdated = onRoomUpdated
        self.onRoomClosed = onRoomClosed
        _roomName = State(initialValue: room.name)
        _roomDescription = State(initialValue: room.description ?? "")
        _isArchived = State(initialValue: room.archivedAt != nil)
    }

    private var isDirector: Bool { appSession.role == .schoolDirector }
    private var canEditRoom: Bool { isDirector && room.systemManaged == false }
    private var canLeave: Bool {
        room.systemManaged == false && (appSession.role == .parent || appSession.role == .teacher)
    }
    private var filteredDirectory: [SchoolDirectoryEntry] {
        let query = memberSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return directory.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
    }
    private var currentMemberDirectory: [SchoolDirectoryEntry] {
        let memberIds = Set(members.map(\.userId))
        return directory
            .filter { memberIds.contains($0.userId) }
            .sorted { lhs, rhs in
                if lhs.schoolRole == .schoolDirector, rhs.schoolRole != .schoolDirector { return true }
                if lhs.schoolRole != .schoolDirector, rhs.schoolRole == .schoolDirector { return false }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        settingsSection("Room") {
                            HStack {
                                Label(room.name, systemImage: "person.3.fill")
                                Spacer()
                                Text("\(members.count) members").font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
                            }
                            if room.systemManaged {
                                Label("Created automatically by FireflyFM", systemImage: "lock.shield.fill")
                                    .font(.caption)
                                    .foregroundColor(AppConstants.Colors.secondaryText)
                                if room.isReadOnly {
                                    Label("Archived • Read only", systemImage: "archivebox.fill")
                                        .font(.caption.bold())
                                        .foregroundColor(.orange)
                                }
                            }
                            if canEditRoom {
                                labeledTextField("Name", text: $roomName)
                                labeledTextField("Description", text: $roomDescription, axis: .vertical)
                                Toggle("Archived", isOn: $isArchived).tint(AppConstants.Colors.accessibleYellow)
                                Button { saveRoom() } label: {
                                    Label("Save Room Details", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SettingsPrimaryButtonStyle())
                                .disabled(roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                            } else {
                                Text(room.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? room.description! : "No room description has been added.")
                                    .font(.subheadline)
                                    .foregroundColor(AppConstants.Colors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        settingsSection("Members") {
                            if canEditRoom {
                                TextField("Search parents and teachers", text: $memberSearch)
                                    .textFieldStyle(.roundedBorder)
                                ForEach(filteredDirectory) { entry in
                                    Button {
                                        guard entry.id != appSession.profile?.id else { return }
                                        if selectedMemberIds.contains(entry.id) { selectedMemberIds.remove(entry.id) }
                                        else { selectedMemberIds.insert(entry.id) }
                                    } label: {
                                        HStack {
                                            Image(systemName: selectedMemberIds.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                                            VStack(alignment: .leading) {
                                                Text(entry.displayName).foregroundColor(AppConstants.Colors.primaryText)
                                                Text(entry.schoolRole.title).font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
                                            }
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button { saveMembers() } label: {
                                    Label("Update Members", systemImage: "person.2.badge.gearshape.fill").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SettingsPrimaryButtonStyle())
                            } else if currentMemberDirectory.isEmpty {
                                Text("Member details are unavailable right now.")
                                    .font(.subheadline)
                                    .foregroundColor(AppConstants.Colors.secondaryText)
                            } else {
                                ForEach(currentMemberDirectory) { entry in
                                    memberRow(entry)
                                }
                            }
                        }

                        settingsSection("Shared in this Chat") {
                            ForEach(ChatAttachmentCategory.allCases) { category in
                                Button {
                                    selectedAttachmentCategory = category
                                } label: {
                                    HStack {
                                        Label(category.title, systemImage: category.symbol)
                                            .foregroundColor(AppConstants.Colors.primaryText)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.bold())
                                            .foregroundColor(AppConstants.Colors.secondaryText)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        settingsSection("Notifications") {
                            Toggle(isOn: $notificationsEnabled) {
                                Label("Room Notifications", systemImage: notificationsEnabled ? "bell.fill" : "bell.slash.fill")
                            }
                            .tint(AppConstants.Colors.accessibleYellow)
                            .onChange(of: notificationsEnabled) { _, value in updateNotifications(enabled: value) }
                        }

                        if canEditRoom || canLeave {
                            settingsSection(isDirector ? "Lifecycle" : "Room Access") {
                                if canLeave {
                                    Text("Leaving removes this room and its messages from your account. A school director can invite you again later.")
                                        .font(.caption)
                                        .foregroundColor(AppConstants.Colors.secondaryText)
                                    Button(role: .destructive) { showingLeaveConfirmation = true } label: {
                                        Label("Leave Room", systemImage: "rectangle.portrait.and.arrow.right.fill").frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(SettingsDestructiveButtonStyle())
                                }
                                if canEditRoom {
                                    Text("Deleting hides the room immediately and keeps its lifecycle audit record.")
                                        .font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
                                    Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                                        Label("Delete Room", systemImage: "trash.fill").frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(SettingsDestructiveButtonStyle())
                                }
                            }
                        }

                        if let errorMessage { Text(errorMessage).font(.caption).foregroundColor(.red) }
                    }
                    .padding()
                }
            }
            .navigationTitle(isDirector ? "Room Settings" : "Room Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete this room?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Room", role: .destructive) { deleteRoom() }
            }
            .confirmationDialog("Leave \(room.name)?", isPresented: $showingLeaveConfirmation, titleVisibility: .visible) {
                Button("Leave Room", role: .destructive) { leaveRoom() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will immediately lose access to this chat and its message history.")
            }
            .sheet(item: $selectedAttachmentCategory) { category in
                ChatAttachmentGalleryView(room: room, initialCategory: category)
            }
            .task { await loadSettings() }
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.caption.bold()).foregroundColor(AppConstants.Colors.accessibleYellow)
            content()
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card).cornerRadius(8)
    }

    private func labeledTextField(_ title: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
            TextField(title, text: text, axis: axis).lineLimit(axis == .vertical ? 3...6 : 1...1)
                .padding(10).background(AppConstants.Colors.background.opacity(0.5)).cornerRadius(8)
        }
    }

    private func memberRow(_ entry: SchoolDirectoryEntry) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: entry.avatarUrl.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle()
                    .fill(AppConstants.Colors.raised)
                    .overlay {
                        Text(entry.displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                    }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                Text(entry.schoolRole.title)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
            }
            Spacer()
        }
    }

    @MainActor
    private func loadSettings() async {
        do {
            members = try await ChatService.shared.fetchParticipants(roomId: room.id)
            if let schoolId = room.schoolId {
                directory = try await SchoolOperationsService.shared.fetchDirectory(schoolId: schoolId)
            }
            selectedMemberIds = Set(members.map(\.userId))
            if let userId = appSession.profile?.id,
               let participant = members.first(where: { $0.userId == userId }) {
                notificationsEnabled = participant.notificationsEnabled
            }
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = AppErrorMessage.school("Could not load settings", error)
        }
    }

    private func saveRoom() {
        isSaving = true
        Task {
            do {
                let updated = try await SchoolOperationsService.shared.updateManagedChatRoom(
                    roomId: room.id,
                    name: roomName.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: roomDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : roomDescription,
                    imageURL: room.profileImageUrl,
                    archived: isArchived
                )
                await MainActor.run { isSaving = false; onRoomUpdated(updated) }
            } catch {
                await MainActor.run { isSaving = false; errorMessage = AppErrorMessage.school("Could not save room", error) }
            }
        }
    }

    private func saveMembers() {
        Task {
            do {
                try await SchoolOperationsService.shared.setManagedChatParticipants(roomId: room.id, participantIds: Array(selectedMemberIds))
                await loadSettings()
            } catch {
                await MainActor.run { errorMessage = AppErrorMessage.school("Could not update members", error) }
            }
        }
    }

    private func updateNotifications(enabled: Bool) {
        Task {
            do { try await ChatService.shared.setNotificationsEnabled(roomId: room.id, enabled: enabled) }
            catch {
                await MainActor.run { notificationsEnabled.toggle(); errorMessage = AppErrorMessage.school("Could not update notifications", error) }
            }
        }
    }

    private func deleteRoom() {
        Task {
            do {
                try await SchoolOperationsService.shared.deleteManagedChatRoom(roomId: room.id)
                await MainActor.run { onRoomClosed() }
            } catch {
                await MainActor.run { errorMessage = AppErrorMessage.school("Could not delete room", error) }
            }
        }
    }

    private func leaveRoom() {
        Task {
            do {
                try await SchoolOperationsService.shared.leaveManagedChatRoom(roomId: room.id)
                await MainActor.run { onRoomClosed() }
            } catch {
                await MainActor.run { errorMessage = AppErrorMessage.school("Could not leave room", error) }
            }
        }
    }
}

private struct ChatAttachmentGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let room: ChatRoom
    let initialCategory: ChatAttachmentCategory

    @State private var category: ChatAttachmentCategory
    @State private var messages: [ChatMessageModel] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
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
        isLoading = true
        errorMessage = nil
        do {
            messages = try await ChatService.shared.fetchAttachmentMessages(for: room.id, category: category)
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = AppErrorMessage.school("Could not load attachments", error)
        }
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

    private func prepareExport(_ selectedMessages: [ChatMessageModel]) {
        guard !selectedMessages.isEmpty else { return }
        isPreparingExport = true
        errorMessage = nil

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
                    let destination = directory.appendingPathComponent("\(index + 1)-\(safeFilename(suggestedName))")
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
                errorMessage = AppErrorMessage.school("Could not prepare attachments", error)
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

    private func safeFilename(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = value.components(separatedBy: invalidCharacters).joined(separator: "-")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Attachment" : cleaned
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

private struct SettingsPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.bold()).foregroundColor(AppConstants.Colors.primaryActionText)
            .padding(.vertical, 12).background(AppConstants.Colors.primaryAction.opacity(configuration.isPressed ? 0.75 : 1)).cornerRadius(8)
    }
}

private struct SettingsDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.bold()).foregroundColor(AppConstants.Colors.primaryText)
            .padding(.vertical, 12).background(Color.red.opacity(configuration.isPressed ? 0.55 : 0.35)).cornerRadius(8)
    }
}
