import Foundation

enum NotificationFeatureDestination: Equatable {
    case assignment(UUID)
    case paperwork
    case events
    case training
    case childConnection
    case attendance(UUID?)
    case childChat(UUID)
    case childCareEvent(UUID)
    case childProfile(UUID)
    case familyRequests(UUID?)
    case care
    case chatRoom(UUID)
    case detail
}

struct NotificationDestinationResolver {
    func resolve(_ notification: NotificationInboxItem) -> NotificationFeatureDestination {
        let sourceId = notification.route?.id ?? notification.sourceId

        switch notification.route?.type ?? notification.sourceType {
        case "assignment":
            return sourceId.map(NotificationFeatureDestination.assignment) ?? .detail
        case "paperwork_assignment":
            return .paperwork
        case "school_event":
            return .events
        case "training_assignment":
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
            return sourceId.map(NotificationFeatureDestination.chatRoom) ?? .detail
        default:
            return resolveLegacyCategory(notification)
        }
    }

    private func resolveLegacyCategory(_ notification: NotificationInboxItem) -> NotificationFeatureDestination {
        switch notification.category {
        case "paperwork_due", "paperwork_reviewed":
            .paperwork
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
        default:
            .detail
        }
    }
}
