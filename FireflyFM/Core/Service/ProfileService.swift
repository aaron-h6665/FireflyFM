//
//  ProfileService.swift
//  FireflyFM
//

import Foundation
import Supabase

final class ProfileService {
    static let shared = ProfileService()

    private let client = AppConstants.supabase

    private init() {}

    func currentUserId() async throws -> UUID {
        try await client.auth.session.user.id
    }

    func fetchCurrentProfile() async throws -> UserProfile {
        let user = try await client.auth.session.user
        if let profile = try await fetchProfile(id: user.id) {
            return profile
        }

        let fallbackName = displayName(from: user) ?? "Firefly User"
        try await upsertProfile(id: user.id, displayName: fallbackName, avatarUrl: nil)
        return UserProfile(id: user.id, displayName: fallbackName, avatarUrl: nil, createdAt: nil, updatedAt: nil)
    }

    func fetchProfile(id: UUID) async throws -> UserProfile? {
        let profiles: [UserProfile] = try await client.from("profiles")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value

        return profiles.first
    }

    func fetchProfiles(ids: [UUID]) async throws -> [UUID: UserProfile] {
        let uniqueIds = Array(Set(ids))
        guard !uniqueIds.isEmpty else { return [:] }

        let profiles: [UserProfile] = try await client.from("profiles")
            .select()
            .in("id", values: uniqueIds)
            .execute()
            .value

        return Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }

    func searchProfiles(query: String, excluding idsToExclude: [UUID] = []) async throws -> [UserProfile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let profiles: [UserProfile] = try await client.from("profiles")
            .select()
            .ilike("display_name", pattern: "%\(trimmed)%")
            .order("display_name", ascending: true)
            .limit(20)
            .execute()
            .value

        let excluded = Set(idsToExclude)
        return profiles.filter { !excluded.contains($0.id) }
    }

    func upsertCurrentProfile(displayName: String, avatarUrl: String?) async throws -> UserProfile {
        let user = try await client.auth.session.user
        try await upsertProfile(id: user.id, displayName: displayName, avatarUrl: avatarUrl)

        let metadata: [String: AnyJSON] = [
            "display_name": .string(displayName),
            "avatar_url": avatarUrl.map { .string($0) } ?? .null
        ]
        _ = try? await client.auth.update(user: UserAttributes(data: metadata))

        return try await fetchProfile(id: user.id) ?? UserProfile(id: user.id, displayName: displayName, avatarUrl: avatarUrl)
    }

    func upsertProfile(id: UUID, displayName: String, avatarUrl: String?) async throws {
        let profile = ProfileUpsert(
            id: id,
            displayName: displayName,
            avatarUrl: avatarUrl,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        try await client.from("profiles")
            .upsert(profile)
            .execute()
    }

    func uploadAvatar(data: Data) async throws -> String {
        let userId = try await currentUserId()
        let path = "profile_avatars/\(userId.uuidString)-\(UUID().uuidString).jpg"

        try await client.storage
            .from("chat_attachments")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))

        return try await client.storage
            .from("chat_attachments")
            .createSignedURL(path: path, expiresIn: 60 * 60 * 24 * 365)
            .absoluteString
    }

    private func displayName(from user: User) -> String? {
        if case let .string(displayName)? = user.userMetadata["display_name"], !displayName.isEmpty {
            return displayName
        }

        let firstName: String?
        if case let .string(value)? = user.userMetadata["first_name"] {
            firstName = value
        } else {
            firstName = nil
        }

        let lastName: String?
        if case let .string(value)? = user.userMetadata["last_name"] {
            lastName = value
        } else {
            lastName = nil
        }

        let combined = [firstName, lastName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return combined.isEmpty ? nil : combined
    }
}

private struct ProfileUpsert: Encodable {
    let id: UUID
    let displayName: String
    let avatarUrl: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        if let avatarUrl {
            try container.encode(avatarUrl, forKey: .avatarUrl)
        } else {
            try container.encodeNil(forKey: .avatarUrl)
        }
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
