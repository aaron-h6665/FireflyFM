import Foundation
import Observation

enum OnboardingManagementMode: Hashable {
    case hqDirector
    case schoolDirector

    var initialRole: SchoolRole { self == .hqDirector ? .schoolDirector : .parent }
    var availableRoles: [SchoolRole] { self == .hqDirector ? [.schoolDirector] : [.parent, .teacher] }
    var usesHQInvitationFlow: Bool { self == .hqDirector }
}

extension SchoolRole {
    var onboardingManagementTitle: String {
        switch self {
        case .schoolDirector: "School Director Onboarding"
        case .parent: "Parent Onboarding"
        case .teacher: "Teacher Onboarding"
        case .hqDirector: "Onboarding"
        }
    }

    var onboardingTemplateTitle: String {
        switch self {
        case .schoolDirector: "Director Template"
        case .parent: "Parent Template"
        case .teacher: "Teacher Template"
        case .hqDirector: "Template"
        }
    }

    var supportsChildSpecificOnboarding: Bool { self == .parent }
    var onboardingReviewerLabel: String {
        self == .schoolDirector ? "Reviewed by FireflyFM HQ" : "Reviewed by your school director"
    }
    var onboardingManagerReviewHelp: String {
        self == .schoolDirector
            ? "FireflyFM HQ reviews director work."
            : "The approved school director reviews parent and teacher work."
    }
}

struct OnboardingRequirementSaveRequest {
    let templateId: UUID
    let requirementId: UUID?
    let title: String
    let description: String?
    let subjectScope: OnboardingSubjectScope
    let position: Int
    let attachments: [OnboardingAttachmentDescriptor]
    let blocksAccess: Bool
    let childRecordBinding: ChildRequirementBinding
}

struct OnboardingAttachmentUploadRequest {
    let schoolId: UUID
    let templateId: UUID
    let editorId: UUID
    let fileURL: URL
}

struct OnboardingMemberInviteRequest {
    let schoolId: UUID
    let email: String
    let displayName: String
    let role: SchoolRole
}

struct OnboardingWorkflowClient {
    var fetchParentForm: (UUID) async throws -> GoogleFormConnection?
    var fetchForms: (UUID, SchoolRole) async throws -> [GoogleFormConnection]
    var fetchTemplate: (UUID, SchoolRole) async throws -> OnboardingTemplateBundle
    var fetchProgress: (UUID, SchoolRole) async throws -> OnboardingRoleProgress
    var ensureDraft: (UUID, SchoolRole) async throws -> OnboardingTemplate
    var saveRequirement: (OnboardingRequirementSaveRequest) async throws -> OnboardingTemplateRequirement
    var removeRequirement: (UUID) async throws -> Void
    var reorderRequirements: (UUID, [UUID]) async throws -> Void
    var publishTemplate: (UUID) async throws -> OnboardingTemplate
    var deleteDraft: (UUID) async throws -> Void
    var archiveTemplate: (UUID) async throws -> OnboardingTemplate
    var uploadAttachment: (OnboardingAttachmentUploadRequest) async throws -> OnboardingAttachmentDescriptor
    var removePrivateFiles: ([String]) async throws -> Void
    var fetchDashboard: (UUID) async throws -> [OnboardingDashboardItem]
    var createMemberInvite: (OnboardingMemberInviteRequest) async throws -> RoleInvite

    static let live = OnboardingWorkflowClient(
        fetchParentForm: { try await SchoolWorkflowService.shared.fetchParentGoogleFormConnection(schoolId: $0) },
        fetchForms: { try await SchoolWorkflowService.shared.fetchGoogleFormConnections(schoolId: $0, role: $1) },
        fetchTemplate: { try await SchoolWorkflowService.shared.fetchOnboardingTemplate(schoolId: $0, role: $1) },
        fetchProgress: { try await SchoolWorkflowService.shared.fetchOnboardingRoleProgress(schoolId: $0, role: $1) },
        ensureDraft: { try await SchoolWorkflowService.shared.ensureOnboardingTemplateDraft(schoolId: $0, role: $1) },
        saveRequirement: { request in
            try await SchoolWorkflowService.shared.saveOnboardingTemplateRequirement(
                templateId: request.templateId,
                requirementId: request.requirementId,
                title: request.title,
                description: request.description,
                subjectScope: request.subjectScope,
                position: request.position,
                attachments: request.attachments,
                blocksAccess: request.blocksAccess,
                childRecordBinding: request.childRecordBinding
            )
        },
        removeRequirement: { try await SchoolWorkflowService.shared.removeOnboardingTemplateRequirement(requirementId: $0) },
        reorderRequirements: {
            try await SchoolWorkflowService.shared.reorderOnboardingTemplateRequirements(templateId: $0, requirementIds: $1)
        },
        publishTemplate: { try await SchoolWorkflowService.shared.publishOnboardingTemplate(templateId: $0) },
        deleteDraft: { try await SchoolWorkflowService.shared.deleteOnboardingTemplateDraft(templateId: $0) },
        archiveTemplate: { try await SchoolWorkflowService.shared.archiveOnboardingTemplate(templateId: $0) },
        uploadAttachment: { request in
            try await SchoolWorkflowService.shared.uploadOnboardingTemplateAttachment(
                schoolId: request.schoolId,
                templateId: request.templateId,
                editorId: request.editorId,
                fileURL: request.fileURL
            )
        },
        removePrivateFiles: { try await SchoolService.shared.removePrivateFiles(paths: $0) },
        fetchDashboard: { try await SchoolWorkflowService.shared.fetchMyOnboardingDashboard(schoolId: $0) },
        createMemberInvite: { request in
            try await SchoolService.shared.createMemberRoleInvite(
                schoolId: request.schoolId,
                email: request.email,
                displayName: request.displayName,
                role: request.role
            )
        }
    )
}

@MainActor
@Observable
final class OnboardingManagementModel {
    private let client: OnboardingWorkflowClient
    private(set) var bundle = OnboardingTemplateBundle(template: nil, requirements: [], attachments: [])
    private(set) var progress = OnboardingRoleProgress.empty
    private(set) var parentFormConnected = false
    private(set) var formsByRole: [SchoolRole: [GoogleFormConnection]] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: OnboardingWorkflowClient) { self.client = client }

    func load(schoolId: UUID, role: SchoolRole) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let bundle = client.fetchTemplate(schoolId, role)
            async let progress = client.fetchProgress(schoolId, role)
            async let forms = client.fetchForms(schoolId, role)
            (self.bundle, self.progress, formsByRole[role]) = try await (bundle, progress, forms)
            parentFormConnected = formsByRole[.parent]?.isEmpty == false
        } catch where AppErrorMessage.isCancellation(error) {}
        catch { errorMessage = AppErrorMessage.school("Could not load onboarding", error) }
    }
}

struct DeletedOnboardingRequirement {
    let requirement: OnboardingTemplateRequirement
    let attachments: [OnboardingAttachmentDescriptor]
}

@MainActor
@Observable
final class OnboardingTemplateBuilderModel {
    private let client: OnboardingWorkflowClient
    private(set) var bundle = OnboardingTemplateBundle(template: nil, requirements: [], attachments: [])
    private(set) var lastDeleted: DeletedOnboardingRequirement?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: OnboardingWorkflowClient) { self.client = client }

    func load(schoolId: UUID, role: SchoolRole) async {
        isLoading = true
        defer { isLoading = false }
        do {
            bundle = try await client.fetchTemplate(schoolId, role)
            errorMessage = nil
        } catch where AppErrorMessage.isCancellation(error) {}
        catch { errorMessage = AppErrorMessage.school("Could not load template", error) }
    }

    func prepareDraft(schoolId: UUID, role: SchoolRole) async -> OnboardingTemplate? {
        isSaving = true
        defer { isSaving = false }
        do {
            let draft = try await client.ensureDraft(schoolId, role)
            await load(schoolId: schoolId, role: role)
            bundle.template = draft
            return draft
        } catch {
            errorMessage = AppErrorMessage.school("Could not prepare the template", error)
            return nil
        }
    }

    func mappedRequirement(_ original: OnboardingTemplateRequirement) -> OnboardingTemplateRequirement? {
        bundle.requirements.first { $0.id == original.id }
            ?? bundle.requirements.first { $0.position == original.position && $0.title == original.title }
    }

    func duplicate(_ original: OnboardingTemplateRequirement, schoolId: UUID, role: SchoolRole) async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await client.ensureDraft(schoolId, role)
            await load(schoolId: schoolId, role: role)
            guard let template = bundle.template else { return }
            let source = mappedRequirement(original) ?? original
            let attachments = bundle.attachments(for: source.id).map {
                OnboardingAttachmentDescriptor(
                    privateFilePath: $0.privateFilePath,
                    fileName: $0.fileName,
                    contentType: $0.contentType
                )
            }
            _ = try await client.saveRequirement(.init(
                templateId: template.id,
                requirementId: nil,
                title: "\(source.title) Copy",
                description: source.description,
                subjectScope: source.subjectScope,
                position: bundle.requirements.count,
                attachments: attachments,
                blocksAccess: source.blocksAccess,
                childRecordBinding: source.childRecordBinding
            ))
            await load(schoolId: schoolId, role: role)
        } catch { errorMessage = AppErrorMessage.school("Could not duplicate requirement", error) }
    }

    func remove(_ original: OnboardingTemplateRequirement, schoolId: UUID, role: SchoolRole) async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await client.ensureDraft(schoolId, role)
            await load(schoolId: schoolId, role: role)
            guard let mapped = mappedRequirement(original) else { return }
            lastDeleted = DeletedOnboardingRequirement(
                requirement: mapped,
                attachments: bundle.attachments(for: mapped.id).map {
                    OnboardingAttachmentDescriptor(
                        privateFilePath: $0.privateFilePath,
                        fileName: $0.fileName,
                        contentType: $0.contentType
                    )
                }
            )
            try await client.removeRequirement(mapped.id)
            await load(schoolId: schoolId, role: role)
        } catch { errorMessage = AppErrorMessage.school("Could not remove requirement", error) }
    }

    func undoDelete(schoolId: UUID, role: SchoolRole) async {
        guard let snapshot = lastDeleted, let template = bundle.template else { return }
        lastDeleted = nil
        do {
            let requirement = snapshot.requirement
            _ = try await client.saveRequirement(.init(
                templateId: template.id,
                requirementId: nil,
                title: requirement.title,
                description: requirement.description,
                subjectScope: requirement.subjectScope,
                position: bundle.requirements.count,
                attachments: snapshot.attachments,
                blocksAccess: requirement.blocksAccess,
                childRecordBinding: requirement.childRecordBinding
            ))
            await load(schoolId: schoolId, role: role)
        } catch { errorMessage = AppErrorMessage.school("Could not restore requirement", error) }
    }

    func reorder(_ requirements: [OnboardingTemplateRequirement], templateId: UUID, schoolId: UUID, role: SchoolRole) async {
        bundle.requirements = requirements.enumerated().map { index, value in
            var copy = value
            copy.position = index
            return copy
        }
        do { try await client.reorderRequirements(templateId, requirements.map(\.id)) }
        catch {
            errorMessage = AppErrorMessage.school("Could not reorder requirements", error)
            await load(schoolId: schoolId, role: role)
        }
    }

    func publish(templateId: UUID, schoolId: UUID, role: SchoolRole) async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await client.publishTemplate(templateId)
            await load(schoolId: schoolId, role: role)
        } catch { errorMessage = AppErrorMessage.school("Could not publish template", error) }
    }

    func removeTemplate(_ template: OnboardingTemplate, schoolId: UUID, role: SchoolRole) async {
        do {
            if template.status == .draft { try await client.deleteDraft(template.id) }
            else { _ = try await client.archiveTemplate(template.id) }
            await load(schoolId: schoolId, role: role)
        } catch { errorMessage = AppErrorMessage.school("Could not remove template", error) }
    }
}

@MainActor
@Observable
final class OnboardingRequirementEditorModel {
    private let client: OnboardingWorkflowClient
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: OnboardingWorkflowClient) { self.client = client }

    func save(
        request: OnboardingRequirementSaveRequest,
        schoolId: UUID,
        editorId: UUID,
        selectedFileURLs: [URL]
    ) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        var newlyUploaded: [OnboardingAttachmentDescriptor] = []
        do {
            var request = request
            for fileURL in selectedFileURLs {
                let uploaded = try await client.uploadAttachment(.init(
                    schoolId: schoolId,
                    templateId: request.templateId,
                    editorId: editorId,
                    fileURL: fileURL
                ))
                newlyUploaded.append(uploaded)
                request = .init(
                    templateId: request.templateId,
                    requirementId: request.requirementId,
                    title: request.title,
                    description: request.description,
                    subjectScope: request.subjectScope,
                    position: request.position,
                    attachments: request.attachments + [uploaded],
                    blocksAccess: request.blocksAccess,
                    childRecordBinding: request.childRecordBinding
                )
            }
            _ = try await client.saveRequirement(request)
            return true
        } catch {
            try? await client.removePrivateFiles(newlyUploaded.map(\.privateFilePath))
            errorMessage = AppErrorMessage.school("Could not save requirement", error)
            return false
        }
    }
}

@MainActor
@Observable
final class OnboardingAccessGateModel {
    private let client: OnboardingWorkflowClient
    private(set) var items: [OnboardingDashboardItem] = []
    private(set) var imports: [GoogleFormImport] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: OnboardingWorkflowClient) { self.client = client }

    func load(schoolId: UUID) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await client.fetchDashboard(schoolId)
            errorMessage = nil
            let completed = items.filter { ["approved", "waived"].contains($0.status) }.count
            return items.isEmpty == false && completed == items.count
        } catch where AppErrorMessage.isCancellation(error) { return false }
        catch {
            errorMessage = AppErrorMessage.school("Could not load setup", error)
            return false
        }
    }

    var latestImport: GoogleFormImport? {
        imports.first
    }

    func loadImports(schoolId: UUID) async {
        imports = (try? await SchoolWorkflowService.shared.fetchGoogleFormImports(schoolId: schoolId)) ?? []
    }
}

@MainActor
@Observable
final class OnboardingMemberInviteModel {
    private let client: OnboardingWorkflowClient
    private(set) var createdInvite: RoleInvite?
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: OnboardingWorkflowClient) { self.client = client }

    func create(_ request: OnboardingMemberInviteRequest) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            createdInvite = try await client.createMemberInvite(request)
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not create invitation", error)
            return false
        }
    }
}
