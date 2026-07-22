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
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var room: ChatRoom
    @State private var searchTrigger = 0
    @State private var showingSettings = false
    @State private var memberCount = 0

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
                        VStack(alignment: .leading, spacing: 1) {
                            Text(room.name).font(.headline).lineLimit(1)
                            Text("\(memberCount) members").font(.caption2).foregroundColor(AppConstants.Colors.secondaryText)
                        }
                        .foregroundColor(AppConstants.Colors.primaryText)
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        searchTrigger += 1
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(AppConstants.Colors.primaryText)

                    if appSession.role == .schoolDirector {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(AppConstants.Colors.primaryText)
                    }
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
            .task {
                memberCount = (try? await ChatService.shared.fetchParticipants(roomId: room.id).count) ?? 0
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
                        .foregroundColor(AppConstants.Colors.primaryText)
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
