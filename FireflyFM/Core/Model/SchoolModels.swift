//
//  SchoolModels.swift
//  FireflyFM
//

import Foundation

enum SchoolRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case parent
    case teacher
    case schoolDirector = "school_director"
    case hqDirector = "hq_director"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .parent: "Parent"
        case .teacher: "Teacher"
        case .schoolDirector: "School Director"
        case .hqDirector: "Headquarter Director"
        }
    }

    var canManageSchool: Bool {
        self == .schoolDirector || self == .hqDirector
    }

    var canManageEvents: Bool {
        self == .teacher || canManageSchool
    }
}

struct School: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var description: String?
    var tourUrl: String?
    var profileImageUrl: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case tourUrl = "tour_url"
        case profileImageUrl = "profile_image_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SchoolCreationResult: Codable, Hashable {
    var schoolId: UUID
    var schoolName: String
    var inviteToken: String
    var inviteUrl: String?

    enum CodingKeys: String, CodingKey {
        case schoolId = "school_id"
        case schoolName = "school_name"
        case inviteToken = "invite_token"
        case inviteUrl = "invite_url"
    }
}

struct SchoolMembership: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var userId: UUID
    var role: SchoolRole
    var active: Bool
    var joinedAt: Date?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case userId = "user_id"
        case role, active
        case joinedAt = "joined_at"
        case createdAt = "created_at"
    }
}

struct SchoolInvite: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var code: String
    var role: SchoolRole
    var createdBy: UUID?
    var active: Bool
    var maxUses: Int?
    var useCount: Int
    var expiresAt: Date?
    var createdAt: Date?

    init(
        id: UUID = UUID(),
        schoolId: UUID,
        code: String = SchoolInvite.makeCode(),
        role: SchoolRole,
        createdBy: UUID? = nil,
        active: Bool = true,
        maxUses: Int? = 1,
        useCount: Int = 0,
        expiresAt: Date? = nil,
        createdAt: Date? = Date()
    ) {
        self.id = id
        self.schoolId = schoolId
        self.code = code
        self.role = role
        self.createdBy = createdBy
        self.active = active
        self.maxUses = maxUses
        self.useCount = useCount
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case code, role
        case createdBy = "created_by"
        case active
        case maxUses = "max_uses"
        case useCount = "use_count"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }

    private static func makeCode() -> String {
        UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(10)
            .uppercased()
    }
}

struct SchoolMembershipContext: Identifiable, Hashable {
    var id: UUID { membership.id }
    var school: School
    var membership: SchoolMembership
}

struct NewsletterPost: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var title: String
    var body: String
    var createdBy: UUID?
    var createdAt: Date?
    var updatedAt: Date?

    init(id: UUID = UUID(), schoolId: UUID, title: String, body: String, createdBy: UUID? = nil, createdAt: Date? = Date(), updatedAt: Date? = nil) {
        self.id = id
        self.schoolId = schoolId
        self.title = title
        self.body = body
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case title, body
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SchoolEvent: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var title: String
    var description: String?
    var startAt: Date
    var endAt: Date?
    var allDay: Bool
    var repeatRule: String?
    var createdBy: UUID?
    var createdAt: Date?
    var updatedAt: Date?

    init(id: UUID = UUID(), schoolId: UUID, title: String, description: String? = nil, startAt: Date, endAt: Date? = nil, allDay: Bool = false, repeatRule: String? = nil, createdBy: UUID? = nil, createdAt: Date? = Date(), updatedAt: Date? = nil) {
        self.id = id
        self.schoolId = schoolId
        self.title = title
        self.description = description
        self.startAt = startAt
        self.endAt = endAt
        self.allDay = allDay
        self.repeatRule = repeatRule
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case title, description
        case startAt = "start_at"
        case endAt = "end_at"
        case allDay = "all_day"
        case repeatRule = "repeat_rule"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SchoolEventInvite: Codable, Hashable {
    var eventId: UUID
    var userId: UUID
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

struct AppNotification: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var title: String
    var body: String
    var category: String
    var sourceType: String?
    var sourceId: UUID?
    var createdBy: UUID?
    var createdAt: Date?

    init(id: UUID = UUID(), schoolId: UUID, title: String, body: String, category: String, sourceType: String? = nil, sourceId: UUID? = nil, createdBy: UUID? = nil, createdAt: Date? = Date()) {
        self.id = id
        self.schoolId = schoolId
        self.title = title
        self.body = body
        self.category = category
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.createdBy = createdBy
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case title, body, category
        case sourceType = "source_type"
        case sourceId = "source_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

struct NotificationRecipient: Codable, Hashable {
    var notificationId: UUID
    var userId: UUID
    var readAt: Date?
    var deliveredAt: Date?

    enum CodingKeys: String, CodingKey {
        case notificationId = "notification_id"
        case userId = "user_id"
        case readAt = "read_at"
        case deliveredAt = "delivered_at"
    }
}

struct Child: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var firstName: String
    var lastName: String
    var birthdate: Date?
    var active: Bool
    var createdAt: Date?
    var updatedAt: Date?

    init(id: UUID = UUID(), schoolId: UUID, firstName: String, lastName: String, birthdate: Date? = nil, active: Bool = true, createdAt: Date? = Date(), updatedAt: Date? = nil) {
        self.id = id
        self.schoolId = schoolId
        self.firstName = firstName
        self.lastName = lastName
        self.birthdate = birthdate
        self.active = active
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var fullName: String { "\(firstName) \(lastName)" }

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case birthdate, active
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct Classroom: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var name: String
    var isDefault: Bool
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case name
        case isDefault = "is_default"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChildGuardian: Codable, Identifiable, Hashable {
    var childId: UUID
    var guardianId: UUID
    var relationship: String?
    var createdAt: Date?

    var id: String { "\(childId.uuidString)-\(guardianId.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case childId = "child_id"
        case guardianId = "guardian_id"
        case relationship
        case createdAt = "created_at"
    }
}

struct ChildMedicalProfile: Codable, Identifiable, Hashable {
    var childId: UUID
    var allergies: String?
    var medicalNotes: String?
    var medicationInstructions: String?
    var sleepHabits: String?
    var dietaryNotes: String?
    var emergencyNotes: String?
    var updatedBy: UUID?
    var updatedAt: Date?

    var id: UUID { childId }

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

struct ChildEmergencyContact: Codable, Identifiable, Hashable {
    var id: UUID
    var childId: UUID
    var name: String
    var relationship: String?
    var phone: String?
    var email: String?
    var canPickup: Bool
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case childId = "child_id"
        case name, relationship, phone, email
        case canPickup = "can_pickup"
        case createdAt = "created_at"
    }
}

struct ChildProgressReport: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var childId: UUID
    var title: String
    var body: String?
    var fileName: String?
    var filePath: String?
    var createdBy: UUID?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case childId = "child_id"
        case title, body
        case fileName = "file_name"
        case filePath = "file_path"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

struct ChildGoal: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var childId: UUID
    var title: String
    var notes: String?
    var status: String
    var dueAt: Date?
    var createdBy: UUID?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case childId = "child_id"
        case title, notes, status
        case dueAt = "due_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

struct ChildDocument: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var childId: UUID
    var title: String
    var documentType: String
    var fileName: String?
    var filePath: String?
    var uploadedBy: UUID?
    var verificationStatus: String
    var reviewedBy: UUID?
    var reviewedAt: Date?
    var flagReason: String?
    var createdAt: Date?

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
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case flagReason = "flag_reason"
        case createdAt = "created_at"
    }
}

struct ChildAttendance: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var childId: UUID
    var checkedInAt: Date?
    var checkedOutAt: Date?
    var recordedBy: UUID?
    var notes: String?
    var createdAt: Date?

    init(id: UUID = UUID(), schoolId: UUID, childId: UUID, checkedInAt: Date? = nil, checkedOutAt: Date? = nil, recordedBy: UUID? = nil, notes: String? = nil, createdAt: Date? = Date()) {
        self.id = id
        self.schoolId = schoolId
        self.childId = childId
        self.checkedInAt = checkedInAt
        self.checkedOutAt = checkedOutAt
        self.recordedBy = recordedBy
        self.notes = notes
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case childId = "child_id"
        case checkedInAt = "checked_in_at"
        case checkedOutAt = "checked_out_at"
        case recordedBy = "recorded_by"
        case notes
        case createdAt = "created_at"
    }
}

struct ChildActivityLog: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var childId: UUID
    var activityType: String
    var notes: String?
    var recordedBy: UUID?
    var recordedAt: Date?

    init(id: UUID = UUID(), schoolId: UUID, childId: UUID, activityType: String, notes: String? = nil, recordedBy: UUID? = nil, recordedAt: Date? = Date()) {
        self.id = id
        self.schoolId = schoolId
        self.childId = childId
        self.activityType = activityType
        self.notes = notes
        self.recordedBy = recordedBy
        self.recordedAt = recordedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case childId = "child_id"
        case activityType = "activity_type"
        case notes
        case recordedBy = "recorded_by"
        case recordedAt = "recorded_at"
    }
}

struct MedicationInstruction: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var childId: UUID
    var title: String
    var dosage: String?
    var instructions: String?
    var scheduledAt: Date
    var repeatRule: String?
    var startsOn: Date?
    var endsOn: Date?
    var createdBy: UUID?
    var active: Bool
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case childId = "child_id"
        case title, dosage, instructions
        case scheduledAt = "scheduled_at"
        case repeatRule = "repeat_rule"
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case createdBy = "created_by"
        case active
        case createdAt = "created_at"
    }
}

struct MedicationTask: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var childId: UUID
    var instructionId: UUID
    var dueAt: Date
    var status: String
    var assignedTo: UUID?
    var escalatedAt: Date?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case childId = "child_id"
        case instructionId = "instruction_id"
        case dueAt = "due_at"
        case status
        case assignedTo = "assigned_to"
        case escalatedAt = "escalated_at"
        case createdAt = "created_at"
    }
}

struct MedicationAcknowledgement: Codable, Identifiable, Hashable {
    var id: UUID
    var taskId: UUID
    var schoolId: UUID
    var childId: UUID
    var acknowledgedBy: UUID
    var dosageGiven: String?
    var notes: String?
    var givenAt: Date
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case schoolId = "school_id"
        case childId = "child_id"
        case acknowledgedBy = "acknowledged_by"
        case dosageGiven = "dosage_given"
        case notes
        case givenAt = "given_at"
        case createdAt = "created_at"
    }
}

struct MedicationEscalation: Codable, Identifiable, Hashable {
    var id: UUID
    var taskId: UUID
    var schoolId: UUID
    var childId: UUID
    var reason: String
    var status: String
    var createdAt: Date?
    var resolvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case schoolId = "school_id"
        case childId = "child_id"
        case reason, status
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
    }
}

struct OnboardingRequirement: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var title: String
    var description: String?
    var requirementType: String
    var targetRole: SchoolRole?
    var targetUserId: UUID?
    var fileName: String?
    var filePath: String?
    var assignedBy: UUID?
    var dueAt: Date?
    var createdAt: Date?

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
        case dueAt = "due_at"
        case createdAt = "created_at"
    }
}

struct DocumentSubmission: Codable, Identifiable, Hashable {
    var id: UUID
    var requirementId: UUID
    var schoolId: UUID
    var submittedBy: UUID
    var fileName: String?
    var filePath: String?
    var status: String
    var reviewerMessage: String?
    var reviewedBy: UUID?
    var reviewedAt: Date?
    var submittedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case requirementId = "requirement_id"
        case schoolId = "school_id"
        case submittedBy = "submitted_by"
        case fileName = "file_name"
        case filePath = "file_path"
        case status
        case reviewerMessage = "reviewer_message"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case submittedAt = "submitted_at"
    }
}

struct PaymentSetupRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var userId: UUID
    var paymentType: String
    var status: String
    var notes: String?
    var updatedAt: Date?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case userId = "user_id"
        case paymentType = "payment_type"
        case status, notes
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }
}

struct CommunityPost: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var body: String
    var imagePath: String?
    var createdBy: UUID?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case body
        case imagePath = "image_path"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommunityAlbum: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var title: String
    var description: String?
    var coverPath: String?
    var createdBy: UUID?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case title, description
        case coverPath = "cover_path"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

struct CommunityAlbumMedia: Codable, Identifiable, Hashable {
    var id: UUID
    var albumId: UUID
    var schoolId: UUID
    var fileName: String?
    var filePath: String
    var contentType: String?
    var uploadedBy: UUID?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case albumId = "album_id"
        case schoolId = "school_id"
        case fileName = "file_name"
        case filePath = "file_path"
        case contentType = "content_type"
        case uploadedBy = "uploaded_by"
        case createdAt = "created_at"
    }
}

struct QueuedNotification: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID?
    var userId: UUID?
    var title: String
    var body: String
    var category: String
    var deliverAt: Date
    var deliveredAt: Date?
    var status: String
    var sourceType: String?
    var sourceId: UUID?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case userId = "user_id"
        case title, body, category
        case deliverAt = "deliver_at"
        case deliveredAt = "delivered_at"
        case status
        case sourceType = "source_type"
        case sourceId = "source_id"
        case createdAt = "created_at"
    }
}

struct PaperworkAssignment: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var title: String
    var description: String?
    var fileName: String?
    var filePath: String?
    var assignedBy: UUID?
    var dueAt: Date?
    var createdAt: Date?

    init(id: UUID = UUID(), schoolId: UUID, title: String, description: String? = nil, fileName: String? = nil, filePath: String? = nil, assignedBy: UUID? = nil, dueAt: Date? = nil, createdAt: Date? = Date()) {
        self.id = id
        self.schoolId = schoolId
        self.title = title
        self.description = description
        self.fileName = fileName
        self.filePath = filePath
        self.assignedBy = assignedBy
        self.dueAt = dueAt
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case title, description
        case fileName = "file_name"
        case filePath = "file_path"
        case assignedBy = "assigned_by"
        case dueAt = "due_at"
        case createdAt = "created_at"
    }
}

struct PaperworkAssignmentRecipient: Codable, Hashable {
    var assignmentId: UUID
    var parentId: UUID
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case assignmentId = "assignment_id"
        case parentId = "parent_id"
        case createdAt = "created_at"
    }
}

struct PaperworkSubmission: Codable, Identifiable, Hashable {
    var id: UUID
    var assignmentId: UUID
    var schoolId: UUID
    var submittedBy: UUID
    var fileName: String?
    var filePath: String?
    var status: String
    var flagReason: String?
    var reviewedBy: UUID?
    var reviewedAt: Date?
    var submittedAt: Date?

    init(id: UUID = UUID(), assignmentId: UUID, schoolId: UUID, submittedBy: UUID, fileName: String? = nil, filePath: String? = nil, status: String = "submitted", flagReason: String? = nil, reviewedBy: UUID? = nil, reviewedAt: Date? = nil, submittedAt: Date? = Date()) {
        self.id = id
        self.assignmentId = assignmentId
        self.schoolId = schoolId
        self.submittedBy = submittedBy
        self.fileName = fileName
        self.filePath = filePath
        self.status = status
        self.flagReason = flagReason
        self.reviewedBy = reviewedBy
        self.reviewedAt = reviewedAt
        self.submittedAt = submittedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case assignmentId = "assignment_id"
        case schoolId = "school_id"
        case submittedBy = "submitted_by"
        case fileName = "file_name"
        case filePath = "file_path"
        case status
        case flagReason = "flag_reason"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case submittedAt = "submitted_at"
    }
}

struct CurriculumResource: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var title: String
    var description: String?
    var fileName: String?
    var filePath: String?
    var uploadedBy: UUID?
    var createdAt: Date?
    var updatedAt: Date?

    init(id: UUID = UUID(), schoolId: UUID, title: String, description: String? = nil, fileName: String? = nil, filePath: String? = nil, uploadedBy: UUID? = nil, createdAt: Date? = Date(), updatedAt: Date? = nil) {
        self.id = id
        self.schoolId = schoolId
        self.title = title
        self.description = description
        self.fileName = fileName
        self.filePath = filePath
        self.uploadedBy = uploadedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case title, description
        case fileName = "file_name"
        case filePath = "file_path"
        case uploadedBy = "uploaded_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TrainingAssignment: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var title: String
    var description: String?
    var fileName: String?
    var filePath: String?
    var assignedBy: UUID?
    var dueAt: Date?
    var createdAt: Date?

    init(id: UUID = UUID(), schoolId: UUID, title: String, description: String? = nil, fileName: String? = nil, filePath: String? = nil, assignedBy: UUID? = nil, dueAt: Date? = nil, createdAt: Date? = Date()) {
        self.id = id
        self.schoolId = schoolId
        self.title = title
        self.description = description
        self.fileName = fileName
        self.filePath = filePath
        self.assignedBy = assignedBy
        self.dueAt = dueAt
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case title, description
        case fileName = "file_name"
        case filePath = "file_path"
        case assignedBy = "assigned_by"
        case dueAt = "due_at"
        case createdAt = "created_at"
    }
}

struct TrainingAssignmentRecipient: Codable, Hashable {
    var assignmentId: UUID
    var teacherId: UUID
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case assignmentId = "assignment_id"
        case teacherId = "teacher_id"
        case createdAt = "created_at"
    }
}

struct TrainingSubmission: Codable, Identifiable, Hashable {
    var id: UUID
    var assignmentId: UUID
    var schoolId: UUID
    var submittedBy: UUID
    var fileName: String?
    var filePath: String?
    var status: String
    var flagReason: String?
    var reviewedBy: UUID?
    var reviewedAt: Date?
    var submittedAt: Date?

    init(id: UUID = UUID(), assignmentId: UUID, schoolId: UUID, submittedBy: UUID, fileName: String? = nil, filePath: String? = nil, status: String = "submitted", flagReason: String? = nil, reviewedBy: UUID? = nil, reviewedAt: Date? = nil, submittedAt: Date? = Date()) {
        self.id = id
        self.assignmentId = assignmentId
        self.schoolId = schoolId
        self.submittedBy = submittedBy
        self.fileName = fileName
        self.filePath = filePath
        self.status = status
        self.flagReason = flagReason
        self.reviewedBy = reviewedBy
        self.reviewedAt = reviewedAt
        self.submittedAt = submittedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case assignmentId = "assignment_id"
        case schoolId = "school_id"
        case submittedBy = "submitted_by"
        case fileName = "file_name"
        case filePath = "file_path"
        case status
        case flagReason = "flag_reason"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case submittedAt = "submitted_at"
    }
}
