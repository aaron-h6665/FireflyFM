import Foundation
import Observation
import Auth
import PostgREST
import Supabase

struct NotificationInboxClient {
    var fetchDirectory: (UUID) async throws -> [SchoolDirectoryEntry]

    static let live = NotificationInboxClient(
        fetchDirectory: { try await SchoolOperationsService.shared.fetchDirectory(schoolId: $0) }
    )
}

@MainActor
@Observable
final class NotificationInboxModel {
    private let client: NotificationInboxClient
    private(set) var members: [SchoolDirectoryEntry] = []

    init() { client = .live }
    init(client: NotificationInboxClient) { self.client = client }

    func loadDirectory(schoolId: UUID?, canCompose: Bool) async throws {
        guard canCompose, let schoolId else {
            members = []
            return
        }
        members = try await client.fetchDirectory(schoolId)
    }
}

struct NotificationPreferencesClient {
    var fetch: () async throws -> [NotificationPreference]
    var currentUserId: () async throws -> UUID
    var save: ([NotificationPreference]) async throws -> Void

    static let live = NotificationPreferencesClient(
        fetch: { try await SchoolOperationsService.shared.fetchNotificationPreferences() },
        currentUserId: { try await AppConfiguration.supabase.auth.session.user.id },
        save: { try await SchoolOperationsService.shared.saveNotificationPreferences($0) }
    )
}

struct NotificationPreferenceDraft {
    let category: String
    let enabled: Bool
}

@MainActor
@Observable
final class NotificationPreferencesModel {
    private let client: NotificationPreferencesClient
    private(set) var preferences: [NotificationPreference] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: NotificationPreferencesClient) { self.client = client }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { preferences = try await client.fetch() }
        catch where AppErrorMessage.isCancellation(error) {}
        catch { errorMessage = AppErrorMessage.school("Could not load notification settings", error) }
    }

    func save(
        drafts: [NotificationPreferenceDraft],
        quietHoursStart: String?,
        quietHoursEnd: String?
    ) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let userId = try await client.currentUserId()
            let preferences = drafts.map {
                NotificationPreference(
                    userId: userId,
                    category: $0.category,
                    enabled: $0.enabled,
                    quietHoursStart: quietHoursStart,
                    quietHoursEnd: quietHoursEnd,
                    timeZone: TimeZone.current.identifier
                )
            }
            try await client.save(preferences)
            self.preferences = preferences
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not save notification settings", error)
            return false
        }
    }
}

struct NotificationDestinationClient {
    var fetchCareEvent: (UUID) async throws -> ChildCareEvent?
    var fetchChild: (UUID) async throws -> Child?
    var fetchChatRoom: (UUID) async throws -> ChatRoom?
    var fetchFamilyChatRoom: (UUID) async throws -> ChatRoom?

    static let live = NotificationDestinationClient(
        fetchCareEvent: { id in
            let rows: [ChildCareEvent] = try await AppConfiguration.supabase
                .from("child_care_events").select().eq("id", value: id).limit(1).execute().value
            return rows.first
        },
        fetchChild: { id in
            let rows: [Child] = try await AppConfiguration.supabase
                .from("children").select().eq("id", value: id).limit(1).execute().value
            return rows.first
        },
        fetchChatRoom: { id in
            let rooms: [ChatRoom] = try await AppConfiguration.supabase
                .from("chat_rooms").select().eq("id", value: id).limit(1).execute().value
            return rooms.first
        },
        fetchFamilyChatRoom: { childId in
            let rooms: [ChatRoom] = try await AppConfiguration.supabase.from("chat_rooms")
                .select()
                .eq("subject_child_id", value: childId)
                .eq("room_type", value: "child_family")
                .order("created_at", ascending: false)
                .limit(5)
                .execute()
                .value
            return rooms.first(where: { $0.deletedAt == nil })
        }
    )
}

@MainActor
@Observable
final class ChildCareNotificationModel {
    private let client: NotificationDestinationClient
    private(set) var event: ChildCareEvent?
    private(set) var child: Child?
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: NotificationDestinationClient) { self.client = client }

    func load(eventId: UUID) async {
        do {
            event = try await client.fetchCareEvent(eventId)
            if let childId = event?.childId { child = try await client.fetchChild(childId) }
            if event == nil { errorMessage = "You may no longer have access to this care event." }
        } catch where AppErrorMessage.isCancellation(error) {}
        catch { errorMessage = AppErrorMessage.school("Could not open the care event", error) }
    }
}

enum NotificationLookupKind {
    case child(UUID)
    case chatRoom(UUID)
    case familyChat(UUID)
}

@MainActor
@Observable
final class NotificationLookupModel {
    private let client: NotificationDestinationClient
    private(set) var child: Child?
    private(set) var room: ChatRoom?
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: NotificationDestinationClient) { self.client = client }

    func load(_ kind: NotificationLookupKind) async {
        do {
            switch kind {
            case .child(let id):
                child = try await client.fetchChild(id)
                if child == nil { errorMessage = "You may no longer have access to this child." }
            case .chatRoom(let id):
                room = try await client.fetchChatRoom(id)
                if room == nil { errorMessage = "You may have been removed from this room." }
            case .familyChat(let childId):
                room = try await client.fetchFamilyChatRoom(childId)
                if room == nil { errorMessage = "You may no longer have access to this child’s family chat." }
            }
        } catch where AppErrorMessage.isCancellation(error) {}
        catch {
            let label: String
            switch kind {
            case .child: label = "Could not open the child profile"
            case .chatRoom: label = "Could not open this chat"
            case .familyChat: label = "Could not open the family chat"
            }
            errorMessage = AppErrorMessage.school(label, error)
        }
    }
}

struct NotificationComposerClient {
    var createAnnouncement: (UUID, String, String, [UUID]) async throws -> Void

    static let live = NotificationComposerClient(
        createAnnouncement: {
            try await SchoolOperationsService.shared.createAnnouncement(
                schoolId: $0,
                title: $1,
                body: $2,
                recipientIds: $3
            )
        }
    )
}

@MainActor
@Observable
final class NotificationComposerModel {
    private let client: NotificationComposerClient
    private(set) var isSending = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: NotificationComposerClient) { self.client = client }

    func send(schoolId: UUID, title: String, body: String, recipientIds: [UUID]) async -> Bool {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await client.createAnnouncement(schoolId, title, body, recipientIds)
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not send notification", error)
            return false
        }
    }
}
