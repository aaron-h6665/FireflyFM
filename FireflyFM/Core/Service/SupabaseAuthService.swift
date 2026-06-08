//
//  SupabaseAuthService.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/8/26.
//

import Foundation
import Supabase

struct SupabaseAuthService {
    private let client: SupabaseClient
    
    init() {
        self.client = SupabaseClient.init(
            supabaseURL: URL(string: AppConstants.projectURLString)!, supabaseKey: AppConstants.projectAPIKey)
    }
    
    func login(withEmail email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }
    
    func signUp(withEmail email: String, password: String) async throws {
        try await client.auth.signUp(email: email, password: password)
    }
    
    func signOut() async throws {
        try await client.auth.signOut()
    }
    
    func getAuthState() async throws{
        
    }
}
