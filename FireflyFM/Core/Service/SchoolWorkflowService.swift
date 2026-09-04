//
//  SchoolWorkflowService.swift
//  FireflyFM
//

import Foundation
import Supabase

struct CommunityMediaUpload: Hashable {
    let data: Data
    let fileName: String
    let contentType: String?
}

struct NewsletterMediaUpload: Hashable {
    let data: Data
    let fileName: String
    let contentType: String?
    let altText: String?
    let caption: String?
    let layout: NewsletterMediaLayout
    let linkURL: String?
}

struct OnboardingAttachmentDescriptor: Codable, Hashable {
    let privateFilePath: String
    let fileName: String
    let contentType: String?

    enum CodingKeys: String, CodingKey {
        case privateFilePath = "private_file_path"
        case fileName = "file_name"
        case contentType = "content_type"
    }
}

struct AssignmentDetailBundle {
    let assignment: Assignment
    let capabilities: AssignmentViewerCapabilities
    let materials: [AssignmentMaterial]
    let recipients: [AssignmentRecipient]
    let submissions: [AssignmentSubmission]
    let attachments: [AssignmentSubmissionAttachment]
    let readReceipts: [AssignmentReadReceipt]
    let feedbackMessages: [AssignmentFeedbackMessage]
    let events: [AssignmentEvent]
}

struct AssignmentMaterialUpdate: Identifiable, Hashable {
    let id: UUID
    var materialType: String
    var title: String
    var url: String?
    var privateFilePath: String?
    var fileName: String?
    var contentType: String?
    var localFileURL: URL?

    nonisolated init(
        id: UUID = UUID(),
        materialType: String = "file",
        title: String = "",
        url: String? = nil,
        privateFilePath: String? = nil,
        fileName: String? = nil,
        contentType: String? = nil,
        localFileURL: URL? = nil
    ) {
        self.id = id
        self.materialType = materialType
        self.title = title
        self.url = url
        self.privateFilePath = privateFilePath
        self.fileName = fileName
        self.contentType = contentType
        self.localFileURL = localFileURL
    }

    nonisolated init(material: AssignmentMaterial) {
        self.init(
            id: material.id,
            materialType: material.materialType,
            title: material.title ?? material.fileName ?? "",
            url: material.url,
            privateFilePath: material.privateFilePath,
            fileName: material.fileName,
            contentType: material.contentType
        )
    }
}

private struct AssignmentDetailPayload: Decodable {
    let assignment: Assignment
    let capabilities: AssignmentViewerCapabilities
    let materials: [AssignmentMaterial]
    let recipients: [AssignmentRecipient]
    let submissions: [AssignmentSubmission]
    let attachments: [AssignmentSubmissionAttachment]
    let readReceipts: [AssignmentReadReceipt]
    let feedbackMessages: [AssignmentFeedbackMessage]
    let events: [AssignmentEvent]

    enum CodingKeys: String, CodingKey {
        case assignment, capabilities, materials, recipients, submissions, attachments, events
        case readReceipts = "read_receipts"
        case feedbackMessages = "feedback_messages"
    }
}

final class SchoolWorkflowService {
    static let shared = SchoolWorkflowService()

    private let client = AppConstants.supabase

    private init() {}

    // MARK: - Canvas Assignments

    func fetchAssignmentInbox(categories: [AssignmentCategory]? = nil, archived: Bool = false) async throws -> [AssignmentInboxItem] {
        _ = try await client.rpc("publish_due_assignments").execute()
        return try await client.rpc(
            "fetch_my_assignment_agenda_v2",
            params: AssignmentAgendaFetchParams(categories: categories?.map(\.rawValue), archived: archived)
        )
        .execute()
        .value
    }

    func fetchAssignmentReviewQueue(schoolId: UUID, categories: [AssignmentCategory]? = nil, archived: Bool = false) async throws -> [AssignmentInboxItem] {
        try await client.rpc(
            "fetch_my_assignment_review_queue_v2",
            params: AssignmentFetchParams(
                schoolId: schoolId,
                categories: categories?.map(\.rawValue),
                archived: archived
            )
        )
        .execute()
        .value
    }

    func fetchAssignmentDetail(assignmentId: UUID) async throws -> AssignmentDetailBundle {
        let payloads: [AssignmentDetailPayload] = try await client.rpc(
            "fetch_assignment_detail",
            params: AssignmentIdParams(assignmentId: assignmentId)
        )
        .execute()
        .value

        guard let payload = payloads.first else {
            throw SchoolWorkflowError.notFound
        }

        return AssignmentDetailBundle(
            assignment: payload.assignment,
            capabilities: payload.capabilities,
            materials: payload.materials,
            recipients: payload.recipients,
            submissions: payload.submissions,
            attachments: payload.attachments,
            readReceipts: payload.readReceipts,
            feedbackMessages: payload.feedbackMessages,
            events: payload.events
        )
    }

    func createAssignment(
        schoolId: UUID,
        title: String,
        description: String?,
        category: AssignmentCategory,
        audienceRole: SchoolRole?,
        childId: UUID?,
        dueAt: Date?,
        recipientIds: [UUID],
        materialURLs: [String],
        materialType: String,
        materialFileURLs: [URL],
        status: String,
        publishAt: Date?,
        idempotencyKey: String
    ) async throws -> Assignment {
        let linkMaterials = materialURLs.compactMap { value -> AssignmentCreateMaterial? in
            let cleanURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleanURL.isEmpty == false else { return nil }
            return AssignmentCreateMaterial(
                materialType: materialType,
                title: "Link",
                url: cleanURL,
                privateFilePath: nil,
                fileName: nil,
                contentType: nil
            )
        }

        let assignments: [Assignment] = try await client.rpc(
            "create_assignment_v2",
            params: CreateAssignmentParams(
                schoolId: schoolId,
                title: title,
                description: description,
                category: category.rawValue,
                audienceRole: audienceRole?.rawValue,
                childId: childId,
                dueAt: dueAt,
                requiresReview: true,
                recipientIds: recipientIds,
                materials: linkMaterials,
                status: status,
                publishAt: publishAt,
                closeAt: nil,
                idempotencyKey: idempotencyKey
            )
        )
        .execute()
        .value

        guard let assignment = assignments.first else {
            throw SchoolWorkflowError.notFound
        }

        var uploadedMaterials: [AssignmentMaterialInsert] = []
        for materialFileURL in materialFileURLs {
            let safeName = SchoolService.shared.safeStorageFileName(for: materialFileURL)
            let path = "schools/\(schoolId.uuidString)/assignments/\(assignment.id.uuidString)/materials/\(UUID().uuidString)/\(safeName)"
            let upload = try await SchoolService.shared.uploadPrivateFile(fileURL: materialFileURL, path: path)
            uploadedMaterials.append(
                AssignmentMaterialInsert(
                    assignmentId: assignment.id,
                    materialType: materialType,
                    title: upload.name,
                    url: nil,
                    privateFilePath: upload.path,
                    fileName: upload.name,
                    contentType: upload.contentType
                )
            )
        }
        if uploadedMaterials.isEmpty == false {
            try await client.from("assignment_materials")
                .insert(uploadedMaterials)
                .execute()
        }

        return assignment
    }

    func markAssignmentViewed(assignmentId: UUID) async throws {
        _ = try await client.rpc(
            "mark_assignment_viewed",
            params: AssignmentIdParams(assignmentId: assignmentId)
        )
        .execute()
    }

    func acknowledgeAssignment(assignmentId: UUID) async throws {
        _ = try await client.rpc(
            "acknowledge_assignment",
            params: AssignmentIdParams(assignmentId: assignmentId)
        )
        .execute()
    }

    @available(*, deprecated, message: "Use acknowledgeAssignment(assignmentId:) for explicit acknowledgment.")
    func markAssignmentRead(assignmentId: UUID) async throws {
        try await acknowledgeAssignment(assignmentId: assignmentId)
    }

    func submitAssignment(
        assignment: Assignment,
        fileURLs: [URL],
        feedbackText: String?,
        idempotencyKey: String,
        structuredPayload: [String: FireflyJSONValue] = [:]
    ) async throws -> AssignmentSubmission {
        let priorResults: [AssignmentSubmission] = try await client.rpc(
            "fetch_assignment_submission_mutation",
            params: AssignmentSubmissionMutationLookupParams(
                assignmentId: assignment.id,
                idempotencyKey: idempotencyKey
            )
        )
        .execute()
        .value
        if let priorResult = priorResults.first {
            return priorResult
        }

        let user = try await client.auth.session.user
        var uploads: [SchoolFileUpload] = []
        for (index, fileURL) in fileURLs.enumerated() {
            let safeName = SchoolService.shared.safeStorageFileName(for: fileURL)
            let path = "schools/\(assignment.schoolId.uuidString)/assignments/\(assignment.id.uuidString)/submissions/\(user.id.uuidString)/\(idempotencyKey)/\(index)-\(safeName)"
            uploads.append(try await SchoolService.shared.uploadPrivateFile(fileURL: fileURL, path: path))
        }
        do {
            let submissions: [AssignmentSubmission] = try await client.rpc(
                "submit_assignment_with_payload",
                params: SubmitAssignmentParams(
                    assignmentId: assignment.id,
                    structuredPayload: structuredPayload,
                    feedbackText: feedbackText?.trimmingCharacters(in: .whitespacesAndNewlines),
                    attachments: uploads.map {
                        AssignmentAttachmentDescriptor(
                            privateFilePath: $0.path,
                            fileName: $0.name,
                            contentType: $0.contentType
                        )
                    },
                    idempotencyKey: idempotencyKey
                )
            )
            .execute()
            .value

            guard let submission = submissions.first else {
                throw SchoolWorkflowError.notFound
            }

            return submission
        } catch {
            if uploads.isEmpty == false {
                _ = try? await client.storage
                    .from("school_private_files")
                    .remove(paths: uploads.map(\.path))
            }
            throw error
        }
    }

    func fetchAssignmentChildBinding(assignmentId: UUID) async throws -> ChildRequirementBinding {
        let rawValue: String = try await client.rpc(
            "fetch_assignment_child_binding",
            params: AssignmentIdParams(assignmentId: assignmentId)
        )
        .execute()
        .value
        return ChildRequirementBinding(rawValue: rawValue) ?? .none
    }

    func reviewAssignmentSubmission(
        submissionId: UUID,
        status: String,
        message: String?,
        score: Int?,
        idempotencyKey: String
    ) async throws -> AssignmentSubmission {
        let submissions: [AssignmentSubmission] = try await client.rpc(
            "review_assignment_submission_v2",
            params: ReviewAssignmentSubmissionParams(
                submissionId: submissionId,
                status: status,
                reviewerMessage: message,
                idempotencyKey: idempotencyKey,
                score: score
            )
        )
        .execute()
        .value

        guard let submission = submissions.first else {
            throw SchoolWorkflowError.notFound
        }
        return submission
    }

    func updateAssignment(
        assignment: Assignment,
        title: String,
        description: String?,
        dueAt: Date?,
        allowResubmission: Bool,
        materials: [AssignmentMaterialUpdate]
    ) async throws -> Assignment {
        var uploadedPaths: [String] = []
        var descriptors: [AssignmentMaterialMutation] = []
        do {
            for material in materials {
                var path = material.privateFilePath
                var name = material.fileName
                var contentType = material.contentType
                if let localURL = material.localFileURL {
                    let safeName = SchoolService.shared.safeStorageFileName(for: localURL)
                    let uploadPath = "schools/\(assignment.schoolId.uuidString)/assignments/\(assignment.id.uuidString)/materials/\(UUID().uuidString)/\(safeName)"
                    let upload = try await SchoolService.shared.uploadPrivateFile(fileURL: localURL, path: uploadPath)
                    uploadedPaths.append(upload.path)
                    path = upload.path
                    name = upload.name
                    contentType = upload.contentType
                }
                descriptors.append(AssignmentMaterialMutation(
                    materialType: material.materialType,
                    title: material.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                    url: material.url?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                    privateFilePath: path,
                    fileName: name,
                    contentType: contentType
                ))
            }

            let assignments: [Assignment] = try await client.rpc(
                "update_assignment_v2",
                params: UpdateAssignmentDetailsParams(
                    assignmentId: assignment.id,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description?.trimmingCharacters(in: .whitespacesAndNewlines),
                    dueAt: dueAt,
                    allowResubmission: allowResubmission,
                    materials: descriptors
                )
            )
            .execute()
            .value

            guard let saved = assignments.first else { throw SchoolWorkflowError.notFound }
            return saved
        } catch {
            if uploadedPaths.isEmpty == false {
                try? await SchoolService.shared.removePrivateFiles(paths: uploadedPaths)
            }
            throw error
        }
    }

    func postAssignmentComment(
        assignmentId: UUID,
        recipientId: UUID,
        body: String,
        idempotencyKey: String
    ) async throws -> AssignmentFeedbackMessage {
        let messages: [AssignmentFeedbackMessage] = try await client.rpc(
            "post_assignment_comment_v2",
            params: PostAssignmentCommentParams(
                assignmentId: assignmentId,
                recipientId: recipientId,
                body: body.trimmingCharacters(in: .whitespacesAndNewlines),
                idempotencyKey: idempotencyKey
            )
        )
        .execute()
        .value

        guard let message = messages.first else {
            throw SchoolWorkflowError.notFound
        }
        return message
    }

    func updateAssignmentSubmissionScore(
        submissionId: UUID,
        score: Int?,
        idempotencyKey: String
    ) async throws -> AssignmentSubmission {
        let submissions: [AssignmentSubmission] = try await client.rpc(
            "update_assignment_submission_score",
            params: UpdateAssignmentScoreParams(
                submissionId: submissionId,
                score: score,
                idempotencyKey: idempotencyKey
            )
        ).execute().value
        guard let submission = submissions.first else { throw SchoolWorkflowError.notFound }
        return submission
    }

    func setAssignmentStatus(assignmentId: UUID, status: String) async throws -> Assignment {
        let assignments: [Assignment] = try await client.rpc(
            "set_assignment_status",
            params: AssignmentStatusParams(assignmentId: assignmentId, status: status)
        )
        .execute()
        .value

        guard let assignment = assignments.first else {
            throw SchoolWorkflowError.notFound
        }
        return assignment
    }

    // MARK: - Home / Newsletters

    func fetchNewsletters(schoolId: UUID) async throws -> [NewsletterPost] {
        var posts: [NewsletterPost] = try await client.from("newsletters")
            .select()
            .eq("school_id", value: schoolId)
            .order("created_at", ascending: false)
            .limit(25)
            .execute()
            .value

        for index in posts.indices {
            posts[index].media.sort {
                return $0.sortOrder < $1.sortOrder
            }
        }
        return posts
    }

    func createNewsletter(
        schoolId: UUID,
        title: String,
        body: String,
        media: [NewsletterMediaUpload] = []
    ) async throws {
        let newsletterId = UUID()
        var uploadedPaths: [String] = []
        var uploadedMedia: [NewsletterMedia] = []

        do {
            for (index, item) in media.prefix(10).enumerated() {
                let safeName = SchoolService.shared.safeStorageFileName(for: URL(fileURLWithPath: item.fileName))
                let path = "schools/\(schoolId.uuidString.lowercased())/newsletters/\(newsletterId.uuidString.lowercased())/\(index)-\(safeName)"
                let upload = try await SchoolService.shared.uploadPrivateData(
                    data: item.data,
                    path: path,
                    name: item.fileName,
                    contentType: item.contentType
                )
                uploadedPaths.append(upload.path)
                uploadedMedia.append(NewsletterMedia(
                    id: UUID(),
                    fileName: upload.name,
                    filePath: upload.path,
                    contentType: upload.contentType,
                    altText: item.altText?.nilIfBlank,
                    caption: item.caption?.nilIfBlank,
                    sortOrder: index,
                    layout: item.layout,
                    linkURL: item.linkURL?.normalizedWebURLString
                ))
            }

            try await client.rpc(
                "publish_newsletter",
                params: PublishNewsletterParams(
                    newsletterId: newsletterId,
                    schoolId: schoolId,
                    title: title,
                    body: body,
                    media: uploadedMedia,
                    idempotencyKey: newsletterId.uuidString
                )
            )
                .execute()
        } catch {
            try? await SchoolService.shared.removePrivateFiles(paths: uploadedPaths)
            throw error
        }
    }

    func updateNewsletter(
        post: NewsletterPost,
        title: String,
        body: String,
        retainedMedia: [NewsletterMedia],
        newMedia: [NewsletterMediaUpload]
    ) async throws {
        let originalsById = Dictionary(uniqueKeysWithValues: post.media.map { ($0.id, $0) })
        let safeRetained = retainedMedia.prefix(10).compactMap { edited -> NewsletterMedia? in
            guard let original = originalsById[edited.id], original.filePath == edited.filePath else {
                return nil
            }
            return NewsletterMedia(
                id: original.id,
                fileName: original.fileName,
                filePath: original.filePath,
                contentType: original.contentType,
                altText: edited.altText?.nilIfBlank,
                caption: edited.caption?.nilIfBlank,
                sortOrder: 0,
                layout: edited.layout ?? .wide,
                linkURL: edited.linkURL?.normalizedWebURLString
            )
        }
        let remainingSlots = max(0, 10 - safeRetained.count)
        let pendingUploads = Array(newMedia.prefix(remainingSlots))
        var uploadedPaths: [String] = []
        var combinedMedia = safeRetained

        do {
            for (offset, item) in pendingUploads.enumerated() {
                let index = combinedMedia.count
                let safeName = SchoolService.shared.safeStorageFileName(for: URL(fileURLWithPath: item.fileName))
                let path = "schools/\(post.schoolId.uuidString)/newsletters/\(post.id.uuidString)/\(index)-\(UUID().uuidString)-\(safeName)"
                let upload = try await SchoolService.shared.uploadPrivateData(
                    data: item.data,
                    path: path,
                    name: item.fileName,
                    contentType: item.contentType
                )
                uploadedPaths.append(upload.path)
                combinedMedia.append(NewsletterMedia(
                    id: UUID(),
                    fileName: upload.name,
                    filePath: upload.path,
                    contentType: upload.contentType,
                    altText: item.altText?.nilIfBlank,
                    caption: item.caption?.nilIfBlank,
                    sortOrder: safeRetained.count + offset,
                    layout: item.layout,
                    linkURL: item.linkURL?.normalizedWebURLString
                ))
            }

            for index in combinedMedia.indices {
                combinedMedia[index].sortOrder = index
            }

            try await client.from("newsletters")
                .update(NewsletterPostUpdate(
                    title: title,
                    body: body,
                    updatedAt: Date(),
                    media: combinedMedia
                ))
                .eq("id", value: post.id)
                .eq("school_id", value: post.schoolId)
                .execute()

            let retainedPaths = Set(combinedMedia.map(\.filePath))
            let removedPaths = post.media.map(\.filePath).filter { retainedPaths.contains($0) == false }
            try? await SchoolService.shared.removePrivateFiles(paths: removedPaths)
        } catch {
            try? await SchoolService.shared.removePrivateFiles(paths: uploadedPaths)
            throw error
        }
    }

    func deleteNewsletter(_ post: NewsletterPost) async throws {
        try await client.from("newsletters")
            .delete()
            .eq("id", value: post.id)
            .eq("school_id", value: post.schoolId)
            .execute()
        try? await SchoolService.shared.removePrivateFiles(paths: post.media.map(\.filePath))
    }

    // MARK: - Events

    func fetchEvents(schoolId: UUID, includeArchived: Bool = false) async throws -> [SchoolEvent] {
        if includeArchived {
            return try await client.from("school_events")
                .select()
                .eq("school_id", value: schoolId)
                .order("start_at", ascending: true)
                .execute()
                .value
        }
        return try await client.from("school_events")
            .select()
            .eq("school_id", value: schoolId)
            .is("archived_at", value: nil)
            .order("start_at", ascending: true)
            .execute()
            .value
    }

    func createEvent(
        schoolId: UUID,
        title: String,
        description: String?,
        startAt: Date,
        endAt: Date?,
        allDay: Bool = false,
        repeatRule: String? = nil,
        invitedUserIds: [UUID] = []
    ) async throws {
        let user = try await client.auth.session.user
        let eventId = UUID()
        let event = SchoolEvent(
            id: eventId,
            schoolId: schoolId,
            title: title,
            description: description,
            startAt: startAt,
            endAt: endAt,
            allDay: allDay,
            repeatRule: repeatRule,
            createdBy: user.id
        )
        try await client.from("school_events")
            .insert(event)
            .execute()

        if invitedUserIds.isEmpty == false {
            let invites = invitedUserIds.map {
                SchoolEventInvite(eventId: eventId, userId: $0, createdAt: Date())
            }
            try await client.from("school_event_invites")
                .insert(invites)
                .execute()
        }

        let requestedRecipients: [UUID]
        if invitedUserIds.isEmpty {
            let members = try await SchoolService.shared.fetchMembers(schoolId: schoolId)
            requestedRecipients = members.map(\.id)
        } else {
            requestedRecipients = invitedUserIds
        }
        let recipients = try await notificationRecipientsForStaffAction(
            schoolId: schoolId,
            createdBy: user.id,
            requestedRecipientIds: requestedRecipients
        )
        if recipients.isEmpty == false {
            try await createNotification(
                schoolId: schoolId,
                title: "New event: \(title)",
                body: description?.isEmpty == false ? description! : eventTimeSummary(startAt: startAt, endAt: endAt, allDay: allDay),
                category: "event_change",
                sourceType: "school_event",
                sourceId: eventId,
                recipientIds: recipients
            )
        }
    }

    func updateEvent(
        eventId: UUID,
        title: String,
        description: String?,
        startAt: Date,
        endAt: Date?,
        allDay: Bool,
        repeatRule: String?
    ) async throws {
        let update = SchoolEventUpdate(
            title: title,
            description: description,
            startAt: startAt,
            endAt: endAt,
            allDay: allDay,
            repeatRule: repeatRule,
            updatedAt: Date()
        )

        try await client.from("school_events")
            .update(update)
            .eq("id", value: eventId)
            .execute()
    }

    func deleteEvent(eventId: UUID) async throws {
        try await client.from("school_events")
            .delete()
            .eq("id", value: eventId)
            .execute()
    }

    func setEventArchived(eventId: UUID, archived: Bool) async throws -> SchoolEvent {
        let events: [SchoolEvent] = try await client.rpc(
            "set_school_event_archived",
            params: SchoolEventArchiveParams(eventId: eventId, archived: archived)
        )
        .execute()
        .value
        guard let event = events.first else { throw SchoolWorkflowError.notFound }
        return event
    }

    // MARK: - Notifications

    func fetchNotifications(schoolId: UUID) async throws -> [AppNotification] {
        try await client.from("notifications")
            .select()
            .eq("school_id", value: schoolId)
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
    }

    func fetchMyNotifications(limit: Int = 100) async throws -> [NotificationInboxItem] {
        try await client.rpc(
            "fetch_my_notifications",
            params: NotificationLimitParams(limit: limit)
        )
        .execute()
        .value
    }

    func markNotificationRead(notificationId: UUID) async throws {
        _ = try await client.rpc(
            "mark_notification_read",
            params: NotificationIdParams(notificationId: notificationId)
        )
        .execute()
    }

    func markAllNotificationsRead() async throws {
        _ = try await client.rpc("mark_all_notifications_read")
            .execute()
    }

    func markNotificationThreadRead(threadKey: String) async throws {
        _ = try await client.rpc(
            "mark_notification_thread_read",
            params: NotificationThreadParams(threadKey: threadKey)
        )
        .execute()
    }

    func dismissNotification(notificationId: UUID) async throws {
        _ = try await client.rpc(
            "dismiss_notification",
            params: NotificationIdParams(notificationId: notificationId)
        )
        .execute()
    }

    func clearMyNotifications() async throws {
        _ = try await client.rpc("clear_my_notifications")
            .execute()
    }

    func createNotification(
        schoolId: UUID,
        title: String,
        body: String,
        category: String,
        sourceType: String? = nil,
        sourceId: UUID? = nil,
        recipientIds: [UUID]
    ) async throws {
        _ = try await client.rpc(
            "create_transactional_notification",
            params: TransactionalNotificationParams(
                schoolId: schoolId,
                title: title,
                body: body,
                category: category,
                sourceType: sourceType,
                sourceId: sourceId,
                recipientIds: recipientIds,
                idempotencyKey: sourceId.map { "\(category):\($0.uuidString)" } ?? UUID().uuidString
            )
        ).execute()
    }

    func fetchQueuedNotifications(schoolId: UUID) async throws -> [QueuedNotification] {
        try await client.from("queued_notifications")
            .select()
            .eq("school_id", value: schoolId)
            .order("deliver_at", ascending: true)
            .limit(100)
            .execute()
            .value
    }

    func fetchFireflyReflections(schoolId: UUID) async throws -> [QueuedNotification] {
        try await client.from("queued_notifications")
            .select()
            .eq("school_id", value: schoolId)
            .eq("category", value: "firefly_reflection")
            .order("deliver_at", ascending: false)
            .limit(7)
            .execute()
            .value
    }

    // MARK: - Children

    func fetchChildren(schoolId: UUID) async throws -> [Child] {
        try await client.from("children")
            .select()
            .eq("school_id", value: schoolId)
            .eq("active", value: true)
            .order("last_name", ascending: true)
            .execute()
            .value
    }

    func fetchAllChildrenForHQ() async throws -> [Child] {
        try await client.from("children")
            .select()
            .eq("active", value: true)
            .order("last_name", ascending: true)
            .execute()
            .value
    }

    func fetchChildRoster(schoolId: UUID) async throws -> [ChildRosterItem] {
        let children = try await fetchChildren(schoolId: schoolId)
        return try await buildChildRosterItems(children: children, schoolId: schoolId)
    }

    func fetchAllChildRosterForHQ() async throws -> [ChildRosterItem] {
        let children = try await fetchAllChildrenForHQ()
        return try await buildChildRosterItems(children: children, schoolId: nil)
    }

    private func buildChildRosterItems(children: [Child], schoolId: UUID?) async throws -> [ChildRosterItem] {
        let childIds = children.map(\.id)
        guard childIds.isEmpty == false else { return [] }

        let medicalProfiles: [ChildMedicalProfile] = try await client.from("child_medical_profiles")
            .select()
            .in("child_id", values: childIds)
            .execute()
            .value

        let today = DateOnlyCoding.string(from: Date())
        let todayAttendance: [ChildAttendance]
        if let schoolId {
            todayAttendance = try await client.from("child_attendance")
                .select()
                .eq("school_id", value: schoolId)
                .in("child_id", values: childIds)
                .eq("attendance_date", value: today)
                .execute()
                .value
        } else {
            todayAttendance = try await client.from("child_attendance")
                .select()
                .in("child_id", values: childIds)
                .eq("attendance_date", value: today)
                .execute()
                .value
        }

        let medicationTasks: [MedicationTask]
        if let schoolId {
            medicationTasks = try await client.from("medication_tasks")
                .select()
                .eq("school_id", value: schoolId)
                .in("child_id", values: childIds)
                .in("status", values: ["pending", "missed"])
                .execute()
                .value
        } else {
            medicationTasks = try await client.from("medication_tasks")
                .select()
                .in("child_id", values: childIds)
                .in("status", values: ["pending", "missed"])
                .execute()
                .value
        }

        let documents: [ChildDocument] = try await client.from("child_documents")
            .select()
            .in("child_id", values: childIds)
            .execute()
            .value

        let medicalByChild = Dictionary(uniqueKeysWithValues: medicalProfiles.map { ($0.childId, $0) })
        let attendanceByChild = Dictionary(grouping: todayAttendance, by: \.childId).mapValues { records in
            records.sorted { ($0.updatedAt ?? $0.createdAt ?? .distantPast) > ($1.updatedAt ?? $1.createdAt ?? .distantPast) }.first
        }
        let medicationCountByChild = Dictionary(grouping: medicationTasks, by: \.childId).mapValues(\.count)
        let documentsByChild = Dictionary(grouping: documents, by: \.childId)

        return children.map { child in
            let childDocuments = documentsByChild[child.id] ?? []
            return ChildRosterItem(
                child: child,
                medicalProfile: medicalByChild[child.id],
                todayAttendance: attendanceByChild[child.id] ?? nil,
                pendingMedicationCount: medicationCountByChild[child.id] ?? 0,
                submittedDocumentCount: childDocuments.filter { $0.verificationStatus != "verified" }.count,
                verifiedDocumentCount: childDocuments.filter { $0.verificationStatus == "verified" }.count
            )
        }
    }

    func updateChild(childId: UUID, firstName: String, lastName: String, birthdate: Date?) async throws -> Child {
        let update = ChildUpdate(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            birthdate: birthdate,
            updatedAt: Date()
        )

        let children: [Child] = try await client.from("children")
            .update(update)
            .eq("id", value: childId)
            .select()
            .execute()
            .value

        guard let child = children.first else {
            throw SchoolWorkflowError.notFound
        }
        return child
    }

    func archiveChild(childId: UUID, reason: String?) async throws {
        let user = try await client.auth.session.user
        let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let update = ChildArchiveUpdate(
            active: false,
            archivedAt: Date(),
            archivedBy: user.id,
            archiveReason: trimmedReason?.isEmpty == true ? nil : trimmedReason,
            updatedAt: Date()
        )

        try await client.from("children")
            .update(update)
            .eq("id", value: childId)
            .execute()
    }

    func unlinkChildGuardian(childId: UUID, guardianId: UUID) async throws {
        _ = try await client.rpc(
            "revoke_child_guardian",
            params: RevokeChildGuardianParams(
                childId: childId,
                guardianId: guardianId,
                reason: "Revoked by school director"
            )
        ).execute()
    }

    func deactivateSchoolMember(schoolId: UUID, userId: UUID) async throws {
        try await client.from("school_memberships")
            .update(SchoolMembershipDeactivateUpdate(active: false))
            .eq("school_id", value: schoolId)
            .eq("user_id", value: userId)
            .execute()
    }

    func fetchChildGuardians(childId: UUID) async throws -> [ChildGuardian] {
        try await client.from("child_guardians")
            .select()
            .eq("child_id", value: childId)
            .eq("verification_status", value: "verified")
            .is("ended_at", value: nil)
            .execute()
            .value
    }

    func fetchChildEmergencyContacts(childId: UUID) async throws -> [ChildEmergencyContact] {
        try await client.from("child_emergency_contacts")
            .select()
            .eq("child_id", value: childId)
            .order("name", ascending: true)
            .execute()
            .value
    }

    func fetchChildMedicalProfile(childId: UUID) async throws -> ChildMedicalProfile? {
        let profiles: [ChildMedicalProfile] = try await client.from("child_medical_profiles")
            .select()
            .eq("child_id", value: childId)
            .limit(1)
            .execute()
            .value
        return profiles.first
    }

    func saveChildMedicalProfile(
        childId: UUID,
        allergies: String?,
        immunizationStatus: String?,
        physicalStatus: String?,
        medicalNotes: String?,
        medicationInstructions: String?,
        medicineRequirements: String?,
        dietaryNotes: String?,
        emergencyNotes: String?
    ) async throws {
        let user = try await client.auth.session.user
        let upsert = ChildMedicalProfileUpsert(
            childId: childId,
            allergies: allergies,
            immunizationStatus: immunizationStatus,
            physicalStatus: physicalStatus,
            medicalNotes: medicalNotes,
            medicationInstructions: medicationInstructions,
            medicineRequirements: medicineRequirements,
            dietaryNotes: dietaryNotes,
            emergencyNotes: emergencyNotes,
            updatedBy: user.id,
            updatedAt: Date()
        )

        try await client.from("child_medical_profiles")
            .upsert(upsert)
            .execute()
    }

    func fetchChildAttendance(childId: UUID) async throws -> [ChildAttendance] {
        try await client.from("child_attendance")
            .select()
            .eq("child_id", value: childId)
            .order("attendance_date", ascending: false)
            .limit(365)
            .execute()
            .value
    }

    func fetchChildActivityLogs(childId: UUID) async throws -> [ChildActivityLog] {
        try await client.from("child_activity_logs")
            .select()
            .eq("child_id", value: childId)
            .order("recorded_at", ascending: false)
            .limit(60)
            .execute()
            .value
    }

    func fetchChildProgressReports(childId: UUID) async throws -> [ChildProgressReport] {
        try await client.from("child_progress_reports")
            .select()
            .eq("child_id", value: childId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchChildGoals(childId: UUID) async throws -> [ChildGoal] {
        try await client.from("child_goals")
            .select()
            .eq("child_id", value: childId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createChildGoal(schoolId: UUID, childId: UUID, title: String, notes: String?) async throws {
        let user = try await client.auth.session.user
        let goal = ChildGoalInsert(
            schoolId: schoolId,
            childId: childId,
            title: title,
            notes: notes,
            status: "active",
            createdBy: user.id
        )
        try await client.from("child_goals")
            .insert(goal)
            .execute()
    }

    func fetchChildDocuments(childId: UUID) async throws -> [ChildDocument] {
        try await client.from("child_documents")
            .select()
            .eq("child_id", value: childId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func uploadChildDocument(schoolId: UUID, childId: UUID, title: String, documentType: String, fileURL: URL) async throws {
        let user = try await client.auth.session.user
        let documentId = UUID()
        let safeName = SchoolService.shared.safeStorageFileName(for: fileURL)
        let path = "schools/\(schoolId.uuidString)/child_documents/\(childId.uuidString)/\(documentId.uuidString)/\(safeName)"
        let upload = try await SchoolService.shared.uploadPrivateFile(fileURL: fileURL, path: path)
        let document = ChildDocumentInsert(
            id: documentId,
            schoolId: schoolId,
            childId: childId,
            title: title,
            documentType: documentType,
            fileName: upload.name,
            filePath: upload.path,
            uploadedBy: user.id,
            verificationStatus: "submitted"
        )

        try await client.from("child_documents")
            .insert(document)
            .execute()
    }

    func reviewChildDocument(id: UUID, status: String, reason: String?) async throws {
        let user = try await client.auth.session.user
        try await client.from("child_documents")
            .update(ChildDocumentReviewUpdate(verificationStatus: status, reviewedBy: user.id, reviewedAt: Date(), flagReason: reason))
            .eq("id", value: id)
            .execute()
    }

    func fetchMedicationInstructions(childId: UUID) async throws -> [MedicationInstruction] {
        try await client.from("medication_instructions")
            .select()
            .eq("child_id", value: childId)
            .eq("active", value: true)
            .order("scheduled_at", ascending: true)
            .execute()
            .value
    }

    func fetchMedicationTasks(schoolId: UUID, childId: UUID? = nil) async throws -> [MedicationTask] {
        var query = client.from("medication_tasks")
            .select()
            .eq("school_id", value: schoolId)
            .in("status", values: ["pending", "due", "missed"])

        if let childId {
            query = query.eq("child_id", value: childId)
        }

        return try await query
            .order("due_at", ascending: true)
            .limit(80)
            .execute()
            .value
    }

    func createMedicationInstruction(
        schoolId: UUID,
        childId: UUID,
        title: String,
        dosage: String?,
        instructions: String?,
        scheduledAt: Date
    ) async throws {
        _ = try await client.rpc(
            "create_medication_instruction",
            params: CreateMedicationInstructionParams(
                schoolId: schoolId,
                childId: childId,
                title: title,
                dosage: dosage,
                instructions: instructions,
                scheduledAt: scheduledAt
            )
        )
        .execute()
    }

    func acknowledgeMedicationTask(taskId: UUID, dosageGiven: String?, notes: String?) async throws {
        _ = try await client.rpc(
            "acknowledge_medication_task",
            params: AcknowledgeMedicationTaskParams(
                taskId: taskId,
                dosageGiven: dosageGiven,
                notes: notes,
                givenAt: Date()
            )
        )
        .execute()
    }

    // MARK: - Onboarding / Required Documents

    func fetchGoogleFormConnections(schoolId: UUID, role: SchoolRole) async throws -> [GoogleFormConnection] {
        try await client.from("google_form_connections")
            .select()
            .eq("school_id", value: schoolId)
            .eq("form_role", value: role.rawValue)
            .neq("status", value: "disconnected")
            .order("display_order", ascending: true)
            .execute()
            .value
    }

    func startGoogleFormsOAuth(schoolId: UUID) async throws -> GoogleFormsOAuthStart {
        try await invokeGoogleForms("google-forms-oauth", body: GoogleFormsOAuthRequest(action: "start", schoolId: schoolId))
    }

    func completeGoogleFormsOAuth(schoolId: UUID, callbackURL: URL) async throws -> GoogleFormsOAuthCompletion {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            throw SchoolWorkflowError.invalidInput("Google did not return a valid authorization response.")
        }
        return try await invokeGoogleForms(
            "google-forms-oauth",
            body: GoogleFormsOAuthRequest(action: "complete", schoolId: schoolId, code: code, state: state)
        )
    }

    func fetchAuthorizedGoogleForms(schoolId: UUID, credentialId: UUID) async throws -> [GoogleAuthorizedForm] {
        let response: GoogleAuthorizedFormsResponse = try await invokeGoogleForms(
            "google-forms-oauth", body: GoogleFormsOAuthRequest(action: "forms", schoolId: schoolId, credentialId: credentialId)
        )
        return response.forms
    }

    func inspectAuthorizedGoogleForm(schoolId: UUID, credentialId: UUID, formId: String) async throws -> GoogleAuthorizedFormDetails {
        try await invokeGoogleForms(
            "google-forms-oauth", body: GoogleFormsOAuthRequest(action: "inspect", schoolId: schoolId, credentialId: credentialId, formId: formId)
        )
    }

    func connectGoogleForm(
        schoolId: UUID,
        role: SchoolRole,
        credentialId: UUID,
        form: GoogleAuthorizedFormDetails,
        formKey: String,
        mappings: [GoogleFormQuestionMapping],
        templateRequirementId: UUID?,
        isRequired: Bool,
        displayOrder: Int
    ) async throws -> GoogleFormConnection {
        try await invokeGoogleForms(
            "google-forms-oauth",
            body: GoogleFormsOAuthRequest(
                action: "connect", schoolId: schoolId, credentialId: credentialId, formId: form.id,
                formKey: formKey, formRole: role.rawValue, isRequired: isRequired,
                displayOrder: displayOrder, mappings: mappings, templateRequirementId: templateRequirementId
            )
        )
    }

    func disconnectGoogleForm(connectionId: UUID) async throws {
        _ = try await client.rpc(
            "disconnect_google_form_connection",
            params: GoogleFormConnectionIDParams(connectionId: connectionId)
        ).execute()
    }

    func reorderGoogleForms(_ connections: [GoogleFormConnection]) async throws {
        _ = try await client.rpc(
            "reorder_google_form_connections",
            params: GoogleFormConnectionOrderParams(connectionIds: connections.map(\.id))
        ).execute()
    }

    func fetchParentGoogleFormConnections(schoolId: UUID) async throws -> [GoogleFormConnection] {
        try await fetchGoogleFormConnections(schoolId: schoolId, role: .parent)
    }

    func fetchParentGoogleFormConnection(schoolId: UUID) async throws -> GoogleFormConnection? {
        let connections = try await fetchParentGoogleFormConnections(schoolId: schoolId)
        return connections.first
    }

    func disconnectParentGoogleForm(schoolId: UUID) async throws {
        _ = try await client.rpc(
            "disconnect_parent_google_form",
            params: SchoolIdParams(schoolId: schoolId)
        ).execute()
    }

    func requestParentGoogleFormSync(schoolId: UUID) async throws {
        try await requestGoogleFormSync(schoolId: schoolId, role: .parent, connectionId: nil)
    }

    func requestGoogleFormSync(schoolId: UUID, role: SchoolRole, connectionId: UUID?) async throws {
        do {
            _ = try await client.functions.invoke(
                "sync-google-onboarding-forms",
                options: FunctionInvokeOptions(
                    body: GoogleFormSyncRequest(schoolId: schoolId, formRole: role.rawValue, connectionId: connectionId),
                    encoder: JSONEncoder()
                )
            )
        } catch {
            throw googleFormsFunctionError(error)
        }
    }

    func fetchGoogleFormImports(schoolId: UUID, status: String? = nil) async throws -> [GoogleFormImport] {
        var query = client.from("google_form_imports")
            .select()
            .eq("school_id", value: schoolId)
        if let status { query = query.eq("status", value: status) }
        return try await query.order("created_at", ascending: false).execute().value
    }

    func fetchGoogleFormImportAttachments(importId: UUID) async throws -> [GoogleFormImportAttachment] {
        try await client.from("google_form_import_attachments")
            .select()
            .eq("import_id", value: importId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func reviewGoogleFormImport(importId: UUID, status: String, matchedChildId: UUID? = nil, note: String?) async throws {
        _ = try await client.rpc(
            "approve_google_form_child_intake",
            params: GoogleFormImportReviewParams(
                importId: importId, decision: status, matchedChildId: matchedChildId, reviewNote: note
            )
        ).execute()
    }

    func fetchMyGoogleFormSteps(schoolId: UUID) async throws -> [GoogleFormRecipientStep] {
        try await client.rpc("fetch_my_google_form_steps", params: SchoolIdParams(schoolId: schoolId))
            .execute().value
    }

    func beginGoogleFormSubmission(connectionId: UUID) async throws -> GoogleFormSubmissionLaunch {
        let rows: [GoogleFormSubmissionLaunch] = try await client.rpc(
            "begin_google_form_submission", params: GoogleFormConnectionIDParams(connectionId: connectionId)
        ).execute().value
        guard let launch = rows.first else { throw SchoolWorkflowError.notFound }
        return launch
    }

    private func invokeGoogleForms<Response: Decodable, Body: Encodable>(
        _ function: String,
        body: Body
    ) async throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try await client.functions.invoke(
                function,
                options: FunctionInvokeOptions(body: body, encoder: encoder),
                decoder: decoder
            )
        } catch {
            throw googleFormsFunctionError(error)
        }
    }

    private func googleFormsFunctionError(_ error: Error) -> Error {
        guard case let FunctionsError.httpError(code, data) = error else { return error }
        let message = (try? JSONDecoder().decode(GoogleFormsFunctionFailure.self, from: data).error)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SchoolWorkflowError.invalidInput(
            message?.isEmpty == false ? message! : "Google Forms returned HTTP \(code). Check the deployed function and its configuration."
        )
    }

    func fetchOnboardingTemplate(schoolId: UUID, role: SchoolRole) async throws -> OnboardingTemplateBundle {
        let templates: [OnboardingTemplate] = try await client.from("onboarding_templates")
            .select()
            .eq("school_id", value: schoolId)
            .eq("target_role", value: role.rawValue)
            .order("version", ascending: false)
            .execute()
            .value

        let template = templates.first(where: { $0.status == .draft })
            ?? templates.first(where: { $0.status == .published })
            ?? templates.first
        let activePublishedTemplate = templates.first(where: { $0.status == .published })
        guard let template else {
            return OnboardingTemplateBundle(template: nil, requirements: [], attachments: [])
        }

        let requirements: [OnboardingTemplateRequirement] = try await client.from("onboarding_template_requirements")
            .select()
            .eq("template_id", value: template.id)
            .order("position", ascending: true)
            .execute()
            .value
        guard requirements.isEmpty == false else {
            return OnboardingTemplateBundle(
                template: template,
                requirements: [],
                attachments: [],
                activePublishedTemplate: activePublishedTemplate
            )
        }
        let attachments: [OnboardingTemplateAttachment] = try await client.from("onboarding_template_attachments")
            .select()
            .in("requirement_id", values: requirements.map(\.id))
            .order("position", ascending: true)
            .execute()
            .value
        return OnboardingTemplateBundle(
            template: template,
            requirements: requirements,
            attachments: attachments,
            activePublishedTemplate: activePublishedTemplate
        )
    }

    func ensureOnboardingTemplateDraft(schoolId: UUID, role: SchoolRole) async throws -> OnboardingTemplate {
        let templates: [OnboardingTemplate] = try await client.rpc(
            "ensure_onboarding_template_draft",
            params: OnboardingTemplateRoleParams(schoolId: schoolId, targetRole: role.rawValue)
        )
        .execute()
        .value
        guard let template = templates.first else { throw SchoolWorkflowError.notFound }
        return template
    }

    func uploadOnboardingTemplateAttachment(
        schoolId: UUID,
        templateId: UUID,
        editorId: UUID,
        fileURL: URL
    ) async throws -> OnboardingAttachmentDescriptor {
        let safeName = SchoolService.shared.safeStorageFileName(for: fileURL)
        let path = "schools/\(schoolId.uuidString)/onboarding_templates/\(templateId.uuidString)/\(editorId.uuidString)/\(UUID().uuidString)/\(safeName)"
        let upload = try await SchoolService.shared.uploadPrivateFile(fileURL: fileURL, path: path)
        return OnboardingAttachmentDescriptor(
            privateFilePath: upload.path,
            fileName: upload.name,
            contentType: upload.contentType
        )
    }

    func saveOnboardingTemplateRequirement(
        templateId: UUID,
        requirementId: UUID?,
        title: String,
        description: String?,
        subjectScope: OnboardingSubjectScope,
        position: Int,
        attachments: [OnboardingAttachmentDescriptor],
        blocksAccess: Bool = true,
        childRecordBinding: ChildRequirementBinding = .none
    ) async throws -> OnboardingTemplateRequirement {
        let requirements: [OnboardingTemplateRequirement] = try await client.rpc(
            "save_onboarding_template_requirement_v2",
            params: SaveOnboardingRequirementParams(
                templateId: templateId,
                requirementId: requirementId,
                title: title,
                description: description,
                subjectScope: subjectScope.rawValue,
                position: position,
                attachments: attachments,
                blocksAccess: blocksAccess,
                childRecordBinding: childRecordBinding.rawValue
            )
        )
        .execute()
        .value
        guard let requirement = requirements.first else { throw SchoolWorkflowError.notFound }
        return requirement
    }

    func removeOnboardingTemplateRequirement(requirementId: UUID) async throws {
        _ = try await client.rpc(
            "remove_onboarding_template_requirement",
            params: OnboardingRequirementIdParams(requirementId: requirementId)
        )
        .execute()
    }

    func deleteOnboardingTemplateDraft(templateId: UUID) async throws {
        _ = try await client.rpc(
            "delete_onboarding_template_draft",
            params: OnboardingTemplateIdParams(templateId: templateId)
        )
        .execute()
    }

    func reorderOnboardingTemplateRequirements(templateId: UUID, requirementIds: [UUID]) async throws {
        _ = try await client.rpc(
            "reorder_onboarding_template_requirements",
            params: ReorderOnboardingRequirementsParams(templateId: templateId, requirementIds: requirementIds)
        )
        .execute()
    }

    func publishOnboardingTemplate(templateId: UUID) async throws -> OnboardingTemplate {
        let templates: [OnboardingTemplate] = try await client.rpc(
            "publish_onboarding_template",
            params: OnboardingTemplateIdParams(templateId: templateId)
        )
        .execute()
        .value
        guard let template = templates.first else { throw SchoolWorkflowError.notFound }
        return template
    }

    func archiveOnboardingTemplate(templateId: UUID) async throws -> OnboardingTemplate {
        let templates: [OnboardingTemplate] = try await client.rpc(
            "archive_onboarding_template",
            params: OnboardingTemplateIdParams(templateId: templateId)
        )
        .execute()
        .value
        guard let template = templates.first else { throw SchoolWorkflowError.notFound }
        return template
    }

    func waiveOnboardingAssignment(assignmentId: UUID, reason: String) async throws {
        _ = try await client.rpc(
            "waive_onboarding_assignment",
            params: WaiveOnboardingAssignmentParams(assignmentId: assignmentId, reason: reason)
        )
        .execute()
    }

    func fetchMyOnboardingDashboard(schoolId: UUID) async throws -> [OnboardingDashboardItem] {
        try await client.rpc(
            "fetch_my_onboarding_dashboard",
            params: SchoolIdParams(schoolId: schoolId)
        )
        .execute()
        .value
    }

    func fetchOnboardingRoleProgress(schoolId: UUID, role: SchoolRole) async throws -> OnboardingRoleProgress {
        let rows: [OnboardingRoleProgress] = try await client.rpc(
            "fetch_onboarding_role_progress",
            params: OnboardingTemplateRoleParams(schoolId: schoolId, targetRole: role.rawValue)
        )
        .execute()
        .value
        return rows.first ?? .empty
    }

    func fetchOnboardingRequirements(schoolId: UUID) async throws -> [OnboardingRequirement] {
        try await client.from("onboarding_requirements")
            .select()
            .eq("school_id", value: schoolId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchDocumentSubmissions(schoolId: UUID) async throws -> [DocumentSubmission] {
        try await client.from("document_submissions")
            .select()
            .eq("school_id", value: schoolId)
            .order("submitted_at", ascending: false)
            .execute()
            .value
    }

    func createOnboardingRequirement(
        schoolId: UUID,
        title: String,
        description: String?,
        requirementType: String,
        targetRole: SchoolRole?,
        targetUserId: UUID?,
        fileURL: URL?
    ) async throws {
        let user = try await client.auth.session.user
        let requirementId = UUID()
        var fileName: String?
        var filePath: String?

        if let fileURL {
            let safeName = SchoolService.shared.safeStorageFileName(for: fileURL)
            let path = "schools/\(schoolId.uuidString)/onboarding_requirements/\(requirementId.uuidString)/\(safeName)"
            let upload = try await SchoolService.shared.uploadPrivateFile(fileURL: fileURL, path: path)
            fileName = upload.name
            filePath = upload.path
        }

        let requirement = OnboardingRequirementInsert(
            id: requirementId,
            schoolId: schoolId,
            title: title,
            description: description,
            requirementType: requirementType,
            targetRole: targetRole?.rawValue,
            targetUserId: targetUserId,
            fileName: fileName,
            filePath: filePath,
            assignedBy: user.id
        )

        try await client.from("onboarding_requirements")
            .insert(requirement)
            .execute()

        let recipients: [UUID]
        if let targetUserId {
            recipients = [targetUserId]
        } else if let targetRole {
            recipients = try await SchoolService.shared.fetchMembers(schoolId: schoolId, role: targetRole).map(\.id)
        } else {
            recipients = []
        }

        if recipients.isEmpty == false {
            try await createNotification(
                schoolId: schoolId,
                title: "Required document assigned",
                body: title,
                category: "required_document",
                sourceType: "onboarding_requirement",
                sourceId: requirementId,
                recipientIds: recipients
            )
        }
    }

    func submitRequiredDocument(requirement: OnboardingRequirement, fileURL: URL) async throws {
        let submissionId = UUID()
        let safeName = SchoolService.shared.safeStorageFileName(for: fileURL)
        let uploadPath = "schools/\(requirement.schoolId.uuidString)/document_submissions/\(requirement.id.uuidString)/\(submissionId.uuidString)/\(safeName)"
        let upload = try await SchoolService.shared.uploadPrivateFile(fileURL: fileURL, path: uploadPath)

        _ = try await client.rpc(
            "submit_required_document",
            params: SubmitRequiredDocumentParams(
                requirementId: requirement.id,
                fileName: upload.name,
                filePath: upload.path
            )
        )
        .execute()
    }

    func reviewRequiredDocument(submissionId: UUID, status: String, message: String?) async throws {
        _ = try await client.rpc(
            "review_required_document",
            params: ReviewRequiredDocumentParams(
                submissionId: submissionId,
                status: status,
                reviewerMessage: message
            )
        )
        .execute()
    }

    func fetchPaymentSetupRecords(schoolId: UUID) async throws -> [PaymentSetupRecord] {
        try await client.from("payment_setup_records")
            .select()
            .eq("school_id", value: schoolId)
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    // MARK: - Community

    // MARK: - Paperwork

    func fetchPaperworkAssignments(schoolId: UUID) async throws -> [PaperworkAssignment] {
        try await client.from("paperwork_assignments")
            .select()
            .eq("school_id", value: schoolId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchPaperworkSubmissions(schoolId: UUID) async throws -> [PaperworkSubmission] {
        try await client.from("paperwork_submissions")
            .select()
            .eq("school_id", value: schoolId)
            .order("submitted_at", ascending: false)
            .execute()
            .value
    }

    func createPaperworkAssignment(schoolId: UUID, title: String, description: String?, fileURL: URL?, parentIds: [UUID]) async throws {
        let user = try await client.auth.session.user
        let assignmentId = UUID()
        var fileName: String?
        var filePath: String?

        if let fileURL {
            let safeName = SchoolService.shared.safeStorageFileName(for: fileURL)
            let path = "schools/\(schoolId.uuidString)/paperwork_assignments/\(assignmentId.uuidString)/\(safeName)"
            let upload = try await SchoolService.shared.uploadPrivateFile(fileURL: fileURL, path: path)
            fileName = upload.name
            filePath = upload.path
        }

        let assignment = PaperworkAssignment(
            id: assignmentId,
            schoolId: schoolId,
            title: title,
            description: description,
            fileName: fileName,
            filePath: filePath,
            assignedBy: user.id
        )

        try await client.from("paperwork_assignments")
            .insert(assignment)
            .execute()

        let recipients = parentIds.map {
            PaperworkAssignmentRecipient(assignmentId: assignmentId, parentId: $0, createdAt: Date())
        }
        if recipients.isEmpty == false {
            try await client.from("paperwork_assignment_recipients")
                .insert(recipients)
                .execute()
        }

        try await createNotification(
            schoolId: schoolId,
            title: "Paperwork assigned",
            body: title,
            category: "paperwork_due",
            sourceType: "paperwork_assignment",
            sourceId: assignmentId,
            recipientIds: parentIds
        )
    }

    func submitPaperwork(assignment: PaperworkAssignment, fileURL: URL) async throws -> PaperworkSubmission {
        let user = try await client.auth.session.user
        let submissionId = UUID()
        let safeName = SchoolService.shared.safeStorageFileName(for: fileURL)
        let path = "schools/\(assignment.schoolId.uuidString)/paperwork_submissions/\(user.id.uuidString)/\(submissionId.uuidString)/\(safeName)"
        let upload = try await SchoolService.shared.uploadPrivateFile(fileURL: fileURL, path: path)

        let submissions: [PaperworkSubmission] = try await client.rpc(
            "submit_paperwork_assignment",
            params: SubmitPaperworkAssignmentParams(
                assignmentId: assignment.id,
                fileName: upload.name,
                filePath: upload.path
            )
        )
        .execute()
        .value

        guard let submission = submissions.first else {
            throw SchoolWorkflowError.notFound
        }
        return submission
    }

    func reviewPaperworkSubmission(id: UUID, status: String, reason: String?) async throws {
        let user = try await client.auth.session.user
        let update = ReviewUpdate(
            status: status,
            flagReason: reason,
            reviewedBy: user.id,
            reviewedAt: Date()
        )
        try await client.from("paperwork_submissions")
            .update(update)
            .eq("id", value: id)
            .execute()
    }

    func fetchCommunityPosts(schoolId: UUID) async throws -> [CommunityPost] {
        try await client.from("community_posts")
            .select()
            .eq("school_id", value: schoolId)
            .order("created_at", ascending: false)
            .limit(50)
            .execute()
            .value
    }

    func createCommunityPost(schoolId: UUID, body: String, imageURL: URL?) async throws {
        let attachment = try imageURL.map { url in
            let data = try Data(contentsOf: url)
            return CommunityMediaUpload(
                data: data,
                fileName: url.lastPathComponent.isEmpty ? "Image" : url.lastPathComponent,
                contentType: "image/jpeg"
            )
        }
        try await createCommunityPost(
            schoolId: schoolId,
            body: body,
            attachment: attachment,
            linkedEventId: nil,
            pollQuestion: nil,
            pollOptions: [],
            scheduledAt: nil
        )
    }

    func createCommunityPost(
        schoolId: UUID,
        body: String,
        attachment: CommunityMediaUpload?,
        linkedEventId: UUID?,
        pollQuestion: String?,
        pollOptions: [String],
        scheduledAt: Date?
    ) async throws {
        let postId = UUID()
        var imagePath: String?
        var attachmentPath: String?
        var attachmentName: String?
        var attachmentType: String?

        if let attachment {
            let safeName = safeStorageFileName(attachment.fileName)
            let path = "schools/\(schoolId.uuidString.lowercased())/community_posts/\(postId.uuidString.lowercased())/\(safeName)"
            let upload = try await SchoolService.shared.uploadPrivateData(
                data: attachment.data,
                path: path,
                name: attachment.fileName,
                contentType: attachment.contentType
            )
            attachmentPath = upload.path
            attachmentName = upload.name
            attachmentType = upload.contentType
            if attachment.contentType?.hasPrefix("image/") == true {
                imagePath = upload.path
            }
        }

        do {
            try await client.rpc(
                "publish_community_post",
                params: PublishCommunityPostParams(
                    postId: postId,
                    schoolId: schoolId,
                    body: body,
                    imagePath: imagePath,
                    attachmentPath: attachmentPath,
                    attachmentName: attachmentName,
                    attachmentType: attachmentType,
                    linkedEventId: linkedEventId,
                    pollQuestion: pollQuestion,
                    pollOptions: pollOptions.isEmpty ? nil : pollOptions,
                    scheduledAt: scheduledAt,
                    idempotencyKey: postId.uuidString
                )
            )
            .execute()
        } catch {
            if let attachmentPath {
                try? await SchoolService.shared.removePrivateFiles(paths: [attachmentPath])
            }
            throw error
        }
    }

    func updateCommunityPost(
        postId: UUID,
        body: String,
        linkedEventId: UUID?,
        pollQuestion: String?,
        pollOptions: [String],
        scheduledAt: Date?
    ) async throws {
        let update = CommunityPostUpdate(
            body: body,
            linkedEventId: linkedEventId,
            pollQuestion: pollQuestion,
            pollOptions: pollOptions.isEmpty ? nil : pollOptions,
            scheduledAt: scheduledAt,
            updatedAt: Date()
        )

        try await client.from("community_posts")
            .update(update)
            .eq("id", value: postId)
            .execute()
    }

    func fetchCommunityAlbums(schoolId: UUID) async throws -> [CommunityAlbum] {
        try await client.from("community_albums")
            .select()
            .eq("school_id", value: schoolId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchCommunityAlbumMedia(schoolId: UUID) async throws -> [UUID: [CommunityAlbumMedia]] {
        let media: [CommunityAlbumMedia] = try await client.from("community_album_media")
            .select()
            .eq("school_id", value: schoolId)
            .order("created_at", ascending: true)
            .execute()
            .value

        return Dictionary(grouping: media, by: \.albumId)
    }

    func fetchCommunityAlbumMedia(albumId: UUID) async throws -> [CommunityAlbumMedia] {
        try await client.from("community_album_media")
            .select()
            .eq("album_id", value: albumId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func deleteCommunityAlbumMedia(_ media: CommunityAlbumMedia) async throws {
        try await client.from("community_album_media")
            .delete()
            .eq("id", value: media.id)
            .execute()

        _ = try? await client.storage
            .from("school_private_files")
            .remove(paths: [media.filePath])
    }

    func createCommunityAlbum(schoolId: UUID, title: String, description: String?, coverURL: URL?) async throws {
        var media: [CommunityMediaUpload] = []
        if let coverURL {
            let data = try Data(contentsOf: coverURL)
            media = [CommunityMediaUpload(data: data, fileName: coverURL.lastPathComponent, contentType: "image/jpeg")]
        }
        _ = try await createCommunityAlbum(schoolId: schoolId, title: title, description: description, media: media)
    }

    @discardableResult
    func createCommunityAlbum(schoolId: UUID, title: String, description: String?, media: [CommunityMediaUpload]) async throws -> CommunityAlbum {
        let albumId = UUID()
        let limitedMedia = Array(media.prefix(100))
        var uploads: [SchoolFileUpload] = []

        for item in limitedMedia {
            let safeName = safeStorageFileName(item.fileName)
            let path = "schools/\(schoolId.uuidString.lowercased())/community_albums/\(albumId.uuidString.lowercased())/media/\(UUID().uuidString)-\(safeName)"
            let upload = try await SchoolService.shared.uploadPrivateData(
                data: item.data,
                path: path,
                name: item.fileName,
                contentType: item.contentType
            )
            uploads.append(upload)
        }

        let albums: [CommunityAlbum]
        do {
            albums = try await client.rpc(
                "publish_community_album",
                params: PublishCommunityAlbumParams(
                    albumId: albumId,
                    schoolId: schoolId,
                    title: title,
                    description: description,
                    coverPath: uploads.first?.path,
                    media: uploads.map(CommunityAlbumRPCMedia.init),
                    idempotencyKey: albumId.uuidString
                )
            )
            .execute()
            .value
        } catch {
            try? await SchoolService.shared.removePrivateFiles(paths: uploads.map(\.path))
            throw error
        }

        guard let album = albums.first else {
            throw SchoolWorkflowError.notFound
        }
        return album
    }

    func addMediaToCommunityAlbum(schoolId: UUID, album: CommunityAlbum, media: [CommunityMediaUpload]) async throws {
        let limitedMedia = Array(media.prefix(100))
        var uploads: [SchoolFileUpload] = []

        for item in limitedMedia {
            let safeName = safeStorageFileName(item.fileName)
            let path = "schools/\(schoolId.uuidString.lowercased())/community_albums/\(album.id.uuidString.lowercased())/media/\(UUID().uuidString)-\(safeName)"
            let upload = try await SchoolService.shared.uploadPrivateData(
                data: item.data,
                path: path,
                name: item.fileName,
                contentType: item.contentType
            )
            uploads.append(upload)
        }

        if uploads.isEmpty == false {
            do {
                _ = try await client.rpc(
                    "append_community_album_media",
                    params: AppendCommunityAlbumMediaParams(
                        albumId: album.id,
                        media: uploads.map(CommunityAlbumRPCMedia.init),
                        idempotencyKey: UUID().uuidString
                    )
                )
                .execute()
            } catch {
                try? await SchoolService.shared.removePrivateFiles(paths: uploads.map(\.path))
                throw error
            }
        }
    }

    func ensureAllPhotosAlbum(schoolId: UUID) async throws -> CommunityAlbum {
        let existing: [CommunityAlbum] = try await client.from("community_albums")
            .select()
            .eq("school_id", value: schoolId)
            .eq("title", value: "All Photos")
            .limit(1)
            .execute()
            .value

        if let album = existing.first {
            return album
        }

        let user = try await client.auth.session.user
        let albums: [CommunityAlbum] = try await client.from("community_albums")
            .insert(CommunityAlbumInsert(
                id: UUID(),
                schoolId: schoolId,
                title: "All Photos",
                description: "School-wide shared photos and videos.",
                coverPath: nil,
                createdBy: user.id
            ))
            .select()
            .execute()
            .value
        guard let album = albums.first else { throw SchoolWorkflowError.notFound }
        return album
    }

    private func safeStorageFileName(_ rawName: String) -> String {
        let fallback = rawName.isEmpty ? "attachment" : rawName
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = fallback.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let joined = String(sanitized)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return joined.isEmpty ? "attachment-\(UUID().uuidString)" : joined
    }

    private func notifyCommunityPostCreated(
        schoolId: UUID,
        postId: UUID,
        body: String,
        createdBy: UUID
    ) async throws {
        let members = try await SchoolService.shared.fetchMembers(schoolId: schoolId)
        let recipients = try await notificationRecipientsForStaffAction(
            schoolId: schoolId,
            createdBy: createdBy,
            requestedRecipientIds: members.map(\.id)
        )

        guard recipients.isEmpty == false else { return }

        let preview = body.trimmingCharacters(in: .whitespacesAndNewlines)
        try await createNotification(
            schoolId: schoolId,
            title: "New community post",
            body: preview.isEmpty ? "A new school post was shared." : String(preview.prefix(140)),
            category: "community_post",
            sourceType: "community_post",
            sourceId: postId,
            recipientIds: recipients
        )
    }

    private func notifyNewsletterCreated(
        schoolId: UUID,
        newsletterId: UUID,
        title: String,
        body: String,
        createdBy: UUID
    ) async throws {
        let members = try await SchoolService.shared.fetchMembers(schoolId: schoolId)
        let recipients = try await notificationRecipientsForStaffAction(
            schoolId: schoolId,
            createdBy: createdBy,
            requestedRecipientIds: members.map(\.id)
        )

        guard recipients.isEmpty == false else { return }

        let preview = body
            .replacingOccurrences(of: "[#*_`]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try await createNotification(
            schoolId: schoolId,
            title: "New newsletter: \(title)",
            body: preview.isEmpty ? "A new school newsletter was published." : String(preview.prefix(160)),
            category: "newsletter",
            sourceType: "newsletter",
            sourceId: newsletterId,
            recipientIds: recipients
        )
    }

    private func notificationRecipientsForStaffAction(
        schoolId: UUID,
        createdBy: UUID,
        requestedRecipientIds: [UUID]
    ) async throws -> [UUID] {
        let members = try await SchoolService.shared.fetchMembers(schoolId: schoolId)
        let requested = Set(requestedRecipientIds)
        let actorRole = members.first(where: { $0.id == createdBy })?.membership.role

        return members
            .filter { requested.contains($0.id) }
            .filter { $0.id != createdBy }
            .filter { member in
                if actorRole?.canManageSchool == true {
                    return true
                }
                return member.membership.role == .parent || member.membership.role.canManageSchool
            }
            .map(\.id)
    }

    // MARK: - Curriculum / Training

    func fetchCurriculumResources(schoolId: UUID) async throws -> [CurriculumResource] {
        try await client.from("curriculum_resources")
            .select()
            .eq("school_id", value: schoolId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createCurriculumResource(
        schoolId: UUID,
        title: String,
        description: String?,
        fileURL: URL?,
        materialUrl: String? = nil,
        materialType: String? = nil
    ) async throws {
        let user = try await client.auth.session.user
        let resourceId = UUID()
        var fileName: String?
        var filePath: String?

        if let fileURL {
            let safeName = SchoolService.shared.safeStorageFileName(for: fileURL)
            let path = "schools/\(schoolId.uuidString)/curriculum_resources/\(resourceId.uuidString)/\(safeName)"
            let upload = try await SchoolService.shared.uploadPrivateFile(fileURL: fileURL, path: path)
            fileName = upload.name
            filePath = upload.path
        }

        let resource = CurriculumResource(
            id: resourceId,
            schoolId: schoolId,
            title: title,
            description: description,
            fileName: fileName,
            filePath: filePath,
            materialUrl: materialUrl,
            materialType: materialType ?? (filePath == nil ? "link" : "file"),
            uploadedBy: user.id
        )
        try await client.from("curriculum_resources")
            .insert(resource)
            .execute()
    }

    func fetchTrainingAssignments(schoolId: UUID) async throws -> [TrainingAssignment] {
        try await client.from("training_assignments")
            .select()
            .eq("school_id", value: schoolId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchTrainingSubmissions(schoolId: UUID) async throws -> [TrainingSubmission] {
        try await client.from("training_submissions")
            .select()
            .eq("school_id", value: schoolId)
            .order("submitted_at", ascending: false)
            .execute()
            .value
    }

    func createTrainingAssignment(
        schoolId: UUID,
        title: String,
        description: String?,
        fileURL: URL?,
        teacherIds: [UUID],
        materialUrl: String? = nil,
        materialType: String? = nil,
        dueAt: Date? = nil
    ) async throws {
        let user = try await client.auth.session.user
        let assignmentId = UUID()
        var fileName: String?
        var filePath: String?

        if let fileURL {
            let safeName = SchoolService.shared.safeStorageFileName(for: fileURL)
            let path = "schools/\(schoolId.uuidString)/training_assignments/\(assignmentId.uuidString)/\(safeName)"
            let upload = try await SchoolService.shared.uploadPrivateFile(fileURL: fileURL, path: path)
            fileName = upload.name
            filePath = upload.path
        }

        let assignment = TrainingAssignment(
            id: assignmentId,
            schoolId: schoolId,
            title: title,
            description: description,
            fileName: fileName,
            filePath: filePath,
            materialUrl: materialUrl,
            materialType: materialType ?? (filePath == nil ? "link" : "file"),
            assignedBy: user.id,
            dueAt: dueAt
        )
        try await client.from("training_assignments")
            .insert(assignment)
            .execute()

        let recipients = teacherIds.map {
            TrainingAssignmentRecipient(assignmentId: assignmentId, teacherId: $0, createdAt: Date())
        }
        if recipients.isEmpty == false {
            try await client.from("training_assignment_recipients")
                .insert(recipients)
                .execute()
        }

        try await createNotification(
            schoolId: schoolId,
            title: "Training assigned",
            body: title,
            category: "training_assigned",
            recipientIds: teacherIds
        )
    }

    func fetchTrainingReadReceipts(schoolId: UUID) async throws -> [TrainingReadReceipt] {
        let assignments = try await fetchTrainingAssignments(schoolId: schoolId)
        let assignmentIds = assignments.map(\.id)
        guard !assignmentIds.isEmpty else { return [] }

        return try await client.from("training_read_receipts")
            .select()
            .in("assignment_id", values: assignmentIds)
            .execute()
            .value
    }

    func fetchCurriculumReadReceipts(schoolId: UUID) async throws -> [CurriculumReadReceipt] {
        let resources = try await fetchCurriculumResources(schoolId: schoolId)
        let resourceIds = resources.map(\.id)
        guard !resourceIds.isEmpty else { return [] }

        return try await client.from("curriculum_read_receipts")
            .select()
            .in("resource_id", values: resourceIds)
            .execute()
            .value
    }

    func markCurriculumResourceRead(resourceId: UUID) async throws {
        let user = try await client.auth.session.user
        try await client.from("curriculum_read_receipts")
            .upsert(CurriculumReadReceipt(resourceId: resourceId, userId: user.id, checkedAt: Date()))
            .execute()
    }

    func markTrainingAssignmentRead(assignmentId: UUID) async throws {
        let user = try await client.auth.session.user
        try await client.from("training_read_receipts")
            .upsert(TrainingReadReceipt(assignmentId: assignmentId, userId: user.id, checkedAt: Date()))
            .execute()
    }

    func submitTraining(assignment: TrainingAssignment, fileURL: URL) async throws {
        let user = try await client.auth.session.user
        let submissionId = UUID()
        let safeName = SchoolService.shared.safeStorageFileName(for: fileURL)
        let path = "schools/\(assignment.schoolId.uuidString)/training_submissions/\(user.id.uuidString)/\(submissionId.uuidString)/\(safeName)"
        let upload = try await SchoolService.shared.uploadPrivateFile(fileURL: fileURL, path: path)
        let submission = TrainingSubmission(
            id: submissionId,
            assignmentId: assignment.id,
            schoolId: assignment.schoolId,
            submittedBy: user.id,
            fileName: upload.name,
            filePath: upload.path
        )

        try await client.from("training_submissions")
            .insert(submission)
            .execute()
    }

    private func eventTimeSummary(startAt: Date, endAt: Date?, allDay: Bool) -> String {
        if allDay {
            return startAt.formatted(date: .abbreviated, time: .omitted)
        }

        if let endAt {
            return "\(startAt.formatted(date: .abbreviated, time: .shortened)) - \(endAt.formatted(date: .omitted, time: .shortened))"
        }

        return startAt.formatted(date: .abbreviated, time: .shortened)
    }
}

enum SchoolWorkflowError: LocalizedError {
    case notFound
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "The requested school workflow item was not found or is not visible to this account. Refresh the list and confirm that the assignment recipient and school access are still active."
        case let .invalidInput(message):
            return message
        }
    }
}

private struct RevokeChildGuardianParams: Encodable {
    let childId: UUID
    let guardianId: UUID
    let reason: String
    enum CodingKeys: String, CodingKey {
        case childId = "input_child_id"
        case guardianId = "input_guardian_id"
        case reason = "input_reason"
    }
}

private struct ChildUpdate: Encodable {
    let firstName: String
    let lastName: String
    let birthdate: Date?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case birthdate
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(lastName, forKey: .lastName)
        try DateOnlyCoding.encodeDateOnlyIfPresent(birthdate, to: &container, forKey: .birthdate)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private struct GoogleFormsOAuthRequest: Encodable {
    let action: String
    let schoolId: UUID
    var credentialId: UUID?
    var code: String?
    var state: String?
    var formId: String?
    var formKey: String?
    var formRole: String?
    var isRequired: Bool?
    var displayOrder: Int?
    var mappings: [GoogleFormQuestionMapping]?
    var templateRequirementId: UUID?

    init(
        action: String,
        schoolId: UUID,
        credentialId: UUID? = nil,
        code: String? = nil,
        state: String? = nil,
        formId: String? = nil,
        formKey: String? = nil,
        formRole: String? = nil,
        isRequired: Bool? = nil,
        displayOrder: Int? = nil,
        mappings: [GoogleFormQuestionMapping]? = nil,
        templateRequirementId: UUID? = nil
    ) {
        self.action = action; self.schoolId = schoolId; self.credentialId = credentialId
        self.code = code; self.state = state; self.formId = formId; self.formKey = formKey
        self.formRole = formRole; self.isRequired = isRequired; self.displayOrder = displayOrder
        self.mappings = mappings; self.templateRequirementId = templateRequirementId
    }

    enum CodingKeys: String, CodingKey {
        case action
        case schoolId
        case credentialId
        case code, state
        case formId
        case formKey
        case formRole
        case isRequired
        case displayOrder
        case mappings
        case templateRequirementId
    }
}

private struct GoogleFormsFunctionFailure: Decodable {
    let error: String?
}

private struct GoogleFormConnectionIDParams: Encodable {
    let connectionId: UUID
    enum CodingKeys: String, CodingKey { case connectionId = "input_connection_id" }
}

private struct GoogleFormConnectionOrderParams: Encodable {
    let connectionIds: [UUID]
    enum CodingKeys: String, CodingKey { case connectionIds = "input_connection_ids" }
}

private struct GoogleFormSyncRequest: Encodable {
    let schoolId: UUID
    let formRole: String
    let connectionId: UUID?
    enum CodingKeys: String, CodingKey {
        case schoolId = "schoolId"
        case formRole = "formRole"
        case connectionId = "connectionId"
    }
}

private struct GoogleFormImportReviewParams: Encodable {
    let importId: UUID
    let decision: String
    let matchedChildId: UUID?
    let reviewNote: String?

    enum CodingKeys: String, CodingKey {
        case importId = "input_import_id"
        case decision = "input_decision"
        case matchedChildId = "input_matched_child_id"
        case reviewNote = "input_review_note"
    }
}

private struct ChildArchiveUpdate: Encodable {
    let active: Bool
    let archivedAt: Date
    let archivedBy: UUID
    let archiveReason: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case active
        case archivedAt = "archived_at"
        case archivedBy = "archived_by"
        case archiveReason = "archive_reason"
        case updatedAt = "updated_at"
    }
}

private struct SchoolMembershipDeactivateUpdate: Encodable {
    let active: Bool
}

private struct ChildMedicalProfileUpsert: Encodable {
    let childId: UUID
    let allergies: String?
    let immunizationStatus: String?
    let physicalStatus: String?
    let medicalNotes: String?
    let medicationInstructions: String?
    let medicineRequirements: String?
    let dietaryNotes: String?
    let emergencyNotes: String?
    let updatedBy: UUID
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case childId = "child_id"
        case allergies
        case immunizationStatus = "immunization_status"
        case physicalStatus = "physical_status"
        case medicalNotes = "medical_notes"
        case medicationInstructions = "medication_instructions"
        case medicineRequirements = "medicine_requirements"
        case dietaryNotes = "dietary_notes"
        case emergencyNotes = "emergency_notes"
        case updatedBy = "updated_by"
        case updatedAt = "updated_at"
    }
}

private struct ChildGoalInsert: Encodable {
    let schoolId: UUID
    let childId: UUID
    let title: String
    let notes: String?
    let status: String
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case schoolId = "school_id"
        case childId = "child_id"
        case title, notes, status
        case createdBy = "created_by"
    }
}

private struct ChildDocumentInsert: Encodable {
    let id: UUID
    let schoolId: UUID
    let childId: UUID
    let title: String
    let documentType: String
    let fileName: String?
    let filePath: String?
    let uploadedBy: UUID
    let verificationStatus: String

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case childId = "child_id"
        case title
        case documentType = "document_type"
        case fileName = "file_name"
        case filePath = "file_path"
        case uploadedBy = "uploaded_by"
        case verificationStatus = "verification_status"
    }
}

private struct ChildDocumentReviewUpdate: Encodable {
    let verificationStatus: String
    let reviewedBy: UUID
    let reviewedAt: Date
    let flagReason: String?

    enum CodingKeys: String, CodingKey {
        case verificationStatus = "verification_status"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case flagReason = "flag_reason"
    }
}

private struct CreateMedicationInstructionParams: Encodable {
    let schoolId: UUID
    let childId: UUID
    let title: String
    let dosage: String?
    let instructions: String?
    let scheduledAt: Date

    enum CodingKeys: String, CodingKey {
        case schoolId = "school_id"
        case childId = "child_id"
        case title, dosage, instructions
        case scheduledAt = "scheduled_at"
    }
}

private struct AcknowledgeMedicationTaskParams: Encodable {
    let taskId: UUID
    let dosageGiven: String?
    let notes: String?
    let givenAt: Date

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case dosageGiven = "dosage_given"
        case notes
        case givenAt = "given_at"
    }
}

private struct AssignmentFetchParams: Encodable {
    let schoolId: UUID
    let categories: [String]?
    let archived: Bool

    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
        case categories = "input_categories"
        case archived = "input_archived"
    }
}

private struct AssignmentAgendaFetchParams: Encodable {
    let categories: [String]?
    let archived: Bool

    enum CodingKeys: String, CodingKey {
        case categories = "input_categories"
        case archived = "input_archived"
    }
}

private struct AssignmentCreateMaterial: Encodable {
    let materialType: String
    let title: String?
    let url: String?
    let privateFilePath: String?
    let fileName: String?
    let contentType: String?

    enum CodingKeys: String, CodingKey {
        case materialType = "material_type"
        case title, url
        case privateFilePath = "private_file_path"
        case fileName = "file_name"
        case contentType = "content_type"
    }
}

private struct CreateAssignmentParams: Encodable {
    let schoolId: UUID
    let title: String
    let description: String?
    let category: String
    let audienceRole: String?
    let childId: UUID?
    let dueAt: Date?
    let requiresReview: Bool
    let recipientIds: [UUID]
    let materials: [AssignmentCreateMaterial]
    let status: String
    let publishAt: Date?
    let closeAt: Date?
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
        case title = "input_title"
        case description = "input_description"
        case category = "input_category"
        case audienceRole = "input_audience_role"
        case childId = "input_child_id"
        case dueAt = "input_due_at"
        case requiresReview = "input_requires_review"
        case recipientIds = "input_recipient_ids"
        case materials = "input_materials"
        case status = "input_status"
        case publishAt = "input_publish_at"
        case closeAt = "input_close_at"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct AssignmentIdParams: Encodable {
    let assignmentId: UUID

    enum CodingKeys: String, CodingKey {
        case assignmentId = "input_assignment_id"
    }
}

private struct AssignmentStatusParams: Encodable {
    let assignmentId: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case assignmentId = "input_assignment_id"
        case status = "input_status"
    }
}

private struct SubmitAssignmentParams: Encodable {
    let assignmentId: UUID
    let structuredPayload: [String: FireflyJSONValue]
    let feedbackText: String?
    let attachments: [AssignmentAttachmentDescriptor]
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case assignmentId = "input_assignment_id"
        case structuredPayload = "input_structured_payload"
        case feedbackText = "input_feedback_text"
        case attachments = "input_attachments"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct AssignmentSubmissionMutationLookupParams: Encodable {
    let assignmentId: UUID
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case assignmentId = "input_assignment_id"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct AssignmentAttachmentDescriptor: Encodable {
    let privateFilePath: String
    let fileName: String?
    let contentType: String?

    enum CodingKeys: String, CodingKey {
        case privateFilePath = "private_file_path"
        case fileName = "file_name"
        case contentType = "content_type"
    }
}

private struct ReviewAssignmentSubmissionParams: Encodable {
    let submissionId: UUID
    let status: String
    let reviewerMessage: String?
    let idempotencyKey: String
    let score: Int?

    enum CodingKeys: String, CodingKey {
        case submissionId = "input_submission_id"
        case status = "input_status"
        case reviewerMessage = "input_reviewer_message"
        case idempotencyKey = "input_idempotency_key"
        case score = "input_score"
    }
}

private struct UpdateAssignmentDetailsParams: Encodable {
    let assignmentId: UUID
    let title: String
    let description: String?
    let dueAt: Date?
    let allowResubmission: Bool
    let materials: [AssignmentMaterialMutation]

    enum CodingKeys: String, CodingKey {
        case assignmentId = "input_assignment_id"
        case title = "input_title"
        case description = "input_description"
        case dueAt = "input_due_at"
        case allowResubmission = "input_allow_resubmission"
        case materials = "input_materials"
    }
}

private struct AssignmentMaterialMutation: Encodable {
    let materialType: String
    let title: String?
    let url: String?
    let privateFilePath: String?
    let fileName: String?
    let contentType: String?

    enum CodingKeys: String, CodingKey {
        case materialType = "material_type"
        case title, url
        case privateFilePath = "private_file_path"
        case fileName = "file_name"
        case contentType = "content_type"
    }
}

private struct PostAssignmentCommentParams: Encodable {
    let assignmentId: UUID
    let recipientId: UUID
    let body: String
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case assignmentId = "input_assignment_id"
        case recipientId = "input_recipient_id"
        case body = "input_body"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct UpdateAssignmentScoreParams: Encodable {
    let submissionId: UUID
    let score: Int?
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case submissionId = "input_submission_id"
        case score = "input_score"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct TransactionalNotificationParams: Encodable {
    let schoolId: UUID
    let title: String
    let body: String
    let category: String
    let sourceType: String?
    let sourceId: UUID?
    let recipientIds: [UUID]
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
        case title = "input_title"
        case body = "input_body"
        case category = "input_category"
        case sourceType = "input_source_type"
        case sourceId = "input_source_id"
        case recipientIds = "input_recipient_ids"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct NotificationLimitParams: Encodable {
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case limit = "input_limit"
    }
}

private struct NotificationIdParams: Encodable {
    let notificationId: UUID

    enum CodingKeys: String, CodingKey {
        case notificationId = "input_notification_id"
    }
}

private struct NotificationThreadParams: Encodable {
    let threadKey: String

    enum CodingKeys: String, CodingKey {
        case threadKey = "input_thread_key"
    }
}

private struct PublishCommunityPostParams: Encodable {
    let postId: UUID
    let schoolId: UUID
    let body: String
    let imagePath: String?
    let attachmentPath: String?
    let attachmentName: String?
    let attachmentType: String?
    let linkedEventId: UUID?
    let pollQuestion: String?
    let pollOptions: [String]?
    let scheduledAt: Date?
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case postId = "input_post_id"
        case schoolId = "input_school_id"
        case body = "input_body"
        case imagePath = "input_image_path"
        case attachmentPath = "input_attachment_path"
        case attachmentName = "input_attachment_name"
        case attachmentType = "input_attachment_type"
        case linkedEventId = "input_linked_event_id"
        case pollQuestion = "input_poll_question"
        case pollOptions = "input_poll_options"
        case scheduledAt = "input_scheduled_at"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct PublishNewsletterParams: Encodable {
    let newsletterId: UUID
    let schoolId: UUID
    let title: String
    let body: String
    let media: [NewsletterMedia]
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case newsletterId = "input_newsletter_id"
        case schoolId = "input_school_id"
        case title = "input_title"
        case body = "input_body"
        case media = "input_media"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct CommunityAlbumRPCMedia: Encodable {
    let fileName: String?
    let filePath: String
    let contentType: String?

    init(_ upload: SchoolFileUpload) {
        fileName = upload.name
        filePath = upload.path
        contentType = upload.contentType
    }

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case filePath = "file_path"
        case contentType = "content_type"
    }
}

private struct PublishCommunityAlbumParams: Encodable {
    let albumId: UUID
    let schoolId: UUID
    let title: String
    let description: String?
    let coverPath: String?
    let media: [CommunityAlbumRPCMedia]
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case albumId = "input_album_id"
        case schoolId = "input_school_id"
        case title = "input_title"
        case description = "input_description"
        case coverPath = "input_cover_path"
        case media = "input_media"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct AppendCommunityAlbumMediaParams: Encodable {
    let albumId: UUID
    let media: [CommunityAlbumRPCMedia]
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case albumId = "input_album_id"
        case media = "input_media"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct AssignmentMaterialInsert: Encodable {
    let assignmentId: UUID
    let materialType: String
    let title: String?
    let url: String?
    let privateFilePath: String?
    let fileName: String?
    let contentType: String?

    enum CodingKeys: String, CodingKey {
        case assignmentId = "assignment_id"
        case materialType = "material_type"
        case title, url
        case privateFilePath = "private_file_path"
        case fileName = "file_name"
        case contentType = "content_type"
    }
}

private struct AssignmentSubmissionAttachmentInsert: Encodable {
    let submissionId: UUID
    let schoolId: UUID
    let privateFilePath: String
    let fileName: String?
    let contentType: String?

    enum CodingKeys: String, CodingKey {
        case submissionId = "submission_id"
        case schoolId = "school_id"
        case privateFilePath = "private_file_path"
        case fileName = "file_name"
        case contentType = "content_type"
    }
}

private struct OnboardingRequirementInsert: Encodable {
    let id: UUID
    let schoolId: UUID
    let title: String
    let description: String?
    let requirementType: String
    let targetRole: String?
    let targetUserId: UUID?
    let fileName: String?
    let filePath: String?
    let assignedBy: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case title, description
        case requirementType = "requirement_type"
        case targetRole = "target_role"
        case targetUserId = "target_user_id"
        case fileName = "file_name"
        case filePath = "file_path"
        case assignedBy = "assigned_by"
    }
}

private struct SchoolIdParams: Encodable {
    let schoolId: UUID

    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
    }
}

private struct OnboardingTemplateRoleParams: Encodable {
    let schoolId: UUID
    let targetRole: String

    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
        case targetRole = "input_target_role"
    }
}

private struct OnboardingTemplateIdParams: Encodable {
    let templateId: UUID

    enum CodingKeys: String, CodingKey {
        case templateId = "input_template_id"
    }
}

private struct OnboardingRequirementIdParams: Encodable {
    let requirementId: UUID

    enum CodingKeys: String, CodingKey {
        case requirementId = "input_requirement_id"
    }
}

private struct WaiveOnboardingAssignmentParams: Encodable {
    let assignmentId: UUID
    let reason: String

    enum CodingKeys: String, CodingKey {
        case assignmentId = "input_assignment_id"
        case reason = "input_reason"
    }
}

private struct ReorderOnboardingRequirementsParams: Encodable {
    let templateId: UUID
    let requirementIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case templateId = "input_template_id"
        case requirementIds = "input_requirement_ids"
    }
}

private struct SaveOnboardingRequirementParams: Encodable {
    let templateId: UUID
    let requirementId: UUID?
    let title: String
    let description: String?
    let subjectScope: String
    let position: Int
    let attachments: [OnboardingAttachmentDescriptor]
    let blocksAccess: Bool
    let childRecordBinding: String

    enum CodingKeys: String, CodingKey {
        case templateId = "input_template_id"
        case requirementId = "input_requirement_id"
        case title = "input_title"
        case description = "input_description"
        case subjectScope = "input_subject_scope"
        case position = "input_position"
        case attachments = "input_attachments"
        case blocksAccess = "input_blocks_access"
        case childRecordBinding = "input_child_record_binding"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(templateId, forKey: .templateId)
        if let requirementId {
            try container.encode(requirementId, forKey: .requirementId)
        } else {
            try container.encodeNil(forKey: .requirementId)
        }
        try container.encode(title, forKey: .title)
        if let description {
            try container.encode(description, forKey: .description)
        } else {
            try container.encodeNil(forKey: .description)
        }
        try container.encode(subjectScope, forKey: .subjectScope)
        try container.encode(position, forKey: .position)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(blocksAccess, forKey: .blocksAccess)
        try container.encode(childRecordBinding, forKey: .childRecordBinding)
    }
}

private struct SubmitRequiredDocumentParams: Encodable {
    let requirementId: UUID
    let fileName: String
    let filePath: String

    enum CodingKeys: String, CodingKey {
        case requirementId = "requirement_id"
        case fileName = "file_name"
        case filePath = "file_path"
    }
}

private struct ReviewRequiredDocumentParams: Encodable {
    let submissionId: UUID
    let status: String
    let reviewerMessage: String?

    enum CodingKeys: String, CodingKey {
        case submissionId = "submission_id"
        case status
        case reviewerMessage = "reviewer_message"
    }
}

private struct SubmitPaperworkAssignmentParams: Encodable {
    let assignmentId: UUID
    let fileName: String
    let filePath: String

    enum CodingKeys: String, CodingKey {
        case assignmentId = "assignment_id"
        case fileName = "file_name"
        case filePath = "file_path"
    }
}

private struct CommunityPostInsert: Encodable {
    let id: UUID
    let schoolId: UUID
    let body: String
    let imagePath: String?
    let attachmentPath: String?
    let attachmentName: String?
    let attachmentType: String?
    let linkedEventId: UUID?
    let pollQuestion: String?
    let pollOptions: [String]?
    let scheduledAt: Date?
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case body
        case imagePath = "image_path"
        case attachmentPath = "attachment_path"
        case attachmentName = "attachment_name"
        case attachmentType = "attachment_type"
        case linkedEventId = "linked_event_id"
        case pollQuestion = "poll_question"
        case pollOptions = "poll_options"
        case scheduledAt = "scheduled_at"
        case createdBy = "created_by"
    }
}

private struct NewsletterPostInsert: Encodable {
    let id: UUID
    let schoolId: UUID
    let title: String
    let body: String
    let createdBy: UUID
    let media: [NewsletterMedia]

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case title, body
        case createdBy = "created_by"
        case media
    }
}

private struct NewsletterPostUpdate: Encodable {
    let title: String
    let body: String
    let updatedAt: Date
    let media: [NewsletterMedia]

    enum CodingKeys: String, CodingKey {
        case title, body, media
        case updatedAt = "updated_at"
    }
}

private struct SchoolEventUpdate: Encodable {
    let title: String
    let description: String?
    let startAt: Date
    let endAt: Date?
    let allDay: Bool
    let repeatRule: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case title, description
        case startAt = "start_at"
        case endAt = "end_at"
        case allDay = "all_day"
        case repeatRule = "repeat_rule"
        case updatedAt = "updated_at"
    }
}

private struct SchoolEventArchiveParams: Encodable {
    let eventId: UUID
    let archived: Bool

    enum CodingKeys: String, CodingKey {
        case eventId = "input_event_id"
        case archived = "input_archived"
    }
}

private struct CommunityPostUpdate: Encodable {
    let body: String
    let linkedEventId: UUID?
    let pollQuestion: String?
    let pollOptions: [String]?
    let scheduledAt: Date?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case body
        case linkedEventId = "linked_event_id"
        case pollQuestion = "poll_question"
        case pollOptions = "poll_options"
        case scheduledAt = "scheduled_at"
        case updatedAt = "updated_at"
    }
}

private struct CommunityAlbumInsert: Encodable {
    let id: UUID
    let schoolId: UUID
    let title: String
    let description: String?
    let coverPath: String?
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case title, description
        case coverPath = "cover_path"
        case createdBy = "created_by"
    }
}

private struct CommunityAlbumMediaInsert: Encodable {
    let albumId: UUID
    let schoolId: UUID
    let fileName: String?
    let filePath: String
    let contentType: String?
    let uploadedBy: UUID

    enum CodingKeys: String, CodingKey {
        case albumId = "album_id"
        case schoolId = "school_id"
        case fileName = "file_name"
        case filePath = "file_path"
        case contentType = "content_type"
        case uploadedBy = "uploaded_by"
    }
}

private struct ReviewUpdate: Encodable {
    let status: String
    let flagReason: String?
    let reviewedBy: UUID
    let reviewedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case flagReason = "flag_reason"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
    }
}
