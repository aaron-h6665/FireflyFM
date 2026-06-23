//
//  SchoolWorkflowService.swift
//  FireflyFM
//

import Foundation
import Supabase

final class SchoolWorkflowService {
    static let shared = SchoolWorkflowService()

    private let client = AppConstants.supabase

    private init() {}

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
            let recipients: [UUID]
            if invitedUserIds.isEmpty {
                let members = try await SchoolService.shared.fetchMembers(schoolId: schoolId)
                recipients = members.map(\.id)
            } else {
                recipients = invitedUserIds
            }
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

    func recordAttendance(schoolId: UUID, childId: UUID, checkingIn: Bool, notes: String?) async throws {
        let user = try await client.auth.session.user
        let attendance = ChildAttendance(
            schoolId: schoolId,
            childId: childId,
            checkedInAt: checkingIn ? Date() : nil,
            checkedOutAt: checkingIn ? nil : Date(),
            recordedBy: user.id,
            notes: notes
        )
        try await client.from("child_attendance")
            .insert(attendance)
            .execute()
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
            .order("created_at", ascending: false)
            .limit(40)
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

    func submitPaperwork(assignment: PaperworkAssignment, fileURL: URL) async throws {
        let user = try await client.auth.session.user
        let submissionId = UUID()
        let safeName = SchoolService.shared.safeStorageFileName(for: fileURL)
        let path = "schools/\(assignment.schoolId.uuidString)/paperwork_submissions/\(user.id.uuidString)/\(submissionId.uuidString)/\(safeName)"
        let upload = try await SchoolService.shared.uploadPrivateFile(fileURL: fileURL, path: path)
        let submission = PaperworkSubmission(
            id: submissionId,
            assignmentId: assignment.id,
            schoolId: assignment.schoolId,
            submittedBy: user.id,
            fileName: upload.name,
            filePath: upload.path
        )

        try await client.from("paperwork_submissions")
            .insert(submission)
            .execute()
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
        let user = try await client.auth.session.user
        let postId = UUID()
        var imagePath: String?

        if let imageURL {
            let safeName = SchoolService.shared.safeStorageFileName(for: imageURL)
            let path = "schools/\(schoolId.uuidString)/community_posts/\(postId.uuidString)/\(safeName)"
            let upload = try await SchoolService.shared.uploadPrivateFile(fileURL: imageURL, path: path)
            imagePath = upload.path
        }

        try await client.from("community_posts")
            .insert(CommunityPostInsert(id: postId, schoolId: schoolId, body: body, imagePath: imagePath, createdBy: user.id))
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

    func createCommunityAlbum(schoolId: UUID, title: String, description: String?, coverURL: URL?) async throws {
        let user = try await client.auth.session.user
        let albumId = UUID()
        var coverPath: String?

        if let coverURL {
            let safeName = SchoolService.shared.safeStorageFileName(for: coverURL)
            let path = "schools/\(schoolId.uuidString)/community_albums/\(albumId.uuidString)/cover/\(safeName)"
            let upload = try await SchoolService.shared.uploadPrivateFile(fileURL: coverURL, path: path)
            coverPath = upload.path
        }

        try await client.from("community_albums")
            .insert(CommunityAlbumInsert(id: albumId, schoolId: schoolId, title: title, description: description, coverPath: coverPath, createdBy: user.id))
            .execute()
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

    func createCurriculumResource(schoolId: UUID, title: String, description: String?, fileURL: URL?) async throws {
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

    func createTrainingAssignment(schoolId: UUID, title: String, description: String?, fileURL: URL?, teacherIds: [UUID]) async throws {
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
            assignedBy: user.id
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

enum SchoolWorkflowError: Error {
    case notFound
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
}

private struct ChildMedicalProfileUpsert: Encodable {
    let childId: UUID
    let allergies: String?
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

private struct CommunityPostInsert: Encodable {
    let id: UUID
    let schoolId: UUID
    let body: String
    let imagePath: String?
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case body
        case imagePath = "image_path"
        case createdBy = "created_by"
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
