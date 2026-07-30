import Foundation
import Observation

struct NewsletterListClient {
    var fetch: (UUID) async throws -> [NewsletterPost]
    var delete: (NewsletterPost) async throws -> Void

    static let live = NewsletterListClient(
        fetch: { schoolId in
            try await SchoolWorkflowService.shared.fetchNewsletters(schoolId: schoolId)
        },
        delete: { post in
            try await SchoolWorkflowService.shared.deleteNewsletter(post)
        }
    )
}

@MainActor
@Observable
final class NewsletterListModel {
    private let client: NewsletterListClient
    private var requestId = UUID()

    private(set) var posts: [NewsletterPost] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var deletingPostId: UUID?

    init() {
        client = .live
    }

    init(client: NewsletterListClient) {
        self.client = client
    }

    func load(schoolId: UUID) async {
        let currentRequestId = UUID()
        requestId = currentRequestId
        phase = posts.isEmpty ? .loading : .loaded

        do {
            let loaded = try await client.fetch(schoolId)
            guard requestId == currentRequestId else { return }
            posts = loaded
            phase = loaded.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            guard requestId == currentRequestId else { return }
            phase = .failed(AppErrorMessage.school("Could not load newsletters", error))
        }
    }

    func delete(_ post: NewsletterPost) async -> Bool {
        guard deletingPostId == nil else { return false }
        deletingPostId = post.id
        defer { deletingPostId = nil }

        do {
            try await client.delete(post)
            posts.removeAll { $0.id == post.id }
            phase = posts.isEmpty ? .empty : .loaded
            return true
        } catch {
            phase = .failed(AppErrorMessage.school("Could not delete newsletter", error))
            return false
        }
    }

    func cancelLoading() {
        requestId = UUID()
    }
}
