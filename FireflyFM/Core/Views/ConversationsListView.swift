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
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var searchText = ""
    @State private var roomItems: [ChatRoomListItem] = []
    @State private var isLoading = true
    @State private var showingCreateChat = false
    @State private var notificationChannels: [RealtimeChannelV2] = []
    @State private var membershipChannel: RealtimeChannelV2?
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
                        ProgressView().tint(AppConstants.Colors.primaryAction)
                        Spacer()
                    } else if filteredRoomItems.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 40))
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.3))
                            Text(searchText.isEmpty ? "No chats yet" : "No chats found")
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.5))
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

                if appSession.role == .schoolDirector {
                    floatingCreateButton
                }
            }
            .sheet(isPresented: $showingCreateChat) {
                CreateChatRoomView {
                    Task { await loadRooms() }
                }
            }
        }
        .task(id: appSession.activeMembershipId) {
            await ChatNotificationManager.shared.requestAuthorization()
            await loadRooms()
            await startMembershipChannel()
        }
        .onDisappear {
            Task {
                await unsubscribeNotificationChannels()
                await stopMembershipChannel()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Chat")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(AppConstants.Colors.primaryText)

                Spacer()

                if appSession.role == .schoolDirector {
                    Button {
                        showingCreateChat = true
                    } label: {
                        Image(systemName: "message.badge.plus")
                            .font(.system(size: 24))
                            .foregroundColor(AppConstants.Colors.primaryText)
                    }
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.6))
                TextField("Search rooms", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(AppConstants.Colors.primaryText)
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
                        .foregroundColor(AppConstants.Colors.brandNavy)
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
            let fetchedItems = try await ChatService.shared.fetchMyRoomListItems(
                schoolId: appSession.activeSchool?.id,
                includeAllSchoolRooms: appSession.role?.canOverseeSchoolChats == true
            )
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
    private func startMembershipChannel() async {
        await stopMembershipChannel()
        let resolvedUserId: UUID?
        if let currentUserId {
            resolvedUserId = currentUserId
        } else {
            resolvedUserId = try? await AppConstants.supabase.auth.session.user.id
        }
        guard let userId = resolvedUserId else { return }
        let channel = AppConstants.supabase.realtimeV2.channel("chat_membership_\(userId.uuidString)")
        let insertions = await channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "chat_participants",
            filter: .eq("user_id", value: userId.uuidString)
        )
        let updates = await channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "chat_participants",
            filter: .eq("user_id", value: userId.uuidString)
        )
        let deletions = await channel.postgresChange(
            DeleteAction.self,
            schema: "public",
            table: "chat_participants",
            filter: .eq("user_id", value: userId.uuidString)
        )
        membershipChannel = channel
        Task { for await _ in insertions { await loadRooms() } }
        Task { for await _ in updates { await loadRooms() } }
        Task { for await _ in deletions { await loadRooms() } }
        do {
            try await channel.subscribeWithError()
        } catch {
            print("DEBUG: Failed to subscribe to chat membership changes - \(error)")
        }
    }

    @MainActor
    private func stopMembershipChannel() async {
        await membershipChannel?.unsubscribe()
        membershipChannel = nil
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

        if message.mediaPath != nil || message.mediaUrl != nil {
            return "Photo"
        }

        if let attachmentName = message.attachmentName {
            return attachmentName
        }

        if message.filePath != nil || message.fileUrl != nil {
            return "File attachment"
        }

        if message.audioPath != nil || message.audioUrl != nil {
            return "Voice message"
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
                        .foregroundColor(AppConstants.Colors.primaryText)
                        .lineLimit(1)

                    if item.notificationsEnabled == false {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.45))
                    }
                }

                Text(previewText)
                    .font(.subheadline)
                    .foregroundColor(
                        item.unreadCount > 0
                            ? AppConstants.Colors.primaryText.opacity(0.9)
                            : AppConstants.Colors.secondaryText
                    )
                    .fontWeight(item.unreadCount > 0 ? .semibold : .regular)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(timeAgo(from: item.lastActivityAt))
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.5))

                if item.unreadCount > 0 {
                    Text(item.unreadCount > 99 ? "99+" : "\(item.unreadCount)")
                        .font(.caption2.bold())
                        .foregroundColor(AppConstants.Colors.brandNavy)
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
                        .foregroundColor(AppConstants.Colors.primaryText)
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
        if message.mediaPath != nil || message.mediaUrl != nil {
            return "Photo"
        }
        if let attachmentName = message.attachmentName {
            return attachmentName
        }
        if message.filePath != nil || message.fileUrl != nil {
            return "File attachment"
        }
        if message.audioPath != nil || message.audioUrl != nil {
            return "Voice message"
        }
        return "Message"
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
