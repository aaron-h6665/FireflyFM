import Foundation

struct ChildConnectionSubmission {
    let schoolId: UUID
    let legalFirstName: String
    let legalLastName: String
    let birthdate: Date
    let relationship: String
}

struct ChildConnectionDecision {
    let requestId: UUID
    let approved: Bool
    let matchedChildId: UUID?
    let note: String
}

struct ChildIdentityUpdate {
    let childId: UUID
    let firstName: String
    let lastName: String
    let birthdate: Date
}

struct ChildrenWorkflowClient {
    var submitConnection: (ChildConnectionSubmission) async throws -> ChildConnectionRequest
    var fetchConnections: (UUID, ChildConnectionStatus?) async throws -> [ChildConnectionRequest]
    var fetchChildren: (UUID) async throws -> [Child]
    var reviewConnection: (ChildConnectionDecision) async throws -> ChildConnectionRequest
    var updateIdentity: (ChildIdentityUpdate) async throws -> Child

    static let live = ChildrenWorkflowClient(
        submitConnection: { request in
            try await SchoolOperationsService.shared.submitConnectionRequest(
                schoolId: request.schoolId,
                legalFirstName: request.legalFirstName,
                legalLastName: request.legalLastName,
                birthdate: request.birthdate,
                relationship: request.relationship
            )
        },
        fetchConnections: {
            try await SchoolOperationsService.shared.fetchConnectionRequests(schoolId: $0, status: $1)
        },
        fetchChildren: { try await SchoolWorkflowService.shared.fetchChildren(schoolId: $0) },
        reviewConnection: { decision in
            try await SchoolOperationsService.shared.reviewConnectionRequest(
                requestId: decision.requestId,
                approved: decision.approved,
                matchedChildId: decision.matchedChildId,
                note: decision.note
            )
        },
        updateIdentity: { update in
            try await SchoolWorkflowService.shared.updateChild(
                childId: update.childId,
                firstName: update.firstName,
                lastName: update.lastName,
                birthdate: update.birthdate
            )
        }
    )
}
