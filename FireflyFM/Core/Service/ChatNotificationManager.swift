//
//  ChatNotificationManager.swift
//  FireflyFM
//

import Foundation
import Supabase
import UIKit
import UserNotifications

final class ChatNotificationManager {
    static let shared = ChatNotificationManager()
    private static let storedTokenKey = "firefly.apns-device-token"

    private init() {}

    @MainActor
    func requestAuthorization() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if allowed { UIApplication.shared.registerForRemoteNotifications() }
        } catch {
            print("DEBUG: Notification authorization failed - \(error)")
        }
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

    func notifyIncomingMessage(roomName: String, message: ChatMessageModel) {
        let content = UNMutableNotificationContent()
        content.title = roomName
        content.body = summary(for: message)
        content.sound = .default
        content.userInfo = [
            "room_id": message.roomId.uuidString,
            "message_id": message.id.uuidString
        ]

        let request = UNNotificationRequest(
            identifier: "chat-\(message.id.uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("DEBUG: Failed to schedule chat notification - \(error)")
            }
        }
    }

    private static var apnsEnvironment: String {
#if DEBUG
        "development"
#else
        "production"
#endif
    }

    private func summary(for message: ChatMessageModel) -> String {
        if message.isDeleted {
            return "Message deleted"
        }

        if let text = message.text, !text.isEmpty {
            return text
        }

        if message.mediaUrl != nil {
            return "Photo"
        }

        if let attachmentName = message.attachmentName {
            return attachmentName
        }

        if message.fileUrl != nil {
            return "File attachment"
        }

        return "New message"
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
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await ChatNotificationManager.shared.storeAndSyncDeviceToken(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("DEBUG: Remote notification registration failed - \(error)")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let value = response.notification.request.content.userInfo["deep_link"] as? String,
              let url = URL(string: value) else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .fireflyRemoteNotificationTapped, object: url)
        }
    }
}
