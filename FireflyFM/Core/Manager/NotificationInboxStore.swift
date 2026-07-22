import Foundation
internal import Combine

@MainActor
final class NotificationInboxStore: ObservableObject {
    @Published private(set) var notifications: [NotificationInboxItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    var unreadCount: Int {
        notifications.lazy.filter { $0.readAt == nil }.count
    }

    func refresh() async {
        isLoading = true
        do {
            notifications = try await SchoolWorkflowService.shared.fetchMyNotifications()
            errorMessage = nil
        } catch where AppErrorMessage.isCancellation(error) {
        } catch {
            errorMessage = AppErrorMessage.school("Could not load notifications", error)
        }
        isLoading = false
    }

    func markRead(_ notification: NotificationInboxItem) async {
        guard notification.readAt == nil else { return }
        do {
            try await SchoolWorkflowService.shared.markNotificationRead(notificationId: notification.id)
            if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
                notifications[index].readAt = Date()
            }
        } catch {
            errorMessage = AppErrorMessage.school("Could not mark notification read", error)
        }
    }

    @discardableResult
    func dismiss(_ notification: NotificationInboxItem) async -> Bool {
        do {
            try await SchoolWorkflowService.shared.dismissNotification(notificationId: notification.id)
            notifications.removeAll { $0.id == notification.id }
            errorMessage = nil
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not delete notification", error)
            return false
        }
    }

    @discardableResult
    func dismissAll() async -> Bool {
        do {
            try await SchoolWorkflowService.shared.clearMyNotifications()
            notifications = []
            errorMessage = nil
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not clear notifications", error)
            return false
        }
    }

    func clear() {
        notifications = []
        errorMessage = nil
        isLoading = false
    }
}
