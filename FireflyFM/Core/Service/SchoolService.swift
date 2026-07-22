//
//  SchoolService.swift
//  FireflyFM
//

import Foundation
import Supabase
import UniformTypeIdentifiers

final class SchoolService {
    static let shared = SchoolService()

    private let client = AppConstants.supabase

    private init() {}

    func fetchSchemaVersion() async throws -> Int64 {
        try await client.rpc("get_firefly_schema_version").execute().value
    }

    func fetchMembershipContexts() async throws -> [SchoolMembershipContext] {
        let user = try await client.auth.session.user

        let memberships: [SchoolMembership] = try await client.from("school_memberships")
            .select()
            .eq("user_id", value: user.id)
            .eq("active", value: true)
            .execute()
            .value

        let schoolIds = memberships.map(\.schoolId)
        guard !schoolIds.isEmpty else { return [] }

        let loadedSchools: [School] = try await client.from("schools")
            .select()
            .in("id", values: schoolIds)
            .execute()
            .value
        let schools = await resolveSchoolMedia(loadedSchools)

        let schoolsById = Dictionary(uniqueKeysWithValues: schools.map { ($0.id, $0) })
        let contexts: [SchoolMembershipContext] = memberships.compactMap { membership in
            guard let school = schoolsById[membership.schoolId] else { return nil }
            return SchoolMembershipContext(school: school, membership: membership)
        }
        .sorted { $0.school.name < $1.school.name }

        if contexts.isEmpty {
            throw SchoolAccessLoadError.membershipSchoolsNotVisible(membershipCount: memberships.count)
        }

        return contexts
    }

    func fetchSchoolsForHQ() async throws -> [School] {
        let schools: [School] = try await client.from("schools")
            .select()
            .order("name", ascending: true)
            .execute()
            .value
        return await resolveSchoolMedia(schools)
    }

    func updateSchool(
        schoolId: UUID,
        name: String,
        description: String? = nil,
        tourUrl: String? = nil,
        profileImageUrl: String?,
        profileImagePath: String?
    ) async throws -> School {
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTourUrl = tourUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        let update = SchoolUpdate(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: trimmedDescription?.isEmpty == true ? nil : trimmedDescription,
            tourUrl: trimmedTourUrl?.isEmpty == true ? nil : trimmedTourUrl,
            profileImageUrl: profileImageUrl,
            profileImagePath: profileImagePath,
            updatedAt: Date()
        )

        let schools: [School] = try await client.from("schools")
            .update(update)
            .eq("id", value: schoolId)
            .select()
            .execute()
            .value

        guard let school = schools.first else {
            throw SchoolServiceError.notFound
        }
        return await resolveSchoolMedia([school]).first ?? school
    }

    func uploadSchoolProfileImage(data: Data, schoolId: UUID) async throws -> String {
        try UploadPolicy.validate(data: data, fileName: "School profile image")
        let path = "schools/\(schoolId.uuidString)/school_assets/\(schoolId.uuidString)/\(UUID().uuidString).jpg"
        try await client.storage
            .from("school_private_files")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        return path
    }

    private func resolveSchoolMedia(_ schools: [School]) async -> [School] {
        var resolved: [School] = []
        for var school in schools {
            school.profileImageUrl = await SignedMediaResolver.shared.resolve(
                bucket: "school_private_files",
                path: school.profileImagePath,
                legacyURL: school.profileImageUrl
            )
            resolved.append(school)
        }
        return resolved
    }

    func archiveAndDeleteSchool(school: School, confirmationName: String) async throws -> UUID {
        let results: [SchoolDeletionArchiveResult] = try await client.rpc(
            "archive_and_delete_school",
            params: ArchiveAndDeleteSchoolParams(
                schoolId: school.id,
                confirmationName: confirmationName
            )
        )
        .execute()
        .value

        guard let archiveId = results.first?.archiveId else {
            throw SchoolServiceError.notFound
        }
        return archiveId
    }

    func createSchoolWithDirectorInvite(
        name: String,
        directorEmail: String,
        directorName: String?
    ) async throws -> SchoolCreationResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = directorEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedDirectorName = directorName?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else { throw SchoolServiceError.invalidSchoolName }
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            throw SchoolServiceError.invalidEmail
        }

        let results: [SchoolCreationResult] = try await client.rpc(
            "create_school_with_director_invite",
            params: CreateSchoolWithDirectorInviteParams(
                schoolName: trimmedName,
                directorEmail: trimmedEmail,
                directorName: trimmedDirectorName?.isEmpty == false ? trimmedDirectorName : nil
            )
        )
        .execute()
        .value

        guard let result = results.first else {
            throw SchoolServiceError.notFound
        }

        return result
    }

    func createSchoolForOnboarding(name: String) async throws -> School {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else { throw SchoolServiceError.invalidSchoolName }

        let schools: [School] = try await client.rpc(
            "create_school_for_onboarding",
            params: CreateSchoolForOnboardingParams(schoolName: trimmedName)
        )
        .execute()
        .value
        guard let school = schools.first else { throw SchoolServiceError.notFound }
        return school
    }

    func createDirectorInvite(
        schoolId: UUID,
        directorEmail: String,
        directorName: String?
    ) async throws -> SchoolCreationResult {
        let trimmedEmail = directorEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedName = directorName?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedEmail.contains("@") else { throw SchoolServiceError.invalidEmail }

        let results: [SchoolCreationResult] = try await client.rpc(
            "create_school_director_invite",
            params: CreateSchoolDirectorInviteParams(
                schoolId: schoolId,
                directorEmail: trimmedEmail,
                directorName: trimmedName?.isEmpty == false ? trimmedName : nil
            )
        )
        .execute()
        .value

        guard let result = results.first else {
            throw SchoolServiceError.notFound
        }
        return result
    }

    func createMemberRoleInvite(
        schoolId: UUID,
        email: String,
        displayName: String?,
        role: SchoolRole
    ) async throws -> RoleInvite {
        guard role == .parent || role == .teacher else { throw SchoolServiceError.invalidCode }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            throw SchoolServiceError.invalidEmail
        }
        let invites: [RoleInvite] = try await client.rpc(
            "create_member_role_invite",
            params: CreateMemberRoleInviteParams(
                schoolId: schoolId,
                email: normalizedEmail,
                displayName: displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
                role: role.rawValue
            )
        )
        .execute()
        .value
        guard let invite = invites.first else { throw SchoolServiceError.notFound }
        return invite
    }

    func fetchPendingDirectorInvites(schoolId: UUID) async throws -> [RoleInvite] {
        let invites: [RoleInvite] = try await client.from("role_invites")
            .select()
            .eq("school_id", value: schoolId)
            .eq("role", value: SchoolRole.schoolDirector.rawValue)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value

        return invites.filter { invite in
            guard let expiresAt = invite.expiresAt else { return true }
            return expiresAt > Date()
        }
    }

    func joinSchool(code: String) async throws -> SchoolMembership {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { throw SchoolServiceError.invalidCode }

        let memberships: [SchoolMembership] = try await client.rpc(
            "join_school",
            params: JoinSchoolParams(inviteText: trimmedCode)
        ).execute().value
        guard let membership = memberships.first else { throw SchoolServiceError.notFound }
        return membership
    }

    func previewRoleInvite(token: String) async throws -> RoleInvitePreview {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw SchoolServiceError.invalidCode }
        let previews: [RoleInvitePreview] = try await client.rpc(
            "preview_role_invite",
            params: AcceptRoleInviteParams(inviteToken: trimmedToken)
        ).execute().value
        guard let preview = previews.first else { throw SchoolServiceError.notFound }
        return preview
    }

    func acceptRoleInvite(token: String) async throws -> SchoolMembership {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw SchoolServiceError.invalidCode }

        let memberships: [SchoolMembership] = try await client.rpc(
            "accept_role_invite",
            params: AcceptRoleInviteParams(inviteToken: trimmedToken)
        ).execute().value
        guard let membership = memberships.first else { throw SchoolServiceError.notFound }
        return membership
    }

    func fetchInvites(schoolId: UUID) async throws -> [SchoolInvite] {
        let invites: [SchoolInvite] = try await client.from("school_invites")
            .select()
            .eq("school_id", value: schoolId)
            .eq("active", value: true)
            .order("created_at", ascending: false)
            .execute()
            .value

        return invites.filter { invite in
            guard let maxUses = invite.maxUses else { return true }
            return invite.useCount < maxUses
        }
    }

    func createInvite(schoolId: UUID, role: SchoolRole, maxUses: Int = 1) async throws -> SchoolInvite {
        let user = try await client.auth.session.user
        let invite = SchoolInvite(
            schoolId: schoolId,
            role: role,
            createdBy: user.id,
            maxUses: maxUses
        )

        let invites: [SchoolInvite] = try await client.from("school_invites")
            .insert(invite)
            .select()
            .execute()
            .value

        guard let createdInvite = invites.first else {
            throw SchoolServiceError.notFound
        }
        return createdInvite
    }

    func fetchMembers(schoolId: UUID, role: SchoolRole? = nil) async throws -> [SchoolMember] {
        var query = client.from("school_memberships")
            .select()
            .eq("school_id", value: schoolId)
            .eq("active", value: true)

        if let role {
            query = query.eq("role", value: role.rawValue)
        }

        let memberships: [SchoolMembership] = try await query
            .execute()
            .value

        let profilesById = try await ProfileService.shared.fetchProfiles(ids: memberships.map(\.userId))
        return memberships.map { membership in
            SchoolMember(membership: membership, profile: profilesById[membership.userId])
        }
    }

    func signedPrivateFileURL(path: String) async throws -> URL {
        try await SignedMediaResolver.shared.url(bucket: "school_private_files", path: path)
    }

    func removePrivateFiles(paths: [String]) async throws {
        guard paths.isEmpty == false else { return }
        _ = try await client.storage
            .from("school_private_files")
            .remove(paths: paths)
    }

    func uploadPrivateFile(fileURL: URL, path: String) async throws -> SchoolFileUpload {
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        try UploadPolicy.validate(fileURL: fileURL)
        let data = try Data(contentsOf: fileURL)
        let contentType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
        try await client.storage
            .from("school_private_files")
            .upload(path, data: data, options: FileOptions(contentType: contentType, upsert: true))

        return SchoolFileUpload(
            path: path,
            name: fileURL.lastPathComponent.isEmpty ? "Attachment" : fileURL.lastPathComponent,
            contentType: contentType,
            size: data.count
        )
    }

    func uploadPrivateData(data: Data, path: String, name: String, contentType: String?) async throws -> SchoolFileUpload {
        try UploadPolicy.validate(data: data, fileName: name.isEmpty ? "Attachment" : name)
        try await client.storage
            .from("school_private_files")
            .upload(path, data: data, options: FileOptions(contentType: contentType, upsert: true))

        return SchoolFileUpload(
            path: path,
            name: name.isEmpty ? "Attachment" : name,
            contentType: contentType,
            size: data.count
        )
    }

    func safeStorageFileName(for fileURL: URL) -> String {
        let rawName = fileURL.lastPathComponent.isEmpty ? "attachment" : fileURL.lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = rawName.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let joined = String(sanitized)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return joined.isEmpty ? "attachment-\(UUID().uuidString)" : joined
    }
}

enum SchoolAccessLoadError: LocalizedError {
    case membershipSchoolsNotVisible(membershipCount: Int)

    var errorDescription: String? {
        switch self {
        case .membershipSchoolsNotVisible(let membershipCount):
            return "Your account has \(membershipCount) active school membership row(s), but the matching school record could not be loaded. Check the schools table rows and school RLS policies."
        }
    }
}

enum SchoolServiceError: Error {
    case invalidCode
    case invalidEmail
    case invalidSchoolName
    case notFound
}

struct SchoolMember: Identifiable, Hashable {
    var id: UUID { membership.userId }
    var membership: SchoolMembership
    var profile: UserProfile?

    var displayName: String {
        profile?.displayName ?? "School Member"
    }
}

struct SchoolFileUpload: Hashable {
    let path: String
    let name: String
    let contentType: String?
    let size: Int
}

private struct SchoolUpdate: Encodable {
    let name: String
    let description: String?
    let tourUrl: String?
    let profileImageUrl: String?
    let profileImagePath: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case name, description
        case tourUrl = "tour_url"
        case profileImageUrl = "profile_image_url"
        case profileImagePath = "profile_image_path"
        case updatedAt = "updated_at"
    }
}

private struct JoinSchoolParams: Encodable {
    let inviteText: String

    enum CodingKeys: String, CodingKey {
        case inviteText = "invite_text"
    }
}

private struct AcceptRoleInviteParams: Encodable {
    let inviteToken: String

    enum CodingKeys: String, CodingKey {
        case inviteToken = "invite_token"
    }
}

private struct CreateSchoolWithDirectorInviteParams: Encodable {
    let schoolName: String
    let directorEmail: String
    let directorName: String?

    enum CodingKeys: String, CodingKey {
        case schoolName = "input_school_name"
        case directorEmail = "input_director_email"
        case directorName = "input_director_name"
    }
}

private struct CreateSchoolDirectorInviteParams: Encodable {
    let schoolId: UUID
    let directorEmail: String
    let directorName: String?

    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
        case directorEmail = "input_director_email"
        case directorName = "input_director_name"
    }
}

private struct CreateSchoolForOnboardingParams: Encodable {
    let schoolName: String

    enum CodingKeys: String, CodingKey {
        case schoolName = "input_school_name"
    }
}

private struct CreateMemberRoleInviteParams: Encodable {
    let schoolId: UUID
    let email: String
    let displayName: String?
    let role: String

    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
        case email = "input_email"
        case displayName = "input_display_name"
        case role = "input_role"
    }
}

private struct ArchiveAndDeleteSchoolParams: Encodable {
    let schoolId: UUID
    let confirmationName: String

    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
        case confirmationName = "confirmation_name"
    }
}

private struct SchoolDeletionArchiveResult: Decodable {
    let archiveId: UUID

    enum CodingKeys: String, CodingKey {
        case archiveId = "archive_id"
    }
}
