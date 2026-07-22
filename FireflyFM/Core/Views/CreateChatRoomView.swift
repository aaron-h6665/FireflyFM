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
    @EnvironmentObject private var appSession: AppSessionManager
    
    @State private var roomName = ""
    @State private var roomDescription = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var selectedImage: Image?
    @State private var selectedMembershipId: UUID?
    @State private var roomType = "public"
    
    @State private var isCreating = false
    @State private var errorMessage: String?

    var fixedSchool: School?
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
                                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.8))
                                        Text("Add Photo")
                                            .font(.caption)
                                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.8))
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
                            if let fixedSchool {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("School")
                                        .font(.caption.bold())
                                        .foregroundColor(AppConstants.Colors.accessibleYellow)

                                    HStack(spacing: 10) {
                                        SchoolAvatarView(school: fixedSchool, size: 34)
                                        Text(fixedSchool.name)
                                            .font(.subheadline.bold())
                                            .foregroundColor(AppConstants.Colors.primaryText)
                                        Spacer()
                                    }
                                    .padding()
                                    .background(AppConstants.Colors.card)
                                    .cornerRadius(12)
                                }
                            } else if appSession.canSwitchSchools {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("School")
                                        .font(.caption.bold())
                                        .foregroundColor(AppConstants.Colors.accessibleYellow)

                                    Picker("School", selection: Binding(
                                        get: { selectedMembershipId ?? appSession.activeMembershipId ?? appSession.memberships.first?.membership.id },
                                        set: { selectedMembershipId = $0 }
                                    )) {
                                        ForEach(appSession.memberships) { context in
                                            Text(context.school.name).tag(Optional(context.membership.id))
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(AppConstants.Colors.accessibleYellow)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .background(AppConstants.Colors.card)
                                    .cornerRadius(12)
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Chat Type")
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)

                                Picker("Chat Type", selection: $roomType) {
                                    Text("Public").tag("public")
                                    Text("Private").tag("private")
                                }
                                .pickerStyle(.segmented)
                            }

                            // Room Name
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Room Name")
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                                
                                TextField("E.g. Parent-Teacher Association", text: $roomName)
                                    .padding()
                                    .background(AppConstants.Colors.card)
                                    .cornerRadius(12)
                                    .foregroundColor(AppConstants.Colors.primaryText)
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
                                    .foregroundColor(AppConstants.Colors.primaryText)
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
                        .foregroundColor(AppConstants.Colors.primaryText)
                        .tint(AppConstants.Colors.accessibleYellow)
                }
            }
            .navigationTitle("New Chat Room")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if fixedSchool == nil {
                    selectedMembershipId = appSession.activeMembershipId ?? appSession.memberships.first?.membership.id
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppConstants.Colors.primaryText)
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
                // Create the room and participant relationship before writing
                // its private participant-scoped cover image.
                let room = try await ChatService.shared.createRoom(
                    name: roomName,
                    description: roomDescription.isEmpty ? nil : roomDescription,
                    schoolId: selectedSchoolId,
                    roomType: roomType
                )
                if let data = selectedImageData, let schoolId = selectedSchoolId {
                    let path = try await ChatService.shared.uploadRoomProfileImage(
                        data: data,
                        schoolId: schoolId,
                        roomId: room.id
                    )
                    try await ChatService.shared.updateRoomProfilePath(id: room.id, path: path)
                }
                
                await MainActor.run {
                    isCreating = false
                    onRoomCreated()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = AppErrorMessage.school("Could not create room", error)
                }
            }
        }
    }

    private var selectedSchoolId: UUID? {
        if let fixedSchool {
            return fixedSchool.id
        }
        guard let selectedMembershipId,
              let context = appSession.memberships.first(where: { $0.membership.id == selectedMembershipId })
        else {
            return appSession.activeSchool?.id
        }
        return context.school.id
    }
}

#Preview {
    CreateChatRoomView(onRoomCreated: {})
}
