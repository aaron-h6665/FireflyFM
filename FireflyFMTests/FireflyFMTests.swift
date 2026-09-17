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
        #expect(AppSessionManager.requiredSchemaVersion == 20260915140000)
    }

    @Test func paperworkAssignmentRecipientDecodesWithParentOrUserId() throws {
        let assignmentId = UUID()
        let idVal = UUID()

        let legacyJson = """
        {
            "assignment_id": "\(assignmentId.uuidString)",
            "parent_id": "\(idVal.uuidString)"
        }
        """.data(using: .utf8)!
        let legacyRecipient = try JSONDecoder().decode(PaperworkAssignmentRecipient.self, from: legacyJson)
        #expect(legacyRecipient.assignmentId == assignmentId)
        #expect(legacyRecipient.parentId == idVal)
        #expect(legacyRecipient.userId == idVal)

        let normalizedJson = """
        {
            "assignment_id": "\(assignmentId.uuidString)",
            "user_id": "\(idVal.uuidString)"
        }
        """.data(using: .utf8)!
        let normalizedRecipient = try JSONDecoder().decode(PaperworkAssignmentRecipient.self, from: normalizedJson)
        #expect(normalizedRecipient.assignmentId == assignmentId)
        #expect(normalizedRecipient.parentId == idVal)
        #expect(normalizedRecipient.userId == idVal)

        let conflictingJson = """
        {
            "assignment_id": "\(assignmentId.uuidString)",
            "parent_id": "\(idVal.uuidString)",
            "user_id": "\(UUID().uuidString)"
        }
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PaperworkAssignmentRecipient.self, from: conflictingJson)
        }
    }

    @Test func paperworkSubmissionSelectsLatestAttemptPerSubmitter() {
        let assignmentId = UUID()
        let schoolId = UUID()
        let firstSubmitter = UUID()
        let secondSubmitter = UUID()
        let oldest = PaperworkSubmission(
            assignmentId: assignmentId,
            schoolId: schoolId,
            submittedBy: firstSubmitter,
            status: "changes_requested",
            attemptNumber: 1,
            submittedAt: Date(timeIntervalSince1970: 100)
        )
        let latest = PaperworkSubmission(
            assignmentId: assignmentId,
            schoolId: schoolId,
            submittedBy: firstSubmitter,
            status: "resubmitted",
            attemptNumber: 2,
            submittedAt: Date(timeIntervalSince1970: 200)
        )
        let other = PaperworkSubmission(
            assignmentId: assignmentId,
            schoolId: schoolId,
            submittedBy: secondSubmitter,
            submittedAt: Date(timeIntervalSince1970: 150)
        )

        let selected = PaperworkSubmission.latestPerSubmitter(in: [oldest, other, latest])
        #expect(selected.map(\.id) == [latest.id, other.id])
    }

    @Test @MainActor func paperworkWorkspaceModelInitialStateAndNilSchool() async {
        let model = PaperworkWorkspaceModel()
        #expect(model.items.isEmpty)
        #expect(!model.isLoading)
        #expect(model.errorMessage == nil)

        await model.load(schoolId: nil, crossSchool: false, archived: false)
        #expect(model.items.isEmpty)
        #expect(!model.isLoading)
        #expect(model.errorMessage == nil)
    }
    @Test func reviewedGoogleFormResponsesAreArchivedAndReadOnly() {
        for status in ["pending_review", "ambiguous", "error"] {
            #expect(GoogleFormResponseArchiveFilter.active.includes(status: status))
            #expect(GoogleFormResponsePresentation.canReview(status: status))
        }
        for status in ["approved", "rejected", "changes_requested"] {
            #expect(GoogleFormResponseArchiveFilter.archived.includes(status: status))
            #expect(!GoogleFormResponsePresentation.canReview(status: status))
        }
    }

    @Test func googleFormWaitingStateRemainsOpenable() {
        #expect(GoogleFormRecipientPresentation.canOpen(status: "awaiting_sync"))
        #expect(GoogleFormRecipientPresentation.canOpen(status: nil))
        #expect(GoogleFormRecipientPresentation.canOpen(status: "changes_requested"))
        #expect(!GoogleFormRecipientPresentation.canOpen(status: "approved"))
        #expect(!GoogleFormRecipientPresentation.canOpen(status: "pending_review"))
    }

    @Test func googleFormAnswersUseTitlesAndHideTheRoutingReference() {
        let token = String(repeating: "a", count: 64)
        let rows = GoogleFormAnswerPresentation.rows(
            payload: [
                "1e56dc1f": .string("2022-01-02"),
                "7181a7e3": .string(token),
                "unmapped": .string("Extra answer")
            ],
            questions: [
                .init(id: "1e56dc1f", title: "Date of Birth", fieldKey: "child_birthdate"),
                .init(id: "7181a7e3", title: "FireflyFM submission reference", fieldKey: "submission_reference")
            ]
        )

        #expect(rows.map(\.title) == ["Date of Birth", "Question 2"])
        #expect(rows.map(\.value) == ["2022-01-02", "Extra answer"])
        #expect(!rows.contains(where: { $0.id == "7181a7e3" }))
    }

    @Test func googleFormResumeSurvivesNewStoreInstanceAndSeparatesAccounts() {
        var entries: [String: Data] = [:]
        let store = GoogleFormResumeStore(read: { entries[$0] }, write: { entries[$0] = $1 })
        let connection = UUID(), user = UUID()
        let key = GoogleFormResumeStore.key(backend: "test", userId: user, connectionId: connection)
        let token = String(repeating: "a", count: 64)
        let now = Date()
        store.save(.init(connectionId: connection,
            launchURL: "https://docs.google.com/forms/d/e/test/viewform?entry.1904322531=\(token)",
            expiresAt: now.addingTimeInterval(7200)), for: key)
        let reopened = GoogleFormResumeStore(read: { entries[$0] }, write: { entries[$0] = $1 })
        #expect(reopened.token(for: key, now: now) == token)
        #expect(reopened.token(for: GoogleFormResumeStore.key(backend: "test", userId: UUID(), connectionId: connection)) == nil)
        #expect(reopened.token(for: GoogleFormResumeStore.key(backend: "other", userId: user, connectionId: connection)) == nil)
        #expect(reopened.token(for: key, now: now.addingTimeInterval(7201)) == nil)
        #expect(entries[key] == nil)
    }

    @Test func assignmentConversationHeightIsResponsiveAndClamped() {
        #expect(AssignmentConversationLayout.maximumHeight(for: 500) == 240)
        #expect(AssignmentConversationLayout.maximumHeight(for: 1_000) == 350)
        #expect(AssignmentConversationLayout.maximumHeight(for: 1_500) == 420)
    }

    @Test @MainActor func parentAssignmentLoadSkipsManagerReviewQueue() async {
        var inboxCallCount = 0
        var reviewCallCount = 0
        let model = AssignmentListModel(client: AssignmentListClient(
            fetchSchools: { [] },
            fetchInbox: { _, _ in
                inboxCallCount += 1
                return []
            },
            fetchReviewQueue: { _, _, _ in
                reviewCallCount += 1
                throw URLError(.timedOut)
            }
        ))

        await model.load(
            schoolId: UUID(),
            categories: nil,
            archived: false,
            reviewOnly: false,
            canReview: false
        )

        #expect(inboxCallCount == 1)
        #expect(reviewCallCount == 0)
        #expect(model.phase == .empty)
        #expect(model.errorMessage == nil)
    }

    @Test @MainActor func assignmentComposerLoadsOptionsForEverySelectedSchool() async {
        let firstSchoolId = UUID()
        let secondSchoolId = UUID()
        var memberLoads = Set<UUID>()
        var childLoads = Set<UUID>()
        let model = AssignmentComposerModel(client: AssignmentComposerClient(
            fetchMembers: { schoolId in
                memberLoads.insert(schoolId)
                return []
            },
            fetchChildren: { schoolId in
                childLoads.insert(schoolId)
                return []
            },
            create: { _ in throw URLError(.unsupportedURL) }
        ))

        await model.load(schoolIds: [firstSchoolId, secondSchoolId])

        #expect(memberLoads == [firstSchoolId, secondSchoolId])
        #expect(childLoads == [firstSchoolId, secondSchoolId])
        #expect(Set(model.membersBySchool.keys) == [firstSchoolId, secondSchoolId])
        #expect(Set(model.childrenBySchool.keys) == [firstSchoolId, secondSchoolId])
        #expect(model.phase == .loaded)
    }

    @Test @MainActor func assignmentComposerRetriesOnlySchoolsThatFailed() async throws {
        let firstSchoolId = UUID()
        let secondSchoolId = UUID()
        var attempts: [UUID: Int] = [:]
        let model = AssignmentComposerModel(client: AssignmentComposerClient(
            fetchMembers: { _ in [] },
            fetchChildren: { _ in [] },
            create: { draft in
                attempts[draft.schoolId, default: 0] += 1
                if draft.schoolId == secondSchoolId, attempts[draft.schoolId] == 1 {
                    throw URLError(.timedOut)
                }
                return testAssignment(schoolId: draft.schoolId)
            }
        ))
        let drafts = [
            testAssignmentDraft(schoolId: firstSchoolId, idempotencyKey: "first"),
            testAssignmentDraft(schoolId: secondSchoolId, idempotencyKey: "second")
        ]

        #expect(await model.save(drafts) == false)
        #expect(attempts[firstSchoolId] == 1)
        #expect(attempts[secondSchoolId] == 1)
        #expect(model.errorMessage?.contains("1 of 2 schools") == true)

        #expect(await model.save(drafts))
        #expect(attempts[firstSchoolId] == 1)
        #expect(attempts[secondSchoolId] == 2)
        #expect(model.errorMessage == nil)
    }

    @Test @MainActor func assignmentRecipientSelectionKeepsTheSamePersonDistinctAcrossSchools() {
        let userId = UUID()
        let firstSchoolId = UUID()
        let secondSchoolId = UUID()

        let first = AssignmentRecipientSelectionKey(schoolId: firstSchoolId, userId: userId)
        let second = AssignmentRecipientSelectionKey(schoolId: secondSchoolId, userId: userId)

        #expect(first != second)
        #expect(Set([first, second]).count == 2)
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

    @Test func assignmentFileImportSourcesExposeGoogleDriveAndFiles() {
        #expect(AssignmentFileImportSource.allCases == [.googleDrive, .files])
        #expect(AssignmentFileImportSource.googleDrive.title == "Google Drive")
        #expect(AssignmentFileImportSource.googleDrive.pickerHelp?.contains("Locations") == true)
        #expect(AssignmentFileImportSource.files.pickerHelp == nil)
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
        #expect(AppErrorMessage.isCancellation(NSError(
            domain: "Swift.CancellationError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed. (Swift.CancellationError error 1.)"]
        )))

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

    @Test func zelleNotificationsOpenTheReferencedInvoice() throws {
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

        let expected = NotificationFeatureDestination.zelleInvoice(invoiceId, schoolId: schoolId)
        #expect(resolver.resolve(try JSONDecoder().decode(NotificationInboxItem.self, from: sourceJSON)) == expected)
        #expect(resolver.resolve(try JSONDecoder().decode(NotificationInboxItem.self, from: legacyJSON)) == expected)
    }

    @Test func zelleNotificationWithoutAnInvoiceFallsBackToBilling() throws {
        let json = """
        {
          "id": "\(UUID())", "school_id": "\(UUID())", "school_name": "Beta School",
          "title": "Payment update", "body": "Open payments.",
          "category": "zelle_payment", "source_type": "zelle_invoice"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(NotificationInboxItem.self, from: json)
        #expect(NotificationDestinationResolver().resolve(item) == .billing)
    }

    @Test func googleFormResponseNotificationOpensDirectorReviewQueue() throws {
        let json = """
        {
          "id": "\(UUID())", "school_id": "\(UUID())", "school_name": "Beta School",
          "title": "New onboarding Form response", "body": "A response is ready for review.",
          "category": "google_form_response", "source_type": "google_form_import", "source_id": "\(UUID())"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(NotificationInboxItem.self, from: json)
        #expect(NotificationDestinationResolver().resolve(item) == .googleFormReview)
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
        #expect(SchoolRole.parent.has(.viewPaperwork))
        #expect(SchoolRole.teacher.has(.viewPaperwork))
        #expect(!SchoolRole.teacher.has(.viewBilling))
        #expect(!SchoolRole.teacher.has(.payInvoices))
        #expect(SchoolRole.schoolDirector.has(.createPaperwork))
        #expect(SchoolRole.hqDirector.has(.reviewPaperwork))
        #expect(!SchoolRole.parent.has(.createPaperwork))
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

    @Test func hqDirectorCrossSchoolChatCapabilities() {
        let hqPolicy = ChatAccessPolicy(context: AppAccessContext(role: .hqDirector))
        let directorPolicy = ChatAccessPolicy(context: AppAccessContext(role: .schoolDirector, activeSchoolId: UUID()))
        let teacherPolicy = ChatAccessPolicy(context: AppAccessContext(role: .teacher, activeSchoolId: UUID()))
        let parentPolicy = ChatAccessPolicy(context: AppAccessContext(role: .parent, activeSchoolId: UUID()))

        #expect(hqPolicy.canCreateHQRoom)
        #expect(hqPolicy.canManageHQRoom)
        #expect(hqPolicy.canCreateAnyRoom)
        #expect(!hqPolicy.canCreateSchoolRoom)

        #expect(!directorPolicy.canCreateHQRoom)
        #expect(directorPolicy.canCreateSchoolRoom)
        #expect(directorPolicy.canCreateAnyRoom)

        #expect(!teacherPolicy.canCreateHQRoom)
        #expect(!teacherPolicy.canCreateSchoolRoom)
        #expect(!teacherPolicy.canCreateAnyRoom)

        #expect(!parentPolicy.canCreateHQRoom)
        #expect(!parentPolicy.canCreateSchoolRoom)
        #expect(!parentPolicy.canCreateAnyRoom)

        let hqRoom = ChatRoom(name: "Cross Campus Leadership", roomType: "hq_custom", systemManaged: false)
        let schoolRoom = ChatRoom(name: "Classroom updates", schoolId: UUID(), roomType: "custom", systemManaged: false)

        #expect(hqRoom.isHQCustomRoom)
        #expect(!schoolRoom.isHQCustomRoom)

        #expect(hqPolicy.canManage(room: hqRoom))
        #expect(!hqPolicy.canManage(room: schoolRoom))
        #expect(!directorPolicy.canManage(room: hqRoom))
    }

    @Test func chatParticipantInvitedStateDistinction() {
        let member = ChatParticipant(roomId: UUID(), userId: UUID(), role: "member")
        let invited = ChatParticipant(roomId: UUID(), userId: UUID(), role: "invited")
        let owner = ChatParticipant(roomId: UUID(), userId: UUID(), role: "owner")

        #expect(!member.isInvited)
        #expect(invited.isInvited)
        #expect(!owner.isInvited)
        #expect(owner.isOwner)
    }

    @Test func hqDirectoryEntryDecodingAndRoleTitle() throws {
        let json = """
        {
            "user_id": "11111111-1111-1111-1111-111111111111",
            "display_name": "Jane Doe",
            "avatar_url": null,
            "role": "teacher",
            "school_id": "22222222-2222-2222-2222-222222222222",
            "school_name": "Sunset Valley"
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(HQDirectoryEntry.self, from: json)
        #expect(entry.userId == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(entry.displayName == "Jane Doe")
        #expect(entry.roleTitle == "Teacher")
        #expect(entry.schoolName == "Sunset Valley")
        #expect(entry.initials == "JD")
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
        #expect(!assignmentPolicy.canAssign(to: .parent, category: .paperwork))
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
        #expect(!assignmentPolicy.canAssign(
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

        let paperworkPolicy = PaperworkAccessPolicy(context: director)
        #expect(paperworkPolicy.canView)
        #expect(paperworkPolicy.canCreate)
        #expect(paperworkPolicy.canReview)

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
        #expect(PaymentAccessPolicy(context: hq).canManage)
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
        let teacherId = UUID()
        let teacher = PaymentAccessPolicy(context: AppAccessContext(userId: teacherId, role: .teacher, activeSchoolId: schoolId))

        #expect(namedParent.canView)
        #expect(namedParent.canPay(invoice: invoice))
        #expect(!otherParent.canPay(invoice: invoice))
        #expect(director.canManage)
        #expect(director.canReview(invoice: invoice))
        #expect(!director.canPay(invoice: invoice))
        #expect(!teacher.canView)

        var teacherOnboardingInvoice = invoice
        teacherOnboardingInvoice.payerUserId = teacherId
        teacherOnboardingInvoice.payerRole = .teacher
        teacherOnboardingInvoice.originalOnboardingRequirementId = UUID()
        let assignedTeacher = PaymentAccessPolicy(context: AppAccessContext(
            userId: teacherOnboardingInvoice.payerUserId,
            role: .teacher,
            activeSchoolId: schoolId
        ))
        #expect(!assignedTeacher.canView)
        #expect(assignedTeacher.canPay(invoice: teacherOnboardingInvoice))
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

    @Test func paymentAmountsRejectMalformedAndOutOfRangeInput() {
        #expect(PaymentAmountParser.cents(from: "$1,234.56") == 123456)
        #expect(PaymentAmountParser.cents(from: " 12.50 ") == 1250)
        #expect(PaymentAmountParser.cents(from: ".50") == 50)
        #expect(PaymentAmountParser.cents(from: "1000000") == 100000000)
        for invalid in ["12abc", "1,23", "1e5", "-10", "NaN", "1.999", "1000000.01",
                        "999999999999999999999999999999999999999999999999999999", "$$10"] {
            #expect(PaymentAmountParser.cents(from: invalid) == 0)
        }
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

    @Test @MainActor func paymentsModelPreventsOverlappingInvoiceRequests() async {
        let schoolId = UUID()
        let invoice = billingInvoice(schoolId: schoolId, parentId: UUID())
        var calls = 0
        var resume: CheckedContinuation<Void, Never>?
        let model = PaymentsModel(client: PaymentsClient(
            fetchProfile: { _ in nil }, fetchInvoices: { _ in [] }, fetchInvoice: { _ in invoice },
            fetchItems: { _ in [] }, fetchSubmissions: { _ in [] }, fetchParents: { _ in [] },
            fetchChildren: { _ in [] }, fetchSchools: { [] },
            saveProfile: { _ in throw TestFeatureError.expected },
            createInvoice: { _ in
                calls += 1
                await withCheckedContinuation { resume = $0 }
                return invoice
            },
            submitPayment: { _ in throw TestFeatureError.expected },
            reviewPayment: { _, _, _ in invoice }, voidInvoice: { _, _ in invoice }
        ))
        let policy = PaymentAccessPolicy(context: AppAccessContext(
            userId: UUID(), role: .schoolDirector, activeSchoolId: schoolId
        ))
        let draft = ZelleInvoiceDraft(schoolId: schoolId, payerUserId: invoice.payerUserId,
            childId: nil, description: "Tuition", dueAt: nil,
            items: [.init(description: "Tuition", quantity: 1, unitAmountCents: 500)],
            idempotencyKey: "test-overlap")
        let first = Task { await model.createInvoice(draft, policy: policy) }
        while resume == nil { await Task.yield() }
        #expect(model.isMutating)
        #expect(await model.createInvoice(draft, policy: policy) == false)
        #expect(calls == 1)
        #expect(model.isMutating)
        resume?.resume()
        #expect(await first.value)
        #expect(!model.isMutating)
        #expect(model.invoices.count == 1)
    }

    @Test @MainActor func hqDirectorCanManageBillingAndInspectFeeSummaries() async throws {
        let schoolA = School(id: UUID(), name: "Maple Academy")
        let schoolB = School(id: UUID(), name: "Pine Pre-K")
        let parentId = UUID()

        var invA1 = billingInvoice(schoolId: schoolA.id, parentId: parentId)
        invA1.status = .paid
        invA1.amountDueCents = 15000
        invA1.amountPaidCents = 15000

        var invA2 = billingInvoice(schoolId: schoolA.id, parentId: parentId)
        invA2.status = .open
        invA2.amountDueCents = 10000
        invA2.amountPaidCents = 0
        invA2.dueAt = Calendar.current.date(byAdding: .day, value: -2, to: Date())

        var invB1 = billingInvoice(schoolId: schoolB.id, parentId: parentId)
        invB1.status = .paid
        invB1.amountDueCents = 25000
        invB1.amountPaidCents = 25000

        let client = PaymentsClient(
            fetchProfile: { _ in nil },
            fetchInvoices: { _ in [invA1, invA2, invB1] },
            fetchInvoice: { _ in nil },
            fetchItems: { _ in [] },
            fetchSubmissions: { _ in [] },
            fetchParents: { _ in [] },
            fetchChildren: { _ in [] },
            fetchSchools: { [schoolA, schoolB] },
            saveProfile: { _ in throw TestFeatureError.expected },
            createInvoice: { _ in throw TestFeatureError.expected },
            submitPayment: { _ in throw TestFeatureError.expected },
            reviewPayment: { _, _, _ in throw TestFeatureError.expected },
            voidInvoice: { _, _ in throw TestFeatureError.expected }
        )

        let hqPolicy = PaymentAccessPolicy(context: AppAccessContext(
            userId: UUID(),
            role: .hqDirector,
            activeSchoolId: schoolA.id
        ))

        #expect(hqPolicy.canManage)
        #expect(hqPolicy.hasCrossSchoolScope)
        #expect(hqPolicy.canReview(invoice: invA1))
        #expect(hqPolicy.canReview(invoice: invB1))

        let model = PaymentsModel(client: client)
        await model.load(schoolId: schoolA.id, policy: hqPolicy)

        #expect(model.schools.count == 2)
        #expect(model.invoices.count == 3)

        #expect(model.collectedCents == 40000)
        #expect(model.outstandingCents == 10000)
        #expect(model.overdueCount == 1)

        #expect(model.invoices(for: schoolA.id).count == 2)
        #expect(model.collectedCents(for: schoolA.id) == 15000)
        #expect(model.outstandingCents(for: schoolA.id) == 10000)
        #expect(model.overdueCount(for: schoolA.id) == 1)

        #expect(model.invoices(for: schoolB.id).count == 1)
        #expect(model.collectedCents(for: schoolB.id) == 25000)
        #expect(model.outstandingCents(for: schoolB.id) == 0)
        #expect(model.overdueCount(for: schoolB.id) == 0)

        let summaries = model.feeSummaries()
        #expect(summaries.count == 2)
        let mapleSummary = try #require(summaries.first(where: { $0.school.id == schoolA.id }))
        #expect(mapleSummary.collectedCents == 15000)
        #expect(mapleSummary.outstandingCents == 10000)
        #expect(mapleSummary.invoiceCount == 2)
        #expect(mapleSummary.overdueCount == 1)

        let pineSummary = try #require(summaries.first(where: { $0.school.id == schoolB.id }))
        #expect(pineSummary.collectedCents == 25000)
        #expect(pineSummary.outstandingCents == 0)
        #expect(pineSummary.invoiceCount == 1)
        #expect(pineSummary.overdueCount == 0)
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

    @Test @MainActor func eventEditorLoadsMembersForEverySelectedSchool() async {
        let schoolA = UUID()
        let schoolB = UUID()
        let memberA = SchoolMember(
            membership: SchoolMembership(id: UUID(), schoolId: schoolA, userId: UUID(), role: .teacher, active: true),
            profile: nil
        )
        let memberB = SchoolMember(
            membership: SchoolMembership(id: UUID(), schoolId: schoolB, userId: UUID(), role: .teacher, active: true),
            profile: nil
        )

        var requestedSchoolIds: [UUID] = []
        let client = EventEditorClient(
            create: { _, _, _, _, _, _, _, _ in },
            update: { _, _, _, _, _, _, _ in },
            fetchMembers: { schoolId in
                requestedSchoolIds.append(schoolId)
                if schoolId == schoolA {
                    return [memberA]
                } else if schoolId == schoolB {
                    return [memberB]
                }
                return []
            }
        )

        let model = EventEditorModel(client: client)
        await model.loadMembers(schoolIds: [schoolA, schoolB])

        #expect(Set(requestedSchoolIds) == [schoolA, schoolB])
        #expect(model.membersBySchool[schoolA]?.count == 1)
        #expect(model.membersBySchool[schoolB]?.count == 1)
    }

    @Test @MainActor func eventEditorRetriesOnlySchoolsThatFailed() async {
        let schoolA = UUID()
        let schoolB = UUID()
        var createdSchoolIds: [UUID] = []
        var shouldSchoolBFail = true

        let client = EventEditorClient(
            create: { schoolId, _, _, _, _, _, _, _ in
                if schoolId == schoolB && shouldSchoolBFail {
                    throw TestFeatureError.expected
                }
                createdSchoolIds.append(schoolId)
            },
            update: { _, _, _, _, _, _, _ in },
            fetchMembers: { _ in [] }
        )

        let model = EventEditorModel(client: client)
        let drafts = [
            EventCreationDraft(
                schoolId: schoolA,
                title: "Field Trip",
                description: nil,
                startAt: Date(),
                endAt: Date().addingTimeInterval(3600),
                allDay: false,
                repeatRule: nil,
                invitedUserIds: [],
                idempotencyKey: "mutation-\(schoolA)"
            ),
            EventCreationDraft(
                schoolId: schoolB,
                title: "Field Trip",
                description: nil,
                startAt: Date(),
                endAt: Date().addingTimeInterval(3600),
                allDay: false,
                repeatRule: nil,
                invitedUserIds: [],
                idempotencyKey: "mutation-\(schoolB)"
            )
        ]

        let firstResult = await model.save(drafts: drafts)
        #expect(firstResult == false)
        #expect(createdSchoolIds == [schoolA])
        #expect(model.errorMessage?.contains("Event created for 1 of 2 schools") == true)

        // Retry: schoolB now succeeds
        shouldSchoolBFail = false
        let retryResult = await model.save(drafts: drafts)
        #expect(retryResult == true)
        // schoolA should NOT be created again
        #expect(createdSchoolIds == [schoolA, schoolB])
        #expect(model.errorMessage == nil)
    }

    @Test func eventRecipientSelectionKeepsSamePersonDistinctAcrossSchools() {
        let personId = UUID()
        let schoolA = UUID()
        let schoolB = UUID()

        let keyA = EventRecipientSelectionKey(schoolId: schoolA, userId: personId)
        let keyB = EventRecipientSelectionKey(schoolId: schoolB, userId: personId)

        #expect(keyA != keyB)
        var selection = Set<EventRecipientSelectionKey>()
        selection.insert(keyA)
        #expect(selection.contains(keyA))
        #expect(!selection.contains(keyB))
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

private func testAssignmentDraft(schoolId: UUID, idempotencyKey: String) -> AssignmentDraft {
    AssignmentDraft(
        schoolId: schoolId,
        title: "Test assignment",
        description: nil,
        category: .training,
        audienceRole: .teacher,
        childId: nil,
        dueAt: nil,
        recipientIds: [UUID()],
        materialURLs: [],
        materialType: "file",
        materialFileURLs: [],
        status: "published",
        publishAt: nil,
        idempotencyKey: idempotencyKey
    )
}

private func testAssignment(schoolId: UUID) -> Assignment {
    Assignment(
        id: UUID(),
        schoolId: schoolId,
        childId: nil,
        title: "Test assignment",
        description: nil,
        category: .training,
        audienceRole: .teacher,
        assignedBy: UUID(),
        dueAt: nil,
        publishAt: nil,
        closeAt: nil,
        status: "published",
        visibility: "assigned",
        requiresReview: true,
        allowResubmission: true,
        legacySourceType: nil,
        legacySourceId: nil,
        createdAt: Date(),
        updatedAt: Date(),
        currentRevisionId: nil
    )
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
