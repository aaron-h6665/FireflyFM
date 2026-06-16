//
//  ChatViewWrapper.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI

struct ChatViewWrapper: UIViewControllerRepresentable {
    let room: ChatRoom
    
    func makeUIViewController(context: Context) -> ChatViewManager {
        let chatManager = ChatViewManager()
        chatManager.room = room
        return chatManager
    }
    
    func updateUIViewController(_ uiViewController: ChatViewManager, context: Context) {
        // Updates can go here if needed
    }
}
