//
//  SchoolModels.swift
//  FireflyFM
//

import Foundation

enum DateOnlyCoding {
    static func string(from date: Date) -> String {
        formatter().string(from: date)
    }

    static func date(from value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let date = formatter().date(from: String(trimmed.prefix(10))) {
            return date
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: trimmed)
    }

    static func decodeDateOnlyIfPresent<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> Date? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return date(from: value)
        }
        return try container.decodeIfPresent(Date.self, forKey: key)
    }

    static func encodeDateOnlyIfPresent<K: CodingKey>(
        _ date: Date?,
        to container: inout KeyedEncodingContainer<K>,
        forKey key: K
    ) throws {
        if let date {
            try container.encode(string(from: date), forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

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
        has(.manageMemberOnboarding) || has(.manageSchools)
    }

    /// School directors oversee all rooms in their own school. HQ directors keep
    /// global operational access, but only see private chats they explicitly join.
    var canOverseeSchoolChats: Bool {
        has(.overseeSchoolChats)
    }

    var canManageEvents: Bool {
        has(.manageEvents)
    }
}

struct School: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var description: String?
    var tourUrl: String?
    var profileImageUrl: String?
    var profileImagePath: String? = nil
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case tourUrl = "tour_url"
        case profileImageUrl = "profile_image_url"
        case profileImagePath = "profile_image_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SchoolCreationResult: Codable, Hashable {
    var schoolId: UUID
    var schoolName: String
    var inviteToken: String
    var inviteUrl: String?

    var shareInviteURL: URL? {
        RoleInviteLinkBuilder.shareURL(token: inviteToken)
    }

    enum CodingKeys: String, CodingKey {
        case schoolId = "school_id"
        case schoolName = "school_name"
        case inviteToken = "invite_token"
        case inviteUrl = "invite_url"
    }
}

enum RoleInviteLinkBuilder {
    static func shareURL(token: String) -> URL? {
        if let configuredBase = Bundle.main.object(forInfoDictionaryKey: "RoleInviteUniversalBaseURL") as? String,
           configuredBase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           var components = URLComponents(string: configuredBase) {
            var queryItems = components.queryItems ?? []
            queryItems.removeAll { $0.name == "token" }
            queryItems.append(URLQueryItem(name: "token", value: token))
            components.queryItems = queryItems
            if let url = components.url, url.scheme?.lowercased() == "https" {
                return url
            }
        }
        return manualURL(token: token)
    }

    static func manualURL(token: String) -> URL? {
        URL(string: "fireflyfm://role-invite?token=\(token)")
    }
}

struct SchoolMembership: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var userId: UUID
    var role: SchoolRole
    var active: Bool
    var accessState: String?
    var joinedAt: Date?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case userId = "user_id"
        case role, active
        case accessState = "access_state"
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

struct RoleInvite: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var email: String
    var displayName: String?
    var role: SchoolRole
    var token: String?
    var status: String
    var invitedBy: UUID?
    var acceptedBy: UUID?
    var acceptedAt: Date?
    var expiresAt: Date?
    var createdAt: Date?

    var inviteURL: URL? {
        guard let token, token.isEmpty == false else { return nil }
        return RoleInviteLinkBuilder.shareURL(token: token)
    }

    var manualInviteURL: URL? {
        guard let token, token.isEmpty == false else { return nil }
        return RoleInviteLinkBuilder.manualURL(token: token)
    }

    enum CodingKeys: String, CodingKey {
        case id, email, role, token, status
        case schoolId = "school_id"
        case displayName = "display_name"
        case invitedBy = "invited_by"
        case acceptedBy = "accepted_by"
        case acceptedAt = "accepted_at"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

struct RoleInvitePreview: Codable, Identifiable, Hashable {
    var id: UUID { inviteId }
    var inviteId: UUID
    var schoolId: UUID
    var schoolName: String
    var role: SchoolRole
    var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case inviteId = "invite_id"
        case schoolId = "school_id"
        case schoolName = "school_name"
        case role
        case expiresAt = "expires_at"
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
    var media: [NewsletterMedia]

    init(
        id: UUID = UUID(),
        schoolId: UUID,
        title: String,
        body: String,
        createdBy: UUID? = nil,
        createdAt: Date? = Date(),
        updatedAt: Date? = nil,
        media: [NewsletterMedia] = []
    ) {
        self.id = id
        self.schoolId = schoolId
        self.title = title
        self.body = body
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.media = media
    }

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case title, body
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case media
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        schoolId = try container.decode(UUID.self, forKey: .schoolId)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        createdBy = try container.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        media = try container.decodeIfPresent([NewsletterMedia].self, forKey: .media) ?? []
    }
}

enum NewsletterMediaLayout: String, Codable, CaseIterable, Identifiable, Hashable {
    case wide
    case inset
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wide: "Full width"
        case .inset: "Inset"
        case .compact: "Compact"
        }
    }
}

struct NewsletterMedia: Codable, Identifiable, Hashable {
    var id: UUID
    var fileName: String?
    var filePath: String
    var contentType: String?
    var altText: String?
    var caption: String?
    var sortOrder: Int
    var layout: NewsletterMediaLayout? = nil
    var linkURL: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case fileName = "file_name"
        case filePath = "file_path"
        case contentType = "content_type"
        case altText = "alt_text"
        case caption
        case sortOrder = "sort_order"
        case layout
        case linkURL = "link_url"
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
    var archivedAt: Date?
    var archivedBy: UUID?
    var createdAt: Date?
    var updatedAt: Date?

    init(id: UUID = UUID(), schoolId: UUID, title: String, description: String? = nil, startAt: Date, endAt: Date? = nil, allDay: Bool = false, repeatRule: String? = nil, createdBy: UUID? = nil, archivedAt: Date? = nil, archivedBy: UUID? = nil, createdAt: Date? = Date(), updatedAt: Date? = nil) {
        self.id = id
        self.schoolId = schoolId
        self.title = title
        self.description = description
        self.startAt = startAt
        self.endAt = endAt
        self.allDay = allDay
        self.repeatRule = repeatRule
        self.createdBy = createdBy
        self.archivedAt = archivedAt
        self.archivedBy = archivedBy
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
        case archivedAt = "archived_at"
        case archivedBy = "archived_by"
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
    var archivedAt: Date?
    var archivedBy: UUID?
    var archiveReason: String?
    var createdAt: Date?
    var updatedAt: Date?

    init(
        id: UUID = UUID(),
        schoolId: UUID,
        firstName: String,
        lastName: String,
        birthdate: Date? = nil,
        active: Bool = true,
        archivedAt: Date? = nil,
        archivedBy: UUID? = nil,
        archiveReason: String? = nil,
        createdAt: Date? = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.schoolId = schoolId
        self.firstName = firstName
        self.lastName = lastName
        self.birthdate = birthdate
        self.active = active
        self.archivedAt = archivedAt
        self.archivedBy = archivedBy
        self.archiveReason = archiveReason
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
        case archivedAt = "archived_at"
        case archivedBy = "archived_by"
        case archiveReason = "archive_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        schoolId = try container.decode(UUID.self, forKey: .schoolId)
        firstName = try container.decode(String.self, forKey: .firstName)
        lastName = try container.decode(String.self, forKey: .lastName)
        birthdate = try DateOnlyCoding.decodeDateOnlyIfPresent(from: container, forKey: .birthdate)
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        archivedBy = try container.decodeIfPresent(UUID.self, forKey: .archivedBy)
        archiveReason = try container.decodeIfPresent(String.self, forKey: .archiveReason)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(schoolId, forKey: .schoolId)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(lastName, forKey: .lastName)
        try DateOnlyCoding.encodeDateOnlyIfPresent(birthdate, to: &container, forKey: .birthdate)
        try container.encode(active, forKey: .active)
        try container.encodeIfPresent(archivedAt, forKey: .archivedAt)
        try container.encodeIfPresent(archivedBy, forKey: .archivedBy)
        try container.encodeIfPresent(archiveReason, forKey: .archiveReason)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
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
    var immunizationStatus: String?
    var physicalStatus: String?
    var medicalNotes: String?
    var medicationInstructions: String?
    var medicineRequirements: String?
    var dietaryNotes: String?
    var emergencyNotes: String?
    var updatedBy: UUID?
    var updatedAt: Date?

    var id: UUID { childId }

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
    var attendanceDate: Date?
    var checkedInAt: Date?
    var checkedOutAt: Date?
    var recordedBy: UUID?
    var checkedInBy: UUID?
    var checkedOutBy: UUID?
    var checkInConfirmedAt: Date?
    var checkOutConfirmedAt: Date?
    var notes: String?
    var createdAt: Date?
    var updatedAt: Date?

    init(
        id: UUID = UUID(),
        schoolId: UUID,
        childId: UUID,
        attendanceDate: Date? = Date(),
        checkedInAt: Date? = nil,
        checkedOutAt: Date? = nil,
        recordedBy: UUID? = nil,
        checkedInBy: UUID? = nil,
        checkedOutBy: UUID? = nil,
        checkInConfirmedAt: Date? = nil,
        checkOutConfirmedAt: Date? = nil,
        notes: String? = nil,
        createdAt: Date? = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.schoolId = schoolId
        self.childId = childId
        self.attendanceDate = attendanceDate
        self.checkedInAt = checkedInAt
        self.checkedOutAt = checkedOutAt
        self.recordedBy = recordedBy
        self.checkedInBy = checkedInBy
        self.checkedOutBy = checkedOutBy
        self.checkInConfirmedAt = checkInConfirmedAt
        self.checkOutConfirmedAt = checkOutConfirmedAt
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case childId = "child_id"
        case attendanceDate = "attendance_date"
        case checkedInAt = "checked_in_at"
        case checkedOutAt = "checked_out_at"
        case recordedBy = "recorded_by"
        case checkedInBy = "checked_in_by"
        case checkedOutBy = "checked_out_by"
        case checkInConfirmedAt = "check_in_confirmed_at"
        case checkOutConfirmedAt = "check_out_confirmed_at"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        schoolId = try container.decode(UUID.self, forKey: .schoolId)
        childId = try container.decode(UUID.self, forKey: .childId)
        attendanceDate = try DateOnlyCoding.decodeDateOnlyIfPresent(from: container, forKey: .attendanceDate)
        checkedInAt = try container.decodeIfPresent(Date.self, forKey: .checkedInAt)
        checkedOutAt = try container.decodeIfPresent(Date.self, forKey: .checkedOutAt)
        recordedBy = try container.decodeIfPresent(UUID.self, forKey: .recordedBy)
        checkedInBy = try container.decodeIfPresent(UUID.self, forKey: .checkedInBy)
        checkedOutBy = try container.decodeIfPresent(UUID.self, forKey: .checkedOutBy)
        checkInConfirmedAt = try container.decodeIfPresent(Date.self, forKey: .checkInConfirmedAt)
        checkOutConfirmedAt = try container.decodeIfPresent(Date.self, forKey: .checkOutConfirmedAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(schoolId, forKey: .schoolId)
        try container.encode(childId, forKey: .childId)
        try DateOnlyCoding.encodeDateOnlyIfPresent(attendanceDate, to: &container, forKey: .attendanceDate)
        try container.encodeIfPresent(checkedInAt, forKey: .checkedInAt)
        try container.encodeIfPresent(checkedOutAt, forKey: .checkedOutAt)
        try container.encodeIfPresent(recordedBy, forKey: .recordedBy)
        try container.encodeIfPresent(checkedInBy, forKey: .checkedInBy)
        try container.encodeIfPresent(checkedOutBy, forKey: .checkedOutBy)
        try container.encodeIfPresent(checkInConfirmedAt, forKey: .checkInConfirmedAt)
        try container.encodeIfPresent(checkOutConfirmedAt, forKey: .checkOutConfirmedAt)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
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

struct ChildRosterItem: Identifiable, Hashable {
    var id: UUID { child.id }
    var child: Child
    var medicalProfile: ChildMedicalProfile?
    var todayAttendance: ChildAttendance?
    var pendingMedicationCount: Int
    var submittedDocumentCount: Int
    var verifiedDocumentCount: Int

    var attendanceStatus: String {
        guard let todayAttendance else { return "Not arrived" }
        if todayAttendance.checkedInAt != nil && todayAttendance.checkedOutAt == nil {
            return "Checked in"
        }
        if todayAttendance.checkedOutAt != nil {
            return "Checked out"
        }
        return "Not arrived"
    }

    var isCheckedIn: Bool {
        todayAttendance?.checkedInAt != nil && todayAttendance?.checkedOutAt == nil
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

enum OnboardingTemplateStatus: String, Codable, CaseIterable, Hashable {
    case draft
    case published
    case archived

    var title: String { rawValue.capitalized }
}

enum OnboardingSubjectScope: String, Codable, CaseIterable, Identifiable, Hashable {
    case member
    case child

    var id: String { rawValue }
    var title: String {
        switch self {
        case .member: "Parent"
        case .child: "Each Child"
        }
    }
}

enum OnboardingRequirementType: String, Codable, CaseIterable, Hashable {
    case document
    case acknowledgement
    case payment
}

struct OnboardingTemplate: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var targetRole: SchoolRole
    var name: String
    var version: Int
    var status: OnboardingTemplateStatus
    var createdBy: UUID?
    var publishedAt: Date?
    var archivedAt: Date?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, version, status
        case schoolId = "school_id"
        case targetRole = "target_role"
        case createdBy = "created_by"
        case publishedAt = "published_at"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct OnboardingTemplateRequirement: Codable, Identifiable, Hashable {
    var id: UUID
    var templateId: UUID
    var requirementKey: UUID
    var position: Int
    var requirementType: OnboardingRequirementType
    var title: String
    var description: String?
    var subjectScope: OnboardingSubjectScope
    var blocksAccess: Bool
    var childRecordBinding: ChildRequirementBinding
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, position, title, description
        case templateId = "template_id"
        case requirementKey = "requirement_key"
        case requirementType = "requirement_type"
        case subjectScope = "subject_scope"
        case blocksAccess = "blocks_access"
        case childRecordBinding = "child_record_binding"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct OnboardingTemplateAttachment: Codable, Identifiable, Hashable {
    var id: UUID
    var requirementId: UUID
    var position: Int
    var privateFilePath: String
    var fileName: String
    var contentType: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, position
        case requirementId = "requirement_id"
        case privateFilePath = "private_file_path"
        case fileName = "file_name"
        case contentType = "content_type"
        case createdAt = "created_at"
    }
}

struct OnboardingTemplateBundle: Hashable {
    var template: OnboardingTemplate?
    var requirements: [OnboardingTemplateRequirement]
    var attachments: [OnboardingTemplateAttachment]
    var activePublishedTemplate: OnboardingTemplate? = nil

    var hasPublishedVersion: Bool {
        activePublishedTemplate != nil || template?.status == .published
    }

    func attachments(for requirementId: UUID) -> [OnboardingTemplateAttachment] {
        attachments
            .filter { $0.requirementId == requirementId }
            .sorted { $0.position < $1.position }
    }
}

struct OnboardingDashboardItem: Codable, Identifiable, Hashable {
    var requirementInstanceId: UUID
    var assignmentId: UUID?
    var childId: UUID?
    var title: String
    var description: String?
    var subjectScope: OnboardingSubjectScope
    var position: Int
    var status: String
    var materialCount: Int
    var childFirstName: String?
    var childLastName: String?
    var reviewerLabel: String

    var id: UUID { requirementInstanceId }
    var childName: String? {
        let value = [childFirstName, childLastName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    enum CodingKeys: String, CodingKey {
        case title, description, position, status
        case requirementInstanceId = "requirement_instance_id"
        case assignmentId = "assignment_id"
        case childId = "child_id"
        case subjectScope = "subject_scope"
        case materialCount = "material_count"
        case childFirstName = "child_first_name"
        case childLastName = "child_last_name"
        case reviewerLabel = "reviewer_label"
    }
}

struct OnboardingRoleProgress: Codable, Hashable {
    var memberCount: Int
    var onboardingCount: Int
    var fullCount: Int
    var needsReviewCount: Int

    static let empty = OnboardingRoleProgress(
        memberCount: 0,
        onboardingCount: 0,
        fullCount: 0,
        needsReviewCount: 0
    )

    enum CodingKeys: String, CodingKey {
        case memberCount = "member_count"
        case onboardingCount = "onboarding_count"
        case fullCount = "full_count"
        case needsReviewCount = "needs_review_count"
    }
}

struct GoogleFormConnection: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var formRole: String
    var formKey: String?
    var formId: String
    var formURL: String
    var formTitle: String?
    var googleAccountEmail: String?
    var isRequired: Bool?
    var displayOrder: Int?
    var status: String
    var lastSyncedAt: Date?
    var nextSyncAfter: Date?
    var lastError: String?
    var createdBy: UUID
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case schoolId = "school_id"
        case formRole = "form_role"
        case formKey = "form_key"
        case formId = "form_id"
        case formURL = "form_url"
        case formTitle = "form_title"
        case googleAccountEmail = "google_account_email"
        case isRequired = "is_required"
        case displayOrder = "display_order"
        case lastSyncedAt = "last_synced_at"
        case nextSyncAfter = "next_sync_after"
        case lastError = "last_error"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct GoogleFormImport: Codable, Identifiable, Hashable {
    var id: UUID
    var connectionId: UUID
    var schoolId: UUID
    var googleResponseId: String
    var responseCreatedAt: Date?
    var responseSubmittedAt: Date?
    var respondentEmail: String?
    var childId: UUID?
    var submittedPayload: [String: FireflyJSONValue]
    var status: String
    var reviewNote: String?
    var reviewedBy: UUID?
    var reviewedAt: Date?
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case connectionId = "connection_id"
        case schoolId = "school_id"
        case googleResponseId = "google_response_id"
        case responseCreatedAt = "response_created_at"
        case responseSubmittedAt = "response_submitted_at"
        case respondentEmail = "respondent_email"
        case childId = "child_id"
        case submittedPayload = "submitted_payload"
        case reviewNote = "review_note"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct GoogleFormImportAttachment: Codable, Identifiable, Hashable {
    var id: UUID
    var importId: UUID
    var questionId: String
    var googleFileId: String
    var fileName: String
    var contentType: String?
    var privateFilePath: String?
    var documentType: String
    var childDocumentId: UUID?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case importId = "import_id"
        case questionId = "question_id"
        case googleFileId = "google_file_id"
        case fileName = "file_name"
        case contentType = "content_type"
        case privateFilePath = "private_file_path"
        case documentType = "document_type"
        case childDocumentId = "child_document_id"
        case createdAt = "created_at"
    }
}

struct CommunityPost: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var body: String
    var imagePath: String?
    var attachmentPath: String?
    var attachmentName: String?
    var attachmentType: String?
    var linkedEventId: UUID?
    var pollQuestion: String?
    var pollOptions: [String]?
    var scheduledAt: Date?
    var createdBy: UUID?
    var createdAt: Date?
    var updatedAt: Date?

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
    var materialUrl: String?
    var materialType: String?
    var uploadedBy: UUID?
    var createdAt: Date?
    var updatedAt: Date?

    init(id: UUID = UUID(), schoolId: UUID, title: String, description: String? = nil, fileName: String? = nil, filePath: String? = nil, materialUrl: String? = nil, materialType: String? = nil, uploadedBy: UUID? = nil, createdAt: Date? = Date(), updatedAt: Date? = nil) {
        self.id = id
        self.schoolId = schoolId
        self.title = title
        self.description = description
        self.fileName = fileName
        self.filePath = filePath
        self.materialUrl = materialUrl
        self.materialType = materialType
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
        case materialUrl = "material_url"
        case materialType = "material_type"
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
    var materialUrl: String?
    var materialType: String?
    var assignedBy: UUID?
    var dueAt: Date?
    var createdAt: Date?

    init(id: UUID = UUID(), schoolId: UUID, title: String, description: String? = nil, fileName: String? = nil, filePath: String? = nil, materialUrl: String? = nil, materialType: String? = nil, assignedBy: UUID? = nil, dueAt: Date? = nil, createdAt: Date? = Date()) {
        self.id = id
        self.schoolId = schoolId
        self.title = title
        self.description = description
        self.fileName = fileName
        self.filePath = filePath
        self.materialUrl = materialUrl
        self.materialType = materialType
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
        case materialUrl = "material_url"
        case materialType = "material_type"
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

struct CurriculumReadReceipt: Codable, Identifiable, Hashable {
    var resourceId: UUID
    var userId: UUID
    var checkedAt: Date?

    var id: String { "\(resourceId.uuidString)-\(userId.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case resourceId = "resource_id"
        case userId = "user_id"
        case checkedAt = "checked_at"
    }
}

struct TrainingReadReceipt: Codable, Identifiable, Hashable {
    var assignmentId: UUID
    var userId: UUID
    var checkedAt: Date?

    var id: String { "\(assignmentId.uuidString)-\(userId.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case assignmentId = "assignment_id"
        case userId = "user_id"
        case checkedAt = "checked_at"
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

enum AssignmentCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case paperwork
    case training
    case curriculum
    case onboarding
    case childRecord = "child_record"
    case compliance
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paperwork: "Paperwork"
        case .training: "Training"
        case .curriculum: "Curriculum"
        case .onboarding: "Onboarding"
        case .childRecord: "Child Record"
        case .compliance: "Compliance"
        case .general: "General"
        }
    }
}

enum AssignmentCompletionStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case notStarted = "not_started"
    case read
    case submitted
    case reviewed
    case accepted
    case changesRequested = "changes_requested"
    case resubmitted
    case excused
    case flagged
    case overdue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notStarted: "Not Started"
        case .read: "Read"
        case .submitted: "Submitted"
        case .reviewed: "Reviewed"
        case .accepted: "Accepted"
        case .changesRequested: "Changes Requested"
        case .resubmitted: "Resubmitted"
        case .excused: "Excused"
        case .flagged: "Flagged"
        case .overdue: "Overdue"
        }
    }
}

enum AssignmentLifecycleStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case draft
    case scheduled
    case published
    case closed
    case archived

    var id: String { rawValue }
}

enum AssignmentSubmissionStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case submitted
    case resubmitted
    case changesRequested = "changes_requested"
    case accepted

    var id: String { rawValue }
}

struct Assignment: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var childId: UUID?
    var title: String
    var description: String?
    var category: AssignmentCategory
    var audienceRole: SchoolRole?
    var assignedBy: UUID?
    var dueAt: Date?
    var publishAt: Date?
    var closeAt: Date?
    var status: String?
    var visibility: String?
    var requiresReview: Bool?
    var allowResubmission: Bool?
    var legacySourceType: String?
    var legacySourceId: UUID?
    var createdAt: Date?
    var updatedAt: Date?
    var currentRevisionId: UUID?

    var lifecycleStatus: AssignmentLifecycleStatus? {
        status.flatMap(AssignmentLifecycleStatus.init(rawValue:))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case childId = "child_id"
        case title, description, category
        case audienceRole = "audience_role"
        case assignedBy = "assigned_by"
        case dueAt = "due_at"
        case publishAt = "publish_at"
        case closeAt = "close_at"
        case status, visibility
        case requiresReview = "requires_review"
        case allowResubmission = "allow_resubmission"
        case legacySourceType = "legacy_source_type"
        case legacySourceId = "legacy_source_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case currentRevisionId = "current_revision_id"
    }
}

struct AssignmentRecipient: Codable, Identifiable, Hashable {
    var assignmentId: UUID
    var userId: UUID
    var roleAtAssignment: SchoolRole?
    var childId: UUID?
    var completionStatus: AssignmentCompletionStatus
    var viewedAt: Date?
    var completedAt: Date?
    var createdAt: Date?

    var id: String { "\(assignmentId.uuidString)-\(userId.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case assignmentId = "assignment_id"
        case userId = "user_id"
        case roleAtAssignment = "role_at_assignment"
        case childId = "child_id"
        case completionStatus = "completion_status"
        case viewedAt = "viewed_at"
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }
}

struct AssignmentMaterial: Codable, Identifiable, Hashable {
    var id: UUID
    var assignmentId: UUID
    var materialType: String
    var title: String?
    var url: String?
    var privateFilePath: String?
    var fileName: String?
    var contentType: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case assignmentId = "assignment_id"
        case materialType = "material_type"
        case title, url
        case privateFilePath = "private_file_path"
        case fileName = "file_name"
        case contentType = "content_type"
        case createdAt = "created_at"
    }
}

struct AssignmentSubmission: Codable, Identifiable, Hashable {
    var id: UUID
    var assignmentId: UUID
    var schoolId: UUID
    var submittedBy: UUID
    var attemptNumber: Int?
    var supersedesSubmissionId: UUID?
    var status: String
    var score: Int?
    var reviewerMessage: String?
    var reviewedBy: UUID?
    var reviewedAt: Date?
    var submittedAt: Date?
    var structuredPayload: [String: FireflyJSONValue]
    var assignmentRevisionId: UUID?

    var workflowStatus: AssignmentSubmissionStatus? {
        AssignmentSubmissionStatus(rawValue: status)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case assignmentId = "assignment_id"
        case schoolId = "school_id"
        case submittedBy = "submitted_by"
        case attemptNumber = "attempt_number"
        case supersedesSubmissionId = "supersedes_submission_id"
        case status
        case score
        case reviewerMessage = "reviewer_message"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case submittedAt = "submitted_at"
        case structuredPayload = "structured_payload"
        case assignmentRevisionId = "assignment_revision_id"
    }
}

struct AssignmentSubmissionAttachment: Codable, Identifiable, Hashable {
    var id: UUID
    var submissionId: UUID
    var schoolId: UUID
    var privateFilePath: String
    var fileName: String?
    var contentType: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case submissionId = "submission_id"
        case schoolId = "school_id"
        case privateFilePath = "private_file_path"
        case fileName = "file_name"
        case contentType = "content_type"
        case createdAt = "created_at"
    }
}

struct AssignmentReadReceipt: Codable, Identifiable, Hashable {
    var assignmentId: UUID
    var userId: UUID
    var checkedAt: Date?

    var id: String { "\(assignmentId.uuidString)-\(userId.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case assignmentId = "assignment_id"
        case userId = "user_id"
        case checkedAt = "checked_at"
    }
}

struct AssignmentFeedbackMessage: Codable, Identifiable, Hashable {
    var id: UUID
    var assignmentId: UUID
    var submissionId: UUID?
    var schoolId: UUID
    var senderId: UUID
    var recipientId: UUID?
    var body: String
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case assignmentId = "assignment_id"
        case submissionId = "submission_id"
        case schoolId = "school_id"
        case senderId = "sender_id"
        case recipientId = "recipient_id"
        case body
        case createdAt = "created_at"
    }
}

struct AssignmentEvent: Codable, Identifiable, Hashable {
    var id: UUID
    var assignmentId: UUID
    var schoolId: UUID
    var actorId: UUID?
    var eventType: String
    var metadata: AssignmentEventMetadata?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case assignmentId = "assignment_id"
        case schoolId = "school_id"
        case actorId = "actor_id"
        case eventType = "event_type"
        case metadata
        case createdAt = "created_at"
    }
}

struct AssignmentEventMetadata: Codable, Hashable {
    var submissionId: UUID?
    var recipientId: UUID?
    var attemptNumber: Int?
    var revisionId: UUID?
    var materialCount: Int?
    var oldScore: Int?
    var newScore: Int?
    var score: Int?

    enum CodingKeys: String, CodingKey {
        case submissionId = "submission_id"
        case recipientId = "recipient_id"
        case attemptNumber = "attempt_number"
        case revisionId = "revision_id"
        case materialCount = "material_count"
        case oldScore = "old_score"
        case newScore = "new_score"
        case score
    }
}

struct AssignmentInboxItem: Codable, Identifiable, Hashable {
    var assignmentId: UUID
    var schoolId: UUID
    var schoolName: String?
    var childId: UUID?
    var title: String
    var description: String?
    var category: AssignmentCategory
    var dueAt: Date?
    var assignedBy: UUID?
    var createdAt: Date?
    var lifecycleStatus: AssignmentLifecycleStatus?
    var completionStatus: AssignmentCompletionStatus
    var viewedAt: Date?
    var acknowledgedAt: Date?
    var hasUnreadFeedback: Bool?
    var submittedAt: Date?
    var reviewStatus: String?
    var reviewedAt: Date?
    var reviewerMessage: String?
    var childFirstName: String?
    var childLastName: String?
    var materialCount: Int
    var submissionCount: Int
    var recipientCount: Int
    var needsReviewCount: Int?
    var changesRequestedCount: Int?
    var notStartedCount: Int?
    var overdueCount: Int?
    var completeCount: Int?

    var id: UUID { assignmentId }

    var childDisplayName: String? {
        let name = [childFirstName, childLastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? nil : name
    }

    enum CodingKeys: String, CodingKey {
        case assignmentId = "assignment_id"
        case schoolId = "school_id"
        case schoolName = "school_name"
        case childId = "child_id"
        case title, description, category
        case dueAt = "due_at"
        case assignedBy = "assigned_by"
        case createdAt = "created_at"
        case lifecycleStatus = "lifecycle_status"
        case completionStatus = "completion_status"
        case viewedAt = "viewed_at"
        case acknowledgedAt = "acknowledged_at"
        case hasUnreadFeedback = "has_unread_feedback"
        case submittedAt = "submitted_at"
        case reviewStatus = "review_status"
        case reviewedAt = "reviewed_at"
        case reviewerMessage = "reviewer_message"
        case childFirstName = "child_first_name"
        case childLastName = "child_last_name"
        case materialCount = "material_count"
        case submissionCount = "submission_count"
        case recipientCount = "recipient_count"
        case needsReviewCount = "needs_review_count"
        case changesRequestedCount = "changes_requested_count"
        case notStartedCount = "not_started_count"
        case overdueCount = "overdue_count"
        case completeCount = "complete_count"
    }
}

struct AssignmentViewerCapabilities: Codable, Hashable {
    var userId: UUID
    var isRecipient: Bool
    var canAcknowledge: Bool
    var canSubmit: Bool
    var canReview: Bool
    var canManage: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case isRecipient = "is_recipient"
        case canAcknowledge = "can_acknowledge"
        case canSubmit = "can_submit"
        case canReview = "can_review"
        case canManage = "can_manage"
    }
}

struct NotificationInboxItem: Codable, Identifiable, Hashable {
    var id: UUID
    var schoolId: UUID
    var schoolName: String
    var title: String
    var subtitle: String?
    var body: String
    var safeBody: String
    var category: String
    var sourceType: String?
    var sourceId: UUID?
    var createdBy: UUID?
    var createdAt: Date?
    var readAt: Date?
    var priority: String
    var route: NotificationRoute?
    var threadKey: String?
    var interruptionLevel: String
    var deliveryState: NotificationDeliveryState
    var attemptCount: Int
    var lastError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case schoolId = "school_id"
        case schoolName = "school_name"
        case title, subtitle, body, category
        case safeBody = "safe_body"
        case sourceType = "source_type"
        case sourceId = "source_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case readAt = "read_at"
        case priority, route
        case threadKey = "thread_key"
        case interruptionLevel = "interruption_level"
        case deliveryState = "delivery_state"
        case attemptCount = "attempt_count"
        case lastError = "last_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        schoolId = try container.decode(UUID.self, forKey: .schoolId)
        schoolName = try container.decode(String.self, forKey: .schoolName)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        body = try container.decode(String.self, forKey: .body)
        safeBody = try container.decodeIfPresent(String.self, forKey: .safeBody) ?? body
        category = try container.decode(String.self, forKey: .category)
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
        sourceId = try container.decodeIfPresent(UUID.self, forKey: .sourceId)
        createdBy = try container.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        readAt = try container.decodeIfPresent(Date.self, forKey: .readAt)
        priority = try container.decodeIfPresent(String.self, forKey: .priority) ?? "routine"
        route = try? container.decodeIfPresent(NotificationRoute.self, forKey: .route)
        threadKey = try container.decodeIfPresent(String.self, forKey: .threadKey)
        interruptionLevel = try container.decodeIfPresent(String.self, forKey: .interruptionLevel) ?? "active"
        deliveryState = try container.decodeIfPresent(NotificationDeliveryState.self, forKey: .deliveryState) ?? .queued
        attemptCount = try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }
}
