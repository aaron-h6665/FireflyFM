//
//  ChatService.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import Foundation
import Supabase
import UniformTypeIdentifiers

class ChatService {
    static let shared = ChatService()
    private let client = AppConstants.supabase

    private init() {}

    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: - Rooms

    func fetchMyRooms() async throws -> [ChatRoom] {
        try await fetchMyRoomListItems().map(\.room)
    }

    func fetchMyRoomListItems(schoolId: UUID? = nil, includeAllSchoolRooms: Bool = false) async throws -> [ChatRoomListItem] {
        let user = try await client.auth.session.user

        let participants: [ChatParticipant] = try await client.from("chat_participants")
            .select()
            .eq("user_id", value: user.id)
            .execute()
            .value

        let rooms: [ChatRoom]
        if includeAllSchoolRooms, let schoolId {
            rooms = try await client.from("chat_rooms")
                .select()
                .eq("school_id", value: schoolId)
                .execute()
                .value
        } else {
            let participantRoomIds = participants.map(\.roomId)
            if participantRoomIds.isEmpty { return [] }

            var roomQuery = client.from("chat_rooms")
                .select()
                .in("id", values: participantRoomIds)
            if let schoolId {
                roomQuery = roomQuery.eq("school_id", value: schoolId)
            }
            rooms = try await roomQuery
                .execute()
                .value
        }

        let roomIds = rooms.map(\.id)
        if roomIds.isEmpty { return [] }
        let messages: [ChatMessageModel] = try await client.from("messages")
            .select()
            .in("room_id", values: roomIds)
            .order("created_at", ascending: false)
            .execute()
            .value

        let participantsByRoom = Dictionary(uniqueKeysWithValues: participants.map { ($0.roomId, $0) })
        var latestMessageByRoom: [UUID: ChatMessageModel] = [:]
        var unreadCountsByRoom: [UUID: Int] = [:]

        for message in messages {
            if latestMessageByRoom[message.roomId] == nil {
                latestMessageByRoom[message.roomId] = message
            }

            guard
                let participant = participantsByRoom[message.roomId],
                message.senderId != user.id,
                !message.isDeleted
            else { continue }

            let readBoundary = participant.lastReadAt ?? participant.joinedAt
            if message.createdAt > readBoundary {
                unreadCountsByRoom[message.roomId, default: 0] += 1
            }
        }

        return rooms.compactMap { room in
            let participant = participantsByRoom[room.id] ?? ChatParticipant(
                roomId: room.id,
                userId: user.id,
                joinedAt: room.createdAt,
                lastReadAt: room.createdAt,
                notificationsEnabled: true,
                role: "school_director"
            )
            return ChatRoomListItem(
                room: room,
                participant: participant,
                lastMessage: latestMessageByRoom[room.id],
                unreadCount: unreadCountsByRoom[room.id, default: 0]
            )
        }
        .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    func createRoom(name: String, description: String? = nil, profileImageUrl: String? = nil, schoolId: UUID? = nil, roomType: String = "public") async throws -> ChatRoom {
        let user = try await client.auth.session.user

        let newRoom = ChatRoom(
            name: name,
            description: description,
            profileImageUrl: profileImageUrl,
            schoolId: schoolId,
            roomType: roomType,
            createdBy: user.id
        )

        try await client.from("chat_rooms")
            .insert(newRoom)
            .execute()

        let participant = ChatParticipant(
            roomId: newRoom.id,
            userId: user.id,
            joinedAt: Date(),
            lastReadAt: Date(),
            notificationsEnabled: true,
            role: "owner"
        )
        do {
            try await client.from("chat_participants")
                .insert(participant)
                .execute()
        } catch {
            try? await client.from("chat_rooms")
                .delete()
                .eq("id", value: newRoom.id)
                .execute()
            throw error
        }

        return newRoom
    }

    func joinRoom(invite: String) async throws -> ChatRoom {
        let trimmedInvite = invite.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInvite.isEmpty else {
            throw ChatServiceError.invalidInvite
        }

        let rooms: [ChatRoom] = try await client.rpc(
            "join_chat_room",
            params: JoinRoomParams(inviteText: trimmedInvite)
        )
        .execute()
        .value

        guard let room = rooms.first else {
            throw ChatServiceError.notFound
        }
        return room
    }

    func updateRoom(id: UUID, name: String, description: String?) async throws -> ChatRoom {
        let update = RoomUpdate(
            name: name,
            description: description,
            updatedAt: dateFormatter.string(from: Date())
        )

        let rooms: [ChatRoom] = try await client.from("chat_rooms")
            .update(update)
            .eq("id", value: id)
            .select()
            .execute()
            .value

        guard let room = rooms.first else {
            throw ChatServiceError.notFound
        }
        return room
    }

    func deleteRoom(id: UUID) async throws {
        try await client.from("chat_rooms")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func fetchParticipants(roomId: UUID) async throws -> [ChatParticipant] {
        try await client.from("chat_participants")
            .select()
            .eq("room_id", value: roomId)
            .order("joined_at", ascending: true)
            .execute()
            .value
    }

    func addMember(roomId: UUID, userId: UUID) async throws {
        let participant = ChatParticipant(
            roomId: roomId,
            userId: userId,
            joinedAt: Date(),
            lastReadAt: Date(),
            notificationsEnabled: true,
            role: "member"
        )

        try await client.from("chat_participants")
            .upsert(participant)
            .execute()
    }

    func leaveRoom(roomId: UUID) async throws {
        let user = try await client.auth.session.user

        try await client.from("chat_participants")
            .delete()
            .eq("room_id", value: roomId)
            .eq("user_id", value: user.id)
            .execute()
    }

    func setNotificationsEnabled(roomId: UUID, enabled: Bool) async throws {
        let user = try await client.auth.session.user
        let update = ParticipantSettingsUpdate(notificationsEnabled: enabled)

        try await client.from("chat_participants")
            .update(update)
            .eq("room_id", value: roomId)
            .eq("user_id", value: user.id)
            .execute()
    }

    func markRoomAsRead(roomId: UUID) async throws {
        let user = try await client.auth.session.user
        let update = ParticipantReadUpdate(lastReadAt: dateFormatter.string(from: Date()))

        try await client.from("chat_participants")
            .update(update)
            .eq("room_id", value: roomId)
            .eq("user_id", value: user.id)
            .execute()
    }

    // MARK: - Storage

    func uploadImage(data: Data, path: String) async throws -> String {
        try await uploadData(data, path: path, contentType: "image/jpeg")
    }

    func uploadData(_ data: Data, path: String, contentType: String? = nil) async throws -> String {
        try await client.storage
            .from("chat_attachments")
            .upload(path, data: data, options: FileOptions(contentType: contentType))

        return try await client.storage
            .from("chat_attachments")
            .createSignedURL(path: path, expiresIn: 60 * 60 * 24 * 365)
            .absoluteString
    }

    func uploadFile(fileURL: URL, roomId: UUID) async throws -> ChatAttachmentUploadResult {
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: fileURL)
        let name = fileURL.lastPathComponent.isEmpty ? "Attachment" : fileURL.lastPathComponent
        let contentType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
        let path = "rooms/\(roomId.uuidString)/files/\(UUID().uuidString)-\(name)"
        let url = try await uploadData(data, path: path, contentType: contentType)

        return ChatAttachmentUploadResult(
            url: url,
            name: name,
            type: contentType ?? "application/octet-stream",
            size: data.count
        )
    }

    func uploadImageAttachment(data: Data, roomId: UUID) async throws -> ChatAttachmentUploadResult {
        let path = "rooms/\(roomId.uuidString)/images/\(UUID().uuidString).jpg"
        let url = try await uploadData(data, path: path, contentType: "image/jpeg")

        return ChatAttachmentUploadResult(
            url: url,
            name: "Photo.jpg",
            type: "image/jpeg",
            size: data.count
        )
    }

    func uploadAudioAttachment(data: Data, roomId: UUID) async throws -> ChatAttachmentUploadResult {
        let path = "rooms/\(roomId.uuidString)/audio/\(UUID().uuidString).m4a"
        let url = try await uploadData(data, path: path, contentType: "audio/mp4")

        return ChatAttachmentUploadResult(
            url: url,
            name: "Voice message.m4a",
            type: "audio/mp4",
            size: data.count
        )
    }

    // MARK: - Messages

    func fetchMessages(for roomId: UUID) async throws -> [ChatMessageModel] {
        try await client.from("messages")
            .select()
            .eq("room_id", value: roomId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func searchMessages(in roomId: UUID, query: String) async throws -> [ChatMessageModel] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let pattern = "%\(trimmedQuery)%"

        let textMatches: [ChatMessageModel] = try await client.from("messages")
            .select()
            .eq("room_id", value: roomId)
            .eq("is_deleted", value: false)
            .ilike("text", pattern: pattern)
            .order("created_at", ascending: false)
            .limit(50)
            .execute()
            .value

        let attachmentMatches: [ChatMessageModel] = try await client.from("messages")
            .select()
            .eq("room_id", value: roomId)
            .eq("is_deleted", value: false)
            .ilike("attachment_name", pattern: pattern)
            .order("created_at", ascending: false)
            .limit(50)
            .execute()
            .value

        let merged = (textMatches + attachmentMatches).reduce(into: [UUID: ChatMessageModel]()) { partial, message in
            partial[message.id] = message
        }

        return merged.values.sorted { $0.createdAt > $1.createdAt }
    }

    func sendMessage(
        roomId: UUID,
        text: String?,
        mediaUrl: String? = nil,
        fileUrl: String? = nil,
        audioUrl: String? = nil,
        attachmentType: String? = nil,
        attachmentName: String? = nil,
        attachmentSize: Int? = nil,
        replyToMessageId: UUID? = nil
    ) async throws {
        let user = try await client.auth.session.user

        let message = ChatMessageModel(
            roomId: roomId,
            senderId: user.id,
            text: text,
            mediaUrl: mediaUrl,
            fileUrl: fileUrl,
            audioUrl: audioUrl,
            attachmentType: attachmentType,
            attachmentName: attachmentName,
            attachmentSize: attachmentSize,
            replyToMessageId: replyToMessageId
        )

        try await client.from("messages")
            .insert(message)
            .execute()
    }

    func updateMessage(id: UUID, newText: String) async throws {
        let update = MessageTextUpdate(
            text: newText,
            updatedAt: dateFormatter.string(from: Date())
        )

        try await client.from("messages")
            .update(update)
            .eq("id", value: id)
            .execute()
    }

    func deleteMessage(id: UUID) async throws {
        let update = MessageDeleteUpdate(
            text: nil,
            mediaUrl: nil,
            fileUrl: nil,
            audioUrl: nil,
            attachmentType: nil,
            attachmentName: nil,
            attachmentSize: nil,
            updatedAt: dateFormatter.string(from: Date()),
            deletedAt: dateFormatter.string(from: Date()),
            isDeleted: true
        )

        try await client.from("messages")
            .update(update)
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Realtime Subscriptions

    struct DeletedMessageModel: Codable {
        let id: UUID
    }

    func subscribeToMessages(
        in roomId: UUID,
        channelName: String? = nil,
        onInsert: @escaping (ChatMessageModel) -> Void,
        onUpdate: @escaping (ChatMessageModel) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) async -> RealtimeChannelV2 {
        let resolvedChannelName = channelName ?? "messages_room_\(roomId.uuidString)"
        let channel = await client.realtimeV2.channel(resolvedChannelName)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateStr) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateStr) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateStr)")
        }

        let insertions = await channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages",
            filter: .eq("room_id", value: roomId.uuidString)
        )
        let updates = await channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "messages",
            filter: .eq("room_id", value: roomId.uuidString)
        )
        let deletions = await channel.postgresChange(
            DeleteAction.self,
            schema: "public",
            table: "messages",
            filter: .eq("room_id", value: roomId.uuidString)
        )

        Task {
            for await insertion in insertions {
                do {
                    let newMessage = try insertion.decodeRecord(as: ChatMessageModel.self, decoder: decoder)
                    onInsert(newMessage)
                } catch {
                    print("DEBUG: Failed to decode realtime insert message: \(error)")
                }
            }
        }

        Task {
            for await update in updates {
                do {
                    let updatedMessage = try update.decodeRecord(as: ChatMessageModel.self, decoder: decoder)
                    onUpdate(updatedMessage)
                } catch {
                    print("DEBUG: Failed to decode realtime update message: \(error)")
                }
            }
        }

        Task {
            for await deletion in deletions {
                do {
                    let oldRecord = try deletion.decodeOldRecord(as: DeletedMessageModel.self, decoder: decoder)
                    onDelete(oldRecord.id)
                } catch {
                    print("DEBUG: Failed to decode realtime delete message: \(error)")
                }
            }
        }

        Task {
            do {
                try await channel.subscribeWithError()
            } catch {
                print("DEBUG: Failed to subscribe to channel: \(error)")
            }
        }
        return channel
    }
}

enum ChatServiceError: Error {
    case notFound
    case invalidInvite
}

private struct JoinRoomParams: Encodable {
    let inviteText: String

    enum CodingKeys: String, CodingKey {
        case inviteText = "invite_text"
    }
}

private struct RoomUpdate: Encodable {
    let name: String
    let description: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case name, description
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if let description {
            try container.encode(description, forKey: .description)
        } else {
            try container.encodeNil(forKey: .description)
        }
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private struct ParticipantSettingsUpdate: Encodable {
    let notificationsEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case notificationsEnabled = "notifications_enabled"
    }
}

private struct ParticipantReadUpdate: Encodable {
    let lastReadAt: String

    enum CodingKeys: String, CodingKey {
        case lastReadAt = "last_read_at"
    }
}

private struct MessageTextUpdate: Encodable {
    let text: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case text
        case updatedAt = "updated_at"
    }
}

private struct MessageDeleteUpdate: Encodable {
    let text: String?
    let mediaUrl: String?
    let fileUrl: String?
    let audioUrl: String?
    let attachmentType: String?
    let attachmentName: String?
    let attachmentSize: Int?
    let updatedAt: String
    let deletedAt: String
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case text
        case mediaUrl = "media_url"
        case fileUrl = "file_url"
        case audioUrl = "audio_url"
        case attachmentType = "attachment_type"
        case attachmentName = "attachment_name"
        case attachmentSize = "attachment_size"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case isDeleted = "is_deleted"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .text)
        try container.encodeNil(forKey: .mediaUrl)
        try container.encodeNil(forKey: .fileUrl)
        try container.encodeNil(forKey: .audioUrl)
        try container.encodeNil(forKey: .attachmentType)
        try container.encodeNil(forKey: .attachmentName)
        try container.encodeNil(forKey: .attachmentSize)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
        try container.encode(isDeleted, forKey: .isDeleted)
    }
}
