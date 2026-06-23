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

        let schools: [School] = try await client.from("schools")
            .select()
            .in("id", values: schoolIds)
            .execute()
            .value

        let schoolsById = Dictionary(uniqueKeysWithValues: schools.map { ($0.id, $0) })
        return memberships.compactMap { membership in
            guard let school = schoolsById[membership.schoolId] else { return nil }
            return SchoolMembershipContext(school: school, membership: membership)
        }
        .sorted { $0.school.name < $1.school.name }
    }

    func fetchSchoolsForHQ() async throws -> [School] {
        try await client.from("schools")
            .select()
            .order("name", ascending: true)
            .execute()
            .value
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
        guard !trimmedEmail.isEmpty else { throw SchoolServiceError.invalidEmail }

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

    func joinSchool(code: String) async throws -> [SchoolMembershipContext] {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { throw SchoolServiceError.invalidCode }

        _ = try await client.rpc("join_school", params: JoinSchoolParams(inviteText: trimmedCode))
            .execute()

        return try await fetchMembershipContexts()
    }

    func acceptRoleInvite(token: String) async throws -> [SchoolMembershipContext] {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw SchoolServiceError.invalidCode }

        _ = try await client.rpc("accept_role_invite", params: AcceptRoleInviteParams(inviteToken: trimmedToken))
            .execute()

        return try await fetchMembershipContexts()
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

    func signedPrivateFileURL(path: String, expiresIn: Int = 300) async throws -> URL {
        try await client.storage
            .from("school_private_files")
            .createSignedURL(path: path, expiresIn: expiresIn)
    }

    func uploadPrivateFile(fileURL: URL, path: String) async throws -> SchoolFileUpload {
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

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
