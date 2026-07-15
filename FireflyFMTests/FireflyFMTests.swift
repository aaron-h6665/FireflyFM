//
//  FireflyFMTests.swift
//  FireflyFMTests
//
//  Created by FireflyFM contributors on 6/8/26.
//

import Testing
import Foundation
@testable import FireflyFM

struct FireflyFMTests {

    @Test @MainActor func childBirthdateDecodesPostgresDateOnlyValue() throws {
        let childId = UUID()
        let schoolId = UUID()
        let json = """
        {
          "id": "\(childId.uuidString)",
          "school_id": "\(schoolId.uuidString)",
          "first_name": "Avery",
          "last_name": "Child",
          "birthdate": "2021-09-10",
          "active": true
        }
        """.data(using: .utf8)!

        let child = try JSONDecoder().decode(Child.self, from: json)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: try #require(child.birthdate))

        #expect(child.id == childId)
        #expect(child.schoolId == schoolId)
        #expect(components.year == 2021)
        #expect(components.month == 9)
        #expect(components.day == 10)
    }

    @Test func cancellationDetectionFiltersBenignTaskTeardown() {
        #expect(AppErrorMessage.isCancellation(CancellationError()))
        #expect(AppErrorMessage.isCancellation(URLError(.cancelled)))

        let backendError = NSError(
            domain: "PostgREST",
            code: 403,
            userInfo: [NSLocalizedDescriptionKey: "permission denied for relation children"]
        )
        #expect(!AppErrorMessage.isCancellation(backendError))
    }

    @Test @MainActor func signOutPublishesSigningOutStateUntilAuthCompletes() async throws {
        let service = DelayedSignOutAuthService(delayNanoseconds: 50_000_000)
        let manager = AuthManager(service: service)
        manager.authState = .authenticated

        let signOutTask = Task {
            await manager.signOut()
        }

        try await Task.sleep(nanoseconds: 5_000_000)
        #expect(manager.isSigningOut)

        await signOutTask.value
        #expect(!manager.isSigningOut)
        #expect(manager.authState == .notAuthenticated)
    }
}

private final class DelayedSignOutAuthService: AuthServicing {
    let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func login(withEmail email: String, password: String) async throws -> AuthenticationState {
        .authenticated
    }

    func signUp(withEmail email: String, password: String, firstName: String, lastName: String, role: UserRole) async throws -> AuthenticationState {
        .authenticated
    }

    func signOut() async throws {
        try await Task.sleep(nanoseconds: delayNanoseconds)
    }

    func getAuthState() async throws -> AuthenticationState {
        .authenticated
    }

}
