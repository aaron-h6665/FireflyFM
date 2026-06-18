//
//  ChatViewWrapper.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI
import SDWebImageSwiftUI

struct ChatRoomScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var room: ChatRoom
    @State private var searchTrigger = 0
    @State private var showingSettings = false

    var onRoomChanged: () -> Void

    init(room: ChatRoom, onRoomChanged: @escaping () -> Void = {}) {
        _room = State(initialValue: room)
        self.onRoomChanged = onRoomChanged
    }

    var body: some View {
        ChatViewWrapper(room: room, searchTrigger: searchTrigger)
            .toolbar(.hidden, for: .tabBar)
            .toolbarBackground(AppConstants.Colors.card, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 12) {
                        roomAvatar(size: 32)
                        Text(room.name)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        searchTrigger += 1
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showingSettings) {
                ChatRoomSettingsView(
                    room: room,
                    onRoomUpdated: { updatedRoom in
                        room = updatedRoom
                        onRoomChanged()
                    },
                    onRoomClosed: {
                        showingSettings = false
                        onRoomChanged()
                        dismiss()
                    }
                )
            }
    }

    @ViewBuilder
    private func roomAvatar(size: CGFloat) -> some View {
        if let profileUrl = room.profileImageUrl, let url = URL(string: profileUrl) {
            WebImage(url: url)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: size, height: size)
                .overlay(
                    Text(String(room.name.prefix(1)).uppercased())
                        .font(.caption.bold())
                        .foregroundColor(.white)
                )
        }
    }
}

struct ChatViewWrapper: UIViewControllerRepresentable {
    let room: ChatRoom
    let searchTrigger: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(searchTrigger: searchTrigger)
    }

    func makeUIViewController(context: Context) -> ChatViewManager {
        let chatManager = ChatViewManager()
        chatManager.room = room
        return chatManager
    }

    func updateUIViewController(_ uiViewController: ChatViewManager, context: Context) {
        uiViewController.room = room

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
