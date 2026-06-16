//
//  ConversationsListView.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI

struct ConversationsListView: View {
    @State private var searchText = ""
    @State private var rooms: [ChatRoom] = []
    @State private var isLoading = true
    @State private var showingNewChatAlert = false
    @State private var newChatName = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                
                VStack {
                    // Custom Header
                    HStack {
                        Text("Chat")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        HStack(spacing: 20) {
                            Button {
                                // TODO: Toggle search bar or navigate to search
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                            }
                            
                            Button {
                                showingNewChatAlert = true
                            } label: {
                                Image(systemName: "message.badge.plus")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    
                    if isLoading {
                        Spacer()
                        ProgressView().tint(.white)
                        Spacer()
                    } else if rooms.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.3))
                            Text("No chats yet")
                                .foregroundColor(.white.opacity(0.5))
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(rooms) { room in
                                    NavigationLink(destination: ChatViewWrapper(room: room)
                                        .navigationTitle(room.name)
                                        .navigationBarTitleDisplayMode(.inline)) {
                                        ChatRoomRow(room: room)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .alert("New Chat Room", isPresented: $showingNewChatAlert) {
                TextField("Room Name", text: $newChatName)
                Button("Cancel", role: .cancel) { newChatName = "" }
                Button("Create") {
                    createNewRoom()
                }
            } message: {
                Text("Enter a name for the new chat room.")
            }
        }
        .task {
            await loadRooms()
        }
    }
    
    private func loadRooms() async {
        do {
            let fetchedRooms = try await ChatService.shared.fetchMyRooms()
            await MainActor.run {
                self.rooms = fetchedRooms
                self.isLoading = false
            }
        } catch {
            print("DEBUG: Failed to fetch rooms - \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }
    
    private func createNewRoom() {
        guard !newChatName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let name = newChatName
        newChatName = ""
        
        Task {
            do {
                _ = try await ChatService.shared.createRoom(name: name)
                await loadRooms()
            } catch {
                print("DEBUG: Failed to create room - \(error)")
            }
        }
    }
}

struct ChatRoomRow: View {
    let room: ChatRoom
    
    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(String(room.name.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Tap to view messages...")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack {
                Text(timeAgo(from: room.createdAt))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(12)
    }
    
    // Quick helper for relative time
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
