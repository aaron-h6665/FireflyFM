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
    var profileImagePath: String?
    var inviteHash: String?
    var schoolId: UUID?
    var roomType: String?
    var subjectChildId: UUID?
    var systemManaged: Bool
    var createdAt: Date
    var createdBy: UUID?
    var updatedAt: Date?
    var archivedAt: Date?
    var archiveReason: String?
    var retentionUntil: Date?
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        profileImageUrl: String? = nil,
        profileImagePath: String? = nil,
        inviteHash: String? = nil,
        schoolId: UUID? = nil,
        roomType: String? = "custom",
        subjectChildId: UUID? = nil,
        systemManaged: Bool = false,
        createdAt: Date = Date(),
        createdBy: UUID? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.profileImageUrl = profileImageUrl
        self.profileImagePath = profileImagePath
        self.inviteHash = inviteHash
        self.schoolId = schoolId
        self.roomType = roomType
        self.subjectChildId = subjectChildId
        self.systemManaged = systemManaged
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.updatedAt = updatedAt
        self.archivedAt = nil
        self.archiveReason = nil
        self.retentionUntil = nil
        self.deletedAt = nil
    }

    var isChildFamilyRoom: Bool { roomType == "child_family" }
    var isSchoolCommunityRoom: Bool { roomType == "school_group" }
    var isCustomRoom: Bool { roomType == "custom" }
    var isReadOnly: Bool { archivedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case profileImageUrl = "profile_image_url"
        case profileImagePath = "profile_image_path"
        case inviteHash = "invite_hash"
        case schoolId = "school_id"
        case roomType = "room_type"
        case subjectChildId = "subject_child_id"
        case systemManaged = "system_managed"
        case createdAt = "created_at"
        case createdBy = "created_by"
        case updatedAt = "updated_at"
        case archivedAt = "archived_at"
        case archiveReason = "archive_reason"
        case retentionUntil = "retention_until"
        case deletedAt = "deleted_at"
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
    var membershipSource: String

    init(
        roomId: UUID,
        userId: UUID,
        joinedAt: Date = Date(),
        lastReadAt: Date? = nil,
        notificationsEnabled: Bool = true,
        role: String? = "member",
        membershipSource: String = "manual"
    ) {
        self.roomId = roomId
        self.userId = userId
        self.joinedAt = joinedAt
        self.lastReadAt = lastReadAt
        self.notificationsEnabled = notificationsEnabled
        self.role = role
        self.membershipSource = membershipSource
    }

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
        case lastReadAt = "last_read_at"
        case notificationsEnabled = "notifications_enabled"
        case role
        case membershipSource = "membership_source"
    }
}

struct ManagedChatRoomAccessRow: Codable {
    let id: UUID
    let name: String
    let description: String?
    let profileImageUrl: String?
    let profileImagePath: String?
    let schoolId: UUID
    let roomType: String?
    let subjectChildId: UUID?
    let systemManaged: Bool?
    let createdAt: Date?
    let createdBy: UUID?
    let updatedAt: Date?
    let archivedAt: Date?
    let archiveReason: String?
    let retentionUntil: Date?
    let deletedAt: Date?
    let participantJoinedAt: Date?
    let participantLastReadAt: Date?
    let participantNotificationsEnabled: Bool?
    let participantRole: String?
    let participantMembershipSource: String?

    func room() -> ChatRoom {
        let effectiveCreatedAt = createdAt ?? updatedAt ?? Date.distantPast
        var room = ChatRoom(
            id: id,
            name: name,
            description: description,
            profileImageUrl: profileImageUrl,
            profileImagePath: profileImagePath,
            inviteHash: nil,
            schoolId: schoolId,
            roomType: roomType ?? "custom",
            subjectChildId: subjectChildId,
            systemManaged: systemManaged ?? false,
            createdAt: effectiveCreatedAt,
            createdBy: createdBy,
            updatedAt: updatedAt
        )
        room.archivedAt = archivedAt
        room.archiveReason = archiveReason
        room.retentionUntil = retentionUntil
        room.deletedAt = deletedAt
        return room
    }

    func participant(userId: UUID) -> ChatParticipant {
        ChatParticipant(
            roomId: id,
            userId: userId,
            joinedAt: participantJoinedAt ?? createdAt ?? Date.distantPast,
            lastReadAt: participantLastReadAt,
            notificationsEnabled: participantNotificationsEnabled ?? true,
            role: participantRole ?? "member",
            membershipSource: participantMembershipSource ?? "manual"
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case profileImageUrl = "profile_image_url"
        case profileImagePath = "profile_image_path"
        case schoolId = "school_id"
        case roomType = "room_type"
        case subjectChildId = "subject_child_id"
        case systemManaged = "system_managed"
        case createdAt = "created_at"
        case createdBy = "created_by"
        case updatedAt = "updated_at"
        case archivedAt = "archived_at"
        case archiveReason = "archive_reason"
        case retentionUntil = "retention_until"
        case deletedAt = "deleted_at"
        case participantJoinedAt = "participant_joined_at"
        case participantLastReadAt = "participant_last_read_at"
        case participantNotificationsEnabled = "participant_notifications_enabled"
        case participantRole = "participant_role"
        case participantMembershipSource = "participant_membership_source"
    }
}

struct ChatMessageModel: Codable, Identifiable, Hashable {
    var id: UUID
    var roomId: UUID
    var schoolId: UUID?
    var senderId: UUID
    var text: String?
    var mediaUrl: String?
    var fileUrl: String?
    var audioUrl: String?
    var mediaPath: String?
    var filePath: String?
    var audioPath: String?
    var attachmentType: String?
    var attachmentName: String?
    var attachmentSize: Int?
    var entryKind: String
    var structuredSourceType: String?
    var structuredSourceId: UUID?
    var linkedCareEventId: UUID?
    var audioDurationSeconds: Double?
    var replyToMessageId: UUID?
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?
    var isDeleted: Bool

    init(
        id: UUID = UUID(),
        roomId: UUID,
        schoolId: UUID? = nil,
        senderId: UUID,
        text: String? = nil,
        mediaUrl: String? = nil,
        fileUrl: String? = nil,
        audioUrl: String? = nil,
        mediaPath: String? = nil,
        filePath: String? = nil,
        audioPath: String? = nil,
        attachmentType: String? = nil,
        attachmentName: String? = nil,
        attachmentSize: Int? = nil,
        entryKind: String = "message",
        structuredSourceType: String? = nil,
        structuredSourceId: UUID? = nil,
        linkedCareEventId: UUID? = nil,
        audioDurationSeconds: Double? = nil,
        replyToMessageId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.roomId = roomId
        self.schoolId = schoolId
        self.senderId = senderId
        self.text = text
        self.mediaUrl = mediaUrl
        self.fileUrl = fileUrl
        self.audioUrl = audioUrl
        self.mediaPath = mediaPath
        self.filePath = filePath
        self.audioPath = audioPath
        self.attachmentType = attachmentType
        self.attachmentName = attachmentName
        self.attachmentSize = attachmentSize
        self.entryKind = entryKind
        self.structuredSourceType = structuredSourceType
        self.structuredSourceId = structuredSourceId
        self.linkedCareEventId = linkedCareEventId
        self.audioDurationSeconds = audioDurationSeconds
        self.replyToMessageId = replyToMessageId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isDeleted = isDeleted
    }

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case schoolId = "school_id"
        case senderId = "sender_id"
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
        case entryKind = "entry_kind"
        case structuredSourceType = "structured_source_type"
        case structuredSourceId = "structured_source_id"
        case linkedCareEventId = "linked_care_event_id"
        case audioDurationSeconds = "audio_duration_seconds"
        case replyToMessageId = "reply_to_message_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case isDeleted = "is_deleted"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        roomId = try container.decode(UUID.self, forKey: .roomId)
        schoolId = try container.decodeIfPresent(UUID.self, forKey: .schoolId)
        senderId = try container.decode(UUID.self, forKey: .senderId)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        mediaUrl = try container.decodeIfPresent(String.self, forKey: .mediaUrl)
        fileUrl = try container.decodeIfPresent(String.self, forKey: .fileUrl)
        audioUrl = try container.decodeIfPresent(String.self, forKey: .audioUrl)
        mediaPath = try container.decodeIfPresent(String.self, forKey: .mediaPath)
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        audioPath = try container.decodeIfPresent(String.self, forKey: .audioPath)
        attachmentType = try container.decodeIfPresent(String.self, forKey: .attachmentType)
        attachmentName = try container.decodeIfPresent(String.self, forKey: .attachmentName)
        attachmentSize = try container.decodeIfPresent(Int.self, forKey: .attachmentSize)
        entryKind = try container.decodeIfPresent(String.self, forKey: .entryKind) ?? "message"
        structuredSourceType = try container.decodeIfPresent(String.self, forKey: .structuredSourceType)
        structuredSourceId = try container.decodeIfPresent(UUID.self, forKey: .structuredSourceId)
        linkedCareEventId = try container.decodeIfPresent(UUID.self, forKey: .linkedCareEventId)
        audioDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .audioDurationSeconds)
        replyToMessageId = try container.decodeIfPresent(UUID.self, forKey: .replyToMessageId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? (deletedAt != nil)
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
    let path: String
    let name: String
    let type: String
    let size: Int
}

enum ChatAttachmentCategory: String, CaseIterable, Identifiable {
    case photos
    case files
    case audio

    var id: String { rawValue }
    var title: String {
        switch self {
        case .photos: "Photos & Videos"
        case .files: "Files"
        case .audio: "Audio"
        }
    }
    var symbol: String {
        switch self {
        case .photos: "photo.on.rectangle.angled"
        case .files: "doc.fill"
        case .audio: "waveform"
        }
    }
}

struct UserProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var avatarUrl: String?
    var avatarPath: String? = nil
    var createdAt: Date?
    var updatedAt: Date?

    var initials: String {
        let parts = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let value = String(parts).uppercased()
        return value.isEmpty ? "?" : value
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case avatarPath = "avatar_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
