//
//  ChatService.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import Foundation
import Supabase

class ChatService {
    static let shared = ChatService()
    private let client = AppConstants.supabase
    
    private init() {}
    
    // MARK: - Rooms
    
    func fetchMyRooms() async throws -> [ChatRoom] {
        let user = try await client.auth.session.user
        
        // Fetch participant rows for current user
        let participants: [ChatParticipant] = try await client.from("chat_participants")
            .select()
            .eq("user_id", value: user.id)
            .execute()
            .value
        
        let roomIds = participants.map { $0.roomId }
        
        if roomIds.isEmpty { return [] }
        
        // Fetch rooms matching those IDs
        let rooms: [ChatRoom] = try await client.from("chat_rooms")
            .select()
            .in("id", values: roomIds)
            .order("created_at", ascending: false)
            .execute()
            .value
        
        return rooms
    }
    
    func createRoom(name: String, description: String? = nil, profileImageUrl: String? = nil) async throws -> ChatRoom {
        let user = try await client.auth.session.user
        
        let newRoom = ChatRoom(
            id: UUID(),
            name: name,
            description: description,
            profileImageUrl: profileImageUrl,
            inviteHash: UUID().uuidString,
            createdAt: Date()
        )
        
        // Insert Room
        try await client.from("chat_rooms")
            .insert(newRoom)
            .execute()
        
        // Add creator as participant
        let participant = ChatParticipant(
            roomId: newRoom.id,
            userId: user.id,
            joinedAt: Date()
        )
        try await client.from("chat_participants")
            .insert(participant)
            .execute()
        
        return newRoom
    }
    
    // MARK: - Storage
    
    func uploadImage(data: Data, path: String) async throws -> String {
        try await client.storage
            .from("chat_attachments")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        
        return try await client.storage
            .from("chat_attachments")
            .createSignedURL(path: path, expiresIn: 60 * 60 * 24 * 365) // 1 year signed URL
            .absoluteString
    }
    
    // MARK: - Messages
    
    func fetchMessages(for roomId: UUID) async throws -> [ChatMessageModel] {
        let messages: [ChatMessageModel] = try await client.from("messages")
            .select()
            .eq("room_id", value: roomId)
            .order("created_at", ascending: true)
            .execute()
            .value
        
        return messages
    }
    
    func sendMessage(roomId: UUID, text: String?, mediaUrl: String? = nil, fileUrl: String? = nil, audioUrl: String? = nil) async throws {
        let user = try await client.auth.session.user
        
        let message = ChatMessageModel(
            id: UUID(),
            roomId: roomId,
            senderId: user.id,
            text: text,
            mediaUrl: mediaUrl,
            fileUrl: fileUrl,
            audioUrl: audioUrl,
            createdAt: Date()
        )
        
        try await client.from("messages")
            .insert(message)
            .execute()
    }
    
    // MARK: - Realtime Subscriptions
    
    func subscribeToMessages(in roomId: UUID, onInsert: @escaping (ChatMessageModel) -> Void) async -> RealtimeChannelV2 {
        let channel = await client.realtimeV2.channel("messages_room_\(roomId.uuidString)")
        
        Task {
            let insertions = await channel.postgresChange(
                InsertAction.self,
                schema: "public",
                table: "messages",
                filter: .eq("room_id", value: roomId.uuidString)
            )
            
            for await insertion in insertions {
                do {
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
                    
                    let newMessage = try insertion.decodeRecord(as: ChatMessageModel.self, decoder: decoder)
                    onInsert(newMessage)
                } catch {
                    print("DEBUG: Failed to decode realtime message: \(error)")
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
