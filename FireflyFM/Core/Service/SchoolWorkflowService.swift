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

    func addChild(schoolId: UUID, firstName: String, lastName: String) async throws {
        let child = Child(schoolId: schoolId, firstName: firstName, lastName: lastName)
        try await client.from("children")
            .insert(child)
            .execute()
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
