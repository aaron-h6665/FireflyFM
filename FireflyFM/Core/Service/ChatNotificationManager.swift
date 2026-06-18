//
//  ChatNotificationManager.swift
//  FireflyFM
//

import Foundation
import UserNotifications

final class ChatNotificationManager {
    static let shared = ChatNotificationManager()

    private init() {}

    func requestAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("DEBUG: Notification authorization failed - \(error)")
        }
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
