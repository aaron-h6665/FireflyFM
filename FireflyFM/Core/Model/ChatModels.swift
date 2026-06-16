//
//  ChatModels.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import Foundation

struct ChatRoom: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let description: String?
    let profileImageUrl: String?
    let inviteHash: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, name, description
        case profileImageUrl = "profile_image_url"
        case inviteHash = "invite_hash"
        case createdAt = "created_at"
    }
}

struct ChatParticipant: Codable, Hashable {
    let roomId: UUID
    let userId: UUID
    let joinedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
    }
}

struct ChatMessageModel: Codable, Identifiable, Hashable {
    let id: UUID
    let roomId: UUID
    let senderId: UUID
    let text: String?
    let mediaUrl: String?
    let fileUrl: String?
    let audioUrl: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case senderId = "sender_id"
        case text
        case mediaUrl = "media_url"
        case fileUrl = "file_url"
        case audioUrl = "audio_url"
        case createdAt = "created_at"
    }
}
