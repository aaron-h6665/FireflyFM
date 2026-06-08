//
//  AuthManager.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/8/26.
//

import Foundation
internal import Combine

@MainActor
final class AuthManager: ObservableObject {
    private let service: SupabaseAuthService
    @Published var error: Error?
    @Published var authState: AuthenticationState = .notDetermind
    
    init(service: SupabaseAuthService) {
        self.service = service
    }
    
    func login(withEmail email: String, password: String) async  {
        do{
            self.authState = try await service.login(withEmail: email, password: password)
        }
        catch{
            self.error = error
            print("DEBUG: Error logging in: \(error)")
        }
    }
    
    func signUp(withEmail email: String, password: String) async -> Bool {
        do{
            self.authState = try await service.signUp(withEmail: email, password: password)
            return true
        }
        catch{
            self.error = error
            print("DEBUG: Error signing up: \(error)")
            return false
        }
    }
    
    func clearError() {
        self.error = nil
    }
    
    func signOut() async {
        do{
            try await service.signOut()
            self.authState = .notAuthenticated
        }
        catch{
            print("DEBUG: Error signing out: \(error)")
        }
    }
    
    func getAuthState() async {
        do {
            self.authState = try await service.getAuthState()
        }
        catch {
            print("DEBUG: Failed to get auth state: \(error)")
        }
    }
}
