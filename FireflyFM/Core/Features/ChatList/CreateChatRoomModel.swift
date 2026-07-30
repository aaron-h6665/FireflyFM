import Foundation
import Observation

struct CreateChatRoomClient {
    var fetchDirectory: (UUID) async throws -> [SchoolDirectoryEntry]
    var createRoom: (UUID, String, String?, [UUID]) async throws -> ChatRoom
    var uploadProfileImage: (Data, UUID, UUID) async throws -> String
    var updateImagePath: (UUID, String) async throws -> ChatRoom

    static let live = CreateChatRoomClient(
        fetchDirectory: { try await SchoolOperationsService.shared.fetchDirectory(schoolId: $0) },
        createRoom: { schoolId, name, description, participantIds in
            try await SchoolOperationsService.shared.createManagedChatRoom(
                schoolId: schoolId,
                name: name,
                description: description,
                imageURL: nil,
                participantIds: participantIds
            )
        },
        uploadProfileImage: { try await ChatService.shared.uploadRoomProfileImage(data: $0, schoolId: $1, roomId: $2) },
        updateImagePath: { try await SchoolOperationsService.shared.updateManagedChatImagePath(roomId: $0, path: $1) }
    )
}

@MainActor
@Observable
final class CreateChatRoomModel {
    private let client: CreateChatRoomClient
    private var requestId = UUID()

    private(set) var directory: [SchoolDirectoryEntry] = []
    private(set) var directoryPhase: AsyncPhase = .idle
    private(set) var isCreating = false
    private(set) var errorMessage: String?

    init() {
        client = .live
    }

    init(client: CreateChatRoomClient) {
        self.client = client
    }

    func loadDirectory(schoolId: UUID, excluding userId: UUID?) async {
        let currentRequestId = UUID()
        requestId = currentRequestId
        directoryPhase = .loading
        errorMessage = nil
        do {
            let loaded = try await client.fetchDirectory(schoolId)
            guard requestId == currentRequestId else { return }
            directory = loaded.filter { $0.id != userId }
            directoryPhase = loaded.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            guard requestId == currentRequestId else { return }
            directoryPhase = .failed(AppErrorMessage.school("Could not load members", error))
        }
    }

    func create(
        schoolId: UUID,
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
                schoolId,
                name.trimmed,
                description.nilIfBlank,
                Array(participantIds)
            )
            if let profileImageData {
                let path = try await client.uploadProfileImage(profileImageData, schoolId, room.id)
                room = try await client.updateImagePath(room.id, path)
            }
            _ = room
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not create room", error)
            return false
        }
    }
}
