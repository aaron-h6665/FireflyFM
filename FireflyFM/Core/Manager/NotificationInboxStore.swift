import Foundation
internal import Combine
import Supabase

@MainActor
final class NotificationInboxStore: ObservableObject {
    @Published private(set) var notifications: [NotificationInboxItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var realtimeChannel: RealtimeChannelV2?

    var unreadCount: Int {
        notifications.lazy.filter { $0.readAt == nil }.count
    }

    func refresh() async {
        isLoading = true
        do {
            notifications = try await SchoolWorkflowService.shared.fetchMyNotifications()
            let deletedMessageIds: Set<UUID> = Set(notifications.compactMap { notification -> UUID? in
                guard notification.category == "chat_message",
                      notification.body == "Message deleted"
                else { return nil }
                return notification.route?.messageId
            })
            await PushNotificationManager.shared.removeNotifications(forMessageIds: deletedMessageIds)
            PushNotificationManager.shared.updateApplicationBadge(unreadCount)
            errorMessage = nil
        } catch where AppErrorMessage.isCancellation(error) {
        } catch {
            errorMessage = AppErrorMessage.school("Could not load notifications", error)
        }
        isLoading = false
    }

    @discardableResult
    func markRead(_ notification: NotificationInboxItem) async -> Bool {
        guard notification.readAt == nil else { return true }
        do {
            try await SchoolWorkflowService.shared.markNotificationRead(notificationId: notification.id)
            if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
                notifications[index].readAt = Date()
            }
            PushNotificationManager.shared.updateApplicationBadge(unreadCount)
            errorMessage = nil
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not mark notification read", error)
            return false
        }
    }

    @discardableResult
    func markAllRead() async -> Bool {
        guard unreadCount > 0 else { return true }
        do {
            try await SchoolWorkflowService.shared.markAllNotificationsRead()
            let readAt = Date()
            for index in notifications.indices where notifications[index].readAt == nil {
                notifications[index].readAt = readAt
            }
            PushNotificationManager.shared.updateApplicationBadge(0)
            errorMessage = nil
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not mark notifications read", error)
            return false
        }
    }

    @discardableResult
    func markThreadRead(_ threadKey: String) async -> Bool {
        do {
            try await SchoolWorkflowService.shared.markNotificationThreadRead(threadKey: threadKey)
            let readAt = Date()
            for index in notifications.indices
            where notifications[index].threadKey == threadKey && notifications[index].readAt == nil {
                notifications[index].readAt = readAt
            }
            PushNotificationManager.shared.updateApplicationBadge(unreadCount)
            errorMessage = nil
            return true
        } catch {
            errorMessage = AppErrorMessage.school("Could not mark conversation activity read", error)
            return false
        }
    }

    @discardableResult
    func dismiss(_ notification: NotificationInboxItem) async -> Bool {
        do {
            try await SchoolWorkflowService.shared.dismissNotification(notificationId: notification.id)
            notifications.removeAll { $0.id == notification.id }
            PushNotificationManager.shared.updateApplicationBadge(unreadCount)
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
            PushNotificationManager.shared.updateApplicationBadge(0)
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
        Task { await stopRealtime() }
    }

    func startRealtime() async {
        await stopRealtime()
        guard let userId = try? await AppConstants.supabase.auth.session.user.id else { return }
        let channel = AppConstants.supabase.realtimeV2.channel("notification_inbox_\(userId.uuidString)")
        let insertions = await channel.postgresChange(
            InsertAction.self, schema: "public", table: "notification_recipients",
            filter: .eq("user_id", value: userId.uuidString)
        )
        let updates = await channel.postgresChange(
            UpdateAction.self, schema: "public", table: "notification_recipients",
            filter: .eq("user_id", value: userId.uuidString)
        )
        let deletions = await channel.postgresChange(
            DeleteAction.self, schema: "public", table: "notification_recipients",
            filter: .eq("user_id", value: userId.uuidString)
        )
        let contentUpdates = await channel.postgresChange(
            UpdateAction.self, schema: "public", table: "notifications",
            filter: .eq("category", value: "chat_message")
        )
        realtimeChannel = channel
        Task { [weak self] in for await _ in insertions { await self?.refresh() } }
        Task { [weak self] in for await _ in updates { await self?.refresh() } }
        Task { [weak self] in for await _ in deletions { await self?.refresh() } }
        Task { [weak self] in for await _ in contentUpdates { await self?.refresh() } }
        do { try await channel.subscribeWithError() }
        catch { errorMessage = AppErrorMessage.school("Live notification updates are unavailable", error) }
    }

    func stopRealtime() async {
        await realtimeChannel?.unsubscribe()
        realtimeChannel = nil
    }
}
