import Foundation
import Observation

struct SchoolDirectorTodayClient {
    var fetchRoster: (UUID) async throws -> [ChildRosterItem]
    var fetchReviewQueue: (UUID) async throws -> [AssignmentInboxItem]

    static let live = SchoolDirectorTodayClient(
        fetchRoster: { schoolId in
            try await SchoolWorkflowService.shared.fetchChildRoster(schoolId: schoolId)
        },
        fetchReviewQueue: { schoolId in
            try await SchoolWorkflowService.shared.fetchAssignmentReviewQueue(schoolId: schoolId)
        }
    )
}

@MainActor
@Observable
final class SchoolDirectorTodayModel {
    private let client: SchoolDirectorTodayClient
    private var requestId = UUID()

    private(set) var roster: [ChildRosterItem] = []
    private(set) var reviewItems: [AssignmentInboxItem] = []
    private(set) var phase: AsyncPhase = .idle

    init() {
        client = .live
    }

    init(client: SchoolDirectorTodayClient) {
        self.client = client
    }

    var checkedInCount: Int { roster.filter(\.isCheckedIn).count }

    func load(schoolId: UUID) async {
        let currentRequestId = UUID()
        requestId = currentRequestId
        phase = .loading

        do {
            async let roster = client.fetchRoster(schoolId)
            async let reviews = client.fetchReviewQueue(schoolId)
            let (loadedRoster, loadedReviews) = try await (roster, reviews)
            guard requestId == currentRequestId else { return }

            self.roster = loadedRoster
            reviewItems = loadedReviews
            phase = .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            guard requestId == currentRequestId else { return }
            phase = .failed(AppErrorMessage.school("Could not load today’s school summary", error))
        }
    }

    func cancelLoading() {
        requestId = UUID()
    }
}
