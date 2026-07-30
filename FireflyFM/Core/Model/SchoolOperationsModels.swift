import Foundation

enum AttendanceAction: String, Codable, CaseIterable, Hashable {
    case checkIn = "check_in"
    case checkOut = "check_out"
    case absent
}

enum FireflyJSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: FireflyJSONValue])
    case array([FireflyJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: FireflyJSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([FireflyJSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }
}

struct SchoolChildAccessContext: Hashable {
    let schoolId: UUID
    let role: SchoolRole
    let canManageConnections: Bool
    let canRecordSchoolCare: Bool

    init(schoolId: UUID, role: SchoolRole) {
        self.schoolId = schoolId
        self.role = role
        canManageConnections = role.has(.manageChildConnections)
        canRecordSchoolCare = role.has(.recordCare)
    }
}

enum ChildConnectionStatus: String, Codable, CaseIterable, Hashable {
    case pending, approved, rejected
}

struct ChildConnectionRequest: Codable, Identifiable, Hashable {
    let id: UUID
    let schoolId: UUID
    let requestedBy: UUID
    let legalFirstName: String
    let legalLastName: String
    let birthdate: Date
    let relationship: String
    let status: ChildConnectionStatus
    let matchedChildId: UUID?
    let reviewedBy: UUID?
    let reviewedAt: Date?
    let reviewNote: String?
    let createdAt: Date

    var legalName: String { "\(legalFirstName) \(legalLastName)" }

    enum CodingKeys: String, CodingKey {
        case id, birthdate, relationship, status
        case schoolId = "school_id"
        case requestedBy = "requested_by"
        case legalFirstName = "legal_first_name"
        case legalLastName = "legal_last_name"
        case matchedChildId = "matched_child_id"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case reviewNote = "review_note"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        schoolId = try container.decode(UUID.self, forKey: .schoolId)
        requestedBy = try container.decode(UUID.self, forKey: .requestedBy)
        legalFirstName = try container.decode(String.self, forKey: .legalFirstName)
        legalLastName = try container.decode(String.self, forKey: .legalLastName)
        guard let decodedBirthdate = try DateOnlyCoding.decodeDateOnlyIfPresent(from: container, forKey: .birthdate) else {
            throw DecodingError.dataCorruptedError(forKey: .birthdate, in: container, debugDescription: "A child connection requires a birthdate")
        }
        birthdate = decodedBirthdate
        relationship = try container.decode(String.self, forKey: .relationship)
        status = try container.decode(ChildConnectionStatus.self, forKey: .status)
        matchedChildId = try container.decodeIfPresent(UUID.self, forKey: .matchedChildId)
        reviewedBy = try container.decodeIfPresent(UUID.self, forKey: .reviewedBy)
        reviewedAt = try container.decodeIfPresent(Date.self, forKey: .reviewedAt)
        reviewNote = try container.decodeIfPresent(String.self, forKey: .reviewNote)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

enum ChildRequirementBinding: String, Codable, CaseIterable, Identifiable, Hashable {
    case none
    case childDocument = "child_document"
    case immunizationRecord = "immunization_record"
    case medicalClearance = "medical_clearance"
    case medicationAuthorization = "medication_authorization"
    case emergencyInformation = "emergency_information"
    case consent

    var id: String { rawValue }
}

struct ChildProfileCompletion: Hashable {
    let identityApproved: Bool
    let blockingRequirementsRemaining: Int
    let nonBlockingRequirementsRemaining: Int
    var grantsAccess: Bool { identityApproved && blockingRequirementsRemaining == 0 }
}

struct ChildProfileChangeRequest: Codable, Identifiable, Hashable {
    let id: UUID
    let schoolId: UUID
    let childId: UUID
    let requestedBy: UUID
    let proposedChanges: [String: FireflyJSONValue]
    let reason: String?
    let status: String
    let reviewedBy: UUID?
    let reviewedAt: Date?
    let reviewNote: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, reason, status
        case schoolId = "school_id"
        case childId = "child_id"
        case requestedBy = "requested_by"
        case proposedChanges = "proposed_changes"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case reviewNote = "review_note"
        case createdAt = "created_at"
    }
}

enum AttendanceState: String, Codable, CaseIterable, Identifiable, Hashable {
    case expected, present
    case checkedOut = "checked_out"
    case absent
    case needsAttention = "needs_attention"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .expected: "Expected"
        case .present: "Present"
        case .checkedOut: "Checked Out"
        case .absent: "Absent"
        case .needsAttention: "Needs Attention"
        }
    }
}

struct AttendanceSession: Codable, Identifiable, Hashable {
    let id: UUID
    let schoolId: UUID
    let childId: UUID
    let attendanceDate: Date
    let state: AttendanceState
    let checkedInAt: Date?
    let checkedOutAt: Date?
    let checkedInBy: UUID?
    let checkedOutBy: UUID?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, state, notes
        case schoolId = "school_id"
        case childId = "child_id"
        case attendanceDate = "attendance_date"
        case checkedInAt = "checked_in_at"
        case checkedOutAt = "checked_out_at"
        case checkedInBy = "checked_in_by"
        case checkedOutBy = "checked_out_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        schoolId = try container.decode(UUID.self, forKey: .schoolId)
        childId = try container.decode(UUID.self, forKey: .childId)
        attendanceDate = try DateOnlyCoding.decodeDateOnlyIfPresent(from: container, forKey: .attendanceDate) ?? Date()
        state = try container.decode(AttendanceState.self, forKey: .state)
        checkedInAt = try container.decodeIfPresent(Date.self, forKey: .checkedInAt)
        checkedOutAt = try container.decodeIfPresent(Date.self, forKey: .checkedOutAt)
        checkedInBy = try container.decodeIfPresent(UUID.self, forKey: .checkedInBy)
        checkedOutBy = try container.decodeIfPresent(UUID.self, forKey: .checkedOutBy)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct AttendanceBatchResult: Codable, Identifiable, Hashable {
    let childId: UUID
    let success: Bool
    let sessionId: UUID?
    let errorCode: String?
    let errorMessage: String?

    var id: UUID { childId }

    enum CodingKeys: String, CodingKey {
        case childId = "child_id"
        case success
        case sessionId = "session_id"
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

enum ChildCareEventType: String, Codable, CaseIterable, Identifiable, Hashable {
    case meal, bottle, nap, potty, diaper, medication
    case healthCheck = "health_check"
    case activity, observation, kudos, incident, note, photo

    var id: String { rawValue }
    var title: String {
        switch self {
        case .activity: "Learning Activity"
        case .healthCheck: "Health Check"
        default: rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    static var composerCases: [ChildCareEventType] { allCases.filter { $0 != .photo } }
    static var mediaLabelCases: [ChildCareEventType] { [.activity, .observation, .kudos, .note] }

    var isDevelopmental: Bool {
        self == .activity || self == .observation || self == .kudos
    }

    var requiresNarrative: Bool {
        switch self {
        case .activity, .observation, .kudos, .incident, .note: true
        default: false
        }
    }
    var symbol: String {
        switch self {
        case .meal: "fork.knife"
        case .bottle: "waterbottle.fill"
        case .nap: "bed.double.fill"
        case .potty: "toilet.fill"
        case .diaper: "figure.child"
        case .medication: "pills.fill"
        case .healthCheck: "cross.case.fill"
        case .activity: "figure.run"
        case .observation: "eye.fill"
        case .kudos: "star.fill"
        case .incident: "exclamationmark.triangle.fill"
        case .note: "note.text"
        case .photo: "photo.fill"
        }
    }
}

enum ChildDevelopmentalDomain: String, Codable, CaseIterable, Identifiable, Hashable {
    case communicationLanguage = "communication_language"
    case socialEmotional = "social_emotional"
    case cognitive
    case physicalMotor = "physical_motor"
    case creative
    case independenceSelfCare = "independence_self_care"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .communicationLanguage: "Communication & Language"
        case .socialEmotional: "Social & Emotional"
        case .cognitive: "Thinking & Learning"
        case .physicalMotor: "Physical & Motor"
        case .creative: "Creative Expression"
        case .independenceSelfCare: "Independence & Self-Care"
        }
    }
    var symbol: String {
        switch self {
        case .communicationLanguage: "bubble.left.and.bubble.right.fill"
        case .socialEmotional: "heart.fill"
        case .cognitive: "brain.head.profile.fill"
        case .physicalMotor: "figure.run"
        case .creative: "paintpalette.fill"
        case .independenceSelfCare: "hands.sparkles.fill"
        }
    }
}

struct ChildCareEvent: Codable, Identifiable, Hashable {
    let id: UUID
    let schoolId: UUID
    let childId: UUID
    let eventType: ChildCareEventType
    let occurredAt: Date
    let details: [String: FireflyJSONValue]
    let visibility: String
    let recordedBy: UUID
    let sourceMedicationTaskId: UUID?
    let sourceMessageId: UUID?
    let developmentalDomains: [String]
    let reportHighlight: Bool
    let createdAt: Date

    var photoPath: String? { details["photo_path"]?.stringValue }

    enum CodingKeys: String, CodingKey {
        case id, details, visibility
        case schoolId = "school_id"
        case childId = "child_id"
        case eventType = "event_type"
        case occurredAt = "occurred_at"
        case recordedBy = "recorded_by"
        case sourceMedicationTaskId = "source_medication_task_id"
        case sourceMessageId = "source_message_id"
        case developmentalDomains = "developmental_domains"
        case reportHighlight = "report_highlight"
        case createdAt = "created_at"
    }
}

struct FamilyRequest: Codable, Identifiable, Hashable {
    let id: UUID
    let schoolId: UUID
    let childId: UUID
    let requestedBy: UUID
    let requestType: String
    let details: [String: FireflyJSONValue]
    let status: String
    let handledBy: UUID?
    let handledAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, details, status
        case schoolId = "school_id"
        case childId = "child_id"
        case requestedBy = "requested_by"
        case requestType = "request_type"
        case handledBy = "handled_by"
        case handledAt = "handled_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum NotificationDeliveryState: String, Codable, CaseIterable, Hashable {
    case queued, delivered, opened, acknowledged, failed, dismissed, expired
}

enum NotificationPreviewMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case senderOnly = "sender_only"
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .senderOnly: "Sender and room only"
        case .full: "Show message text"
        }
    }
}

enum NotificationPermissionState: String, Equatable, Hashable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    var canOpenSystemSettings: Bool { self == .denied }
}

struct UserNotificationSettings: Codable, Hashable {
    let userId: UUID
    var messagePreviewMode: NotificationPreviewMode
    var quietHoursStart: String?
    var quietHoursEnd: String?
    var timeZone: String
    var permissionPromptDeferred: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case messagePreviewMode = "message_preview_mode"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case timeZone = "time_zone"
        case permissionPromptDeferred = "permission_prompt_deferred"
    }
}

struct NotificationPreference: Codable, Hashable {
    let userId: UUID
    let category: String
    var enabled: Bool
    var quietHoursStart: String?
    var quietHoursEnd: String?
    var timeZone: String

    enum CodingKeys: String, CodingKey {
        case category, enabled
        case userId = "user_id"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case timeZone = "time_zone"
    }
}

struct NotificationRoute: Codable, Hashable {
    let type: String
    let id: UUID?
    let childId: UUID?
    let schoolId: UUID?
    let messageId: UUID?

    enum CodingKeys: String, CodingKey {
        case type, id
        case childId = "child_id"
        case schoolId = "school_id"
        case messageId = "message_id"
    }
}

struct SchoolDirectoryEntry: Codable, Identifiable, Hashable {
    let userId: UUID
    let displayName: String
    let avatarUrl: String?
    let schoolRole: SchoolRole
    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case schoolRole = "school_role"
    }
}

struct DirectorManagedChatRoom: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let description: String?
    let profileImageUrl: String?
    let schoolId: UUID
    let createdBy: UUID?
    let createdAt: Date
    let updatedAt: Date?
    let archivedAt: Date?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case profileImageUrl = "profile_image_url"
        case schoolId = "school_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case archivedAt = "archived_at"
        case deletedAt = "deleted_at"
    }
}
