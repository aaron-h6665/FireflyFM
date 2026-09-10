//
//  FireflyFMTests.swift
//  FireflyFMTests
//
//  Created by FireflyFM contributors on 6/8/26.
//

import Testing
import Foundation
@testable import FireflyFM

@MainActor
struct FireflyFMTests {

    @Test @MainActor func backendCompatibilityRequiresBillingSchema() {
        #expect(AppSessionManager.requiredSchemaVersion == 20260907221000)
    }

    @Test func assignmentConversationHeightIsResponsiveAndClamped() {
        #expect(AssignmentConversationLayout.maximumHeight(for: 500) == 240)
        #expect(AssignmentConversationLayout.maximumHeight(for: 1_000) == 350)
        #expect(AssignmentConversationLayout.maximumHeight(for: 1_500) == 420)
    }

    @Test func assignmentDraftAttachmentsPersistUntilRemoved() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("AssignmentDraftAttachmentStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appendingPathComponent("source.pdf")
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("paperwork".utf8).write(to: sourceURL)

        let assignmentId = UUID()
        let ownerId = UUID()
        let store = AssignmentDraftAttachmentStore(
            fileManager: fileManager,
            rootURL: rootURL.appendingPathComponent("drafts", isDirectory: true)
        )
        let persistedURL = try #require(store.add([sourceURL], for: assignmentId, ownerId: ownerId).first)

        #expect(persistedURL.lastPathComponent == "source.pdf")
        #expect(try store.attachments(for: assignmentId, ownerId: ownerId) == [persistedURL])
        #expect(try store.attachments(for: assignmentId, ownerId: UUID()).isEmpty)

        try store.remove(persistedURL, for: assignmentId, ownerId: ownerId)
        #expect(try store.attachments(for: assignmentId, ownerId: ownerId).isEmpty)
    }

    @Test func parentGoogleFormURLParsingAcceptsEditAndResponseLinks() {
        #expect(GoogleFormOnboardingModel.formID(from: "https://docs.google.com/forms/d/abc123/edit") == "abc123")
        #expect(GoogleFormOnboardingModel.formID(from: "https://docs.google.com/forms/d/abc123/viewform") == "abc123")
        #expect(GoogleFormOnboardingModel.formID(from: "https://example.com/forms/d/abc123/edit") == nil)
        #expect(GoogleFormOnboardingModel.formID(from: "not-a-url") == nil)
    }

    @Test func recipientGoogleFormStepDecodesOnlySafeProjectionFields() throws {
        let connectionId = UUID()
        let json = """
        {
          "connection_id": "\(connectionId)",
          "form_title": "Parent intake",
          "form_url": "https://docs.google.com/forms/d/example/viewform",
          "form_role": "parent",
          "is_required": true,
          "display_order": 0,
          "submission_status": "pending_review",
          "review_note": null,
          "submitted_at": null
        }
        """.data(using: .utf8)!

        let step = try JSONDecoder().decode(GoogleFormRecipientStep.self, from: json)

        #expect(step.connectionId == connectionId)
        #expect(step.submissionStatus == "pending_review")
        #expect(step.formRole == "parent")
    }

    @Test func googleAccountSummaryDecodesWithoutOAuthMaterial() throws {
        let credentialId = UUID()
        let json = """
        {
          "credentialId": "\(credentialId)",
          "accountEmail": "director@example.com",
          "status": "connected",
          "linkedFormCount": 2,
          "isSelected": true
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(GoogleAccountConnectionSummary.self, from: json)

        #expect(summary.id == credentialId)
        #expect(summary.isConnected)
        #expect(summary.isSelected)
        #expect(summary.linkedFormCount == 2)
    }

    @Test func googleConnectionProfileVisibilityIsDirectorOnly() {
        let schoolId = UUID()
        #expect(GoogleAccountConnectionPolicy.isVisible(canEditProfile: true, role: .schoolDirector, schoolId: schoolId))
        #expect(!GoogleAccountConnectionPolicy.isVisible(canEditProfile: true, role: .teacher, schoolId: schoolId))
        #expect(!GoogleAccountConnectionPolicy.isVisible(canEditProfile: false, role: .schoolDirector, schoolId: schoolId))
        #expect(!GoogleAccountConnectionPolicy.isVisible(canEditProfile: true, role: .schoolDirector, schoolId: nil))
        #expect(GoogleAccountConnectionPolicy.disconnectExplanation.contains("will not be deleted"))
    }

    @Test func formsSheetFallsBackWhenSharedGoogleAccountIsRevoked() {
        let revoked = GoogleFormsOAuthCompletion(
            credentialId: UUID(), accountEmail: "revoked@example.com"
        )
        let connected = GoogleFormsOAuthCompletion(
            credentialId: UUID(), accountEmail: "connected@example.com"
        )

        let preferred = GoogleFormCredentialSelection.preferred(
            from: [connected],
            shared: revoked
        )

        #expect(preferred == connected)
    }

    @Test @MainActor func selectingGoogleAccountChangesDefaultWithoutReconnecting() async {
        let schoolId = UUID()
        let firstId = UUID()
        let secondId = UUID()
        var selectedId = firstId
        let accounts: () -> [GoogleAccountConnectionSummary] = {
            [
                GoogleAccountConnectionSummary(
                    credentialId: firstId, accountEmail: "first@example.com", status: "connected",
                    linkedFormCount: 1, isSelected: selectedId == firstId
                ),
                GoogleAccountConnectionSummary(
                    credentialId: secondId, accountEmail: "second@example.com", status: "connected",
                    linkedFormCount: 2, isSelected: selectedId == secondId
                )
            ]
        }
        let client = GoogleAccountConnectionClient(
            list: { _ in accounts() },
            select: { requestedSchoolId, credentialId in
                #expect(requestedSchoolId == schoolId)
                selectedId = credentialId
            },
            disconnect: { _, _ in 0 },
            startOAuth: { _, _ in GoogleFormsOAuthStart(authorizationURL: "https://accounts.google.com", callbackScheme: "firefly.fireflyfm") },
            authorize: { url, _ in url },
            completeOAuth: { _, _ in GoogleFormsOAuthCompletion(credentialId: secondId, accountEmail: "second@example.com") }
        )
        let model = GoogleAccountConnectionModel(client: client)
        await model.load(schoolId: schoolId)

        await model.select(accounts()[1], schoolId: schoolId)

        #expect(model.selectedAccount?.id == secondId)
        #expect(model.accounts.first(where: { $0.id == firstId })?.linkedFormCount == 1)
        #expect(model.notice?.contains("Existing Forms keep their current account") == true)
    }

    @Test @MainActor func disconnectingGoogleAccountSurfacesPausedFormCount() async {
        let schoolId = UUID()
        let credentialId = UUID()
        var disconnected = false
        let client = GoogleAccountConnectionClient(
            list: { _ in [
                GoogleAccountConnectionSummary(
                    credentialId: credentialId, accountEmail: "director@example.com",
                    status: disconnected ? "revoked" : "connected", linkedFormCount: 3,
                    isSelected: !disconnected
                )
            ] },
            select: { _, _ in },
            disconnect: { requestedSchoolId, requestedCredentialId in
                #expect(requestedSchoolId == schoolId)
                #expect(requestedCredentialId == credentialId)
                disconnected = true
                return 3
            },
            startOAuth: { _, _ in GoogleFormsOAuthStart(authorizationURL: "https://accounts.google.com", callbackScheme: "firefly.fireflyfm") },
            authorize: { url, _ in url },
            completeOAuth: { _, _ in GoogleFormsOAuthCompletion(credentialId: credentialId, accountEmail: "director@example.com") }
        )
        let model = GoogleAccountConnectionModel(client: client)
        await model.load(schoolId: schoolId)

        await model.disconnect(model.accounts[0], schoolId: schoolId)

        #expect(model.accounts[0].status == "revoked")
        #expect(model.notice == "Google was disconnected and 3 linked Forms were paused.")
    }

    @Test @MainActor func assignmentLifecycleAndRevisionMetadataDecode() throws {
        let assignmentId = UUID()
        let schoolId = UUID()
        let creatorId = UUID()
        let revisionId = UUID()
        let assignmentJSON = """
        {
          "id": "\(assignmentId)",
          "school_id": "\(schoolId)",
          "title": "Family handbook",
          "category": "general",
          "audience_role": "parent",
          "assigned_by": "\(creatorId)",
          "status": "closed",
          "current_revision_id": "\(revisionId)"
        }
        """.data(using: .utf8)!
        let inboxJSON = """
        {
          "assignment_id": "\(assignmentId)",
          "school_id": "\(schoolId)",
          "title": "Family handbook",
          "category": "general",
          "lifecycle_status": "archived",
          "completion_status": "not_started",
          "material_count": 0,
          "submission_count": 1,
          "recipient_count": 1
        }
        """.data(using: .utf8)!

        let assignment = try JSONDecoder().decode(Assignment.self, from: assignmentJSON)
        let inboxItem = try JSONDecoder().decode(AssignmentInboxItem.self, from: inboxJSON)

        #expect(assignment.status == "closed")
        #expect(assignment.currentRevisionId == revisionId)
        #expect(inboxItem.lifecycleStatus == .archived)
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

    @Test func managedChatDiscoveryDecodesRoomAndParticipantTogether() throws {
        let roomId = UUID()
        let schoolId = UUID()
        let userId = UUID()
        let json = """
        {
          "id": "\(roomId)",
          "name": "School Updates",
          "school_id": "\(schoolId)",
          "room_type": "director_managed",
          "created_at": 0,
          "participant_joined_at": 1,
          "participant_notifications_enabled": true,
          "participant_role": "member"
        }
        """.data(using: .utf8)!

        let access = try JSONDecoder().decode(ManagedChatRoomAccessRow.self, from: json)
        let room = access.room()
        let participant = access.participant(userId: userId)

        #expect(room.id == roomId)
        #expect(room.schoolId == schoolId)
        #expect(participant.roomId == roomId)
        #expect(participant.userId == userId)
        #expect(participant.notificationsEnabled)
    }

    @Test @MainActor func newsletterMediaDecodesAlongsideLegacyPosts() throws {
        let postId = UUID()
        let schoolId = UUID()
        let mediaId = UUID()
        let legacyMediaId = UUID()
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
            "sort_order": 0,
            "layout": "inset",
            "link_url": "https://example.com/art-room"
          }, {
            "id": "\(legacyMediaId)",
            "file_name": "legacy-photo.jpg",
            "file_path": "schools/\(schoolId)/newsletters/\(postId)/1-legacy-photo.jpg",
            "content_type": "image/jpeg",
            "sort_order": 1
          }]
        }
        """.data(using: .utf8)!

        let legacyPost = try JSONDecoder().decode(NewsletterPost.self, from: legacyJSON)
        let mediaPost = try JSONDecoder().decode(NewsletterPost.self, from: mediaJSON)

        #expect(legacyPost.media.isEmpty)
        #expect(mediaPost.media.first?.id == mediaId)
        #expect(mediaPost.media.first?.altText == "Children painting together")
        #expect(mediaPost.media.first?.caption == "Tuesday's art session")
        #expect(mediaPost.media.first?.layout == .inset)
        #expect(mediaPost.media.first?.linkURL == "https://example.com/art-room")
        #expect(mediaPost.media.last?.id == legacyMediaId)
        #expect(mediaPost.media.last?.layout == nil)
        #expect(mediaPost.media.last?.linkURL == nil)
    }

    @Test @MainActor func newsletterLegacyFormattingIsConvertedToPlainText() {
        let rendered = newsletterPlainText(
            "## Update\n\n**Bold text**, _italic text_, and [a link](https://example.com)."
        )

        #expect(rendered == "Update\n\nBold text, italic text, and a link.")
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
            "status": "changes_requested",
            "structured_payload": {}
          },
          {
            "id": "\(secondId)",
            "assignment_id": "\(assignmentId)",
            "school_id": "\(schoolId)",
            "submitted_by": "\(userId)",
            "attempt_number": 2,
            "supersedes_submission_id": "\(firstId)",
            "status": "resubmitted",
            "structured_payload": {}
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
          "subject_scope": "child",
          "blocks_access": true,
          "child_record_binding": "child_document"
        }
        """.data(using: .utf8)!

        let requirement = try JSONDecoder().decode(OnboardingTemplateRequirement.self, from: json)

        #expect(requirement.requirementKey == requirementKey)
        #expect(requirement.requirementType == .payment)
        #expect(requirement.subjectScope == .child)
        #expect(requirement.blocksAccess)
        #expect(requirement.childRecordBinding == .childDocument)
    }

    @Test func childProfileCompletionUsesOnlyApprovedIdentityAndBlockingRequirements() {
        #expect(ChildProfileCompletion(
            identityApproved: true,
            blockingRequirementsRemaining: 0,
            nonBlockingRequirementsRemaining: 2
        ).grantsAccess)
        #expect(!ChildProfileCompletion(
            identityApproved: true,
            blockingRequirementsRemaining: 1,
            nonBlockingRequirementsRemaining: 0
        ).grantsAccess)
        #expect(!ChildProfileCompletion(
            identityApproved: false,
            blockingRequirementsRemaining: 0,
            nonBlockingRequirementsRemaining: 0
        ).grantsAccess)
    }

    @Test func childConnectionRequiresBirthdateWhenDecoding() throws {
        let json = """
        {
          "id": "\(UUID())",
          "school_id": "\(UUID())",
          "requested_by": "\(UUID())",
          "legal_first_name": "Avery",
          "legal_last_name": "Child",
          "relationship": "Parent",
          "status": "pending",
          "created_at": 0
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ChildConnectionRequest.self, from: json)
        }
    }

    @Test func notificationRouteAndDeliveryStateDecodeExactDestination() throws {
        let notificationId = UUID()
        let schoolId = UUID()
        let sessionId = UUID()
        let childId = UUID()
        let json = """
        {
          "id": "\(notificationId)",
          "school_id": "\(schoolId)",
          "school_name": "Beta School",
          "title": "Checked in",
          "body": "Avery checked in",
          "category": "attendance_check_in",
          "priority": "routine",
          "route": {
            "type": "attendance_session",
            "id": "\(sessionId)",
            "child_id": "\(childId)"
          },
          "delivery_state": "opened",
          "attempt_count": 2
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(NotificationInboxItem.self, from: json)

        #expect(item.id == notificationId)
        #expect(item.route?.type == "attendance_session")
        #expect(item.route?.id == sessionId)
        #expect(item.route?.childId == childId)
        #expect(item.deliveryState == .opened)
        #expect(item.attemptCount == 2)
    }

    @Test func notificationRoutesOpenPublishedCommunityContent() throws {
        let schoolId = UUID()
        let contentId = UUID()
        let resolver = NotificationDestinationResolver()
        let expected: [(String, NotificationFeatureDestination)] = [
            ("community_post", .communityPost(contentId)),
            ("community_album", .communityAlbum(contentId)),
            ("newsletter", .newsletter(contentId)),
            ("school_announcement", .schoolAnnouncement)
        ]

        for (routeType, destination) in expected {
            let json = """
            {
              "id": "\(UUID())",
              "school_id": "\(schoolId)",
              "school_name": "Beta School",
              "title": "New activity",
              "body": "Open FireflyFM to view it.",
              "category": "\(routeType)",
              "route": { "type": "\(routeType)", "id": "\(contentId)" }
            }
            """.data(using: .utf8)!
            let item = try JSONDecoder().decode(NotificationInboxItem.self, from: json)
            #expect(resolver.resolve(item) == destination)
        }
    }

    @Test func zelleNotificationsOpenPayments() throws {
        let schoolId = UUID()
        let invoiceId = UUID()
        let resolver = NotificationDestinationResolver()
        let sourceJSON = """
        {
          "id": "\(UUID())", "school_id": "\(schoolId)", "school_name": "Beta School",
          "title": "Payment review", "body": "Open the invoice.",
          "category": "zelle_payment", "source_type": "zelle_invoice", "source_id": "\(invoiceId)"
        }
        """.data(using: .utf8)!
        let legacyJSON = """
        {
          "id": "\(UUID())", "school_id": "\(schoolId)", "school_name": "Beta School",
          "title": "Payment review", "body": "Open the invoice.",
          "category": "zelle_payment", "source_id": "\(invoiceId)"
        }
        """.data(using: .utf8)!

        #expect(resolver.resolve(try JSONDecoder().decode(NotificationInboxItem.self, from: sourceJSON)) == .billing)
        #expect(resolver.resolve(try JSONDecoder().decode(NotificationInboxItem.self, from: legacyJSON)) == .billing)
    }

    @Test func notificationActivityGroupsUnreadMessagesByThread() throws {
        let schoolId = UUID()
        let roomId = UUID()
        let messageId = UUID()
        let latestId = UUID()
        let earlierId = UUID()
        let postId = UUID()
        let json = """
        [
          {
            "id": "\(latestId)", "school_id": "\(schoolId)", "school_name": "Beta School",
            "title": "Maya Chen", "subtitle": "Sunshine Room", "body": "Latest message",
            "safe_body": "Sent a message", "category": "chat_message",
            "thread_key": "chat:\(roomId)", "route": { "type": "chat_room", "id": "\(roomId)", "message_id": "\(messageId)" }
          },
          {
            "id": "\(earlierId)", "school_id": "\(schoolId)", "school_name": "Beta School",
            "title": "Jordan Lee", "subtitle": "Sunshine Room", "body": "Earlier message",
            "safe_body": "Sent a message", "category": "chat_message",
            "thread_key": "chat:\(roomId)", "route": { "type": "chat_room", "id": "\(roomId)" }
          },
          {
            "id": "\(postId)", "school_id": "\(schoolId)", "school_name": "Beta School",
            "title": "New post", "body": "School update", "category": "community_post",
            "route": { "type": "community_post", "id": "\(postId)" }
          }
        ]
        """.data(using: .utf8)!

        let items = try JSONDecoder().decode([NotificationInboxItem].self, from: json)
        let groups = NotificationActivityGroup.make(from: items)

        #expect(groups.count == 2)
        #expect(groups[0].kind == .chat)
        #expect(groups[0].latest.id == latestId)
        #expect(groups[0].unreadCount == 2)
        #expect(groups[1].kind == .item)
        #expect(NotificationDestinationResolver().resolve(groups[0].latest) == .chatRoom(roomId, messageId: messageId))
    }

    @Test func schoolChildAccessContextUsesSchoolRolesWithoutClassroomAssignments() {
        let schoolId = UUID()
        let teacher = SchoolChildAccessContext(schoolId: schoolId, role: .teacher)
        let parent = SchoolChildAccessContext(schoolId: schoolId, role: .parent)
        let director = SchoolChildAccessContext(schoolId: schoolId, role: .schoolDirector)

        #expect(teacher.canRecordSchoolCare)
        #expect(!teacher.canManageConnections)
        #expect(!parent.canRecordSchoolCare)
        #expect(director.canRecordSchoolCare)
        #expect(director.canManageConnections)
    }

    @Test func baseCapabilitiesPreserveRoleBoundaries() {
        #expect(SchoolRole.parent.has(.requestChildConnection))
        #expect(!SchoolRole.parent.has(.recordCare))
        #expect(SchoolRole.teacher.has(.recordCare))
        #expect(!SchoolRole.teacher.has(.manageChildConnections))
        #expect(SchoolRole.schoolDirector.has(.overseeSchoolChats))
        #expect(SchoolRole.hqDirector.has(.manageSchools))
        #expect(!SchoolRole.hqDirector.has(.overseeSchoolChats))
        #expect(SchoolRole.hqDirector.has(.recordCare))
        #expect(SchoolRole.schoolDirector.has(.generateChildAISummary))
        #expect(!SchoolRole.parent.has(.generateChildAISummary))
        #expect(!SchoolRole.teacher.has(.generateChildAISummary))
        #expect(!SchoolRole.hqDirector.has(.generateChildAISummary))
    }

    @Test func aiSummaryPromptIncludesAttributionButNotAttachmentLocations() {
        let schoolId = UUID()
        let child = Child(schoolId: schoolId, firstName: "Ada", lastName: "Rivera")
        let senderId = UUID()
        let now = Date()
        let message = ChatMessageModel(
            roomId: UUID(),
            schoolId: schoolId,
            senderId: senderId,
            text: "Enjoyed the block activity.",
            fileUrl: "https://private.invalid/signed-file",
            filePath: "children/private/report.pdf",
            attachmentType: "application/pdf",
            attachmentName: "activity.pdf",
            attachmentSize: 2_048,
            createdAt: now
        )
        let source = ChildAISummarySourceBundle(
            child: child,
            startDate: now.addingTimeInterval(-3_600),
            endDate: now.addingTimeInterval(3_600),
            messages: [message],
            attendance: [],
            careEvents: [],
            goals: [],
            directory: [SchoolDirectoryEntry(userId: senderId, displayName: "Morgan Lee", avatarUrl: nil, schoolRole: .teacher)]
        )

        let prompt = ChildAISummaryPrompt.build(from: source)

        #expect(prompt.text.contains("Morgan Lee (Teacher)"))
        #expect(prompt.text.contains("attachment metadata only"))
        #expect(prompt.text.contains("activity.pdf"))
        #expect(!prompt.text.contains("private.invalid"))
        #expect(!prompt.text.contains("children/private"))
        #expect(prompt.snapshot.attachmentCount == 1)

        let localSummary = LocalExtractiveChildSummaryGenerator.generate(
            from: source,
            snapshot: prompt.snapshot
        )
        #expect(localSummary.contains("Clear outcomes"))
        #expect(localSummary.contains("Communication"))
        #expect(localSummary.contains("Morgan Lee (Teacher)"))
        #expect(localSummary.contains("Enjoyed the block activity."))
        #expect(localSummary.contains("No attendance records were available"))
        #expect(!localSummary.contains("private.invalid"))
        #expect(!localSummary.contains("children/private"))
    }

    @Test func localAISummaryFlagsUnclearChatInsteadOfInventingAnOutcome() {
        let schoolId = UUID()
        let child = Child(schoolId: schoolId, firstName: "Ada", lastName: "Rivera")
        let now = Date()
        let unclearText = "asdf qqq ###"
        let message = ChatMessageModel(
            roomId: UUID(),
            schoolId: schoolId,
            senderId: UUID(),
            text: unclearText,
            createdAt: now
        )
        let source = ChildAISummarySourceBundle(
            child: child,
            startDate: now.addingTimeInterval(-3_600),
            endDate: now.addingTimeInterval(3_600),
            messages: [message],
            attendance: [],
            careEvents: [],
            goals: [],
            directory: []
        )
        let prompt = ChildAISummaryPrompt.build(from: source)

        let localSummary = LocalExtractiveChildSummaryGenerator.generate(
            from: source,
            snapshot: prompt.snapshot
        )

        #expect(localSummary.contains("No recurring theme was supported by multiple clear messages"))
        #expect(localSummary.contains("Message text was too limited or unclear"))
        #expect(localSummary.contains("1 unclear message(s) were excluded"))
        #expect(!localSummary.contains(unclearText))
    }

    @Test func hqAuthorityDoesNotImplyPrivateChatOversight() {
        let policy = ChatAccessPolicy(context: AppAccessContext(role: .hqDirector))
        let room = ChatRoom(name: "Private room", systemManaged: false)

        #expect(!policy.canOverseeSchoolRooms)
        #expect(!policy.canLeave(room: room))
    }

    @Test func childAndAttendancePoliciesRemainContextual() {
        let schoolId = UUID()
        let teacher = AppAccessContext(role: .teacher, activeSchoolId: schoolId)
        let hq = AppAccessContext(role: .hqDirector, selectedSchoolId: schoolId)

        #expect(ChildAccessPolicy(context: teacher).canEditSchoolRecords)
        #expect(!ChildAccessPolicy(context: teacher).canEditIdentity)
        #expect(AttendanceAccessPolicy(context: teacher).canRecord)
        #expect(!AttendanceAccessPolicy(context: teacher).canCorrect)
        #expect(AttendanceAccessPolicy(context: hq).hasCrossSchoolScope)
        #expect(AttendanceAccessPolicy(context: hq).canCorrect)
    }

    @Test func featurePoliciesKeepRoleAndResourceScopeDistinct() {
        let schoolId = UUID()
        let anotherSchoolId = UUID()
        let directorId = UUID()
        let parent = AppAccessContext(role: .parent, activeSchoolId: schoolId)
        let teacher = AppAccessContext(role: .teacher, activeSchoolId: schoolId)
        let director = AppAccessContext(userId: directorId, role: .schoolDirector, activeSchoolId: schoolId)
        let hq = AppAccessContext(role: .hqDirector, selectedSchoolId: schoolId)

        #expect(parent.isInSchool(schoolId))
        #expect(!parent.isInSchool(anotherSchoolId))
        #expect(hq.isInSchool(anotherSchoolId))

        let familyRoom = ChatRoom(name: "Family", roomType: "child_family", systemManaged: true)
        #expect(ChatRoomInteractionPolicy(context: parent, room: familyRoom).capabilities.canCreateFamilyRequest)
        #expect(!ChatRoomInteractionPolicy(context: parent, room: familyRoom).capabilities.canRecordCare)
        #expect(ChatRoomInteractionPolicy(context: teacher, room: familyRoom).capabilities.canRecordCare)

        let assignmentPolicy = AssignmentAccessPolicy(context: director)
        #expect(assignmentPolicy.canCreate)
        #expect(assignmentPolicy.canReview(serverAllowsReview: true))
        #expect(!assignmentPolicy.canReview(serverAllowsReview: false))
        #expect(assignmentPolicy.canAssign(to: .parent, category: .paperwork))
        #expect(!assignmentPolicy.canAssign(to: .teacher, category: .paperwork))
        #expect(!assignmentPolicy.canAssign(
            to: directorId,
            role: .schoolDirector,
            accessState: "full",
            category: .general
        ))
        #expect(!assignmentPolicy.canAssign(
            to: UUID(),
            role: .parent,
            accessState: "onboarding",
            category: .paperwork
        ))
        #expect(!assignmentPolicy.canAssign(
            to: UUID(),
            role: .teacher,
            accessState: "onboarding",
            category: .training
        ))
        #expect(assignmentPolicy.canAssign(
            to: UUID(),
            role: .parent,
            accessState: "full",
            category: .paperwork
        ))
        #expect(assignmentPolicy.canAssign(
            to: UUID(),
            role: .teacher,
            accessState: "full",
            category: .training
        ))

        #expect(EventAccessPolicy(context: teacher).canInvite(memberRole: .parent))
        #expect(!EventAccessPolicy(context: teacher).canInvite(memberRole: .teacher))
        #expect(OnboardingAccessPolicy(context: director).canManageMembers)
        #expect(!OnboardingAccessPolicy(context: director).canManageDirectors)
        #expect(OnboardingAccessPolicy(context: hq).canManageDirectors)
        #expect(CareAccessPolicy(context: teacher).canRecord)
        #expect(FamilyRequestAccessPolicy(context: parent).canCreate)
        #expect(FamilyRequestAccessPolicy(context: director).canHandle)
        #expect(PaymentAccessPolicy(context: director).usesSchoolSetupPresentation)
        #expect(PaymentAccessPolicy(context: director).canManage)
        #expect(!PaymentAccessPolicy(context: hq).canManage)
        #expect(PaymentAccessPolicy(context: hq).hasCrossSchoolScope)
        #expect(NotificationAccessPolicy(context: director).canCompose)
        #expect(!NotificationAccessPolicy(context: hq).canCompose)
    }

    @Test func paymentPolicyKeepsNamedPayerAndReviewerActionsDistinct() {
        let schoolId = UUID()
        let parentId = UUID()
        let invoice = billingInvoice(schoolId: schoolId, parentId: parentId)
        let namedParent = PaymentAccessPolicy(context: AppAccessContext(
            userId: parentId,
            role: .parent,
            activeSchoolId: schoolId
        ))
        let otherParent = PaymentAccessPolicy(context: AppAccessContext(
            userId: UUID(),
            role: .parent,
            activeSchoolId: schoolId
        ))
        let director = PaymentAccessPolicy(context: AppAccessContext(role: .schoolDirector, activeSchoolId: schoolId))
        let teacher = PaymentAccessPolicy(context: AppAccessContext(role: .teacher, activeSchoolId: schoolId))

        #expect(namedParent.canView)
        #expect(namedParent.canPay(invoice: invoice))
        #expect(!otherParent.canPay(invoice: invoice))
        #expect(director.canManage)
        #expect(director.canReview(invoice: invoice))
        #expect(!director.canPay(invoice: invoice))
        #expect(!teacher.canView)
    }

    @Test func paymentReviewRejectsSelfApprovalAndSchoolDirectorReviewOfHQFees() {
        let schoolId = UUID()
        let userId = UUID()
        var invoice = billingInvoice(schoolId: schoolId, parentId: userId)
        let director = PaymentAccessPolicy(context: AppAccessContext(userId: userId, role: .schoolDirector, activeSchoolId: schoolId))
        #expect(!director.canReview(invoice: invoice))
        invoice.payerUserId = UUID()
        invoice.payerRole = .schoolDirector
        invoice.originalOnboardingRequirementId = UUID()
        #expect(invoice.isOnboardingInvoice)
        #expect(!director.canReview(invoice: invoice))
        let hq = PaymentAccessPolicy(context: AppAccessContext(userId: UUID(), role: .hqDirector, activeSchoolId: schoolId))
        #expect(hq.canReview(invoice: invoice))
    }

    @Test func zelleInvoiceDecodesManualProjectionAndDerivesPastDue() throws {
        let schoolId = UUID()
        let parentId = UUID()
        let json = """
        {
          "id": "\(UUID())",
          "school_id": "\(schoolId)",
          "payer_user_id": "\(parentId)",
          "payer_role": "parent",
          "invoice_number": "ZL-00000001",
          "description": "August tuition",
          "currency": "USD",
          "amount_due_cents": 125000,
          "amount_paid_cents": 0,
          "status": "open",
          "due_at": "2020-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let invoice = try decoder.decode(ZelleInvoice.self, from: json)

        #expect(invoice.amountDueCents == 125000)
        #expect(invoice.isPastDue)
        #expect(invoice.displayStatus == "Past due")
    }

    @Test @MainActor func paymentsModelBuildsOperationalSummaryFromInjectedClient() async {
        let schoolId = UUID()
        let parentId = UUID()
        let invoice = billingInvoice(schoolId: schoolId, parentId: parentId)
        let model = PaymentsModel(client: PaymentsClient(
            fetchProfile: { _ in nil },
            fetchInvoices: { _ in [invoice] },
            fetchInvoice: { _ in invoice },
            fetchItems: { _ in [] },
            fetchSubmissions: { _ in [] },
            fetchParents: { _ in [] },
            fetchChildren: { _ in [] },
            fetchSchools: { [] },
            saveProfile: { _ in throw TestFeatureError.expected },
            createInvoice: { _ in invoice },
            submitPayment: { _ in throw TestFeatureError.expected },
            reviewPayment: { _, _, _ in invoice },
            voidInvoice: { _, _ in invoice }
        ))
        let policy = PaymentAccessPolicy(context: AppAccessContext(
            userId: parentId,
            role: .parent,
            activeSchoolId: schoolId
        ))

        await model.load(schoolId: schoolId, policy: policy)
        #expect(model.phase == .loaded)
        #expect(model.outstandingCents == invoice.amountRemainingCents)
        #expect(model.collectedCents == 0)
    }

    @Test func attendanceActionsPreserveServicePayloadValues() {
        #expect(AttendanceAction.checkIn.rawValue == "check_in")
        #expect(AttendanceAction.checkOut.rawValue == "check_out")
        #expect(AttendanceAction.absent.rawValue == "absent")
    }

    @Test @MainActor func newsletterModelRepresentsEmptyAndErrorStates() async {
        let emptyModel = NewsletterListModel(client: NewsletterListClient(
            fetch: { _ in [] },
            delete: { _ in }
        ))
        await emptyModel.load(schoolId: UUID())
        #expect(emptyModel.phase == .empty)

        let errorModel = NewsletterListModel(client: NewsletterListClient(
            fetch: { _ in throw TestFeatureError.expected },
            delete: { _ in }
        ))
        await errorModel.load(schoolId: UUID())
        if case .failed = errorModel.phase {
            #expect(Bool(true))
        } else {
            Issue.record("Expected newsletter load failure")
        }
    }

    @Test @MainActor func childrenRosterModelUsesTheRequestedScope() async {
        let schoolId = UUID()
        var requestedSchoolId: UUID?
        let model = ChildrenRosterModel(client: ChildrenRosterClient(
            fetchSchools: { [] },
            fetchAllChildren: { [] },
            fetchChildren: { id in
                requestedSchoolId = id
                return []
            }
        ))

        await model.load(scope: .school(schoolId))
        #expect(requestedSchoolId == schoolId)
        #expect(model.phase == .empty)
    }

    @Test @MainActor func attendanceModelUsesSchoolScopeAndTypedBatchAction() async {
        let schoolId = UUID()
        let child = Child(schoolId: schoolId, firstName: "Avery", lastName: "Child")
        let model = AttendanceModel(client: AttendanceClient(
            fetchAllChildren: { [] },
            fetchChildren: { id in id == schoolId ? [child] : [] },
            fetchSchools: { [] },
            fetchAllSessions: { _, _ in [] },
            fetchSessions: { id, _, _ in id == schoolId ? [] : [] },
            recordBatch: { childIds, action in
                childIds.map {
                    AttendanceBatchResult(
                        childId: $0,
                        success: action == .checkIn,
                        sessionId: UUID(),
                        errorCode: nil,
                        errorMessage: nil
                    )
                }
            },
            correct: { _ in throw TestFeatureError.expected }
        ))
        let now = Date()

        await model.load(scope: AttendanceScope(
            schoolId: schoolId,
            includesAllSchools: false,
            startDate: now,
            endDate: now
        ))
        #expect(model.children == [child])
        #expect(model.phase == .loaded)

        let results = await model.recordBatch(childIds: [child.id], action: .checkIn)
        #expect(results?.first?.success == true)
    }

    @Test @MainActor func notificationPreferencesModelLoadsAndSavesThroughInjectedClient() async {
        let userId = UUID()
        let initial = NotificationPreference(
            userId: userId,
            category: "chat",
            enabled: false,
            quietHoursStart: nil,
            quietHoursEnd: nil,
            timeZone: "UTC"
        )
        let model = NotificationPreferencesModel(client: NotificationPreferencesClient(
            fetch: { [initial] },
            currentUserId: { userId },
            save: { _ in },
            fetchSettings: {
                UserNotificationSettings(
                    userId: userId,
                    messagePreviewMode: .senderOnly,
                    quietHoursStart: nil,
                    quietHoursEnd: nil,
                    timeZone: "UTC",
                    permissionPromptDeferred: false
                )
            },
            saveSettings: { _ in },
            permissionState: { .authorized },
            openSystemSettings: {}
        ))

        await model.load()
        #expect(model.preferences == [initial])
        #expect(await model.save(
            drafts: [.init(category: "chat", enabled: true)],
            previewMode: .full,
            quietHoursStart: "21:00:00",
            quietHoursEnd: "07:00:00"
        ))
        #expect(model.preferences.first?.enabled == true)
        #expect(model.preferences.first?.quietHoursStart == "21:00:00")
        #expect(model.settings?.messagePreviewMode == .full)
    }

    @Test @MainActor func eventAndCommunityModelsRepresentIndependentEmptyHosts() async {
        let schoolId = UUID()
        let eventModel = EventCatalogModel(client: EventCatalogClient(
            fetchSchools: { [] },
            fetchEvents: { _, _ in [] },
            fetchMembers: { _ in [] },
            fetchProfiles: { _ in [:] },
            deleteEvent: { _ in },
            setArchived: { _, _ in throw TestFeatureError.expected }
        ))
        await eventModel.load(schoolId: schoolId, canManage: false, includeArchived: false)
        #expect(eventModel.phase == .empty)

        let communityModel = CommunityModel(client: CommunityClient(
            fetchPosts: { _ in [] },
            fetchAlbums: { _ in [] },
            fetchAlbumMedia: { _ in [:] },
            fetchDirectory: { _ in [] },
            fetchProfiles: { _ in [:] },
            subscribePosts: { _, _ in throw TestFeatureError.expected },
            unsubscribe: { _ in }
        ))
        await communityModel.load(schoolId: schoolId, events: [])
        #expect(communityModel.phase == .empty)
    }

    @Test @MainActor func upcomingEventsReloadFromTheServerAndExcludeFinishedEvents() async {
        let schoolId = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let finished = SchoolEvent(
            schoolId: schoolId,
            title: "Finished",
            startAt: now.addingTimeInterval(-7_200),
            endAt: now.addingTimeInterval(-3_600)
        )
        let later = SchoolEvent(
            schoolId: schoolId,
            title: "Later",
            startAt: now.addingTimeInterval(7_200)
        )
        let next = SchoolEvent(
            schoolId: schoolId,
            title: "Next",
            startAt: now.addingTimeInterval(3_600)
        )
        var fetchCount = 0
        let client = UpcomingEventsClient(fetchEvents: { requestedSchoolId in
            #expect(requestedSchoolId == schoolId)
            fetchCount += 1
            return [finished, later, next]
        })

        let firstSession = UpcomingEventsModel(client: client, now: { now })
        await firstSession.load(schoolId: schoolId)

        let nextSession = UpcomingEventsModel(client: client, now: { now })
        await nextSession.load(schoolId: schoolId)

        #expect(firstSession.events.map(\.title) == ["Next", "Later"])
        #expect(nextSession.events.map(\.title) == ["Next", "Later"])
        #expect(fetchCount == 2)
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

private func billingInvoice(schoolId: UUID, parentId: UUID) -> ZelleInvoice {
    ZelleInvoice(
        id: UUID(),
        schoolId: schoolId,
        payerUserId: parentId,
        payerRole: .parent,
        childId: nil,
        onboardingRequirementInstanceId: nil,
        invoiceNumber: "ZL-TEST-001",
        description: "Test tuition",
        currency: "USD",
        amountDueCents: 10000,
        amountPaidCents: 0,
        status: .open,
        dueAt: Date().addingTimeInterval(86400),
        issuedAt: Date(),
        paidAt: nil,
        voidedAt: nil,
        createdAt: Date()
    )
}

private enum TestFeatureError: Error {
    case expected
}

@MainActor
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

    func signUp(
        withEmail email: String,
        password: String,
        firstName: String,
        lastName: String,
        role: SignupRole,
        legalAcceptance: LegalAcceptance
    ) async throws -> AuthenticationState {
        .authenticated
    }

    func signOut() async throws {
        try await Task.sleep(nanoseconds: delayNanoseconds)
    }

    func getAuthState() async throws -> AuthenticationState {
        .authenticated
    }

}
