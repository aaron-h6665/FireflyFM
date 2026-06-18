//
//  ChatModels.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import Foundation

struct ChatRoom: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var description: String?
    var profileImageUrl: String?
    var inviteHash: String?
    var createdAt: Date
    var createdBy: UUID?
    var updatedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        profileImageUrl: String? = nil,
        inviteHash: String? = UUID().uuidString,
        createdAt: Date = Date(),
        createdBy: UUID? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.profileImageUrl = profileImageUrl
        self.inviteHash = inviteHash
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case profileImageUrl = "profile_image_url"
        case inviteHash = "invite_hash"
        case createdAt = "created_at"
        case createdBy = "created_by"
        case updatedAt = "updated_at"
    }
}

struct ChatParticipant: Codable, Identifiable, Hashable {
    var id: String { "\(roomId.uuidString)-\(userId.uuidString)" }

    var roomId: UUID
    var userId: UUID
    var joinedAt: Date
    var lastReadAt: Date?
    var notificationsEnabled: Bool
    var role: String?

    init(
        roomId: UUID,
        userId: UUID,
        joinedAt: Date = Date(),
        lastReadAt: Date? = nil,
        notificationsEnabled: Bool = true,
        role: String? = "member"
    ) {
        self.roomId = roomId
        self.userId = userId
        self.joinedAt = joinedAt
        self.lastReadAt = lastReadAt
        self.notificationsEnabled = notificationsEnabled
        self.role = role
    }

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
        case lastReadAt = "last_read_at"
        case notificationsEnabled = "notifications_enabled"
        case role
    }
}

struct ChatMessageModel: Codable, Identifiable, Hashable {
    var id: UUID
    var roomId: UUID
    var senderId: UUID
    var text: String?
    var mediaUrl: String?
    var fileUrl: String?
    var audioUrl: String?
    var attachmentType: String?
    var attachmentName: String?
    var attachmentSize: Int?
    var replyToMessageId: UUID?
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?
    var isDeleted: Bool

    init(
        id: UUID = UUID(),
        roomId: UUID,
        senderId: UUID,
        text: String? = nil,
        mediaUrl: String? = nil,
        fileUrl: String? = nil,
        audioUrl: String? = nil,
        attachmentType: String? = nil,
        attachmentName: String? = nil,
        attachmentSize: Int? = nil,
        replyToMessageId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.roomId = roomId
        self.senderId = senderId
        self.text = text
        self.mediaUrl = mediaUrl
        self.fileUrl = fileUrl
        self.audioUrl = audioUrl
        self.attachmentType = attachmentType
        self.attachmentName = attachmentName
        self.attachmentSize = attachmentSize
        self.replyToMessageId = replyToMessageId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isDeleted = isDeleted
    }

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case senderId = "sender_id"
        case text
        case mediaUrl = "media_url"
        case fileUrl = "file_url"
        case audioUrl = "audio_url"
        case attachmentType = "attachment_type"
        case attachmentName = "attachment_name"
        case attachmentSize = "attachment_size"
        case replyToMessageId = "reply_to_message_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case isDeleted = "is_deleted"
    }
}

struct ChatRoomListItem: Identifiable, Hashable {
    var id: UUID { room.id }

    var room: ChatRoom
    var participant: ChatParticipant
    var lastMessage: ChatMessageModel?
    var unreadCount: Int

    var lastActivityAt: Date {
        lastMessage?.createdAt ?? room.updatedAt ?? room.createdAt
    }

    var notificationsEnabled: Bool {
        participant.notificationsEnabled
    }
}

struct ChatAttachmentUploadResult: Hashable {
    let url: String
    let name: String
    let type: String
    let size: Int
}
