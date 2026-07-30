import Foundation
import Observation
import Supabase

struct ChatRoomListClient {
    typealias MessageSubscription = (
        _ roomId: UUID,
        _ channelName: String,
        _ onInsert: @escaping (ChatMessageModel) -> Void,
        _ onChange: @escaping () -> Void
    ) async -> RealtimeChannelV2
    typealias MembershipSubscription = (
        _ userId: UUID,
        _ channelName: String,
        _ onChange: @escaping () -> Void
    ) async throws -> RealtimeChannelV2

    var currentUserId: () async -> UUID?
    var fetch: (UUID?, Bool) async throws -> [ChatRoomListItem]
    var markRead: (UUID) async throws -> Void
    var setNotifications: (UUID, Bool) async throws -> Void
    var leave: (UUID) async throws -> Void
    var subscribeMessages: MessageSubscription
    var subscribeMembership: MembershipSubscription
    var unsubscribe: (RealtimeChannelV2) async -> Void

    static let live = ChatRoomListClient(
        currentUserId: { try? await AppConfiguration.supabase.auth.session.user.id },
        fetch: { schoolId, includeAllSchoolRooms in
            try await ChatService.shared.fetchMyRoomListItems(
                schoolId: schoolId,
                includeAllSchoolRooms: includeAllSchoolRooms
            )
        },
        markRead: { try await ChatService.shared.markRoomAsRead(roomId: $0) },
        setNotifications: { try await ChatService.shared.setNotificationsEnabled(roomId: $0, enabled: $1) },
        leave: { try await SchoolOperationsService.shared.leaveManagedChatRoom(roomId: $0) },
        subscribeMessages: LiveChatRoomListSubscriptions.subscribeMessages,
        subscribeMembership: LiveChatRoomListSubscriptions.subscribeMembership,
        unsubscribe: { await $0.unsubscribe() }
    )
}

private enum LiveChatRoomListSubscriptions {
    static func subscribeMessages(
        roomId: UUID,
        channelName: String,
        onInsert: @escaping (ChatMessageModel) -> Void,
        onChange: @escaping () -> Void
    ) async -> RealtimeChannelV2 {
        await ChatService.shared.subscribeToMessages(
            in: roomId,
            channelName: channelName,
            onInsert: onInsert,
            onUpdate: { _ in onChange() },
            onDelete: { _ in onChange() }
        )
    }

    static func subscribeMembership(
        userId: UUID,
        channelName: String,
        onChange: @escaping () -> Void
    ) async throws -> RealtimeChannelV2 {
        let channel = AppConfiguration.supabase.realtimeV2.channel(channelName)
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

        Task { for await _ in insertions { onChange() } }
        Task { for await _ in updates { onChange() } }
        Task { for await _ in deletions { onChange() } }
        try await channel.subscribeWithError()
        return channel
    }
}

@MainActor
@Observable
final class ChatRoomListModel {
    private let client: ChatRoomListClient
    private var requestId = UUID()
    private var schoolId: UUID?
    private var includesAllSchoolRooms = false
    private var notificationChannels: [RealtimeChannelV2] = []
    private var membershipChannel: RealtimeChannelV2?
    private var currentUserId: UUID?

    var searchText = ""
    private(set) var roomItems: [ChatRoomListItem] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var mutationError: String?

    init() {
        client = .live
    }

    init(client: ChatRoomListClient) {
        self.client = client
    }

    var filteredRoomItems: [ChatRoomListItem] {
        guard let query = searchText.nilIfBlank else { return roomItems }
        return roomItems.filter {
            $0.room.name.localizedCaseInsensitiveContains(query)
                || ($0.room.description?.localizedCaseInsensitiveContains(query) ?? false)
                || ChatMessagePresentation.preview(for: $0).localizedCaseInsensitiveContains(query)
        }
    }

    func start(schoolId: UUID?, includeAllSchoolRooms: Bool, membershipScope: String) async {
        self.schoolId = schoolId
        self.includesAllSchoolRooms = includeAllSchoolRooms
        currentUserId = await client.currentUserId()
        await load()
        await startMembershipChannel(scope: membershipScope)
    }

    func load() async {
        let currentRequestId = UUID()
        requestId = currentRequestId
        mutationError = nil
        phase = roomItems.isEmpty ? .loading : .loaded

        do {
            let items = try await client.fetch(schoolId, includesAllSchoolRooms)
            guard requestId == currentRequestId else { return }
            roomItems = items
            phase = items.isEmpty ? .empty : .loaded
            await restartNotificationChannels(for: items)
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            guard requestId == currentRequestId else { return }
            phase = .failed(AppErrorMessage.school("Could not load chats", error))
        }
    }

    func markRead(_ item: ChatRoomListItem) async {
        await mutate(errorTitle: "Could not mark chat as read") {
            try await client.markRead(item.room.id)
        }
    }

    func toggleNotifications(_ item: ChatRoomListItem) async {
        await mutate(errorTitle: "Could not update chat notifications") {
            try await client.setNotifications(item.room.id, !item.notificationsEnabled)
        }
    }

    func leave(_ item: ChatRoomListItem) async {
        do {
            try await client.leave(item.room.id)
            roomItems.removeAll { $0.room.id == item.room.id }
            await load()
        } catch {
            mutationError = AppErrorMessage.school("Could not leave room", error)
        }
    }

    func stop() async {
        requestId = UUID()
        for channel in notificationChannels { await client.unsubscribe(channel) }
        notificationChannels = []
        if let membershipChannel { await client.unsubscribe(membershipChannel) }
        membershipChannel = nil
    }

    private func mutate(errorTitle: String, operation: () async throws -> Void) async {
        mutationError = nil
        do {
            try await operation()
            await load()
        } catch {
            mutationError = AppErrorMessage.school(errorTitle, error)
        }
    }

    private func restartNotificationChannels(for items: [ChatRoomListItem]) async {
        for channel in notificationChannels { await client.unsubscribe(channel) }
        notificationChannels = []

        for item in items where item.notificationsEnabled {
            let channel = await client.subscribeMessages(
                item.room.id,
                "room_list_notifications_\(item.room.id.uuidString)",
                { [weak self] message in
                    Task { @MainActor in await self?.handleIncoming(message) }
                },
                { [weak self] in
                    Task { @MainActor in await self?.load() }
                }
            )
            notificationChannels.append(channel)
        }
    }

    private func startMembershipChannel(scope: String) async {
        if let membershipChannel { await client.unsubscribe(membershipChannel) }
        membershipChannel = nil
        guard let currentUserId else { return }

        do {
            membershipChannel = try await client.subscribeMembership(
                currentUserId,
                "chat_membership_\(currentUserId.uuidString)_\(scope)",
                { [weak self] in
                    Task { @MainActor in await self?.load() }
                }
            )
        } catch {
            mutationError = AppErrorMessage.school("Live chat membership updates are unavailable", error)
        }
    }

    private func handleIncoming(_ message: ChatMessageModel) async {
        await load()
    }
}

enum ChatMessagePresentation {
    static func preview(for item: ChatRoomListItem) -> String {
        guard let message = item.lastMessage else {
            return item.room.description ?? "No messages yet"
        }
        if message.isDeleted { return "Message deleted" }
        if let text = message.text?.nilIfBlank { return text }
        if message.mediaPath != nil || message.mediaUrl != nil { return "Photo" }
        if let attachmentName = message.attachmentName?.nilIfBlank { return attachmentName }
        if message.filePath != nil || message.fileUrl != nil { return "File attachment" }
        if message.audioPath != nil || message.audioUrl != nil { return "Voice message" }
        return "Message"
    }
}
