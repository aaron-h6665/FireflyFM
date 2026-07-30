import Foundation
import Observation

struct NewsletterDraft {
    let schoolId: UUID
    let post: NewsletterPost?
    let title: String
    let body: String
    let retainedMedia: [NewsletterMedia]
    let newMedia: [NewsletterMediaUpload]
}

struct NewsletterComposerClient {
    var create: (NewsletterDraft) async throws -> Void
    var update: (NewsletterDraft) async throws -> Void

    static let live = NewsletterComposerClient(
        create: { draft in
            try await SchoolWorkflowService.shared.createNewsletter(
                schoolId: draft.schoolId,
                title: draft.title,
                body: draft.body,
                media: draft.newMedia
            )
        },
        update: { draft in
            guard let post = draft.post else { throw SchoolWorkflowError.notFound }
            try await SchoolWorkflowService.shared.updateNewsletter(
                post: post,
                title: draft.title,
                body: draft.body,
                retainedMedia: draft.retainedMedia,
                newMedia: draft.newMedia
            )
        }
    )
}

@MainActor
@Observable
final class NewsletterComposerModel {
    private let client: NewsletterComposerClient
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: NewsletterComposerClient) { self.client = client }

    func save(_ draft: NewsletterDraft) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if draft.post == nil { try await client.create(draft) }
            else { try await client.update(draft) }
            return true
        } catch {
            errorMessage = AppErrorMessage.school(
                draft.post == nil ? "Could not post newsletter" : "Could not update newsletter",
                error
            )
            return false
        }
    }
}
