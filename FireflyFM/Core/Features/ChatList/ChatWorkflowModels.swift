import Foundation
import Observation
import Supabase

struct ChatRoomUpdateDraft {
    let roomId: UUID
    let name: String
    let description: String?
    let imageURL: String?
    let archived: Bool
}

struct ChatRoomSettingsClient {
    var fetchParticipants: (UUID) async throws -> [ChatParticipant]
    var fetchDirectory: (UUID) async throws -> [SchoolDirectoryEntry]
    var updateRoom: (ChatRoomUpdateDraft) async throws -> ChatRoom
    var setParticipants: (UUID, [UUID]) async throws -> Void
    var setNotifications: (UUID, Bool) async throws -> Void
    var deleteRoom: (UUID) async throws -> Void
    var leaveRoom: (UUID) async throws -> Void

    static let live = ChatRoomSettingsClient(
        fetchParticipants: { try await ChatService.shared.fetchParticipants(roomId: $0) },
        fetchDirectory: { try await SchoolOperationsService.shared.fetchDirectory(schoolId: $0) },
        updateRoom: { draft in
            try await SchoolOperationsService.shared.updateManagedChatRoom(
                roomId: draft.roomId,
                name: draft.name,
                description: draft.description,
                imageURL: draft.imageURL,
                archived: draft.archived
            )
        },
        setParticipants: {
            try await SchoolOperationsService.shared.setManagedChatParticipants(roomId: $0, participantIds: $1)
        },
        setNotifications: { try await ChatService.shared.setNotificationsEnabled(roomId: $0, enabled: $1) },
        deleteRoom: { try await SchoolOperationsService.shared.deleteManagedChatRoom(roomId: $0) },
        leaveRoom: { try await SchoolOperationsService.shared.leaveManagedChatRoom(roomId: $0) }
    )
}

@MainActor
@Observable
final class ChatRoomSettingsModel {
    private let client: ChatRoomSettingsClient
    private(set) var members: [ChatParticipant] = []
    private(set) var directory: [SchoolDirectoryEntry] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: ChatRoomSettingsClient) { self.client = client }

    var currentMemberDirectory: [SchoolDirectoryEntry] {
        let memberIds = Set(members.map(\.userId))
        return directory
            .filter { memberIds.contains($0.userId) }
            .sorted { lhs, rhs in
                let lhsPriority = lhs.schoolRole == .schoolDirector ? 0 : 1
                let rhsPriority = rhs.schoolRole == .schoolDirector ? 0 : 1
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    func load(room: ChatRoom) async {
        phase = .loading
        errorMessage = nil
        do {
            members = try await client.fetchParticipants(room.id)
            if let schoolId = room.schoolId { directory = try await client.fetchDirectory(schoolId) }
            phase = .loaded
        } catch where AppErrorMessage.isCancellation(error) { phase = .idle }
        catch {
            errorMessage = AppErrorMessage.school("Could not load settings", error)
            phase = .failed(errorMessage ?? "Could not load settings")
        }
    }

    func saveRoom(_ draft: ChatRoomUpdateDraft) async -> ChatRoom? {
        isSaving = true
        defer { isSaving = false }
        do { return try await client.updateRoom(draft) }
        catch {
            errorMessage = AppErrorMessage.school("Could not save room", error)
            return nil
        }
    }

    func saveMembers(room: ChatRoom, memberIds: [UUID]) async -> Bool {
        do {
            try await client.setParticipants(room.id, memberIds)
            await load(room: room)
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not update members", error)
            return false
        }
    }

    func updateNotifications(roomId: UUID, enabled: Bool) async -> Bool {
        do {
            try await client.setNotifications(roomId, enabled)
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not update notifications", error)
            return false
        }
    }

    func delete(roomId: UUID) async -> Bool {
        do { try await client.deleteRoom(roomId); return true }
        catch { errorMessage = AppErrorMessage.school("Could not delete room", error); return false }
    }

    func leave(roomId: UUID) async -> Bool {
        do { try await client.leaveRoom(roomId); return true }
        catch { errorMessage = AppErrorMessage.school("Could not leave room", error); return false }
    }
}

struct ChatAttachmentGalleryClient {
    var fetch: (UUID, ChatAttachmentCategory) async throws -> [ChatMessageModel]

    static let live = ChatAttachmentGalleryClient(
        fetch: { try await ChatService.shared.fetchAttachmentMessages(for: $0, category: $1) }
    )
}

@MainActor
@Observable
final class ChatAttachmentGalleryModel {
    private let client: ChatAttachmentGalleryClient
    private(set) var messages: [ChatMessageModel] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: ChatAttachmentGalleryClient) { self.client = client }

    func load(roomId: UUID, category: ChatAttachmentCategory) async {
        phase = .loading
        errorMessage = nil
        do {
            messages = try await client.fetch(roomId, category)
            phase = messages.isEmpty ? .empty : .loaded
        } catch {
            errorMessage = AppErrorMessage.school("Could not load attachments", error)
            phase = .failed(errorMessage ?? "Could not load attachments")
        }
    }
}

@MainActor
@Observable
final class GuardianContactsModel {
    private let fetchContacts: (UUID) async throws -> [ChildEmergencyContact]
    private(set) var contacts: [ChildEmergencyContact] = []
    private(set) var phase: AsyncPhase = .idle
    var errorMessage: String?

    init() {
        fetchContacts = { try await SchoolWorkflowService.shared.fetchChildEmergencyContacts(childId: $0) }
    }

    init(fetchContacts: @escaping (UUID) async throws -> [ChildEmergencyContact]) {
        self.fetchContacts = fetchContacts
    }

    func load(childId: UUID) async {
        phase = .loading
        do {
            contacts = try await fetchContacts(childId)
            phase = contacts.isEmpty ? .empty : .loaded
        } catch {
            errorMessage = AppErrorMessage.school("Could not load guardian contacts", error)
            phase = .failed(errorMessage ?? "Could not load guardian contacts")
        }
    }
}

struct ChatStructuredEntryClient {
    var fetchCareEvent: (UUID) async throws -> ChildCareEvent?
    var fetchFamilyRequest: (UUID) async throws -> FamilyRequest?
    var updateFamilyRequest: (UUID, String) async throws -> FamilyRequest

    static let live = ChatStructuredEntryClient(
        fetchCareEvent: { id in
            let rows: [ChildCareEvent] = try await AppConfiguration.supabase.from("child_care_events")
                .select().eq("id", value: id).limit(1).execute().value
            return rows.first
        },
        fetchFamilyRequest: { id in
            let rows: [FamilyRequest] = try await AppConfiguration.supabase.from("family_requests")
                .select().eq("id", value: id).limit(1).execute().value
            return rows.first
        },
        updateFamilyRequest: {
            try await SchoolOperationsService.shared.updateFamilyRequestStatus(requestId: $0, status: $1)
        }
    )
}

@MainActor
@Observable
final class ChatStructuredEntryModel {
    private let client: ChatStructuredEntryClient
    private(set) var careEvent: ChildCareEvent?
    private(set) var familyRequest: FamilyRequest?
    private(set) var phase: AsyncPhase = .idle
    private(set) var isUpdating = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: ChatStructuredEntryClient) { self.client = client }

    func load(sourceType: String, sourceId: UUID) async {
        phase = .loading
        errorMessage = nil
        do {
            if sourceType == "child_care_events" { careEvent = try await client.fetchCareEvent(sourceId) }
            if sourceType == "family_requests" { familyRequest = try await client.fetchFamilyRequest(sourceId) }
            phase = .loaded
        } catch where AppErrorMessage.isCancellation(error) { phase = .idle }
        catch {
            errorMessage = AppErrorMessage.school("Could not open this update", error)
            phase = .failed(errorMessage ?? "Could not open this update")
        }
    }

    func update(_ request: FamilyRequest, status: String) async {
        isUpdating = true
        defer { isUpdating = false }
        do { familyRequest = try await client.updateFamilyRequest(request.id, status) }
        catch { errorMessage = AppErrorMessage.school("Could not update the request", error) }
    }
}

@MainActor
@Observable
final class ChatRoomInfoModel {
    private let fetchCount: (UUID) async throws -> Int
    private(set) var memberCount = 0

    init() {
        fetchCount = { try await ChatService.shared.fetchParticipants(roomId: $0).count }
    }

    init(fetchCount: @escaping (UUID) async throws -> Int) {
        self.fetchCount = fetchCount
    }

    func load(roomId: UUID) async {
        memberCount = (try? await fetchCount(roomId)) ?? 0
    }
}
