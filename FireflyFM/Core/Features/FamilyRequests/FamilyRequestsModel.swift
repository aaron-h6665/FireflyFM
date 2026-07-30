import Foundation
import Observation

enum FamilyRequestWorkflowStatus: String {
    case acknowledged
    case completed
}

struct FamilyRequestSubmission {
    let childId: UUID
    let type: String
    let message: String
    let effectiveAt: Date
}

struct FamilyRequestsClient {
    var fetchChildren: (UUID) async throws -> [Child]
    var fetchRequests: (UUID) async throws -> [FamilyRequest]
    var updateStatus: (UUID, FamilyRequestWorkflowStatus) async throws -> FamilyRequest
    var submit: (FamilyRequestSubmission) async throws -> FamilyRequest

    static let live = FamilyRequestsClient(
        fetchChildren: { try await SchoolWorkflowService.shared.fetchChildren(schoolId: $0) },
        fetchRequests: { try await SchoolOperationsService.shared.fetchFamilyRequests(schoolId: $0, status: nil) },
        updateStatus: {
            try await SchoolOperationsService.shared.updateFamilyRequestStatus(requestId: $0, status: $1.rawValue)
        },
        submit: { request in
            try await SchoolOperationsService.shared.submitFamilyRequest(
                childId: request.childId,
                type: request.type,
                details: [
                    "message": .string(request.message),
                    "effective_at": .string(ISO8601DateFormatter().string(from: request.effectiveAt))
                ]
            )
        }
    )
}

@MainActor
@Observable
final class FamilyRequestsModel {
    private let client: FamilyRequestsClient
    private var schoolId: UUID?
    private var requestId = UUID()

    private(set) var requests: [FamilyRequest] = []
    private(set) var children: [Child] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var errorMessage: String?

    init() {
        client = .live
    }

    init(client: FamilyRequestsClient) {
        self.client = client
    }

    func load(schoolId: UUID?) async {
        self.schoolId = schoolId
        let currentRequestId = UUID()
        requestId = currentRequestId
        phase = .loading
        errorMessage = nil
        guard let schoolId else {
            children = []
            requests = []
            phase = .empty
            return
        }
        do {
            async let children = client.fetchChildren(schoolId)
            async let requests = client.fetchRequests(schoolId)
            let (loadedChildren, loadedRequests) = try await (children, requests)
            guard requestId == currentRequestId else { return }
            self.children = loadedChildren
            self.requests = loadedRequests
            phase = loadedRequests.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            guard requestId == currentRequestId else { return }
            phase = .idle
        } catch {
            guard requestId == currentRequestId else { return }
            errorMessage = AppErrorMessage.school("Could not load family requests", error)
            phase = .failed(errorMessage ?? "Could not load family requests")
        }
    }

    func child(id: UUID, schoolId: UUID) async throws -> Child? {
        try await client.fetchChildren(schoolId).first(where: { $0.id == id })
    }

    func update(_ request: FamilyRequest, status: FamilyRequestWorkflowStatus) async {
        do {
            _ = try await client.updateStatus(request.id, status)
            await load(schoolId: schoolId)
        } catch {
            errorMessage = AppErrorMessage.school("Could not update request", error)
        }
    }

    func submit(_ request: FamilyRequestSubmission) async throws {
        _ = try await client.submit(request)
    }
}
