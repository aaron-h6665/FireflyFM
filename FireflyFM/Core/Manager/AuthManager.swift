//
//  AuthManager.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/8/26.
//

import Foundation
internal import Combine

protocol AuthServicing {
    func login(withEmail email: String, password: String) async throws -> AuthenticationState
    func signUp(withEmail email: String, password: String, firstName: String, lastName: String, role: UserRole) async throws -> AuthenticationState
    func signOut() async throws
    func getAuthState() async throws -> AuthenticationState
}

@MainActor
final class AuthManager: ObservableObject {
    private let service: any AuthServicing
    @Published var error: Error?
    @Published var authState: AuthenticationState = .notDetermind
    @Published private(set) var isSigningOut = false

    var errorMessage: String? {
        error.map(AppErrorMessage.auth)
    }
    
    init(service: any AuthServicing) {
        self.service = service
    }
    
    func login(withEmail email: String, password: String) async  {
        do{
            self.error = nil
            self.authState = try await service.login(withEmail: email, password: password)
        }
        catch{
            self.error = error
            print("DEBUG: Error logging in: \(error)")
        }
    }
    
    func signUp(withEmail email: String, password: String, firstName: String, lastName: String, role: UserRole) async -> Bool {
        do{
            self.error = nil
            self.authState = try await service.signUp(withEmail: email, password: password, firstName: firstName, lastName: lastName, role: role)
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
        guard !isSigningOut else { return }
        isSigningOut = true
        do{
            try await service.signOut()
            self.error = nil
            self.authState = .notAuthenticated
        }
        catch{
            self.error = error
            print("DEBUG: Error signing out: \(error)")
        }
        isSigningOut = false
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
