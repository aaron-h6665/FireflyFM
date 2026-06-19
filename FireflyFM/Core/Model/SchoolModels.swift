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
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case tourUrl = "tour_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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
