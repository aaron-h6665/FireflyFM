//
//  SupabaseAuthService.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/8/26.
//

import Foundation
import Supabase

struct SupabaseAuthService {
    private let client: SupabaseClient = AppConstants.supabase
    
    func login(withEmail email: String, password: String) async throws -> AuthenticationState {
        try await client.auth.signIn(email: email, password: password)
        return .authenticated
    }
    
    func signUp(withEmail email: String, password: String, firstName: String, lastName: String, role: UserRole) async throws -> AuthenticationState {
        let metadata: [String: AnyJSON] = [
            "first_name": .string(firstName),
            "last_name": .string(lastName),
            "role": .string(role.rawValue)
        ]
        try await client.auth.signUp(email: email, password: password, data: metadata)
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
