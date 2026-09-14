import Foundation
import Observation

struct EventCreationDraft {
    let schoolId: UUID
    let title: String
    let description: String?
    let startAt: Date
    let endAt: Date
    let allDay: Bool
    let repeatRule: String?
    let invitedUserIds: [UUID]
    let idempotencyKey: String
}

struct EventEditorClient {
    var create: (
        UUID,
        String,
        String?,
        Date,
        Date,
        Bool,
        String?,
        [UUID]
    ) async throws -> Void
    var update: (
        UUID,
        String,
        String?,
        Date,
        Date,
        Bool,
        String?
    ) async throws -> Void
    var fetchMembers: (UUID) async throws -> [SchoolMember]

    static let live = EventEditorClient(
        create: { schoolId, title, description, startAt, endAt, allDay, repeatRule, invitedUserIds in
            try await SchoolWorkflowService.shared.createEvent(
                schoolId: schoolId,
                title: title,
                description: description,
                startAt: startAt,
                endAt: endAt,
                allDay: allDay,
                repeatRule: repeatRule,
                invitedUserIds: invitedUserIds
            )
        },
        update: { eventId, title, description, startAt, endAt, allDay, repeatRule in
            try await SchoolWorkflowService.shared.updateEvent(
                eventId: eventId,
                title: title,
                description: description,
                startAt: startAt,
                endAt: endAt,
                allDay: allDay,
                repeatRule: repeatRule
            )
        },
        fetchMembers: { schoolId in
            try await SchoolService.shared.fetchMembers(schoolId: schoolId)
        }
    )
}

@MainActor
@Observable
final class EventEditorModel {
    private let client: EventEditorClient
    private var completedMutationKeys = Set<String>()

    private(set) var membersBySchool: [UUID: [SchoolMember]] = [:]
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init() {
        client = .live
    }

    init(client: EventEditorClient) {
        self.client = client
    }

    func loadMembers(schoolIds: [UUID]) async {
        do {
            var loaded: [UUID: [SchoolMember]] = [:]
            for schoolId in Set(schoolIds) {
                loaded[schoolId] = try await client.fetchMembers(schoolId)
            }
            membersBySchool = loaded
        } catch where AppErrorMessage.isCancellation(error) {
        } catch {
            errorMessage = AppErrorMessage.school("Could not load members", error)
        }
    }

    func save(drafts: [EventCreationDraft]) async -> Bool {
        guard isSaving == false else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let pendingDrafts = drafts.filter { completedMutationKeys.contains($0.idempotencyKey) == false }
        var failures: [Error] = []

        for draft in pendingDrafts {
            do {
                try await client.create(
                    draft.schoolId,
                    draft.title,
                    draft.description,
                    draft.startAt,
                    draft.endAt,
                    draft.allDay,
                    draft.repeatRule,
                    draft.invitedUserIds
                )
                completedMutationKeys.insert(draft.idempotencyKey)
            } catch {
                failures.append(error)
            }
        }

        guard failures.isEmpty else {
            let completedCount = drafts.filter { completedMutationKeys.contains($0.idempotencyKey) }.count
            let lastErrorMessage = failures.last.map { AppErrorMessage.school("Last error", $0) } ?? "Unknown error."
            if drafts.count > 1, completedCount > 0 {
                errorMessage = "Event created for \(completedCount) of \(drafts.count) schools. Try again to finish the remaining schools. \(lastErrorMessage)"
            } else {
                errorMessage = failures.last.map { AppErrorMessage.school("Could not create event", $0) }
            }
            return false
        }
        return true
    }

    func save(
        schoolId: UUID,
        event: SchoolEvent?,
        title: String,
        description: String,
        startAt: Date,
        endAt: Date,
        allDay: Bool,
        repeatRule: String,
        invitedUserIds: [UUID]
    ) async -> Bool {
        guard isSaving == false else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let normalizedTitle = title.trimmed
        let normalizedDescription = description.nilIfBlank
        let normalizedRepeatRule = repeatRule == "none" ? nil : repeatRule

        do {
            if let event {
                try await client.update(
                    event.id,
                    normalizedTitle,
                    normalizedDescription,
                    startAt,
                    endAt,
                    allDay,
                    normalizedRepeatRule
                )
            } else {
                try await client.create(
                    schoolId,
                    normalizedTitle,
                    normalizedDescription,
                    startAt,
                    endAt,
                    allDay,
                    normalizedRepeatRule,
                    invitedUserIds
                )
            }
            return true
        } catch {
            errorMessage = AppErrorMessage.school(
                event == nil ? "Could not create event" : "Could not update event",
                error
            )
            return false
        }
    }
}
