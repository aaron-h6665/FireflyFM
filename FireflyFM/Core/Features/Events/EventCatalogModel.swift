import Foundation
import Observation

struct EventCatalogClient {
    var fetchSchools: () async throws -> [School]
    var fetchEvents: (UUID, Bool) async throws -> [SchoolEvent]
    var fetchMembers: (UUID) async throws -> [SchoolMember]
    var fetchProfiles: ([UUID]) async throws -> [UUID: UserProfile]
    var deleteEvent: (UUID) async throws -> Void
    var setArchived: (UUID, Bool) async throws -> SchoolEvent

    static let live = EventCatalogClient(
        fetchSchools: { try await SchoolService.shared.fetchSchoolsForHQ() },
        fetchEvents: { try await SchoolWorkflowService.shared.fetchEvents(schoolId: $0, includeArchived: $1) },
        fetchMembers: { try await SchoolService.shared.fetchMembers(schoolId: $0) },
        fetchProfiles: { try await ProfileService.shared.fetchProfiles(ids: $0) },
        deleteEvent: { try await SchoolWorkflowService.shared.deleteEvent(eventId: $0) },
        setArchived: { try await SchoolWorkflowService.shared.setEventArchived(eventId: $0, archived: $1) }
    )
}

@MainActor
@Observable
final class EventCatalogModel {
    private let client: EventCatalogClient
    private var requestId = UUID()
    private var loadedSchoolId: UUID?
    private var canManage = false
    private var includesArchived = false

    private(set) var schools: [School] = []
    private(set) var events: [SchoolEvent] = []
    private(set) var members: [SchoolMember] = []
    private(set) var profilesById: [UUID: UserProfile] = [:]
    private(set) var phase: AsyncPhase = .idle
    private(set) var mutationError: String?

    init() {
        client = .live
    }

    init(client: EventCatalogClient) {
        self.client = client
    }

    func loadSchools() async {
        mutationError = nil
        do {
            schools = try await client.fetchSchools()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            mutationError = AppErrorMessage.school("Could not load schools", error)
        }
    }

    func load(schoolId: UUID, canManage: Bool, includeArchived: Bool) async {
        let currentRequestId = UUID()
        requestId = currentRequestId
        loadedSchoolId = schoolId
        self.canManage = canManage
        includesArchived = includeArchived
        mutationError = nil
        phase = events.isEmpty ? .loading : .loaded

        do {
            async let loadedEvents = client.fetchEvents(schoolId, includeArchived && canManage)
            async let loadedMembers: [SchoolMember] = canManage ? client.fetchMembers(schoolId) : []
            let (events, members) = try await (loadedEvents, loadedMembers)
            let profiles = try await client.fetchProfiles(events.compactMap(\.createdBy))
            guard requestId == currentRequestId, loadedSchoolId == schoolId else { return }
            self.events = events
            self.members = members
            profilesById = profiles
            phase = events.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            guard requestId == currentRequestId else { return }
            phase = .failed(AppErrorMessage.school("Could not load events", error))
        }
    }

    func reload() async {
        guard let loadedSchoolId else { return }
        await load(schoolId: loadedSchoolId, canManage: canManage, includeArchived: includesArchived)
    }

    func delete(_ event: SchoolEvent) async {
        await mutate(errorTitle: "Could not delete event") {
            try await client.deleteEvent(event.id)
        }
    }

    func setArchived(_ event: SchoolEvent, archived: Bool) async {
        await mutate(errorTitle: archived ? "Could not archive event" : "Could not restore event") {
            _ = try await client.setArchived(event.id, archived)
        }
    }

    func monthGroups(for events: [SchoolEvent]? = nil) -> [EventMonthGroup] {
        let events = events ?? self.events
        let grouped = Dictionary(grouping: events) { event in
            Calendar.current.date(
                from: Calendar.current.dateComponents([.year, .month], from: event.startAt)
            ) ?? event.startAt
        }
        return grouped.keys.sorted().map { month in
            EventMonthGroup(
                month: month,
                events: (grouped[month] ?? []).sorted { $0.startAt < $1.startAt }
            )
        }
    }

    private func mutate(errorTitle: String, operation: () async throws -> Void) async {
        mutationError = nil
        do {
            try await operation()
            await reload()
        } catch {
            mutationError = AppErrorMessage.school(errorTitle, error)
        }
    }
}
