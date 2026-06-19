//
//  ChatRoomSettingsView.swift
//  FireflyFM
//

import SwiftUI
import Supabase

struct ChatRoomSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    let room: ChatRoom
    var onRoomUpdated: (ChatRoom) -> Void
    var onRoomClosed: () -> Void

    @State private var roomName: String
    @State private var roomDescription: String
    @State private var members: [ChatParticipant] = []
    @State private var currentUserId: UUID?
    @State private var notificationsEnabled = true
    @State private var newMemberId = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var showingLeaveConfirmation = false

    init(
        room: ChatRoom,
        onRoomUpdated: @escaping (ChatRoom) -> Void,
        onRoomClosed: @escaping () -> Void
    ) {
        self.room = room
        self.onRoomUpdated = onRoomUpdated
        self.onRoomClosed = onRoomClosed
        _roomName = State(initialValue: room.name)
        _roomDescription = State(initialValue: room.description ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        settingsSection("Room") {
                            labeledTextField("Name", text: $roomName)
                            labeledTextField("Description", text: $roomDescription, axis: .vertical)

                            Button {
                                saveRoom()
                            } label: {
                                Label("Save Room Details", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SettingsPrimaryButtonStyle())
                            .disabled(roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                        }

                        settingsSection("Members") {
                            if members.isEmpty {
                                Text("No members loaded")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.55))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(members) { member in
                                    HStack {
                                        Image(systemName: member.role == "owner" ? "crown.fill" : "person.fill")
                                            .foregroundColor(AppConstants.Colors.accessibleYellow)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(member.userId.uuidString)
                                                .font(.caption)
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Text(member.role?.capitalized ?? "Member")
                                                .font(.caption2)
                                                .foregroundColor(.white.opacity(0.55))
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                            }

                            HStack(spacing: 10) {
                                TextField("Member user UUID", text: $newMemberId)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(12)
                                    .background(AppConstants.Colors.background.opacity(0.5))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                                    .tint(AppConstants.Colors.accessibleYellow)

                                Button {
                                    addMember()
                                } label: {
                                    Image(systemName: "person.badge.plus")
                                        .frame(width: 42, height: 42)
                                }
                                .buttonStyle(SettingsIconButtonStyle())
                                .disabled(UUID(uuidString: newMemberId.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                            }
                        }

                        settingsSection("Invite") {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Room Code")
                                        .font(.caption.bold())
                                        .foregroundColor(AppConstants.Colors.accessibleYellow)
                                    Text(room.inviteHash ?? room.id.uuidString)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                ShareLink(item: shareText) {
                                    Image(systemName: "square.and.arrow.up")
                                        .frame(width: 42, height: 42)
                                }
                                .buttonStyle(SettingsIconButtonStyle())

                                Button {
                                    UIPasteboard.general.string = room.inviteHash ?? room.id.uuidString
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .frame(width: 42, height: 42)
                                }
                                .buttonStyle(SettingsIconButtonStyle())
                            }
                        }

                        settingsSection("Notifications") {
                            Toggle(isOn: $notificationsEnabled) {
                                Label("Room Notifications", systemImage: notificationsEnabled ? "bell.fill" : "bell.slash.fill")
                                    .foregroundColor(.white)
                            }
                            .tint(AppConstants.Colors.accessibleYellow)
                            .onChange(of: notificationsEnabled) { _, newValue in
                                updateNotifications(enabled: newValue)
                            }
                        }

                        settingsSection("Actions") {
                            Button(role: .destructive) {
                                showingLeaveConfirmation = true
                            } label: {
                                Label("Leave Room", systemImage: "rectangle.portrait.and.arrow.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SettingsDestructiveButtonStyle())

                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete Room", systemImage: "trash.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SettingsDestructiveButtonStyle())
                            .disabled(!canDeleteRoom)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Room Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppConstants.Colors.accessibleYellow)
                }
            }
            .confirmationDialog("Leave this room?", isPresented: $showingLeaveConfirmation, titleVisibility: .visible) {
                Button("Leave Room", role: .destructive) {
                    leaveRoom()
                }
            }
            .confirmationDialog("Delete this room?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Room", role: .destructive) {
                    deleteRoom()
                }
            }
            .task {
                await loadSettings()
            }
        }
    }

    private var shareText: String {
        "Join \(room.name) with room code \(room.inviteHash ?? room.id.uuidString)"
    }

    private var currentParticipant: ChatParticipant? {
        members.first { $0.userId == currentUserId }
    }

    private var canDeleteRoom: Bool {
        appSession.role?.canManageSchool == true
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private func labeledTextField(_ title: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.65))
            TextField(title, text: text, axis: axis)
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
                .padding(12)
                .background(AppConstants.Colors.background.opacity(0.5))
                .cornerRadius(8)
                .foregroundColor(.white)
                .tint(AppConstants.Colors.accessibleYellow)
        }
    }

    @MainActor
    private func loadSettings() async {
        do {
            currentUserId = try await AppConstants.supabase.auth.session.user.id
            members = try await ChatService.shared.fetchParticipants(roomId: room.id)
            if let currentParticipant {
                notificationsEnabled = currentParticipant.notificationsEnabled
            }
        } catch {
            errorMessage = AppErrorMessage.school("Could not load settings", error)
        }
    }

    private func saveRoom() {
        let trimmedName = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let updatedRoom = try await ChatService.shared.updateRoom(
                    id: room.id,
                    name: trimmedName,
                    description: roomDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : roomDescription
                )
                await MainActor.run {
                    isSaving = false
                    onRoomUpdated(updatedRoom)
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not save room", error)
                }
            }
        }
    }

    private func addMember() {
        guard let userId = UUID(uuidString: newMemberId.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        errorMessage = nil

        Task {
            do {
                try await ChatService.shared.addMember(roomId: room.id, userId: userId)
                let updatedMembers = try await ChatService.shared.fetchParticipants(roomId: room.id)
                await MainActor.run {
                    newMemberId = ""
                    members = updatedMembers
                }
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not add member", error)
                }
            }
        }
    }

    private func updateNotifications(enabled: Bool) {
        Task {
            do {
                try await ChatService.shared.setNotificationsEnabled(roomId: room.id, enabled: enabled)
            } catch {
                await MainActor.run {
                    notificationsEnabled.toggle()
                    errorMessage = AppErrorMessage.school("Could not update notifications", error)
                }
            }
        }
    }

    private func leaveRoom() {
        Task {
            do {
                try await ChatService.shared.leaveRoom(roomId: room.id)
                await MainActor.run { onRoomClosed() }
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not leave room", error)
                }
            }
        }
    }

    private func deleteRoom() {
        Task {
            do {
                try await ChatService.shared.deleteRoom(id: room.id)
                await MainActor.run { onRoomClosed() }
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not delete room", error)
                }
            }
        }
    }
}

private struct SettingsPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(.black)
            .padding(.vertical, 12)
            .background(AppConstants.Colors.accessibleYellow.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(8)
    }
}

private struct SettingsIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(AppConstants.Colors.accessibleYellow)
            .background(AppConstants.Colors.background.opacity(configuration.isPressed ? 0.7 : 0.5))
            .cornerRadius(8)
    }
}

private struct SettingsDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .background(Color.red.opacity(configuration.isPressed ? 0.55 : 0.35))
            .cornerRadius(8)
    }
}
