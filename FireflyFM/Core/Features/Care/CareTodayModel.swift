import Foundation
import Observation

struct CareTodayScope: Equatable {
    let schoolId: UUID?
    let includesAllSchools: Bool
    let startDate: Date
    let endDate: Date
}

struct CareEventRecordRequest {
    let childId: UUID
    let type: ChildCareEventType
    let occurredAt: Date
    let details: [String: FireflyJSONValue]
    let isStaffOnly: Bool
    let medicationTaskId: UUID?
    let sourceMessageId: UUID?
    let developmentalDomains: [ChildDevelopmentalDomain]
    let reportHighlight: Bool
    let idempotencyKey: String
}

struct CareClient {
    var fetchChildren: (UUID) async throws -> [Child]
    var fetchAllChildren: () async throws -> [Child]
    var fetchEvents: (UUID, Date, Date) async throws -> [ChildCareEvent]
    var fetchEvent: (UUID) async throws -> ChildCareEvent
    var fetchMedicationTasks: (UUID, UUID) async throws -> [MedicationTask]
    var uploadMedia: (Data, String, String, UUID, UUID) async throws -> ChatAttachmentUploadResult
    var sendMediaMessage: (UUID, ChatAttachmentUploadResult) async throws -> ChatMessageModel
    var recordEvent: (CareEventRecordRequest) async throws -> ChildCareEvent
    var deleteMessage: (UUID) async throws -> Void
    var removePrivateFiles: ([String]) async throws -> Void
    var signedMediaURL: (String) async throws -> URL

    static let live = CareClient(
        fetchChildren: { try await SchoolWorkflowService.shared.fetchChildren(schoolId: $0) },
        fetchAllChildren: { try await SchoolWorkflowService.shared.fetchAllChildrenForHQ() },
        fetchEvents: {
            try await SchoolOperationsService.shared.fetchCareEvents(schoolId: $0, start: $1, end: $2)
        },
        fetchEvent: { try await SchoolOperationsService.shared.fetchCareEvent(id: $0) },
        fetchMedicationTasks: {
            try await SchoolWorkflowService.shared.fetchMedicationTasks(schoolId: $0, childId: $1)
        },
        uploadMedia: {
            try await ChatService.shared.uploadMediaAttachment(
                data: $0,
                fileName: $1,
                contentType: $2,
                schoolId: $3,
                roomId: $4
            )
        },
        sendMediaMessage: { roomId, upload in
            try await ChatService.shared.sendMessage(
                roomId: roomId,
                text: nil,
                mediaPath: upload.path,
                attachmentType: upload.type,
                attachmentName: upload.name,
                attachmentSize: upload.size
            )
        },
        recordEvent: { request in
            try await SchoolOperationsService.shared.recordCareEvent(
                childId: request.childId,
                type: request.type,
                occurredAt: request.occurredAt,
                details: request.details,
                isStaffOnly: request.isStaffOnly,
                medicationTaskId: request.medicationTaskId,
                sourceMessageId: request.sourceMessageId,
                developmentalDomains: request.developmentalDomains,
                reportHighlight: request.reportHighlight,
                idempotencyKey: request.idempotencyKey
            )
        },
        deleteMessage: { try await ChatService.shared.deleteMessage(id: $0) },
        removePrivateFiles: { try await SchoolService.shared.removePrivateFiles(paths: $0) },
        signedMediaURL: { try await SchoolService.shared.signedPrivateFileURL(path: $0) }
    )
}

@MainActor
@Observable
final class CareTodayModel {
    private let client: CareClient
    private var requestId = UUID()

    private(set) var children: [Child] = []
    private(set) var events: [ChildCareEvent] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var errorMessage: String?

    init() {
        client = .live
    }

    init(client: CareClient) {
        self.client = client
    }

    func load(scope: CareTodayScope) async {
        let currentRequestId = UUID()
        requestId = currentRequestId
        phase = .loading
        errorMessage = nil
        do {
            let loadedChildren: [Child]
            var loadedEvents: [ChildCareEvent]
            if scope.includesAllSchools {
                loadedChildren = try await client.fetchAllChildren()
                loadedEvents = []
                for schoolId in Set(loadedChildren.map(\.schoolId)) {
                    try Task.checkCancellation()
                    loadedEvents += try await client.fetchEvents(schoolId, scope.startDate, scope.endDate)
                }
                loadedEvents.sort { $0.occurredAt > $1.occurredAt }
            } else if let schoolId = scope.schoolId {
                async let children = client.fetchChildren(schoolId)
                async let events = client.fetchEvents(schoolId, scope.startDate, scope.endDate)
                (loadedChildren, loadedEvents) = try await (children, events)
            } else {
                loadedChildren = []
                loadedEvents = []
            }

            guard requestId == currentRequestId else { return }
            children = loadedChildren
            events = loadedEvents
            phase = loadedEvents.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            guard requestId == currentRequestId else { return }
            phase = .idle
        } catch {
            guard requestId == currentRequestId else { return }
            errorMessage = AppErrorMessage.school("Could not load today’s care", error)
            phase = .failed(errorMessage ?? "Could not load today’s care")
        }
    }
}
