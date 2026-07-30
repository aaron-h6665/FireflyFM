import Foundation
import Observation

struct HQSchoolsClient {
    var fetchSchools: () async throws -> [School]
    var fetchNewsletters: (UUID) async throws -> [NewsletterPost]

    static let live = HQSchoolsClient(
        fetchSchools: { try await SchoolService.shared.fetchSchoolsForHQ() },
        fetchNewsletters: { try await SchoolWorkflowService.shared.fetchNewsletters(schoolId: $0) }
    )
}

@MainActor
@Observable
final class HQSchoolsModel {
    private let client: HQSchoolsClient
    private(set) var schools: [School] = []
    private(set) var newsletters: [NewsletterPost] = []
    private(set) var newsletterSchoolNames: [UUID: String] = [:]
    private(set) var phase: AsyncPhase = .idle
    private(set) var isLoadingNewsletters = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: HQSchoolsClient) { self.client = client }

    func load() async {
        phase = .loading
        isLoadingNewsletters = true
        errorMessage = nil
        do {
            let schools = try await client.fetchSchools()
            self.schools = schools
            newsletterSchoolNames = Dictionary(uniqueKeysWithValues: schools.map { ($0.id, $0.name) })
            phase = schools.isEmpty ? .empty : .loaded
            newsletters = await withTaskGroup(of: [NewsletterPost].self) { group in
                for school in schools {
                    group.addTask { (try? await self.client.fetchNewsletters(school.id)) ?? [] }
                }
                var combined: [NewsletterPost] = []
                for await posts in group { combined.append(contentsOf: posts.prefix(3)) }
                return combined.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            }
            isLoadingNewsletters = false
        } catch where AppErrorMessage.isCancellation(error) {
            phase = .idle
            isLoadingNewsletters = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load schools", error)
            phase = .failed(errorMessage ?? "Could not load schools")
            isLoadingNewsletters = false
        }
    }

    func replace(_ school: School) {
        guard let index = schools.firstIndex(where: { $0.id == school.id }) else { return }
        schools[index] = school
    }
}

struct HQSchoolOperationsClient {
    var fetchMembers: (UUID) async throws -> [SchoolMember]
    var fetchDirectorInvites: (UUID) async throws -> [RoleInvite]
    var fetchRoster: (UUID) async throws -> [ChildRosterItem]
    var fetchDirectorTemplate: (UUID) async throws -> OnboardingTemplateBundle
    var fetchDirectorProgress: (UUID) async throws -> OnboardingRoleProgress
    var cancelInvite: (UUID) async throws -> Void

    static let live = HQSchoolOperationsClient(
        fetchMembers: { try await SchoolService.shared.fetchMembers(schoolId: $0) },
        fetchDirectorInvites: { try await SchoolService.shared.fetchPendingDirectorInvites(schoolId: $0) },
        fetchRoster: { try await SchoolWorkflowService.shared.fetchChildRoster(schoolId: $0) },
        fetchDirectorTemplate: {
            try await SchoolWorkflowService.shared.fetchOnboardingTemplate(schoolId: $0, role: .schoolDirector)
        },
        fetchDirectorProgress: {
            try await SchoolWorkflowService.shared.fetchOnboardingRoleProgress(schoolId: $0, role: .schoolDirector)
        },
        cancelInvite: { try await SchoolService.shared.cancelDirectorInvite(inviteId: $0) }
    )
}

@MainActor
@Observable
final class HQSchoolOperationsModel {
    private let client: HQSchoolOperationsClient
    private(set) var members: [SchoolMember] = []
    private(set) var pendingDirectorInvites: [RoleInvite] = []
    private(set) var roster: [ChildRosterItem] = []
    private(set) var directorTemplate = OnboardingTemplateBundle(template: nil, requirements: [], attachments: [])
    private(set) var directorProgress = OnboardingRoleProgress.empty
    private(set) var phase: AsyncPhase = .idle
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: HQSchoolOperationsClient) { self.client = client }

    var directors: [SchoolMember] {
        members
            .filter { $0.membership.role == .schoolDirector }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func load(schoolId: UUID) async {
        phase = .loading
        errorMessage = nil
        do {
            async let members = client.fetchMembers(schoolId)
            async let invites = client.fetchDirectorInvites(schoolId)
            async let roster = client.fetchRoster(schoolId)
            async let template = client.fetchDirectorTemplate(schoolId)
            async let progress = client.fetchDirectorProgress(schoolId)
            (self.members, pendingDirectorInvites, self.roster, directorTemplate, directorProgress) = try await (
                members, invites, roster, template, progress
            )
            phase = .loaded
        } catch where AppErrorMessage.isCancellation(error) { phase = .idle }
        catch {
            errorMessage = AppErrorMessage.school("Could not load school operations", error)
            phase = .failed(errorMessage ?? "Could not load school operations")
        }
    }

    func cancel(inviteId: UUID, schoolId: UUID) async {
        do {
            try await client.cancelInvite(inviteId)
            await load(schoolId: schoolId)
        } catch { errorMessage = AppErrorMessage.school("Could not cancel director invitation", error) }
    }
}

struct HQSchoolUpdateRequest {
    let schoolId: UUID
    let name: String
    let description: String
    let tourURL: String?
    let profileImageURL: String?
    let profileImagePath: String?
}

struct HQEventPushRequest {
    let schoolId: UUID
    let title: String
    let description: String?
    let startAt: Date
    let endAt: Date
    let allDay: Bool
}

struct HQSchoolWorkflowClient {
    var createDirectorInvite: (UUID, String, String) async throws -> SchoolCreationResult
    var uploadSchoolImage: (Data, UUID) async throws -> String
    var updateSchool: (HQSchoolUpdateRequest) async throws -> School
    var archiveAndDelete: (School, String) async throws -> UUID
    var createSchool: (String) async throws -> School
    var createEvent: (HQEventPushRequest) async throws -> Void

    static let live = HQSchoolWorkflowClient(
        createDirectorInvite: {
            try await SchoolService.shared.createDirectorInvite(schoolId: $0, directorEmail: $1, directorName: $2)
        },
        uploadSchoolImage: { try await SchoolService.shared.uploadSchoolProfileImage(data: $0, schoolId: $1) },
        updateSchool: { request in
            try await SchoolService.shared.updateSchool(
                schoolId: request.schoolId,
                name: request.name,
                description: request.description,
                tourUrl: request.tourURL,
                profileImageUrl: request.profileImageURL,
                profileImagePath: request.profileImagePath
            )
        },
        archiveAndDelete: { try await SchoolService.shared.archiveAndDeleteSchool(school: $0, confirmationName: $1) },
        createSchool: { try await SchoolService.shared.createSchoolForOnboarding(name: $0) },
        createEvent: { request in
            try await SchoolWorkflowService.shared.createEvent(
                schoolId: request.schoolId,
                title: request.title,
                description: request.description,
                startAt: request.startAt,
                endAt: request.endAt,
                allDay: request.allDay
            )
        }
    )
}
