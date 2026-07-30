//
//  SupabaseAuthService.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/8/26.
//

import Foundation
import Supabase

struct SupabaseAuthService: AuthServicing {
    private let client: SupabaseClient = AppConstants.supabase
    
    func login(withEmail email: String, password: String) async throws -> AuthenticationState {
        try await client.auth.signIn(email: email, password: password)
        return .authenticated
    }
    
    func signUp(
        withEmail email: String,
        password: String,
        firstName: String,
        lastName: String,
        role: SignupRole,
        legalAcceptance: LegalAcceptance
    ) async throws -> AuthenticationState {
        let acceptedAt = ISO8601DateFormatter().string(from: legalAcceptance.acceptedAt)
        let metadata: [String: AnyJSON] = [
            "first_name": .string(firstName),
            "last_name": .string(lastName),
            "display_name": .string("\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)),
            "role": .string(role.rawValue),
            "terms_version": .string(legalAcceptance.termsVersion),
            "privacy_version": .string(legalAcceptance.privacyVersion),
            "ai_notice_version": .string(legalAcceptance.aiNoticeVersion),
            "legal_accepted_at": .string(acceptedAt)
        ]
        let response = try await client.auth.signUp(email: email, password: password, data: metadata)
        let displayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        try? await ProfileService.shared.upsertProfile(
            id: response.user.id,
            displayName: displayName.isEmpty ? email : displayName,
            avatarUrl: nil,
            avatarPath: nil
        )
        guard response.session != nil else {
            throw AuthFlowError.emailConfirmationRequired(email)
        }
        return .authenticated
    }
    
    func signOut() async throws {
        try await client.auth.signOut()
    }
    
    func getAuthState() async throws -> AuthenticationState {
        let user = try? await client.auth.session.user
        return user == nil ? .notAuthenticated : .authenticated
    }
}
