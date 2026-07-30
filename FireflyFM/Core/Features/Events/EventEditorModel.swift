import Foundation
import Observation

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
        }
    )
}

@MainActor
@Observable
final class EventEditorModel {
    private let client: EventEditorClient

    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init() {
        client = .live
    }

    init(client: EventEditorClient) {
        self.client = client
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
