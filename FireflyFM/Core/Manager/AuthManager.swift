//
//  AuthManager.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/8/26.
//

import Foundation

@Observable @MainActor
final class AuthManager {
    private let service: SupabaseAuthService
    var error: Error?
    var authState: AuthenticationState = .notDetermind
    
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
    
    func signUp(withEmail email: String, password: String) async  {
        do{
            self.authState = try await service.signUp(withEmail: email, password: password)
        }
        catch{
            print("DEBUG: Error logging in: \(error)")
        }
    }
    
    func signOut() async {
        do{
            try await service.signOut()
        }
        catch{
            print("DEBUG: Error logging in: \(error)")
        }
    }
    
    func getAuthState() async throws{
        self.authState = try await service.getAuthState()
    }
}
