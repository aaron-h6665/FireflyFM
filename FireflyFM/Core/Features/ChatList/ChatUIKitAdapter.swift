import SwiftUI

struct ChatViewWrapper: UIViewControllerRepresentable {
    let room: ChatRoom
    let capabilities: ChatRoomCapabilities
    let searchTrigger: Int
    let focusMessageId: UUID?
    let onAction: (ChatRoomAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(searchTrigger: searchTrigger)
    }

    func makeUIViewController(context: Context) -> ChatViewManager {
        let chatManager = ChatViewManager()
        chatManager.room = room
        chatManager.capabilities = capabilities
        chatManager.focusMessageId = focusMessageId
        chatManager.onAction = onAction
        return chatManager
    }

    func updateUIViewController(_ uiViewController: ChatViewManager, context: Context) {
        uiViewController.room = room
        uiViewController.capabilities = capabilities
        uiViewController.focusMessageId = focusMessageId
        uiViewController.onAction = onAction
        uiViewController.updateRoomState()

        if context.coordinator.lastSearchTrigger != searchTrigger {
            context.coordinator.lastSearchTrigger = searchTrigger
            uiViewController.presentMessageSearch()
        }
    }

    final class Coordinator {
        var lastSearchTrigger: Int

        init(searchTrigger: Int) {
            self.lastSearchTrigger = searchTrigger
        }
    }
}

