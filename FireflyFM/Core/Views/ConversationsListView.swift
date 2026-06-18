//
//  ConversationsListView.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI
import SDWebImageSwiftUI
import Supabase

struct ConversationsListView: View {
    @EnvironmentObject private var deepLinkManager: DeepLinkManager

    @State private var searchText = ""
    @State private var roomItems: [ChatRoomListItem] = []
    @State private var isLoading = true
    @State private var showingCreateChat = false
    @State private var showingJoinRoom = false
    @State private var joinInviteText = ""
    @State private var pendingLeaveItem: ChatRoomListItem?
    @State private var notificationChannels: [RealtimeChannelV2] = []
    @State private var currentUserId: UUID?

    private var filteredRoomItems: [ChatRoomListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return roomItems }
        return roomItems.filter {
            $0.room.name.localizedCaseInsensitiveContains(query) ||
            ($0.room.description?.localizedCaseInsensitiveContains(query) ?? false) ||
            lastMessagePreview(for: $0).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    if isLoading {
                        Spacer()
                        ProgressView().tint(.white)
                        Spacer()
                    } else if filteredRoomItems.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.3))
                            Text(searchText.isEmpty ? "No chats yet" : "No chats found")
                                .foregroundColor(.white.opacity(0.5))
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(filteredRoomItems) { item in
                                NavigationLink {
                                    ChatRoomScreen(room: item.room) {
                                        Task { await loadRooms() }
                                    }
                                } label: {
                                    ChatRoomRow(item: item)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        pendingLeaveItem = item
                                    } label: {
                                        Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                                    }
                                    .tint(.red)

                                    Button {
                                        Task { await toggleNotifications(item) }
                                    } label: {
                                        Label(item.notificationsEnabled ? "Mute" : "Notify", systemImage: item.notificationsEnabled ? "bell.slash.fill" : "bell.fill")
                                    }
                                    .tint(.orange)

                                    Button {
                                        Task { await markRead(item) }
                                    } label: {
                                        Label("Read", systemImage: "checkmark.circle.fill")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .refreshable {
                            await loadRooms()
                        }
                    }
                }

                floatingCreateButton
            }
            .sheet(isPresented: $showingCreateChat) {
                CreateChatRoomView {
                    Task { await loadRooms() }
                }
            }
            .sheet(isPresented: $showingJoinRoom) {
                JoinChatRoomView(initialInvite: joinInviteText) {
                    Task { await loadRooms() }
                }
            }
            .confirmationDialog(
                "Leave \(pendingLeaveItem?.room.name ?? "this room")?",
                isPresented: Binding(
                    get: { pendingLeaveItem != nil },
                    set: { if !$0 { pendingLeaveItem = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Leave Room", role: .destructive) {
                    confirmLeaveRoom()
                }
                Button("Cancel", role: .cancel) {
                    pendingLeaveItem = nil
                }
            } message: {
                Text("You will stop receiving messages from this room unless you join again with an invite.")
            }
        }
        .task {
            await ChatNotificationManager.shared.requestAuthorization()
            await loadRooms()
            openPendingRoomInviteIfNeeded()
        }
        .onChange(of: deepLinkManager.pendingRoomInvite) { _, _ in
            openPendingRoomInviteIfNeeded()
        }
        .onDisappear {
            Task { await unsubscribeNotificationChannels() }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Chat")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                Button {
                    joinInviteText = ""
                    showingJoinRoom = true
                } label: {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }

                Button {
                    showingCreateChat = true
                } label: {
                    Image(systemName: "message.badge.plus")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.6))
                TextField("Search rooms", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.white)
                    .tint(AppConstants.Colors.accessibleYellow)
            }
            .padding(12)
            .background(AppConstants.Colors.card)
            .cornerRadius(8)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var floatingCreateButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    showingCreateChat = true
                } label: {
                    Image(systemName: "message.fill")
                        .font(.title.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(width: 60, height: 60)
                        .background(AppConstants.Colors.accessibleYellow)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }

    @MainActor
    private func loadRooms() async {
        do {
            currentUserId = try? await AppConstants.supabase.auth.session.user.id
            let fetchedItems = try await ChatService.shared.fetchMyRoomListItems()
            roomItems = fetchedItems
            isLoading = false
            await restartNotificationChannels(for: fetchedItems)
        } catch {
            print("DEBUG: Failed to fetch rooms - \(error)")
            isLoading = false
        }
    }

    @MainActor
    private func restartNotificationChannels(for items: [ChatRoomListItem]) async {
        await unsubscribeNotificationChannels()

        for item in items where item.notificationsEnabled {
            let channel = await ChatService.shared.subscribeToMessages(
                in: item.room.id,
                channelName: "room_list_notifications_\(item.room.id.uuidString)",
                onInsert: { message in
                    Task { await handleIncomingNotification(message) }
                },
                onUpdate: { _ in
                    Task { await loadRooms() }
                },
                onDelete: { _ in
                    Task { await loadRooms() }
                }
            )
            notificationChannels.append(channel)
        }
    }

    @MainActor
    private func unsubscribeNotificationChannels() async {
        for channel in notificationChannels {
            await channel.unsubscribe()
        }
        notificationChannels = []
    }

    @MainActor
    private func handleIncomingNotification(_ message: ChatMessageModel) async {
        guard message.senderId != currentUserId else {
            await loadRooms()
            return
        }

        if let item = roomItems.first(where: { $0.room.id == message.roomId }), item.notificationsEnabled {
            ChatNotificationManager.shared.notifyIncomingMessage(roomName: item.room.name, message: message)
        }

        await loadRooms()
    }

    @MainActor
    private func markRead(_ item: ChatRoomListItem) async {
        do {
            try await ChatService.shared.markRoomAsRead(roomId: item.room.id)
            await loadRooms()
        } catch {
            print("DEBUG: Failed to mark room read - \(error)")
        }
    }

    @MainActor
    private func toggleNotifications(_ item: ChatRoomListItem) async {
        do {
            try await ChatService.shared.setNotificationsEnabled(
                roomId: item.room.id,
                enabled: !item.notificationsEnabled
            )
            await loadRooms()
        } catch {
            print("DEBUG: Failed to update notifications - \(error)")
        }
    }

    @MainActor
    private func leaveRoom(_ item: ChatRoomListItem) async {
        do {
            try await ChatService.shared.leaveRoom(roomId: item.room.id)
            await loadRooms()
        } catch {
            print("DEBUG: Failed to leave room - \(error)")
        }
    }

    private func confirmLeaveRoom() {
        guard let item = pendingLeaveItem else { return }
        pendingLeaveItem = nil
        Task { await leaveRoom(item) }
    }

    @MainActor
    private func openPendingRoomInviteIfNeeded() {
        guard let invite = deepLinkManager.consumeRoomInvite() else { return }
        joinInviteText = invite
        showingJoinRoom = true
    }

    private func lastMessagePreview(for item: ChatRoomListItem) -> String {
        guard let message = item.lastMessage else {
            return item.room.description ?? "No messages yet"
        }

        if message.isDeleted {
            return "Message deleted"
        }

        if let text = message.text, !text.isEmpty {
            return text
        }

        if message.mediaUrl != nil {
            return "Photo"
        }

        if let attachmentName = message.attachmentName {
            return attachmentName
        }

        if message.fileUrl != nil {
            return "File attachment"
        }

        return "Message"
    }
}

struct ChatRoomRow: View {
    let item: ChatRoomListItem

    var body: some View {
        HStack(spacing: 14) {
            roomAvatar

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.room.name)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if item.notificationsEnabled == false {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.45))
                    }
                }

                Text(previewText)
                    .font(.subheadline)
                    .foregroundColor(item.unreadCount > 0 ? .white.opacity(0.9) : .white.opacity(0.58))
                    .fontWeight(item.unreadCount > 0 ? .semibold : .regular)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(timeAgo(from: item.lastActivityAt))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))

                if item.unreadCount > 0 {
                    Text(item.unreadCount > 99 ? "99+" : "\(item.unreadCount)")
                        .font(.caption2.bold())
                        .foregroundColor(.black)
                        .frame(minWidth: 22, minHeight: 22)
                        .padding(.horizontal, item.unreadCount > 9 ? 5 : 0)
                        .background(AppConstants.Colors.accessibleYellow)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    @ViewBuilder
    private var roomAvatar: some View {
        if let profileUrl = item.room.profileImageUrl, let url = URL(string: profileUrl) {
            WebImage(url: url)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 52, height: 52)
                .overlay(
                    Text(String(item.room.name.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundColor(.white)
                )
        }
    }

    private var previewText: String {
        guard let message = item.lastMessage else {
            return item.room.description ?? "No messages yet"
        }

        if message.isDeleted {
            return "Message deleted"
        }
        if let text = message.text, !text.isEmpty {
            return text
        }
        if message.mediaUrl != nil {
            return "Photo"
        }
        if let attachmentName = message.attachmentName {
            return attachmentName
        }
        if message.fileUrl != nil {
            return "File attachment"
        }
        return "Message"
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
