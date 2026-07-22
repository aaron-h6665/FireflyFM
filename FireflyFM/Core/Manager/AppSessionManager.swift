//
//  AppSessionManager.swift
//  FireflyFM
//

import Foundation
internal import Combine

enum BackendCompatibility: Equatable {
    case checking
    case compatible
    case updateRequired
    case unavailable(String)
}

@MainActor
final class AppSessionManager: ObservableObject {
    static let requiredSchemaVersion: Int64 = 20260722000000
    private static let legacyDefaultSchoolId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let defaults = UserDefaults.standard

    @Published private(set) var profile: UserProfile?
    @Published private(set) var memberships: [SchoolMembershipContext] = []
    @Published var activeMembershipId: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var backendCompatibility: BackendCompatibility = .checking

    var activeContext: SchoolMembershipContext? {
        if let activeMembershipId,
           let match = memberships.first(where: { $0.membership.id == activeMembershipId }) {
            return match
        }
        return memberships.first
    }

    var activeSchool: School? {
        activeContext?.school
    }

    var role: SchoolRole? {
        activeContext?.membership.role
    }

    var hasSchoolAccess: Bool {
        activeContext != nil
    }

    var canSwitchSchools: Bool {
        memberships.count > 1
    }

    func refresh(selecting preferredMembershipId: UUID? = nil) async {
        isLoading = true
        errorMessage = nil
        backendCompatibility = .checking

        do {
            let schemaVersion = try await SchoolService.shared.fetchSchemaVersion()
            guard schemaVersion >= Self.requiredSchemaVersion else {
                memberships = []
                activeMembershipId = nil
                backendCompatibility = .updateRequired
                isLoading = false
                return
            }
            backendCompatibility = .compatible
            let loadedProfile = try await ProfileService.shared.fetchCurrentProfile()
            profile = loadedProfile
            memberships = try await SchoolService.shared.fetchMembershipContexts()

            let storedId = defaults.string(forKey: activeMembershipKey(userId: loadedProfile.id))
                .flatMap(UUID.init(uuidString:))
            let requestedContext = preferredMembershipId.flatMap { requestedId in
                memberships.first(where: { $0.membership.id == requestedId })
            }
            let preferredContext = requestedContext ?? storedId.flatMap { storedId in
                memberships.first(where: { $0.membership.id == storedId })
            } ?? memberships.first(where: { $0.school.id != Self.legacyDefaultSchoolId })
                ?? memberships.first
            activeMembershipId = preferredContext?.membership.id
            persistActiveMembership()

            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            let message = AppErrorMessage.school("Could not load school access", error)
            let details = String(describing: error)
            if details.localizedCaseInsensitiveContains("get_firefly_schema_version")
                || details.localizedCaseInsensitiveContains("PGRST202") {
                backendCompatibility = .updateRequired
            } else {
                backendCompatibility = .unavailable(message)
                errorMessage = message
            }
            memberships = []
            activeMembershipId = nil
            isLoading = false
        }
    }

    func setActiveContext(_ context: SchoolMembershipContext) {
        switchActiveMembership(to: context.membership.id)
    }

    func switchActiveMembership(to membershipId: UUID) {
        guard memberships.contains(where: { $0.membership.id == membershipId }) else { return }
        guard activeMembershipId != membershipId else { return }
        activeMembershipId = membershipId
        persistActiveMembership()
        Task { await SignedMediaResolver.shared.clear() }
    }

    func clear() {
        profile = nil
        memberships = []
        activeMembershipId = nil
        errorMessage = nil
        backendCompatibility = .checking
        isLoading = false
        Task { await SignedMediaResolver.shared.clear() }
    }

    private func activeMembershipKey(userId: UUID) -> String {
        "fireflyfm.active-membership.\(userId.uuidString)"
    }

    private func persistActiveMembership() {
        guard let userId = profile?.id, let activeMembershipId else { return }
        defaults.set(activeMembershipId.uuidString, forKey: activeMembershipKey(userId: userId))
    }

#if DEBUG
    func configureForRoleMatrixSmokeTest(role: SchoolRole) {
        let userId = UUID(uuidString: "90000000-0000-0000-0000-000000000001")!
        let schoolId = UUID(uuidString: "90000000-0000-0000-0000-000000000002")!
        let membershipId = UUID(uuidString: "90000000-0000-0000-0000-000000000003")!
        let school = School(
            id: schoolId,
            name: "Firefly Test School",
            description: nil,
            tourUrl: nil,
            profileImageUrl: nil,
            createdAt: nil,
            updatedAt: nil
        )
        let membership = SchoolMembership(
            id: membershipId,
            schoolId: schoolId,
            userId: userId,
            role: role,
            active: true,
            accessState: "full",
            joinedAt: nil,
            createdAt: nil
        )
        profile = UserProfile(id: userId, displayName: "UI Test", avatarUrl: nil)
        memberships = [SchoolMembershipContext(school: school, membership: membership)]
        activeMembershipId = membershipId
        backendCompatibility = .compatible
        errorMessage = nil
        isLoading = false
    }
#endif
}
