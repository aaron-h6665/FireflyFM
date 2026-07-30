import Foundation
import Observation

struct AssignmentSubmissionDraft {
    let assignment: Assignment
    let fileURLs: [URL]
    let feedbackText: String
    let idempotencyKey: String
    let structuredPayload: [String: FireflyJSONValue]
}

struct AssignmentReviewDraft {
    let submissionId: UUID
    let status: String
    let message: String?
    let score: Int?
    let idempotencyKey: String
}

struct AssignmentCommentDraft {
    let assignmentId: UUID
    let recipientId: UUID
    let body: String
    let idempotencyKey: String
}

struct AssignmentScoreUpdate {
    let submissionId: UUID
    let score: Int?
    let idempotencyKey: String
}

struct AssignmentDetailClient {
    var fetch: (UUID) async throws -> AssignmentDetailBundle
    var fetchChildBinding: (UUID) async throws -> ChildRequirementBinding
    var fetchProfiles: ([UUID]) async throws -> [UUID: UserProfile]
    var markViewed: (UUID) async throws -> Void
    var acknowledge: (UUID) async throws -> Void
    var submit: (AssignmentSubmissionDraft) async throws -> Void
    var review: (AssignmentReviewDraft) async throws -> Void
    var waive: (UUID, String) async throws -> Void
    var postComment: (AssignmentCommentDraft) async throws -> Void
    var updateScore: (AssignmentScoreUpdate) async throws -> Void
    var setStatus: (UUID, String) async throws -> Void
    var signedURL: (String) async throws -> URL

    static let live = AssignmentDetailClient(
        fetch: { try await SchoolWorkflowService.shared.fetchAssignmentDetail(assignmentId: $0) },
        fetchChildBinding: { try await SchoolWorkflowService.shared.fetchAssignmentChildBinding(assignmentId: $0) },
        fetchProfiles: { try await ProfileService.shared.fetchProfiles(ids: $0) },
        markViewed: { try await SchoolWorkflowService.shared.markAssignmentViewed(assignmentId: $0) },
        acknowledge: { try await SchoolWorkflowService.shared.acknowledgeAssignment(assignmentId: $0) },
        submit: { draft in
            _ = try await SchoolWorkflowService.shared.submitAssignment(
                assignment: draft.assignment,
                fileURLs: draft.fileURLs,
                feedbackText: draft.feedbackText,
                idempotencyKey: draft.idempotencyKey,
                structuredPayload: draft.structuredPayload
            )
        },
        review: { draft in
            _ = try await SchoolWorkflowService.shared.reviewAssignmentSubmission(
                submissionId: draft.submissionId,
                status: draft.status,
                message: draft.message,
                score: draft.score,
                idempotencyKey: draft.idempotencyKey
            )
        },
        waive: { try await SchoolWorkflowService.shared.waiveOnboardingAssignment(assignmentId: $0, reason: $1) },
        postComment: { draft in
            _ = try await SchoolWorkflowService.shared.postAssignmentComment(
                assignmentId: draft.assignmentId,
                recipientId: draft.recipientId,
                body: draft.body,
                idempotencyKey: draft.idempotencyKey
            )
        },
        updateScore: { update in
            _ = try await SchoolWorkflowService.shared.updateAssignmentSubmissionScore(
                submissionId: update.submissionId,
                score: update.score,
                idempotencyKey: update.idempotencyKey
            )
        },
        setStatus: { assignmentId, status in
            _ = try await SchoolWorkflowService.shared.setAssignmentStatus(assignmentId: assignmentId, status: status)
        },
        signedURL: { try await SchoolService.shared.signedPrivateFileURL(path: $0) }
    )
}

@MainActor
@Observable
final class AssignmentDetailModel {
    private let client: AssignmentDetailClient
    private var hasMarkedViewed = false
    private var requestId = UUID()

    private(set) var bundle: AssignmentDetailBundle?
    private(set) var profilesById: [UUID: UserProfile] = [:]
    private(set) var currentUserId: UUID?
    private(set) var childRequirementBinding: ChildRequirementBinding = .none
    private(set) var phase: AsyncPhase = .idle
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var didMarkViewedOnLastLoad = false

    init() { client = .live }
    init(client: AssignmentDetailClient) { self.client = client }

    func load(assignmentId: UUID) async {
        let currentRequestId = UUID()
        requestId = currentRequestId
        phase = .loading
        errorMessage = nil
        didMarkViewedOnLastLoad = false
        do {
            async let loadedBundle = client.fetch(assignmentId)
            async let loadedBinding = client.fetchChildBinding(assignmentId)
            var bundle = try await loadedBundle
            let binding = try await loadedBinding
            currentUserId = bundle.capabilities.userId
            if bundle.capabilities.isRecipient, hasMarkedViewed == false {
                hasMarkedViewed = true
                do {
                    try await client.markViewed(assignmentId)
                    didMarkViewedOnLastLoad = true
                    bundle = try await client.fetch(assignmentId)
                } catch where AppErrorMessage.isCancellation(error) {
                    phase = .idle
                    return
                } catch {
                    errorMessage = AppErrorMessage.school(
                        "Assignment opened, but its unread state could not be cleared",
                        error
                    )
                }
            }
            let profileIds = Set(
                bundle.recipients.map(\.userId)
                    + bundle.submissions.map(\.submittedBy)
                    + bundle.submissions.compactMap(\.reviewedBy)
                    + bundle.feedbackMessages.map(\.senderId)
                    + bundle.feedbackMessages.compactMap(\.recipientId)
                    + bundle.events.compactMap(\.actorId)
                    + [bundle.assignment.assignedBy].compactMap { $0 }
            )
            let profiles = try await client.fetchProfiles(Array(profileIds))
            guard requestId == currentRequestId else { return }
            self.bundle = bundle
            childRequirementBinding = binding
            profilesById = profiles
            phase = .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            guard requestId == currentRequestId else { return }
            phase = .idle
        } catch {
            guard requestId == currentRequestId else { return }
            errorMessage = AppErrorMessage.school("Could not load assignment", error)
            phase = .failed(errorMessage ?? "Could not load assignment")
        }
    }

    func acknowledge(assignmentId: UUID) async -> Bool {
        await mutate("Could not mark assignment read", assignmentId: assignmentId) {
            try await client.acknowledge(assignmentId)
        }
    }

    func submit(_ draft: AssignmentSubmissionDraft, assignmentId: UUID) async -> Bool {
        await mutate("Could not submit assignment", assignmentId: assignmentId) {
            try await client.submit(draft)
        }
    }

    func review(_ draft: AssignmentReviewDraft, assignmentId: UUID) async -> Bool {
        await mutate("Could not review assignment", assignmentId: assignmentId) {
            try await client.review(draft)
        }
    }

    func waive(assignmentId: UUID, reason: String) async -> Bool {
        await mutate("Could not waive requirement", assignmentId: assignmentId) {
            try await client.waive(assignmentId, reason)
        }
    }

    func postComment(_ draft: AssignmentCommentDraft) async -> Bool {
        await mutate("Could not send comment", assignmentId: draft.assignmentId) {
            try await client.postComment(draft)
        }
    }

    func updateScore(_ update: AssignmentScoreUpdate, assignmentId: UUID) async -> Bool {
        await mutate("Could not update score", assignmentId: assignmentId) {
            try await client.updateScore(update)
        }
    }

    func setStatus(assignmentId: UUID, status: String) async -> Bool {
        await mutate("Could not update assignment status", assignmentId: assignmentId) {
            try await client.setStatus(assignmentId, status)
        }
    }

    func previewURL(path: String, preferredName: String) async -> URL? {
        do {
            let signedURL = try await client.signedURL(path)
            return try await AssignmentPreviewLoader.download(from: signedURL, preferredName: preferredName)
        } catch {
            errorMessage = AppErrorMessage.school("Could not open file", error)
            return nil
        }
    }

    func showError(_ message: String) {
        errorMessage = message
    }

    private func mutate(
        _ failureTitle: String,
        assignmentId: UUID,
        operation: () async throws -> Void
    ) async -> Bool {
        isSaving = true
        errorMessage = nil
        do {
            try await operation()
            isSaving = false
            await load(assignmentId: assignmentId)
            return true
        } catch {
            isSaving = false
            errorMessage = AppErrorMessage.school(failureTitle, error)
            return false
        }
    }
}
