import Foundation
import Observation

struct AssignmentDraft {
    let schoolId: UUID
    let title: String
    let description: String?
    let category: AssignmentCategory
    let audienceRole: SchoolRole?
    let childId: UUID?
    let dueAt: Date?
    let recipientIds: [UUID]
    let materialURLs: [String]
    let materialType: String
    let materialFileURLs: [URL]
    let status: String
    let publishAt: Date?
    let idempotencyKey: String
}

struct AssignmentComposerClient {
    var fetchMembers: (UUID) async throws -> [SchoolMember]
    var fetchChildren: (UUID) async throws -> [Child]
    var create: (AssignmentDraft) async throws -> Assignment

    static let live = AssignmentComposerClient(
        fetchMembers: { try await SchoolService.shared.fetchMembers(schoolId: $0) },
        fetchChildren: { try await SchoolWorkflowService.shared.fetchChildren(schoolId: $0) },
        create: { draft in
            try await SchoolWorkflowService.shared.createAssignment(
                schoolId: draft.schoolId,
                title: draft.title,
                description: draft.description,
                category: draft.category,
                audienceRole: draft.audienceRole,
                childId: draft.childId,
                dueAt: draft.dueAt,
                recipientIds: draft.recipientIds,
                materialURLs: draft.materialURLs,
                materialType: draft.materialType,
                materialFileURLs: draft.materialFileURLs,
                status: draft.status,
                publishAt: draft.publishAt,
                idempotencyKey: draft.idempotencyKey
            )
        }
    )
}

@MainActor
@Observable
final class AssignmentComposerModel {
    private let client: AssignmentComposerClient
    private var completedMutationKeys = Set<String>()
    private(set) var membersBySchool: [UUID: [SchoolMember]] = [:]
    private(set) var childrenBySchool: [UUID: [Child]] = [:]
    private(set) var phase: AsyncPhase = .idle
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: AssignmentComposerClient) { self.client = client }

    func load(schoolIds: [UUID]) async {
        phase = .loading
        errorMessage = nil
        do {
            var loadedMembers: [UUID: [SchoolMember]] = [:]
            var loadedChildren: [UUID: [Child]] = [:]
            for schoolId in Set(schoolIds) {
                async let members = client.fetchMembers(schoolId)
                async let children = client.fetchChildren(schoolId)
                loadedMembers[schoolId] = try await members
                loadedChildren[schoolId] = try await children
            }
            membersBySchool = loadedMembers
            childrenBySchool = loadedChildren
            phase = .loaded
        } catch where AppErrorMessage.isCancellation(error) { phase = .idle }
        catch {
            errorMessage = AppErrorMessage.school("Could not load assignment options", error)
            phase = .failed(errorMessage ?? "Could not load assignment options")
        }
    }

    func save(_ drafts: [AssignmentDraft]) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let pendingDrafts = drafts.filter { completedMutationKeys.contains($0.idempotencyKey) == false }
        var failures: [Error] = []
        for draft in pendingDrafts {
            do {
                _ = try await client.create(draft)
                completedMutationKeys.insert(draft.idempotencyKey)
            } catch {
                failures.append(error)
            }
        }

        guard failures.isEmpty else {
            let completedCount = drafts.filter { completedMutationKeys.contains($0.idempotencyKey) }.count
            let lastErrorMessage = failures.last.map { AppErrorMessage.school("Last error", $0) } ?? "Unknown error."
            if drafts.count > 1, completedCount > 0 {
                errorMessage = "Assignment created for \(completedCount) of \(drafts.count) schools. Try again to finish the remaining schools. \(lastErrorMessage)"
            } else {
                errorMessage = failures.last.map { AppErrorMessage.school("Could not create assignment", $0) }
            }
            return false
        }
        return true
    }
}
