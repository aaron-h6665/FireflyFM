import SwiftUI

struct ChatRoomSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    let room: ChatRoom
    var onRoomUpdated: (ChatRoom) -> Void
    var onRoomClosed: () -> Void

    @State private var model = ChatRoomSettingsModel()
    @State private var roomName: String
    @State private var roomDescription: String
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var memberSearch = ""
    @State private var notificationsEnabled = true
    @State private var isArchived: Bool
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

    private var accessPolicy: ChatAccessPolicy {
        ChatAccessPolicy(context: appSession.accessContext(selectedSchoolId: room.schoolId))
    }
    private var canOverseeRooms: Bool { accessPolicy.canOverseeSchoolRooms }
    private var canEditRoom: Bool { accessPolicy.canOverseeSchoolRooms && room.systemManaged == false }
    private var canLeave: Bool { accessPolicy.canLeave(room: room) }
    private var members: [ChatParticipant] { model.members }
    private var directory: [SchoolDirectoryEntry] { model.directory }
    private var isSaving: Bool { model.isSaving }
    private var errorMessage: String? { model.errorMessage }
    private var filteredDirectory: [SchoolDirectoryEntry] {
        let query = memberSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return directory.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
    }
    private var currentMemberDirectory: [SchoolDirectoryEntry] {
        model.currentMemberDirectory
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
                            settingsSection(canOverseeRooms ? "Lifecycle" : "Room Access") {
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
            .navigationTitle(canOverseeRooms ? "Room Settings" : "Room Details")
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
                        Text(InitialsFormatter.initials(for: entry.displayName, fallback: "?"))
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
        await model.load(room: room)
        selectedMemberIds = Set(model.members.map(\.userId))
        if model.errorMessage == nil {
            if let userId = appSession.profile?.id,
               let participant = model.members.first(where: { $0.userId == userId }) {
                notificationsEnabled = participant.notificationsEnabled
            }
        }
    }

    private func saveRoom() {
        Task {
            if let updated = await model.saveRoom(ChatRoomUpdateDraft(
                    roomId: room.id,
                    name: roomName.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: roomDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : roomDescription,
                    imageURL: room.profileImageUrl,
                    archived: isArchived
                )) {
                onRoomUpdated(updated)
            }
        }
    }

    private func saveMembers() {
        Task {
            _ = await model.saveMembers(room: room, memberIds: Array(selectedMemberIds))
        }
    }

    private func updateNotifications(enabled: Bool) {
        Task {
            if await model.updateNotifications(roomId: room.id, enabled: enabled) == false {
                notificationsEnabled.toggle()
            }
        }
    }

    private func deleteRoom() {
        Task {
            if await model.delete(roomId: room.id) { onRoomClosed() }
        }
    }

    private func leaveRoom() {
        Task {
            if await model.leave(roomId: room.id) { onRoomClosed() }
        }
    }
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
