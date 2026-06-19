//
//  AppSessionManager.swift
//  FireflyFM
//

import Foundation
internal import Combine

@MainActor
final class AppSessionManager: ObservableObject {
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
        memberships.contains { $0.membership.role == .hqDirector } && memberships.count > 1
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            profile = try await ProfileService.shared.fetchCurrentProfile()
            memberships = try await SchoolService.shared.fetchMembershipContexts()

            if let activeMembershipId,
               memberships.contains(where: { $0.membership.id == activeMembershipId }) == false {
                self.activeMembershipId = memberships.first?.membership.id
            } else if activeMembershipId == nil {
                activeMembershipId = memberships.first?.membership.id
            }

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
    }

    func clear() {
        profile = nil
        memberships = []
        activeMembershipId = nil
        errorMessage = nil
        isLoading = false
    }
}
