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

    @Test @MainActor func backendCompatibilityRequiresThePrivateMediaSchema() {
        #expect(AppSessionManager.requiredSchemaVersion == 20260722000000)
    }

    @Test func roleInvitePreviewDecodesOnlyConfirmationFields() throws {
        let inviteId = UUID()
        let schoolId = UUID()
        let json = """
        {
          "invite_id": "\(inviteId)",
          "school_id": "\(schoolId)",
          "school_name": "Firefly Learning Center",
          "role": "parent",
          "expires_at": 0
        }
        """.data(using: .utf8)!

        let preview = try JSONDecoder().decode(RoleInvitePreview.self, from: json)

        #expect(preview.id == inviteId)
        #expect(preview.schoolId == schoolId)
        #expect(preview.schoolName == "Firefly Learning Center")
        #expect(preview.role == .parent)
    }

    @Test func chatMediaDecodesPathAlongsideLegacyFallback() throws {
        let messageId = UUID()
        let roomId = UUID()
        let senderId = UUID()
        let json = """
        {
          "id": "\(messageId)",
          "room_id": "\(roomId)",
          "sender_id": "\(senderId)",
          "media_url": "https://legacy.invalid/photo.jpg",
          "media_path": "schools/school/chat_rooms/room/user/images/photo.jpg",
          "created_at": 0,
          "is_deleted": false
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(ChatMessageModel.self, from: json)

        #expect(message.mediaPath?.hasSuffix("images/photo.jpg") == true)
        #expect(message.mediaUrl == "https://legacy.invalid/photo.jpg")
    }

    @Test @MainActor func newsletterMediaDecodesAlongsideLegacyPosts() throws {
        let postId = UUID()
        let schoolId = UUID()
        let mediaId = UUID()
        let legacyJSON = """
        {
          "id": "\(postId)",
          "school_id": "\(schoolId)",
          "title": "Weekly update",
          "body": "A legacy post without attachments"
        }
        """.data(using: .utf8)!
        let mediaJSON = """
        {
          "id": "\(postId)",
          "school_id": "\(schoolId)",
          "title": "Art room highlights",
          "body": "This week in the studio",
          "media": [{
            "id": "\(mediaId)",
            "file_name": "art-room.jpg",
            "file_path": "schools/\(schoolId)/newsletters/\(postId)/0-art-room.jpg",
            "content_type": "image/jpeg",
            "alt_text": "Children painting together",
            "caption": "Tuesday's art session",
            "sort_order": 0
          }]
        }
        """.data(using: .utf8)!

        let legacyPost = try JSONDecoder().decode(NewsletterPost.self, from: legacyJSON)
        let mediaPost = try JSONDecoder().decode(NewsletterPost.self, from: mediaJSON)

        #expect(legacyPost.media.isEmpty)
        #expect(mediaPost.media.first?.id == mediaId)
        #expect(mediaPost.media.first?.altText == "Children painting together")
        #expect(mediaPost.media.first?.caption == "Tuesday's art session")
    }

    @Test @MainActor func membershipInviteRemainsPendingUntilExplicitlyCleared() throws {
        let manager = DeepLinkManager()
        let url = try #require(URL(string: "fireflyfm://role-invite?token=retry-token"))
        manager.handle(url: url)

        #expect(manager.pendingMembershipInvite == .role(token: "retry-token"))
        manager.clear(.role(token: "different-token"))
        #expect(manager.pendingMembershipInvite == .role(token: "retry-token"))
        manager.clear(.role(token: "retry-token"))
        #expect(manager.pendingMembershipInvite == nil)
    }

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
        let unreadFeedback = try assignmentInboxItem(
            completionStatus: "submitted",
            dueAt: "2026-07-20T20:00:00Z",
            hasUnreadFeedback: true
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        #expect(AssignmentAgendaSection.classify(dueToday, now: now, calendar: calendar) == .today)
        #expect(AssignmentAgendaSection.classify(redo, now: now, calendar: calendar) == .needsAttention)
        #expect(AssignmentAgendaSection.classify(resubmitted, now: now, calendar: calendar) == .awaitingReview)
        #expect(AssignmentAgendaSection.classify(overdue, now: now, calendar: calendar) == .needsAttention)
        #expect(AssignmentAgendaSection.classify(unreadFeedback, now: now, calendar: calendar) == .needsAttention)
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
        #expect(attempts[0].workflowStatus == .changesRequested)
        #expect(attempts[1].workflowStatus == .resubmitted)
    }

    @Test func assignmentCapabilitiesDecodeWithoutRoleGuessing() throws {
        let userId = UUID()
        let json = """
        {
          "user_id": "\(userId)",
          "is_recipient": true,
          "can_acknowledge": true,
          "can_submit": false,
          "can_review": true,
          "can_manage": true
        }
        """.data(using: .utf8)!

        let capabilities = try JSONDecoder().decode(AssignmentViewerCapabilities.self, from: json)

        #expect(capabilities.userId == userId)
        #expect(capabilities.isRecipient)
        #expect(capabilities.canAcknowledge)
        #expect(!capabilities.canSubmit)
        #expect(capabilities.canReview)
        #expect(capabilities.canManage)
    }

    @Test func membershipAccessStateDecodesPerSchool() throws {
        let membershipId = UUID()
        let schoolId = UUID()
        let userId = UUID()
        let json = """
        {
          "id": "\(membershipId)",
          "school_id": "\(schoolId)",
          "user_id": "\(userId)",
          "role": "parent",
          "active": true,
          "access_state": "onboarding"
        }
        """.data(using: .utf8)!

        let membership = try JSONDecoder().decode(SchoolMembership.self, from: json)

        #expect(membership.id == membershipId)
        #expect(membership.schoolId == schoolId)
        #expect(membership.accessState == "onboarding")
    }

    @Test func onboardingRequirementDecodesStableVersionLineageAndPaymentReservation() throws {
        let requirementId = UUID()
        let templateId = UUID()
        let requirementKey = UUID()
        let json = """
        {
          "id": "\(requirementId)",
          "template_id": "\(templateId)",
          "requirement_key": "\(requirementKey)",
          "position": 1,
          "requirement_type": "payment",
          "title": "Enrollment deposit",
          "subject_scope": "child"
        }
        """.data(using: .utf8)!

        let requirement = try JSONDecoder().decode(OnboardingTemplateRequirement.self, from: json)

        #expect(requirement.requirementKey == requirementKey)
        #expect(requirement.requirementType == .payment)
        #expect(requirement.subjectScope == .child)
    }

    @Test func hashedPendingInviteCanDecodeWithoutRecoverableToken() throws {
        let json = """
        {
          "id": "\(UUID())",
          "school_id": "\(UUID())",
          "email": "parent@example.com",
          "role": "parent",
          "status": "pending"
        }
        """.data(using: .utf8)!

        let invite = try JSONDecoder().decode(RoleInvite.self, from: json)

        #expect(invite.token == nil)
        #expect(invite.inviteURL == nil)
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

private func assignmentInboxItem(
    completionStatus: String,
    dueAt: String,
    hasUnreadFeedback: Bool = false
) throws -> AssignmentInboxItem {
    let json = """
    {
      "assignment_id": "\(UUID())",
      "school_id": "\(UUID())",
      "title": "Test assignment",
      "category": "general",
      "due_at": "\(dueAt)",
      "completion_status": "\(completionStatus)",
      "has_unread_feedback": \(hasUnreadFeedback),
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
