//
//  ChatNotificationManager.swift
//  FireflyFM
//

import Foundation
import Supabase
import UIKit
import UserNotifications

final class PushNotificationManager {
    static let shared = PushNotificationManager()
    private static let storedTokenKey = "firefly.apns-device-token"
    private let visibilityLock = NSLock()
    private var visibleChatRoomId: UUID?

    private init() {}

    @MainActor
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if allowed { UIApplication.shared.registerForRemoteNotifications() }
            return allowed
        } catch {
            print("DEBUG: Notification authorization failed - \(error)")
            return false
        }
    }

    @MainActor
    func registerIfAuthorized() async {
        switch await permissionState() {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
            await syncPendingDeviceToken()
        default:
            break
        }
    }

    func permissionState() async -> NotificationPermissionState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }

    func shouldOfferPermissionPrimer() async -> Bool {
        guard await permissionState() == .notDetermined else { return false }
        let settings = try? await SchoolOperationsService.shared.fetchUserNotificationSettings()
        return settings?.permissionPromptDeferred != true
    }

    func deferPermissionPrimer() async {
        guard var settings = try? await SchoolOperationsService.shared.fetchUserNotificationSettings() else { return }
        settings.permissionPromptDeferred = true
        try? await SchoolOperationsService.shared.saveUserNotificationSettings(settings)
    }

    @MainActor
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func storeAndSyncDeviceToken(_ data: Data) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: Self.storedTokenKey)
        await syncPendingDeviceToken()
    }

    func syncPendingDeviceToken() async {
        guard let token = UserDefaults.standard.string(forKey: Self.storedTokenKey), token.isEmpty == false,
              let session = try? await AppConstants.supabase.auth.session else { return }
        let payload = DeviceTokenRegistration(
            userId: session.user.id,
            token: token,
            bundleId: Bundle.main.bundleIdentifier,
            environment: Self.apnsEnvironment,
            lastSeenAt: Date()
        )
        do {
            try await AppConstants.supabase.from("device_tokens")
                .upsert(payload, onConflict: "user_id,token")
                .execute()
        } catch {
            print("DEBUG: Device token sync failed - \(error)")
        }
    }

    func unregisterCurrentDeviceToken() async {
        guard let token = UserDefaults.standard.string(forKey: Self.storedTokenKey),
              let session = try? await AppConstants.supabase.auth.session else { return }
        _ = try? await AppConstants.supabase.from("device_tokens")
            .delete()
            .eq("user_id", value: session.user.id)
            .eq("token", value: token)
            .execute()
    }

    func setVisibleChatRoom(_ roomId: UUID?) {
        visibilityLock.lock()
        visibleChatRoomId = roomId
        visibilityLock.unlock()
    }

    func isVisibleChatNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let route = userInfo["route"] as? [String: Any],
              route["type"] as? String == "chat_room",
              let value = route["id"] as? String,
              let roomId = UUID(uuidString: value) else { return false }
        visibilityLock.lock()
        defer { visibilityLock.unlock() }
        return visibleChatRoomId == roomId
    }

    @MainActor
    func updateApplicationBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, count)) { error in
            if let error { print("DEBUG: App badge update failed - \(error)") }
        }
    }

    func removeNotifications(forMessageIds messageIds: Set<UUID>) async {
        guard !messageIds.isEmpty else { return }
        let center = UNUserNotificationCenter.current()

        let delivered = await center.deliveredNotifications()
        let deliveredIds = delivered.compactMap { notification in
            Self.referencesMessage(notification.request.content.userInfo, in: messageIds)
                ? notification.request.identifier
                : nil
        }
        if !deliveredIds.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredIds)
        }

        let pending = await center.pendingNotificationRequests()
        let pendingIds = pending.compactMap { request in
            Self.referencesMessage(request.content.userInfo, in: messageIds)
                ? request.identifier
                : nil
        }
        if !pendingIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingIds)
        }
    }

    private static var apnsEnvironment: String {
#if DEBUG
        "development"
#else
        "production"
#endif
    }

    private static func referencesMessage(_ userInfo: [AnyHashable: Any], in messageIds: Set<UUID>) -> Bool {
        if let value = userInfo["message_id"] as? String,
           let messageId = UUID(uuidString: value),
           messageIds.contains(messageId) {
            return true
        }

        let routeValue = (userInfo["route"] as? [AnyHashable: Any])?["message_id"]
            ?? (userInfo["route"] as? NSDictionary)?.object(forKey: "message_id")
        guard let value = routeValue as? String,
              let messageId = UUID(uuidString: value) else { return false }
        return messageIds.contains(messageId)
    }
}

private struct DeviceTokenRegistration: Encodable {
    let userId: UUID
    let token: String
    let platform = "ios"
    let bundleId: String?
    let environment: String
    let lastSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case token, platform, environment
        case userId = "user_id"
        case bundleId = "bundle_id"
        case lastSeenAt = "last_seen_at"
    }
}

extension Notification.Name {
    static let fireflyRemoteNotificationTapped = Notification.Name("fireflyRemoteNotificationTapped")
}

final class FireflyAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(Set([
            UNNotificationCategory(identifier: "FIREFLY_CHAT_MESSAGE", actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: "FIREFLY_COMMUNITY_ALBUM", actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: "FIREFLY_COMMUNITY_POST", actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: "FIREFLY_NEWSLETTER", actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: "FIREFLY_ACTIVITY", actions: [], intentIdentifiers: [])
        ]))
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await PushNotificationManager.shared.storeAndSyncDeviceToken(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("DEBUG: Remote notification registration failed - \(error)")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        if PushNotificationManager.shared.isVisibleChatNotification(userInfo) {
            if let route = userInfo["route"] as? [String: Any],
               let value = route["id"] as? String {
                Task {
                    try? await SchoolWorkflowService.shared.markNotificationThreadRead(threadKey: "chat:\(value)")
                }
            }
            return []
        }
        if notification.request.content.interruptionLevel == .passive {
            return [.list, .badge]
        }
        return [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let url: URL?
        if let notificationId = userInfo["notification_id"] as? String {
            url = URL(string: "fireflyfm://notification/\(notificationId)")
        } else if let legacyDeepLink = userInfo["deep_link"] as? String {
            url = URL(string: legacyDeepLink)
        } else {
            url = nil
        }
        guard let url else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .fireflyRemoteNotificationTapped, object: url)
        }
    }
}
