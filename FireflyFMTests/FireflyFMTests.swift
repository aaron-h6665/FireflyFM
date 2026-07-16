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

    @Test func uploadPolicyAllowsTheLimitAndRejectsLargerFiles() throws {
        try UploadPolicy.validate(
            byteCount: UploadPolicy.maxFileBytes,
            fileName: "at-limit.pdf"
        )

        do {
            try UploadPolicy.validate(
                byteCount: UploadPolicy.maxFileBytes + 1,
                fileName: "too-large.pdf"
            )
            #expect(Bool(false), "A file larger than 10 MB should be rejected")
        } catch let error as UploadValidationError {
            #expect(error.localizedDescription.contains("10 MB"))
            #expect(error.localizedDescription.contains("too-large.pdf"))
        }
    }

    @Test func hqSchoolAuthorityDoesNotImplyPrivateChatOversight() {
        #expect(SchoolRole.hqDirector.canManageSchool)
        #expect(!SchoolRole.hqDirector.canOverseeSchoolChats)
        #expect(SchoolRole.schoolDirector.canOverseeSchoolChats)
    }

    @Test func schoolErrorsExplainInvalidAndPendingDirectorInvites() {
        #expect(
            AppErrorMessage.school("Could not invite", SchoolServiceError.invalidEmail)
                == "Could not invite: enter a valid email address."
        )

        let pendingError = NSError(
            domain: "PostgREST",
            code: 409,
            userInfo: [NSLocalizedDescriptionKey: "A school director invitation is already pending"]
        )
        #expect(AppErrorMessage.school("Could not invite", pendingError).contains("already pending"))
    }

    @Test func workflowNotFoundErrorExplainsVisibilityInsteadOfShowingErrorCodeZero() {
        let message = AppErrorMessage.school("Could not open assignment", SchoolWorkflowError.notFound)

        #expect(message.contains("not found or is not visible"))
        #expect(!message.lowercased().contains("error 0"))
    }

    @Test @MainActor func assignmentAgendaClassifiesFeedbackLoopsConsistently() throws {
        let now = ISO8601DateFormatter().date(from: "2026-07-16T16:00:00Z")!
        let dueToday = try assignmentInboxItem(
            completionStatus: "read",
            dueAt: "2026-07-16T20:00:00Z"
        )
        let redo = try assignmentInboxItem(
            completionStatus: "changes_requested",
            dueAt: "2026-07-20T20:00:00Z"
        )
        let resubmitted = try assignmentInboxItem(
            completionStatus: "resubmitted",
            dueAt: "2026-07-20T20:00:00Z"
        )
        let overdue = try assignmentInboxItem(
            completionStatus: "not_started",
            dueAt: "2026-07-15T20:00:00Z"
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        #expect(AssignmentAgendaSection.classify(dueToday, now: now, calendar: calendar) == .today)
        #expect(AssignmentAgendaSection.classify(redo, now: now, calendar: calendar) == .needsAttention)
        #expect(AssignmentAgendaSection.classify(resubmitted, now: now, calendar: calendar) == .completed)
        #expect(AssignmentAgendaSection.classify(overdue, now: now, calendar: calendar) == .needsAttention)
    }

    @Test func assignmentAttemptsDecodeAsImmutableHistory() throws {
        let assignmentId = UUID()
        let schoolId = UUID()
        let userId = UUID()
        let firstId = UUID()
        let secondId = UUID()
        let json = """
        [
          {
            "id": "\(firstId)",
            "assignment_id": "\(assignmentId)",
            "school_id": "\(schoolId)",
            "submitted_by": "\(userId)",
            "attempt_number": 1,
            "status": "changes_requested"
          },
          {
            "id": "\(secondId)",
            "assignment_id": "\(assignmentId)",
            "school_id": "\(schoolId)",
            "submitted_by": "\(userId)",
            "attempt_number": 2,
            "supersedes_submission_id": "\(firstId)",
            "status": "resubmitted"
          }
        ]
        """.data(using: .utf8)!

        let attempts = try JSONDecoder().decode([AssignmentSubmission].self, from: json)

        #expect(attempts.count == 2)
        #expect(attempts[0].attemptNumber == 1)
        #expect(attempts[1].attemptNumber == 2)
        #expect(attempts[1].supersedesSubmissionId == firstId)
        #expect(attempts[0].id != attempts[1].id)
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

private func assignmentInboxItem(completionStatus: String, dueAt: String) throws -> AssignmentInboxItem {
    let json = """
    {
      "assignment_id": "\(UUID())",
      "school_id": "\(UUID())",
      "title": "Test assignment",
      "category": "general",
      "due_at": "\(dueAt)",
      "completion_status": "\(completionStatus)",
      "material_count": 0,
      "submission_count": 0,
      "recipient_count": 1
    }
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(AssignmentInboxItem.self, from: json)
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
