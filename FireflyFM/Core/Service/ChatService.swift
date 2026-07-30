//
//  ChatService.swift
//  FireflyFM
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
        let participants: [ChatParticipant]
        let loadedRooms: [ChatRoom]
        if let schoolId {
            // Fetch room access and the current user's participant settings in
            // one server-authorized query. This avoids a fragile client-side
            // participant -> room join and includes all school rooms for a
            // director without broadening access for teachers or parents.
            let accessRows: [ManagedChatRoomAccessRow] = try await client.rpc(
                "fetch_my_managed_chat_rooms",
                params: ManagedChatRoomSchoolParameters(schoolId: schoolId)
            )
            .execute()
            .value
            loadedRooms = accessRows.map { $0.room() }
            participants = accessRows.map { $0.participant(userId: user.id) }
        } else {
            participants = try await client.from("chat_participants")
                .select()
                .eq("user_id", value: user.id)
                .execute()
                .value
            let participantRoomIds = participants.map(\.roomId)
            if participantRoomIds.isEmpty { return [] }
            loadedRooms = try await client.from("chat_rooms")
                .select()
                .in("id", values: participantRoomIds)
                .execute()
                .value
        }
        _ = includeAllSchoolRooms // Server authorization now determines oversight.
        let rooms = await resolveRoomMedia(loadedRooms)

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

    func fetchParticipants(roomId: UUID) async throws -> [ChatParticipant] {
        try await client.from("chat_participants")
            .select()
            .eq("room_id", value: roomId)
            .order("joined_at", ascending: true)
            .execute()
            .value
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

    func uploadData(_ data: Data, path: String, contentType: String? = nil) async throws -> String {
        try UploadPolicy.validate(data: data, fileName: (path as NSString).lastPathComponent)
        try await client.storage
            .from("school_private_files")
            .upload(path, data: data, options: FileOptions(contentType: contentType))
        return path
    }

    func uploadRoomProfileImage(data: Data, schoolId: UUID, roomId: UUID) async throws -> String {
        let user = try await client.auth.session.user
        let path = privateRoomPath(schoolId: schoolId, roomId: roomId, userId: user.id, kind: "room-profile", fileName: "\(UUID().uuidString).jpg")
        return try await uploadData(data, path: path, contentType: "image/jpeg")
    }

    func uploadFile(fileURL: URL, schoolId: UUID, roomId: UUID) async throws -> ChatAttachmentUploadResult {
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        try UploadPolicy.validate(fileURL: fileURL)
        let data = try Data(contentsOf: fileURL)
        let name = fileURL.lastPathComponent.isEmpty ? "Attachment" : fileURL.lastPathComponent
        let contentType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
        let user = try await client.auth.session.user
        let path = privateRoomPath(schoolId: schoolId, roomId: roomId, userId: user.id, kind: "files", fileName: "\(UUID().uuidString)-\(name)")
        _ = try await uploadData(data, path: path, contentType: contentType)

        return ChatAttachmentUploadResult(
            path: path,
            name: name,
            type: contentType ?? "application/octet-stream",
            size: data.count
        )
    }

    func uploadImageAttachment(data: Data, schoolId: UUID, roomId: UUID) async throws -> ChatAttachmentUploadResult {
        let user = try await client.auth.session.user
        let path = privateRoomPath(schoolId: schoolId, roomId: roomId, userId: user.id, kind: "images", fileName: "\(UUID().uuidString).jpg")
        _ = try await uploadData(data, path: path, contentType: "image/jpeg")

        return ChatAttachmentUploadResult(
            path: path,
            name: "Photo.jpg",
            type: "image/jpeg",
            size: data.count
        )
    }

    func uploadMediaAttachment(
        data: Data,
        fileName: String,
        contentType: String,
        schoolId: UUID,
        roomId: UUID
    ) async throws -> ChatAttachmentUploadResult {
        try UploadPolicy.validate(data: data, fileName: fileName)
        let user = try await client.auth.session.user
        let kind = contentType.hasPrefix("video/") ? "videos" : "images"
        let safeName = fileName.isEmpty ? (kind == "videos" ? "Video.mov" : "Photo.jpg") : fileName
        let path = privateRoomPath(
            schoolId: schoolId,
            roomId: roomId,
            userId: user.id,
            kind: kind,
            fileName: "\(UUID().uuidString)-\(safeName)"
        )
        _ = try await uploadData(data, path: path, contentType: contentType)
        return ChatAttachmentUploadResult(path: path, name: safeName, type: contentType, size: data.count)
    }

    func uploadVideoAttachment(fileURL: URL, schoolId: UUID, roomId: UUID) async throws -> ChatAttachmentUploadResult {
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        try UploadPolicy.validate(fileURL: fileURL)
        let data = try Data(contentsOf: fileURL)
        let sourceName = fileURL.lastPathComponent.isEmpty ? "Video.mov" : fileURL.lastPathComponent
        let contentType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "video/quicktime"
        let user = try await client.auth.session.user
        let path = privateRoomPath(
            schoolId: schoolId,
            roomId: roomId,
            userId: user.id,
            kind: "videos",
            fileName: "\(UUID().uuidString)-\(sourceName)"
        )
        _ = try await uploadData(data, path: path, contentType: contentType)

        return ChatAttachmentUploadResult(
            path: path,
            name: sourceName,
            type: contentType,
            size: data.count
        )
    }

    func uploadAudioAttachment(data: Data, schoolId: UUID, roomId: UUID) async throws -> ChatAttachmentUploadResult {
        let user = try await client.auth.session.user
        let path = privateRoomPath(schoolId: schoolId, roomId: roomId, userId: user.id, kind: "audio", fileName: "\(UUID().uuidString).m4a")
        _ = try await uploadData(data, path: path, contentType: "audio/mp4")

        return ChatAttachmentUploadResult(
            path: path,
            name: "Voice message.m4a",
            type: "audio/mp4",
            size: data.count
        )
    }

    // MARK: - Messages

    func fetchMessages(for roomId: UUID, limit: Int = 150) async throws -> [ChatMessageModel] {
        let messages: [ChatMessageModel] = try await client.from("messages")
            .select()
            .eq("room_id", value: roomId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return await resolveMessageMedia(messages.reversed())
    }

    func fetchMessage(id: UUID) async throws -> ChatMessageModel? {
        let rows: [ChatMessageModel] = try await client.from("messages")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        guard let message = rows.first else { return nil }
        return await resolveMessageMedia(message)
    }

    func fetchAttachmentMessages(
        for roomId: UUID,
        category: ChatAttachmentCategory,
        senderId: UUID? = nil,
        limit: Int = 200
    ) async throws -> [ChatMessageModel] {
        var query = client.from("messages")
            .select()
            .eq("room_id", value: roomId)
            .eq("is_deleted", value: false)

        switch category {
        case .photos:
            query = query.not("media_path", operator: .is, value: "null")
        case .files:
            query = query.not("file_path", operator: .is, value: "null")
        case .audio:
            query = query.not("audio_path", operator: .is, value: "null")
        }
        if let senderId {
            query = query.eq("sender_id", value: senderId)
        }

        let messages: [ChatMessageModel] = try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return await resolveMessageMedia(messages)
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

        return await resolveMessageMedia(merged.values.sorted { $0.createdAt > $1.createdAt })
    }

    @discardableResult
    func sendMessage(
        roomId: UUID,
        text: String?,
        mediaUrl: String? = nil,
        fileUrl: String? = nil,
        audioUrl: String? = nil,
        mediaPath: String? = nil,
        filePath: String? = nil,
        audioPath: String? = nil,
        attachmentType: String? = nil,
        attachmentName: String? = nil,
        attachmentSize: Int? = nil,
        audioDurationSeconds: Double? = nil,
        replyToMessageId: UUID? = nil
    ) async throws -> ChatMessageModel {
        let user = try await client.auth.session.user

        let message = ChatMessageModel(
            roomId: roomId,
            senderId: user.id,
            text: text,
            mediaUrl: mediaUrl,
            fileUrl: fileUrl,
            audioUrl: audioUrl,
            mediaPath: mediaPath,
            filePath: filePath,
            audioPath: audioPath,
            attachmentType: attachmentType,
            attachmentName: attachmentName,
            attachmentSize: attachmentSize,
            audioDurationSeconds: audioDurationSeconds,
            replyToMessageId: replyToMessageId
        )

        let saved: [ChatMessageModel] = try await client.from("messages")
            .insert(message)
            .select()
            .execute()
            .value
        guard let savedMessage = saved.first else { throw ChatServiceError.notFound }
        return savedMessage
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
        let existing: [MessageMediaPaths] = try await client.from("messages")
            .select("media_path,file_path,audio_path")
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        let update = MessageDeleteUpdate(
            text: nil,
            mediaUrl: nil,
            fileUrl: nil,
            audioUrl: nil,
            mediaPath: nil,
            filePath: nil,
            audioPath: nil,
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

        let objectPaths = existing.first.map { message in
            [message.mediaPath, message.filePath, message.audioPath].compactMap { $0 }
        } ?? []
        if objectPaths.isEmpty == false {
            _ = try? await client.storage.from("school_private_files").remove(paths: objectPaths)
        }
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
        let channel = client.realtimeV2.channel(resolvedChannelName)

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

        do {
            try await channel.subscribeWithError()
        } catch {
            print("DEBUG: Failed to subscribe to channel: \(error)")
        }
        return channel
    }

    func resolveMessageMedia(_ message: ChatMessageModel) async -> ChatMessageModel {
        var resolved = message
        resolved.mediaUrl = await SignedMediaResolver.shared.resolve(
            bucket: "school_private_files",
            path: message.mediaPath,
            legacyURL: message.mediaUrl
        )
        resolved.fileUrl = await SignedMediaResolver.shared.resolve(
            bucket: "school_private_files",
            path: message.filePath,
            legacyURL: message.fileUrl
        )
        resolved.audioUrl = await SignedMediaResolver.shared.resolve(
            bucket: "school_private_files",
            path: message.audioPath,
            legacyURL: message.audioUrl
        )
        return resolved
    }

    private func resolveMessageMedia<S: Sequence>(_ messages: S) async -> [ChatMessageModel] where S.Element == ChatMessageModel {
        let indexedMessages = Array(messages).enumerated().map { ($0.offset, $0.element) }
        return await withTaskGroup(of: (Int, ChatMessageModel).self) { group in
            for (index, message) in indexedMessages {
                group.addTask { [self] in
                    guard message.mediaPath != nil || message.filePath != nil || message.audioPath != nil else {
                        return (index, message)
                    }
                    return (index, await resolveMessageMedia(message))
                }
            }

            var resolved = Array<ChatMessageModel?>(repeating: nil, count: indexedMessages.count)
            for await (index, message) in group {
                resolved[index] = message
            }
            return resolved.compactMap { $0 }
        }
    }

    private func resolveRoomMedia(_ rooms: [ChatRoom]) async -> [ChatRoom] {
        var resolved: [ChatRoom] = []
        for var room in rooms {
            room.profileImageUrl = await SignedMediaResolver.shared.resolve(
                bucket: "school_private_files",
                path: room.profileImagePath,
                legacyURL: room.profileImageUrl
            )
            resolved.append(room)
        }
        return resolved
    }

    private func privateRoomPath(schoolId: UUID, roomId: UUID, userId: UUID, kind: String, fileName: String) -> String {
        "schools/\(schoolId.uuidString)/chat_rooms/\(roomId.uuidString)/\(userId.uuidString)/\(kind)/\(fileName)"
    }
}

enum ChatServiceError: Error {
    case notFound
}

private struct ManagedChatRoomSchoolParameters: Encodable {
    let schoolId: UUID

    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
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
    let mediaPath: String?
    let filePath: String?
    let audioPath: String?
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
        case mediaPath = "media_path"
        case filePath = "file_path"
        case audioPath = "audio_path"
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
        try container.encodeNil(forKey: .mediaPath)
        try container.encodeNil(forKey: .filePath)
        try container.encodeNil(forKey: .audioPath)
        try container.encodeNil(forKey: .attachmentType)
        try container.encodeNil(forKey: .attachmentName)
        try container.encodeNil(forKey: .attachmentSize)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
        try container.encode(isDeleted, forKey: .isDeleted)
    }
}

private struct MessageMediaPaths: Decodable {
    let mediaPath: String?
    let filePath: String?
    let audioPath: String?

    enum CodingKeys: String, CodingKey {
        case mediaPath = "media_path"
        case filePath = "file_path"
        case audioPath = "audio_path"
    }
}
