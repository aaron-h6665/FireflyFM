import Foundation
import Supabase

final class SchoolOperationsService {
    static let shared = SchoolOperationsService()

    private let client = AppConstants.supabase
    private init() {}

    func fetchDirectory(schoolId: UUID) async throws -> [SchoolDirectoryEntry] {
        try await client.rpc(
            "fetch_school_directory",
            params: SchoolIdParameters(schoolId: schoolId)
        )
        .execute()
        .value
    }

    func fetchConnectionRequests(schoolId: UUID, status: ChildConnectionStatus? = nil) async throws -> [ChildConnectionRequest] {
        var query = client.from("child_connection_requests")
            .select()
            .eq("school_id", value: schoolId)
        if let status { query = query.eq("status", value: status.rawValue) }
        return try await query.order("created_at", ascending: false).execute().value
    }

    func submitConnectionRequest(
        schoolId: UUID,
        legalFirstName: String,
        legalLastName: String,
        birthdate: Date,
        relationship: String,
        idempotencyKey: String = UUID().uuidString
    ) async throws -> ChildConnectionRequest {
        let rows: [ChildConnectionRequest] = try await client.rpc(
            "submit_child_connection_request",
            params: SubmitConnectionParameters(
                schoolId: schoolId,
                legalFirstName: legalFirstName.trimmingCharacters(in: .whitespacesAndNewlines),
                legalLastName: legalLastName.trimmingCharacters(in: .whitespacesAndNewlines),
                birthdate: birthdate,
                relationship: relationship.trimmingCharacters(in: .whitespacesAndNewlines),
                idempotencyKey: idempotencyKey
            )
        )
        .execute()
        .value
        guard let row = rows.first else { throw SchoolWorkflowError.notFound }
        return row
    }

    func reviewConnectionRequest(
        requestId: UUID,
        approved: Bool,
        matchedChildId: UUID?,
        note: String?
    ) async throws -> ChildConnectionRequest {
        let rows: [ChildConnectionRequest] = try await client.rpc(
            "review_child_connection_request",
            params: ReviewConnectionParameters(
                requestId: requestId,
                decision: approved ? "approved" : "rejected",
                matchedChildId: matchedChildId,
                reviewNote: note,
                idempotencyKey: UUID().uuidString
            )
        )
        .execute()
        .value
        guard let row = rows.first else { throw SchoolWorkflowError.notFound }
        return row
    }

    func createGuardianInvite(
        childId: UUID,
        email: String,
        displayName: String?,
        relationship: String
    ) async throws -> ChildGuardianInviteResult {
        let rows: [ChildGuardianInviteResult] = try await client.rpc(
            "create_child_guardian_invite",
            params: GuardianInviteParameters(
                childId: childId,
                email: email,
                displayName: displayName,
                relationship: relationship
            )
        )
        .execute()
        .value
        guard let row = rows.first else { throw SchoolWorkflowError.notFound }
        return row
    }

    func fetchAttendance(schoolId: UUID, startDate: Date, endDate: Date) async throws -> [AttendanceSession] {
        try await client.from("attendance_sessions")
            .select()
            .eq("school_id", value: schoolId)
            .gte("attendance_date", value: DateOnlyCoding.string(from: startDate))
            .lte("attendance_date", value: DateOnlyCoding.string(from: endDate))
            .order("attendance_date", ascending: false)
            .order("checked_in_at", ascending: false)
            .execute()
            .value
    }

    func fetchAttendanceForHQ(startDate: Date, endDate: Date) async throws -> [AttendanceSession] {
        try await client.from("attendance_sessions")
            .select()
            .gte("attendance_date", value: DateOnlyCoding.string(from: startDate))
            .lte("attendance_date", value: DateOnlyCoding.string(from: endDate))
            .order("attendance_date", ascending: false)
            .execute()
            .value
    }

    @discardableResult
    func recordAttendance(
        childId: UUID,
        action: String,
        occurredAt: Date = Date(),
        notes: String? = nil,
        idempotencyKey: String = UUID().uuidString
    ) async throws -> AttendanceSession {
        let rows: [AttendanceSession] = try await client.rpc(
            "record_school_attendance",
            params: RecordAttendanceParameters(
                childId: childId,
                action: action,
                occurredAt: occurredAt,
                notes: notes,
                idempotencyKey: idempotencyKey
            )
        )
        .execute()
        .value
        guard let row = rows.first else { throw SchoolWorkflowError.notFound }
        return row
    }

    func recordAttendanceBatch(
        childIds: [UUID],
        action: String,
        idempotencyKey: String = UUID().uuidString
    ) async throws -> [AttendanceBatchResult] {
        try await client.rpc(
            "record_attendance_batch",
            params: RecordAttendanceBatchParameters(
                childIds: childIds,
                action: action,
                idempotencyKey: idempotencyKey
            )
        )
        .execute()
        .value
    }

    @discardableResult
    func correctAttendance(
        sessionId: UUID,
        checkedInAt: Date?,
        checkedOutAt: Date?,
        state: AttendanceState,
        notes: String?,
        reason: String
    ) async throws -> AttendanceSession {
        let rows: [AttendanceSession] = try await client.rpc(
            "correct_attendance_session",
            params: CorrectAttendanceParameters(
                sessionId: sessionId,
                checkedInAt: checkedInAt,
                checkedOutAt: checkedOutAt,
                state: state.rawValue,
                notes: notes,
                reason: reason
            )
        )
        .execute()
        .value
        guard let row = rows.first else { throw SchoolWorkflowError.notFound }
        return row
    }

    func fetchCareEvents(schoolId: UUID, start: Date, end: Date, childId: UUID? = nil) async throws -> [ChildCareEvent] {
        var query = client.from("child_care_events")
            .select()
            .eq("school_id", value: schoolId)
            .gte("occurred_at", value: start)
            .lt("occurred_at", value: end)
        if let childId { query = query.eq("child_id", value: childId) }
        return try await query.order("occurred_at", ascending: false).execute().value
    }

    @discardableResult
    func recordCareEvent(
        childId: UUID,
        type: ChildCareEventType,
        occurredAt: Date,
        details: [String: FireflyJSONValue],
        isStaffOnly: Bool,
        medicationTaskId: UUID? = nil,
        idempotencyKey: String = UUID().uuidString
    ) async throws -> ChildCareEvent {
        let rows: [ChildCareEvent] = try await client.rpc(
            "record_child_care_event",
            params: RecordCareParameters(
                childId: childId,
                eventType: type.rawValue,
                occurredAt: occurredAt,
                details: details,
                visibility: isStaffOnly ? "staff_only" : "parent",
                medicationTaskId: medicationTaskId,
                idempotencyKey: idempotencyKey
            )
        )
        .execute()
        .value
        guard let row = rows.first else { throw SchoolWorkflowError.notFound }
        return row
    }

    func uploadCarePhoto(
        data: Data,
        schoolId: UUID,
        childId: UUID,
        isStaffOnly: Bool
    ) async throws -> String {
        let user = try await client.auth.session.user
        let visibility = isStaffOnly ? "staff_only" : "parent"
        let path = [
            "schools", schoolId.uuidString.lowercased(), "care_events",
            childId.uuidString.lowercased(), visibility, user.id.uuidString.lowercased(),
            "\(UUID().uuidString.lowercased()).jpg"
        ].joined(separator: "/")
        _ = try await SchoolService.shared.uploadPrivateData(
            data: data,
            path: path,
            name: "Care photo.jpg",
            contentType: "image/jpeg"
        )
        return path
    }

    func fetchFamilyRequests(schoolId: UUID, status: String? = "open") async throws -> [FamilyRequest] {
        var query = client.from("family_requests").select().eq("school_id", value: schoolId)
        if let status { query = query.eq("status", value: status) }
        return try await query.order("created_at", ascending: false).execute().value
    }

    @discardableResult
    func updateFamilyRequestStatus(requestId: UUID, status: String) async throws -> FamilyRequest {
        let rows: [FamilyRequest] = try await client.rpc(
            "update_family_request_status",
            params: UpdateFamilyRequestParameters(requestId: requestId, status: status)
        )
        .execute()
        .value
        guard let row = rows.first else { throw SchoolWorkflowError.notFound }
        return row
    }

    @discardableResult
    func submitFamilyRequest(
        childId: UUID,
        type: String,
        details: [String: FireflyJSONValue],
        idempotencyKey: String = UUID().uuidString
    ) async throws -> FamilyRequest {
        let rows: [FamilyRequest] = try await client.rpc(
            "submit_family_request",
            params: SubmitFamilyRequestParameters(
                childId: childId,
                requestType: type,
                details: details,
                idempotencyKey: idempotencyKey
            )
        )
        .execute()
        .value
        guard let row = rows.first else { throw SchoolWorkflowError.notFound }
        return row
    }

    func createAnnouncement(
        schoolId: UUID,
        title: String,
        body: String,
        recipientIds: [UUID]
    ) async throws {
        _ = try await client.rpc(
            "create_school_announcement",
            params: AnnouncementParameters(
                schoolId: schoolId,
                title: title,
                body: body,
                recipientIds: recipientIds,
                idempotencyKey: UUID().uuidString
            )
        )
        .execute()
    }

    func fetchNotificationPreferences() async throws -> [NotificationPreference] {
        let user = try await client.auth.session.user
        return try await client.from("notification_preferences")
            .select()
            .eq("user_id", value: user.id)
            .execute()
            .value
    }

    func saveNotificationPreferences(_ preferences: [NotificationPreference]) async throws {
        guard preferences.isEmpty == false else { return }
        try await client.from("notification_preferences")
            .upsert(preferences, onConflict: "user_id,category")
            .execute()
    }

    func createManagedChatRoom(
        schoolId: UUID,
        name: String,
        description: String?,
        imageURL: String?,
        participantIds: [UUID]
    ) async throws -> ChatRoom {
        let rooms: [ChatRoom] = try await client.rpc(
            "create_director_chat_room",
            params: CreateManagedRoomParameters(
                schoolId: schoolId,
                name: name,
                description: description,
                profileImageURL: imageURL,
                participantIds: participantIds,
                idempotencyKey: UUID().uuidString
            )
        )
        .execute()
        .value
        guard let room = rooms.first else { throw SchoolWorkflowError.notFound }
        return room
    }

    func setManagedChatParticipants(roomId: UUID, participantIds: [UUID]) async throws {
        _ = try await client.rpc(
            "set_director_chat_participants",
            params: ManagedRoomParticipantsParameters(roomId: roomId, participantIds: participantIds)
        )
        .execute()
    }

    func updateManagedChatRoom(
        roomId: UUID,
        name: String,
        description: String?,
        imageURL: String?,
        archived: Bool
    ) async throws -> ChatRoom {
        let rooms: [ChatRoom] = try await client.rpc(
            "update_director_chat_room",
            params: UpdateManagedRoomParameters(
                roomId: roomId,
                name: name,
                description: description,
                profileImageURL: imageURL,
                archived: archived
            )
        )
        .execute()
        .value
        guard let room = rooms.first else { throw SchoolWorkflowError.notFound }
        return room
    }

    func updateManagedChatImagePath(roomId: UUID, path: String) async throws -> ChatRoom {
        let rooms: [ChatRoom] = try await client.rpc(
            "update_director_chat_room_image_path",
            params: ManagedRoomImageParameters(roomId: roomId, profileImagePath: path)
        )
        .execute()
        .value
        guard let room = rooms.first else { throw SchoolWorkflowError.notFound }
        return room
    }

    func deleteManagedChatRoom(roomId: UUID) async throws {
        _ = try await client.rpc(
            "delete_director_chat_room",
            params: RoomIdParameters(roomId: roomId)
        )
        .execute()
    }

    func leaveManagedChatRoom(roomId: UUID) async throws {
        _ = try await client.rpc(
            "leave_managed_chat_room",
            params: RoomIdParameters(roomId: roomId)
        )
        .execute()
    }
}

struct ChildGuardianInviteResult: Decodable, Hashable {
    let inviteId: UUID
    let inviteToken: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case inviteId = "invite_id"
        case inviteToken = "invite_token"
        case expiresAt = "expires_at"
    }
}

private struct SchoolIdParameters: Encodable {
    let schoolId: UUID
    enum CodingKeys: String, CodingKey { case schoolId = "input_school_id" }
}

private struct SubmitConnectionParameters: Encodable {
    let schoolId: UUID
    let legalFirstName: String
    let legalLastName: String
    let birthdate: Date
    let relationship: String
    let idempotencyKey: String
    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
        case legalFirstName = "input_legal_first_name"
        case legalLastName = "input_legal_last_name"
        case birthdate = "input_birthdate"
        case relationship = "input_relationship"
        case idempotencyKey = "input_idempotency_key"
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schoolId, forKey: .schoolId)
        try container.encode(legalFirstName, forKey: .legalFirstName)
        try container.encode(legalLastName, forKey: .legalLastName)
        try container.encode(DateOnlyCoding.string(from: birthdate), forKey: .birthdate)
        try container.encode(relationship, forKey: .relationship)
        try container.encode(idempotencyKey, forKey: .idempotencyKey)
    }
}

private struct ReviewConnectionParameters: Encodable {
    let requestId: UUID
    let decision: String
    let matchedChildId: UUID?
    let reviewNote: String?
    let idempotencyKey: String
    enum CodingKeys: String, CodingKey {
        case requestId = "input_request_id"
        case decision = "input_decision"
        case matchedChildId = "input_matched_child_id"
        case reviewNote = "input_review_note"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct GuardianInviteParameters: Encodable {
    let childId: UUID
    let email: String
    let displayName: String?
    let relationship: String
    enum CodingKeys: String, CodingKey {
        case childId = "input_child_id"
        case email = "input_email"
        case displayName = "input_display_name"
        case relationship = "input_relationship"
    }
}

private struct RecordAttendanceParameters: Encodable {
    let childId: UUID
    let action: String
    let occurredAt: Date
    let notes: String?
    let idempotencyKey: String
    enum CodingKeys: String, CodingKey {
        case childId = "input_child_id"
        case action = "input_action"
        case occurredAt = "input_occurred_at"
        case notes = "input_notes"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct RecordAttendanceBatchParameters: Encodable {
    let childIds: [UUID]
    let action: String
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case childIds = "input_child_ids"
        case action = "input_action"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct CorrectAttendanceParameters: Encodable {
    let sessionId: UUID
    let checkedInAt: Date?
    let checkedOutAt: Date?
    let state: String
    let notes: String?
    let reason: String
    enum CodingKeys: String, CodingKey {
        case sessionId = "input_session_id"
        case checkedInAt = "input_checked_in_at"
        case checkedOutAt = "input_checked_out_at"
        case state = "input_state"
        case notes = "input_notes"
        case reason = "input_reason"
    }
}

private struct RecordCareParameters: Encodable {
    let childId: UUID
    let eventType: String
    let occurredAt: Date
    let details: [String: FireflyJSONValue]
    let visibility: String
    let medicationTaskId: UUID?
    let idempotencyKey: String
    enum CodingKeys: String, CodingKey {
        case childId = "input_child_id"
        case eventType = "input_event_type"
        case occurredAt = "input_occurred_at"
        case details = "input_details"
        case visibility = "input_visibility"
        case medicationTaskId = "input_medication_task_id"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct SubmitFamilyRequestParameters: Encodable {
    let childId: UUID
    let requestType: String
    let details: [String: FireflyJSONValue]
    let idempotencyKey: String
    enum CodingKeys: String, CodingKey {
        case childId = "input_child_id"
        case requestType = "input_request_type"
        case details = "input_details"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct UpdateFamilyRequestParameters: Encodable {
    let requestId: UUID
    let status: String
    enum CodingKeys: String, CodingKey {
        case requestId = "input_request_id"
        case status = "input_status"
    }
}

private struct AnnouncementParameters: Encodable {
    let schoolId: UUID
    let title: String
    let body: String
    let recipientIds: [UUID]
    let idempotencyKey: String
    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
        case title = "input_title"
        case body = "input_body"
        case recipientIds = "input_recipient_ids"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct CreateManagedRoomParameters: Encodable {
    let schoolId: UUID
    let name: String
    let description: String?
    let profileImageURL: String?
    let participantIds: [UUID]
    let idempotencyKey: String
    enum CodingKeys: String, CodingKey {
        case schoolId = "input_school_id"
        case name = "input_name"
        case description = "input_description"
        case profileImageURL = "input_profile_image_url"
        case participantIds = "input_participant_ids"
        case idempotencyKey = "input_idempotency_key"
    }
}

private struct ManagedRoomParticipantsParameters: Encodable {
    let roomId: UUID
    let participantIds: [UUID]
    enum CodingKeys: String, CodingKey {
        case roomId = "input_room_id"
        case participantIds = "input_participant_ids"
    }
}

private struct UpdateManagedRoomParameters: Encodable {
    let roomId: UUID
    let name: String
    let description: String?
    let profileImageURL: String?
    let archived: Bool
    enum CodingKeys: String, CodingKey {
        case roomId = "input_room_id"
        case name = "input_name"
        case description = "input_description"
        case profileImageURL = "input_profile_image_url"
        case archived = "input_archived"
    }
}

private struct RoomIdParameters: Encodable {
    let roomId: UUID
    enum CodingKeys: String, CodingKey { case roomId = "input_room_id" }
}

private struct ManagedRoomImageParameters: Encodable {
    let roomId: UUID
    let profileImagePath: String
    enum CodingKeys: String, CodingKey {
        case roomId = "input_room_id"
        case profileImagePath = "input_profile_image_path"
    }
}
