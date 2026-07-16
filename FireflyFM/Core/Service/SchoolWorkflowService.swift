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

struct AssignmentDetailBundle {
    let assignment: Assignment
    let materials: [AssignmentMaterial]
    let recipients: [AssignmentRecipient]
    let submissions: [AssignmentSubmission]
    let attachments: [AssignmentSubmissionAttachment]
    let readReceipts: [AssignmentReadReceipt]
    let feedbackMessages: [AssignmentFeedbackMessage]
    let events: [AssignmentEvent]
}

final class SchoolWorkflowService {
    static let shared = SchoolWorkflowService()

    private let client = AppConstants.supabase

    private init() {}

    // MARK: - Canvas Assignments

    func fetchAssignmentInbox(schoolId: UUID, categories: [AssignmentCategory]? = nil) async throws -> [AssignmentInboxItem] {
        try await client.rpc(
            "fetch_assignment_inbox",
            params: AssignmentFetchParams(
                schoolId: schoolId,
                categories: categories?.map(\.rawValue)
            )
        )
        .execute()
        .value
    }

    func fetchAssignmentReviewQueue(schoolId: UUID, categories: [AssignmentCategory]? = nil) async throws -> [AssignmentInboxItem] {
        try await client.rpc(
            "fetch_assignment_review_queue",
            params: AssignmentFetchParams(
                schoolId: schoolId,
                categories: categories?.map(\.rawValue)
            )
        )
        .execute()
        .value
    }

    func fetchAssignmentDetail(assignmentId: UUID) async throws -> AssignmentDetailBundle {
        let assignments: [Assignment] = try await client.from("assignments")
            .select()
            .eq("id", value: assignmentId)
            .execute()
            .value

        guard let assignment = assignments.first else {
            throw SchoolWorkflowError.notFound
        }

        async let loadedMaterials: [AssignmentMaterial] = client.from("assignment_materials")
            .select()
            .eq("assignment_id", value: assignmentId)
            .order("created_at", ascending: true)
            .execute()
            .value
        async let loadedRecipients: [AssignmentRecipient] = client.from("assignment_recipients")
            .select()
            .eq("assignment_id", value: assignmentId)
            .execute()
            .value
        async let loadedSubmissions: [AssignmentSubmission] = client.from("assignment_submissions")
            .select()
            .eq("assignment_id", value: assignmentId)
            .order("submitted_at", ascending: false)
            .execute()
            .value
        async let loadedReadReceipts: [AssignmentReadReceipt] = client.from("assignment_read_receipts")
            .select()
            .eq("assignment_id", value: assignmentId)
            .execute()
            .value
        async let loadedFeedback: [AssignmentFeedbackMessage] = client.from("assignment_feedback_messages")
            .select()
            .eq("assignment_id", value: assignmentId)
            .order("created_at", ascending: true)
            .execute()
            .value
        async let loadedEvents: [AssignmentEvent] = client.from("assignment_events")
            .select("id,assignment_id,school_id,actor_id,event_type,created_at")
            .eq("assignment_id", value: assignmentId)
            .order("created_at", ascending: false)
            .execute()
            .value

        let materials = try await loadedMaterials
        let recipients = try await loadedRecipients
        let submissions = try await loadedSubmissions
        let readReceipts = try await loadedReadReceipts
        let feedbackMessages = try await loadedFeedback
        let events = try await loadedEvents
        let submissionIds = submissions.map(\.id)
        let attachments: [AssignmentSubmissionAttachment]
        if submissionIds.isEmpty {
            attachments = []
        } else {
            attachments = try await client.from("assignment_submission_attachments")
                .select()
                .in("submission_id", values: submissionIds)
                .order("created_at", ascending: false)
                .execute()
                .value
        }

        return AssignmentDetailBundle(
            assignment: assignment,
            materials: materials,
            recipients: recipients,
            submissions: submissions,
            attachments: attachments,
            readReceipts: readReceipts,
            feedbackMessages: feedbackMessages,
            events: events
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
        publishAt: Date?
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
            "create_assignment",
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
                closeAt: nil
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

    func markAssignmentRead(assignmentId: UUID) async throws {
        _ = try await client.rpc(
            "mark_assignment_read",
            params: AssignmentIdParams(assignmentId: assignmentId)
        )
        .execute()
    }

    func submitAssignment(assignment: Assignment, fileURLs: [URL], feedbackText: String?) async throws -> AssignmentSubmission {
        let user = try await client.auth.session.user
        var uploads: [SchoolFileUpload] = []
        for fileURL in fileURLs {
            let safeName = SchoolService.shared.safeStorageFileName(for: fileURL)
            let path = "schools/\(assignment.schoolId.uuidString)/assignments/\(assignment.id.uuidString)/submissions/\(user.id.uuidString)/\(UUID().uuidString)/\(safeName)"
            uploads.append(try await SchoolService.shared.uploadPrivateFile(fileURL: fileURL, path: path))
        }
        let firstUpload = uploads.first

        let submissions: [AssignmentSubmission] = try await client.rpc(
            "submit_assignment",
            params: SubmitAssignmentParams(
                assignmentId: assignment.id,
                fileName: firstUpload?.name,
                filePath: firstUpload?.path,
                contentType: firstUpload?.contentType,
                feedbackText: feedbackText?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
        .execute()
        .value

        guard let submission = submissions.first else {
            throw SchoolWorkflowError.notFound
        }

        let remainingAttachments = uploads.dropFirst().map { upload in
            AssignmentSubmissionAttachmentInsert(
                submissionId: submission.id,
                schoolId: assignment.schoolId,
                privateFilePath: upload.path,
                fileName: upload.name,
                contentType: upload.contentType
            )
        }
        if remainingAttachments.isEmpty == false {
            try await client.from("assignment_submission_attachments")
                .insert(Array(remainingAttachments))
                .execute()
        }
        return submission
    }

    func reviewAssignmentSubmission(submissionId: UUID, status: String, message: String?) async throws -> AssignmentSubmission {
        let submissions: [AssignmentSubmission] = try await client.rpc(
            "review_assignment_submission",
            params: ReviewAssignmentSubmissionParams(
                submissionId: submissionId,
                status: status,
                reviewerMessage: message
            )
        )
        .execute()
        .value

        guard let submission = submissions.first else {
            throw SchoolWorkflowError.notFound
        }
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
        try await client.from("newsletters")
            .select()
            .eq("school_id", value: schoolId)
            .order("created_at", ascending: false)
            .limit(25)
            .execute()
            .value
    }

    func createNewsletter(schoolId: UUID, title: String, body: String) async throws {
        let user = try await client.auth.session.user
        let post = NewsletterPost(schoolId: schoolId, title: title, body: body, createdBy: user.id)
        try await client.from("newsletters")
            .insert(post)
            .execute()
    }

    // MARK: - Events

    func fetchEvents(schoolId: UUID) async throws -> [SchoolEvent] {
        try await client.from("school_events")
            .select()
            .eq("school_id", value: schoolId)
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
        invitedUserIds: [UUID] = [],
        shareAsNotification: Bool = false
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

        if shareAsNotification {
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

    func createNotification(
        schoolId: UUID,
        title: String,
        body: String,
        category: String,
        sourceType: String? = nil,
        sourceId: UUID? = nil,
        recipientIds: [UUID]
    ) async throws {
        let user = try await client.auth.session.user
        let notification = AppNotification(
            schoolId: schoolId,
            title: title,
            body: body,
            category: category,
            sourceType: sourceType,
            sourceId: sourceId,
            createdBy: user.id
        )

        let inserted: [AppNotification] = try await client.from("notifications")
            .insert(notification)
            .select()
            .execute()
            .value

        guard let createdNotification = inserted.first else { return }

        let recipients = recipientIds.map {
            NotificationRecipient(notificationId: createdNotification.id, userId: $0, readAt: nil, deliveredAt: nil)
        }
        if recipients.isEmpty == false {
            try await client.from("notification_recipients")
                .insert(recipients)
            .execute()
        }
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

    func fetchClassrooms(schoolId: UUID) async throws -> [Classroom] {
        try await client.from("classrooms")
            .select()
            .eq("school_id", value: schoolId)
            .order("name", ascending: true)
            .execute()
            .value
    }

    func addChild(schoolId: UUID, firstName: String, lastName: String) async throws {
        let child = Child(schoolId: schoolId, firstName: firstName, lastName: lastName)
        try await client.from("children")
            .insert(child)
            .execute()
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
        try await client.from("child_guardians")
            .delete()
            .eq("child_id", value: childId)
            .eq("guardian_id", value: guardianId)
            .execute()
    }

    func deactivateSchoolMember(schoolId: UUID, userId: UUID) async throws {
        try await client.from("school_memberships")
            .update(SchoolMembershipDeactivateUpdate(active: false))
            .eq("school_id", value: schoolId)
            .eq("user_id", value: userId)
            .execute()
    }

    func createChildForCurrentParent(
        schoolId: UUID,
        firstName: String,
        lastName: String,
        birthdate: Date?
    ) async throws -> Child {
        let results: [Child] = try await client.rpc(
            "create_child_for_current_parent",
            params: CreateChildForCurrentParentParams(
                schoolId: schoolId,
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                birthdate: birthdate
            )
        )
        .execute()
        .value

        guard let child = results.first else {
            throw SchoolWorkflowError.notFound
        }
        return child
    }

    @discardableResult
    func recordAttendance(
        schoolId: UUID,
        childId: UUID,
        checkingIn: Bool,
        recordedAt: Date = Date(),
        notes: String?
    ) async throws -> ChildAttendance {
        let results: [ChildAttendance] = try await client.rpc(
            "record_child_attendance",
            params: RecordChildAttendanceParams(
                schoolId: schoolId,
                childId: childId,
                checkingIn: checkingIn,
                recordedAt: recordedAt,
                notes: notes
            )
        )
        .execute()
        .value

        guard let attendance = results.first else {
            throw SchoolWorkflowError.notFound
        }
        return attendance
    }

    func recordChildActivity(schoolId: UUID, childId: UUID, activityType: String, notes: String?) async throws {
        let user = try await client.auth.session.user
        let log = ChildActivityLog(
            schoolId: schoolId,
            childId: childId,
            activityType: activityType,
            notes: notes,
            recordedBy: user.id
        )
        try await client.from("child_activity_logs")
            .insert(log)
            .execute()
    }

    func fetchChildGuardians(childId: UUID) async throws -> [ChildGuardian] {
        try await client.from("child_guardians")
            .select()
            .eq("child_id", value: childId)
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
        sleepHabits: String?,
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
            sleepHabits: sleepHabits,
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
            try? await createNotification(
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

        try? await createNotification(
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
        let user = try await client.auth.session.user
        let postId = UUID()
        var imagePath: String?
        var attachmentPath: String?
        var attachmentName: String?
        var attachmentType: String?

        if let attachment {
            let safeName = safeStorageFileName(attachment.fileName)
            let path = "schools/\(schoolId.uuidString)/community_posts/\(postId.uuidString)/\(safeName)"
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

        try await client.from("community_posts")
            .insert(CommunityPostInsert(
                id: postId,
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
                createdBy: user.id
            ))
            .execute()

        try? await notifyCommunityPostCreated(
            schoolId: schoolId,
            postId: postId,
            body: body,
            createdBy: user.id
        )
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
        let user = try await client.auth.session.user
        let albumId = UUID()
        let limitedMedia = Array(media.prefix(100))
        var uploads: [SchoolFileUpload] = []

        for item in limitedMedia {
            let safeName = safeStorageFileName(item.fileName)
            let path = "schools/\(schoolId.uuidString)/community_albums/\(albumId.uuidString)/media/\(UUID().uuidString)-\(safeName)"
            let upload = try await SchoolService.shared.uploadPrivateData(
                data: item.data,
                path: path,
                name: item.fileName,
                contentType: item.contentType
            )
            uploads.append(upload)
        }

        let albums: [CommunityAlbum] = try await client.from("community_albums")
            .insert(CommunityAlbumInsert(
                id: albumId,
                schoolId: schoolId,
                title: title,
                description: description,
                coverPath: uploads.first?.path,
                createdBy: user.id
            ))
            .select()
            .execute()
            .value

        let mediaRows = uploads.map {
            CommunityAlbumMediaInsert(
                albumId: albumId,
                schoolId: schoolId,
                fileName: $0.name,
                filePath: $0.path,
                contentType: $0.contentType,
                uploadedBy: user.id
            )
        }
        if mediaRows.isEmpty == false {
            try await client.from("community_album_media")
                .insert(mediaRows)
                .execute()
        }

        guard let album = albums.first else {
            throw SchoolWorkflowError.notFound
        }
        return album
    }

    func addMediaToCommunityAlbum(schoolId: UUID, album: CommunityAlbum, media: [CommunityMediaUpload]) async throws {
        let user = try await client.auth.session.user
        let limitedMedia = Array(media.prefix(100))
        var rows: [CommunityAlbumMediaInsert] = []

        for item in limitedMedia {
            let safeName = safeStorageFileName(item.fileName)
            let path = "schools/\(schoolId.uuidString)/community_albums/\(album.id.uuidString)/media/\(UUID().uuidString)-\(safeName)"
            let upload = try await SchoolService.shared.uploadPrivateData(
                data: item.data,
                path: path,
                name: item.fileName,
                contentType: item.contentType
            )
            rows.append(CommunityAlbumMediaInsert(
                albumId: album.id,
                schoolId: schoolId,
                fileName: upload.name,
                filePath: upload.path,
                contentType: upload.contentType,
                uploadedBy: user.id
            ))
        }

        if rows.isEmpty == false {
            try await client.from("community_album_media")
                .insert(rows)
                .execute()
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

        return try await createCommunityAlbum(
            schoolId: schoolId,
            title: "All Photos",
            description: "School-wide shared photos and videos.",
            media: []
        )
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

        try? await createNotification(
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

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "The requested school workflow item was not found or is not visible to this account. Refresh the list and confirm that the assignment recipient and school access are still active."
        }
    }
}

private struct CreateChildForCurrentParentParams: Encodable {
    let schoolId: UUID
    let firstName: String
    let lastName: String
    let birthdate: Date?

    enum CodingKeys: String, CodingKey {
        case schoolId = "school_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case birthdate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schoolId, forKey: .schoolId)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(lastName, forKey: .lastName)
        try DateOnlyCoding.encodeDateOnlyIfPresent(birthdate, to: &container, forKey: .birthdate)
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

private struct RecordChildAttendanceParams: Encodable {
    let schoolId: UUID
    let childId: UUID
    let checkingIn: Bool
    let recordedAt: Date
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
        case childId = "input_child_id"
        case checkingIn = "checking_in"
        case recordedAt = "recorded_at"
        case notes = "input_notes"
    }
}

private struct ChildMedicalProfileUpsert: Encodable {
    let childId: UUID
    let allergies: String?
    let immunizationStatus: String?
    let physicalStatus: String?
    let medicalNotes: String?
    let medicationInstructions: String?
    let sleepHabits: String?
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
        case sleepHabits = "sleep_habits"
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

    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
        case categories = "input_categories"
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
    let fileName: String?
    let filePath: String?
    let contentType: String?
    let feedbackText: String?

    enum CodingKeys: String, CodingKey {
        case assignmentId = "input_assignment_id"
        case fileName = "input_file_name"
        case filePath = "input_file_path"
        case contentType = "input_content_type"
        case feedbackText = "input_feedback_text"
    }
}

private struct ReviewAssignmentSubmissionParams: Encodable {
    let submissionId: UUID
    let status: String
    let reviewerMessage: String?

    enum CodingKeys: String, CodingKey {
        case submissionId = "input_submission_id"
        case status = "input_status"
        case reviewerMessage = "input_reviewer_message"
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
