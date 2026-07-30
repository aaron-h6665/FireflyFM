import Foundation
import Observation

struct AssignmentListClient {
    var fetchSchools: () async throws -> [School]
    var fetchInbox: ([AssignmentCategory]?, Bool) async throws -> [AssignmentInboxItem]
    var fetchReviewQueue: (UUID, [AssignmentCategory]?, Bool) async throws -> [AssignmentInboxItem]

    static let live = AssignmentListClient(
        fetchSchools: { try await SchoolService.shared.fetchSchoolsForHQ() },
        fetchInbox: { try await SchoolWorkflowService.shared.fetchAssignmentInbox(categories: $0, archived: $1) },
        fetchReviewQueue: {
            try await SchoolWorkflowService.shared.fetchAssignmentReviewQueue(
                schoolId: $0,
                categories: $1,
                archived: $2
            )
        }
    )
}

@MainActor
@Observable
final class AssignmentListModel {
    private let client: AssignmentListClient
    private var requestId = UUID()

    private(set) var schools: [School] = []
    private(set) var inboxItems: [AssignmentInboxItem] = []
    private(set) var reviewItems: [AssignmentInboxItem] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: AssignmentListClient) { self.client = client }

    func loadSchools() async {
        do { schools = try await client.fetchSchools() }
        catch where AppErrorMessage.isCancellation(error) { return }
        catch { errorMessage = AppErrorMessage.school("Could not load schools", error) }
    }

    func load(
        schoolId: UUID?,
        categories: [AssignmentCategory]?,
        archived: Bool,
        reviewOnly: Bool
    ) async {
        guard let schoolId else {
            inboxItems = []
            reviewItems = []
            phase = .empty
            return
        }
        let currentRequestId = UUID()
        requestId = currentRequestId
        phase = .loading
        errorMessage = nil
        do {
            let loadedInbox: [AssignmentInboxItem]
            let loadedReview: [AssignmentInboxItem]
            if reviewOnly {
                loadedInbox = []
                loadedReview = try await client.fetchReviewQueue(schoolId, categories, archived)
                    .filter { $0.submissionCount > 0 }
            } else {
                async let inbox = client.fetchInbox(categories, archived)
                async let review = client.fetchReviewQueue(schoolId, categories, archived)
                (loadedInbox, loadedReview) = try await (inbox, review)
            }
            guard requestId == currentRequestId else { return }
            inboxItems = loadedInbox
            reviewItems = loadedReview
            phase = loadedInbox.isEmpty && loadedReview.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            guard requestId == currentRequestId else { return }
            phase = .idle
        } catch {
            guard requestId == currentRequestId else { return }
            errorMessage = AppErrorMessage.school("Could not load assignments", error)
            phase = .failed(errorMessage ?? "Could not load assignments")
        }
    }
}
