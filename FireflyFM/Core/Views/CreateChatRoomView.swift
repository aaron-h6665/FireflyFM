//
//  CreateChatRoomView.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI
import PhotosUI

struct CreateChatRoomView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var roomName = ""
    @State private var roomDescription = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var selectedImage: Image?
    
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    var onRoomCreated: () -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // Photo Picker Section
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            ZStack {
                                Circle()
                                    .fill(AppConstants.Colors.card)
                                    .frame(width: 120, height: 120)
                                    .overlay(
                                        Circle().stroke(AppConstants.Colors.accessibleYellow.opacity(0.5), lineWidth: 2)
                                    )
                                
                                if let selectedImage {
                                    selectedImage
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 120)
                                        .clipShape(Circle())
                                } else {
                                    VStack {
                                        Image(systemName: "camera.fill")
                                            .font(.title)
                                            .foregroundColor(.white.opacity(0.8))
                                        Text("Add Photo")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                            }
                        }
                        .onChange(of: selectedItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                    selectedImageData = data
                                    if let uiImage = UIImage(data: data) {
                                        selectedImage = Image(uiImage: uiImage)
                                    }
                                }
                            }
                        }
                        
                        // Input Fields
                        VStack(spacing: 16) {
                            // Room Name
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Room Name")
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                                
                                TextField("E.g. Parent-Teacher Association", text: $roomName)
                                    .padding()
                                    .background(AppConstants.Colors.card)
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                                    .tint(AppConstants.Colors.accessibleYellow)
                            }
                            
                            // Room Description
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Description")
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                                
                                TextField("What is this chat about?", text: $roomDescription, axis: .vertical)
                                    .lineLimit(3...6)
                                    .padding()
                                    .background(AppConstants.Colors.card)
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                                    .tint(AppConstants.Colors.accessibleYellow)
                            }
                        }
                        .padding(.horizontal)
                        
                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.top, 32)
                }
                
                if isCreating {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView("Creating Room...")
                        .padding()
                        .background(AppConstants.Colors.card)
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .tint(AppConstants.Colors.accessibleYellow)
                }
            }
            .navigationTitle("New Chat Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        createRoom()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(roomName.isEmpty ? .gray : AppConstants.Colors.accessibleYellow)
                    .disabled(roomName.isEmpty || isCreating)
                }
            }
        }
    }
    
    private func createRoom() {
        guard !roomName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isCreating = true
        errorMessage = nil
        
        Task {
            do {
                var profileUrl: String? = nil
                
                // 1. Upload image if selected
                if let data = selectedImageData {
                    let path = "room_avatars/\(UUID().uuidString).jpg"
                    profileUrl = try await ChatService.shared.uploadImage(data: data, path: path)
                }
                
                // 2. Create room
                _ = try await ChatService.shared.createRoom(
                    name: roomName,
                    description: roomDescription.isEmpty ? nil : roomDescription,
                    profileImageUrl: profileUrl
                )
                
                await MainActor.run {
                    isCreating = false
                    onRoomCreated()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = "Failed to create room: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    CreateChatRoomView(onRoomCreated: {})
}
