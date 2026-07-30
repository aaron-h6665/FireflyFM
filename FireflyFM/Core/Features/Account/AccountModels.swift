import Foundation
import Observation

extension SchoolRole {
    var inviteDisplayName: String {
        self == .hqDirector ? "HQ Director" : title
    }
}

struct ProfileClient {
    var currentUserId: () async throws -> UUID
    var fetchCurrent: () async throws -> UserProfile
    var fetch: (UUID) async throws -> UserProfile?
    var uploadAvatar: (Data) async throws -> String
    var save: (String, String?, String?) async throws -> UserProfile

    static let live = ProfileClient(
        currentUserId: { try await ProfileService.shared.currentUserId() },
        fetchCurrent: { try await ProfileService.shared.fetchCurrentProfile() },
        fetch: { try await ProfileService.shared.fetchProfile(id: $0) },
        uploadAvatar: { try await ProfileService.shared.uploadAvatar(data: $0) },
        save: {
            try await ProfileService.shared.upsertCurrentProfile(displayName: $0, avatarUrl: $1, avatarPath: $2)
        }
    )
}

@MainActor
@Observable
final class ProfileModel {
    private let client: ProfileClient
    private(set) var currentUserId: UUID?
    private(set) var profile: UserProfile?
    private(set) var phase: AsyncPhase = .idle
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: ProfileClient) { self.client = client }

    func load(profileUserId: UUID?) async {
        phase = .loading
        errorMessage = nil
        do {
            let myUserId = try await client.currentUserId()
            currentUserId = myUserId
            let targetId = profileUserId ?? myUserId
            if targetId == myUserId {
                profile = try await client.fetchCurrent()
            } else {
                profile = try await client.fetch(targetId)
                    ?? UserProfile(id: targetId, displayName: "Firefly User", avatarUrl: nil)
            }
            phase = .loaded
        } catch where AppErrorMessage.isCancellation(error) { phase = .idle }
        catch {
            errorMessage = AppErrorMessage.school("Could not load profile", error)
            phase = .failed(errorMessage ?? "Could not load profile")
        }
    }

    func showPhotoError(_ error: Error) {
        errorMessage = AppErrorMessage.school("Could not load photo", error)
    }

    func save(displayName: String, avatarData: Data?) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let avatarURL: String?
            let avatarPath: String?
            if let avatarData {
                avatarPath = try await client.uploadAvatar(avatarData)
                avatarURL = nil
            } else {
                avatarURL = profile?.avatarPath == nil ? profile?.avatarUrl : nil
                avatarPath = profile?.avatarPath
            }
            profile = try await client.save(displayName, avatarURL, avatarPath)
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not save profile", error)
            return false
        }
    }
}

struct SchoolInvitationClient {
    var previewRoleInvite: (String) async throws -> RoleInvitePreview
    var acceptRoleInvite: (String) async throws -> SchoolMembership
    var joinSchool: (String) async throws -> SchoolMembership

    static let live = SchoolInvitationClient(
        previewRoleInvite: { try await SchoolService.shared.previewRoleInvite(token: $0) },
        acceptRoleInvite: { try await SchoolService.shared.acceptRoleInvite(token: $0) },
        joinSchool: { try await SchoolService.shared.joinSchool(code: $0) }
    )
}

@MainActor
@Observable
final class InviteCoordinatorModel {
    private let client: SchoolInvitationClient
    private(set) var preview: RoleInvitePreview?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: SchoolInvitationClient) { self.client = client }

    func loadPreview(invite: PendingInvite) async {
        guard case .role(let token) = invite else { return }
        do { preview = try await client.previewRoleInvite(token) }
        catch { errorMessage = AppErrorMessage.school("Could not open invitation", error) }
    }

    func accept(invite: PendingInvite) async -> SchoolMembership? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            switch invite {
            case .role(let token): return try await client.acceptRoleInvite(token)
            case .school(let code): return try await client.joinSchool(code)
            }
        } catch {
            errorMessage = AppErrorMessage.school("Could not accept invitation", error)
            return nil
        }
    }
}

@MainActor
@Observable
final class SchoolWelcomeModel {
    private let client: SchoolInvitationClient
    private(set) var isJoining = false
    private(set) var isAcceptingRoleInvite = false
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: SchoolInvitationClient) { self.client = client }

    func join(code: String) async -> SchoolMembership? {
        isJoining = true
        errorMessage = nil
        defer { isJoining = false }
        do { return try await client.joinSchool(code) }
        catch {
            errorMessage = AppErrorMessage.school("Could not join school", error)
            return nil
        }
    }

    func acceptRoleInvite(token: String) async -> SchoolMembership? {
        isAcceptingRoleInvite = true
        errorMessage = nil
        defer { isAcceptingRoleInvite = false }
        do { return try await client.acceptRoleInvite(token) }
        catch {
            errorMessage = AppErrorMessage.school("Could not accept invitation", error)
            return nil
        }
    }
}
