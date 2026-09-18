import Foundation

enum NotificationFeatureDestination: Equatable {
    case assignment(UUID)
    case paperwork
    case paperworkRecord(UUID, sourceType: String, schoolId: UUID)
    case events
    case training
    case childConnection
    case attendance(UUID?)
    case childChat(UUID)
    case childCareEvent(UUID)
    case childProfile(UUID)
    case familyRequests(UUID?)
    case care
    case chatRoom(UUID, messageId: UUID?)
    case communityPost(UUID)
    case communityAlbum(UUID)
    case newsletter(UUID)
    case billing
    case zelleInvoice(UUID, schoolId: UUID)
    case googleFormReview
    case schoolAnnouncement
    case detail
}

struct NotificationDestinationResolver {
    func resolve(_ notification: NotificationInboxItem) -> NotificationFeatureDestination {
        let sourceId = notification.route?.id ?? notification.sourceId

        switch notification.route?.type ?? notification.sourceType {
        case "assignment":
            return sourceId.map(NotificationFeatureDestination.assignment) ?? .detail
        case "paperwork_assignment", "paperwork_request", "paperwork_submission":
            if AppConfiguration.workspaceBetaEnabled, let sourceId {
                return .paperworkRecord(sourceId, sourceType: notification.route?.type ?? notification.sourceType ?? "paperwork_request", schoolId: notification.schoolId)
            }
            return .paperwork
        case "school_event":
            return .events
        case "training_assignment":
            if AppConfiguration.workspaceBetaEnabled, let sourceId { return .assignment(sourceId) }
            return .training
        case "child_connection_request":
            return .childConnection
        case "attendance_session":
            return .attendance(sourceId)
        case "child_care_event":
            if let childId = notification.route?.childId { return .childChat(childId) }
            return sourceId.map(NotificationFeatureDestination.childCareEvent) ?? .detail
        case "child_feed":
            return (notification.route?.childId ?? sourceId)
                .map(NotificationFeatureDestination.childProfile) ?? .detail
        case "family_request":
            if let childId = notification.route?.childId { return .childChat(childId) }
            return .familyRequests(sourceId)
        case "medication_task", "medication_instruction":
            return .care
        case "chat_room":
            return sourceId.map { .chatRoom($0, messageId: notification.route?.messageId) } ?? .detail
        case "community_post":
            return sourceId.map(NotificationFeatureDestination.communityPost) ?? .detail
        case "community_album":
            return sourceId.map(NotificationFeatureDestination.communityAlbum) ?? .detail
        case "newsletter":
            return sourceId.map(NotificationFeatureDestination.newsletter) ?? .detail
        case "billing_invoice":
            return .billing
        case "zelle_invoice":
            return sourceId.map { .zelleInvoice($0, schoolId: notification.schoolId) } ?? .billing
        case "google_form_import", "google_form_response":
            if AppConfiguration.workspaceBetaEnabled, let sourceId {
                return .paperworkRecord(sourceId, sourceType: "google_form_import", schoolId: notification.schoolId)
            }
            return .googleFormReview
        case "school_announcement":
            return .schoolAnnouncement
        default:
            return resolveLegacyCategory(notification)
        }
    }

    private func resolveLegacyCategory(_ notification: NotificationInboxItem) -> NotificationFeatureDestination {
        switch notification.category {
        case "paperwork_due", "paperwork_reviewed", "paperwork_review":
            if AppConfiguration.workspaceBetaEnabled, let sourceId = notification.sourceId {
                .paperworkRecord(sourceId, sourceType: notification.sourceType ?? "paperwork_request", schoolId: notification.schoolId)
            } else {
                .paperwork
            }
        case "event_change":
            .events
        case "training_assigned", "training_reviewed", "curriculum_update":
            .training
        case "assignment_assigned", "assignment_submitted", "assignment_reviewed", "assignment_feedback":
            notification.sourceId.map(NotificationFeatureDestination.assignment) ?? .detail
        case "pickup_change", "absence":
            notification.route?.childId.map(NotificationFeatureDestination.childChat) ?? .familyRequests(nil)
        case "child_update", "medicine_instruction", "medication", "incident_report":
            notification.route?.childId.map(NotificationFeatureDestination.childChat) ?? .care
        case "community_post":
            notification.sourceId.map(NotificationFeatureDestination.communityPost) ?? .detail
        case "community_album", "community_album_batch":
            notification.sourceId.map(NotificationFeatureDestination.communityAlbum) ?? .detail
        case "newsletter":
            notification.sourceId.map(NotificationFeatureDestination.newsletter) ?? .detail
        case "billing_invoice":
            .billing
        case "zelle_payment":
            notification.sourceId.map { .zelleInvoice($0, schoolId: notification.schoolId) } ?? .billing
        case "google_form_response":
            if AppConfiguration.workspaceBetaEnabled, let sourceId = notification.sourceId {
                .paperworkRecord(sourceId, sourceType: "google_form_import", schoolId: notification.schoolId)
            } else {
                .googleFormReview
            }
        case "announcement", "school_announcement":
            .schoolAnnouncement
        default:
            .detail
        }
    }
}
