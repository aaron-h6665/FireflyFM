//
//  CreateHQChatRoomModel.swift
//  FireflyFM
//

import Foundation
import Observation

struct CreateHQChatRoomClient {
    var fetchDirectory: (_ schoolId: UUID?, _ role: String?, _ query: String?) async throws -> [HQDirectoryEntry]
    var createRoom: (_ name: String, _ description: String?, _ participantIds: [UUID]) async throws -> ChatRoom
    var uploadProfileImage: (_ data: Data, _ roomId: UUID) async throws -> String
    var updateImagePath: (_ roomId: UUID, _ path: String) async throws -> ChatRoom

    static let live = CreateHQChatRoomClient(
        fetchDirectory: { schoolId, role, query in
            try await SchoolOperationsService.shared.fetchHQChatDirectory(
                schoolId: schoolId,
                role: role,
                searchQuery: query
            )
        },
        createRoom: { name, description, participantIds in
            try await SchoolOperationsService.shared.createHQChatRoom(
                name: name,
                description: description,
                imageURL: nil,
                participantIds: participantIds
            )
        },
        uploadProfileImage: { data, roomId in
            try await ChatService.shared.uploadRoomProfileImage(data: data, schoolId: nil, roomId: roomId)
        },
        updateImagePath: { roomId, path in
            try await SchoolOperationsService.shared.updateManagedChatImagePath(roomId: roomId, path: path)
        }
    )
}

@MainActor
@Observable
final class CreateHQChatRoomModel {
    private let client: CreateHQChatRoomClient
    private var requestId = UUID()

    private(set) var directory: [HQDirectoryEntry] = []
    private(set) var directoryPhase: AsyncPhase = .idle
    private(set) var isCreating = false
    private(set) var errorMessage: String?

    init(client: CreateHQChatRoomClient = .live) {
        self.client = client
    }

    func loadDirectory(
        schoolId: UUID? = nil,
        role: String? = nil,
        query: String? = nil,
        excluding userId: UUID?
    ) async {
        let currentRequestId = UUID()
        requestId = currentRequestId
        directoryPhase = .loading
        errorMessage = nil

        do {
            let loaded = try await client.fetchDirectory(schoolId, role, query)
            guard requestId == currentRequestId else { return }
            let filtered = loaded.filter { $0.userId != userId }
            directory = filtered
            directoryPhase = filtered.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            guard requestId == currentRequestId else { return }
            directoryPhase = .failed(AppErrorMessage.school("Could not load directory", error))
        }
    }

    func create(
        name: String,
        description: String,
        participantIds: Set<UUID>,
        profileImageData: Data?
    ) async -> Bool {
        guard isCreating == false else { return false }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        do {
            var room = try await client.createRoom(
                name.trimmed,
                description.nilIfBlank,
                Array(participantIds)
            )
            if let profileImageData {
                let path = try await client.uploadProfileImage(profileImageData, room.id)
                room = try await client.updateImagePath(room.id, path)
            }
            _ = room
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not create HQ chat", error)
            return false
        }
    }
}
