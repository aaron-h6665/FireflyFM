//
//  AppSessionManager.swift
//  FireflyFM
//

import Foundation
internal import Combine

@MainActor
final class AppSessionManager: ObservableObject {
    private static let legacyDefaultSchoolId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let defaults = UserDefaults.standard

    @Published private(set) var profile: UserProfile?
    @Published private(set) var memberships: [SchoolMembershipContext] = []
    @Published var activeMembershipId: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

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

    func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            let loadedProfile = try await ProfileService.shared.fetchCurrentProfile()
            profile = loadedProfile
            memberships = try await SchoolService.shared.fetchMembershipContexts()

            let storedId = defaults.string(forKey: activeMembershipKey(userId: loadedProfile.id))
                .flatMap(UUID.init(uuidString:))
            let preferredContext = storedId.flatMap { storedId in
                memberships.first(where: { $0.membership.id == storedId })
            } ?? memberships.first(where: { $0.school.id != Self.legacyDefaultSchoolId })
                ?? memberships.first
            activeMembershipId = preferredContext?.membership.id
            persistActiveMembership()

            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load school access", error)
            memberships = []
            activeMembershipId = nil
            isLoading = false
        }
    }

    func setActiveContext(_ context: SchoolMembershipContext) {
        activeMembershipId = context.membership.id
        persistActiveMembership()
    }

    func clear() {
        profile = nil
        memberships = []
        activeMembershipId = nil
        errorMessage = nil
        isLoading = false
    }

    private func activeMembershipKey(userId: UUID) -> String {
        "fireflyfm.active-membership.\(userId.uuidString)"
    }

    private func persistActiveMembership() {
        guard let userId = profile?.id, let activeMembershipId else { return }
        defaults.set(activeMembershipId.uuidString, forKey: activeMembershipKey(userId: userId))
    }
}
