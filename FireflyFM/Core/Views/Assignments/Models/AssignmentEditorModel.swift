import Foundation
import Observation

struct AssignmentEditDraft {
    let assignment: Assignment
    let title: String
    let description: String?
    let dueAt: Date?
    let allowResubmission: Bool
    let materials: [AssignmentMaterialUpdate]
}

struct AssignmentEditorClient {
    var signedURL: (String) async throws -> URL
    var save: (AssignmentEditDraft) async throws -> Assignment

    static let live = AssignmentEditorClient(
        signedURL: { try await SchoolService.shared.signedPrivateFileURL(path: $0) },
        save: { draft in
            try await SchoolWorkflowService.shared.updateAssignment(
                assignment: draft.assignment,
                title: draft.title,
                description: draft.description,
                dueAt: draft.dueAt,
                allowResubmission: draft.allowResubmission,
                materials: draft.materials
            )
        }
    )
}

@MainActor
@Observable
final class AssignmentEditorModel {
    private let client: AssignmentEditorClient
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: AssignmentEditorClient) { self.client = client }

    func previewURL(path: String, preferredName: String) async -> URL? {
        do {
            let signedURL = try await client.signedURL(path)
            return try await AssignmentPreviewLoader.download(from: signedURL, preferredName: preferredName)
        } catch {
            errorMessage = AppErrorMessage.school("Could not preview material", error)
            return nil
        }
    }

    func save(_ draft: AssignmentEditDraft) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await client.save(draft)
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not edit assignment", error)
            return false
        }
    }
}
