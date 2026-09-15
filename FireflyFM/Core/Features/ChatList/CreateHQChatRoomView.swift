//
//  CreateHQChatRoomView.swift
//  FireflyFM
//

import SwiftUI
import PhotosUI

struct CreateHQChatRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var roomName = ""
    @State private var roomDescription = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var selectedImage: Image?
    @State private var model = CreateHQChatRoomModel()
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var memberSearch = ""
    @State private var selectedCampusId: UUID? = nil
    @State private var roleFilter = "all"
    @State private var accessErrorMessage: String?

    var onRoomCreated: () -> Void

    private var accessPolicy: ChatAccessPolicy {
        ChatAccessPolicy(context: appSession.accessContext())
    }

    private var availableSchools: [School] {
        var seen = Set<UUID>()
        return appSession.memberships.compactMap { context in
            if seen.insert(context.school.id).inserted {
                return context.school
            }
            return nil
        }
    }

    private var filteredDirectory: [HQDirectoryEntry] {
        let query = memberSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.directory.filter { entry in
            if let selectedCampusId, entry.schoolId != selectedCampusId {
                return false
            }
            if roleFilter == "staff" {
                if entry.role != "teacher" && entry.role != "school_director" {
                    return false
                }
            } else if roleFilter == "parent" {
                if entry.role != "parent" {
                    return false
                }
            } else if roleFilter == "hq_director" {
                if entry.role != "hq_director" {
                    return false
                }
            }
            if !query.isEmpty {
                let matchesName = entry.displayName.localizedCaseInsensitiveContains(query)
                let matchesSchool = entry.schoolName.localizedCaseInsensitiveContains(query)
                let matchesRole = entry.roleTitle.localizedCaseInsensitiveContains(query)
                if !matchesName && !matchesSchool && !matchesRole {
                    return false
                }
            }
            return true
        }
    }

    private var selectedBreakdown: (staffCount: Int, parentCount: Int) {
        var staff = 0
        var parents = 0
        for id in selectedMemberIds {
            if let entry = model.directory.first(where: { $0.userId == id }) {
                if entry.role == "parent" {
                    parents += 1
                } else {
                    staff += 1
                }
            }
        }
        return (staff, parents)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        hqBanner
                        roomPhotoPicker
                        roomFields
                        memberPicker

                        if let errorMessage = model.errorMessage ?? accessErrorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                        }
                    }
                    .padding()
                }

                if model.isCreating {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView("Creating HQ chat…")
                        .padding()
                        .background(AppConstants.Colors.card)
                        .cornerRadius(12)
                        .tint(AppConstants.Colors.accessibleYellow)
                }
            }
            .navigationTitle("New HQ Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createRoom() }
                        .fontWeight(.bold)
                        .disabled(roomName.trimmed.isEmpty || model.isCreating || !accessPolicy.canCreateHQRoom)
                }
            }
            .task {
                await loadDirectory()
            }
            .onAppear {
                if !accessPolicy.canCreateHQRoom {
                    accessErrorMessage = "Only an HQ Director can create cross-school HQ chats."
                }
            }
        }
    }

    private var hqBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.crop.circle.fill")
                .font(.title2)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("HQ Portfolio Chat")
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                Text("Cross-school conversation across your entire organization.")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
            }
            Spacer()
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(12)
    }

    private var roomPhotoPicker: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            ZStack {
                Circle()
                    .fill(AppConstants.Colors.card)
                    .frame(width: 104, height: 104)
                if let selectedImage {
                    selectedImage
                        .resizable()
                        .scaledToFill()
                        .frame(width: 104, height: 104)
                        .clipShape(Circle())
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.title)
                        Text("Room photo")
                            .font(.caption)
                    }
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))
                }
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImageData = data
                    selectedImage = Image(uiImage: image)
                }
            }
        }
    }

    private var roomFields: some View {
        VStack(spacing: 14) {
            labeledCard("Room name") {
                TextField("E.g., All Campus Leaders, Summer Transition…", text: $roomName)
            }
            labeledCard("Description") {
                TextField("What is this cross-school conversation for?", text: $roomDescription, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
    }

    private var memberPicker: some View {
        labeledCard("Members · \(selectedMemberIds.count) selected") {
            VStack(spacing: 14) {
                // Campus Selector
                HStack {
                    Text("Campus:")
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.secondaryText)
                    Spacer()
                    Picker("Campus", selection: $selectedCampusId) {
                        Text("All Campuses").tag(nil as UUID?)
                        ForEach(availableSchools) { school in
                            Text(school.name).tag(school.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppConstants.Colors.accessibleYellow)
                }

                // Role Filter
                Picker("Role", selection: $roleFilter) {
                    Text("All").tag("all")
                    Text("Staff").tag("staff")
                    Text("Parents").tag("parent")
                    Text("HQ").tag("hq_director")
                }
                .pickerStyle(.segmented)

                // Search field
                TextField("Search directory by name, role, or school", text: $memberSearch)
                    .textFieldStyle(.roundedBorder)

                // Privacy Notice Banner if parents are selected
                if selectedBreakdown.parentCount > 0 {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(AppConstants.Colors.accessibleYellow)
                            .font(.subheadline)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Parent Privacy Opt-In")
                                .font(.caption.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Text("Staff join directly. Parents will receive an invitation banner and will not see chat history or appear to others until they accept.")
                                .font(.caption2)
                                .foregroundColor(AppConstants.Colors.secondaryText)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppConstants.Colors.accessibleYellow.opacity(0.12))
                    .cornerRadius(8)
                }

                // Member rows
                if model.directoryPhase.isLoading {
                    ProgressView()
                        .tint(AppConstants.Colors.accessibleYellow)
                        .padding(.vertical, 8)
                } else if filteredDirectory.isEmpty {
                    Text("No matching people found")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.secondaryText)
                        .padding(.vertical, 8)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredDirectory) { member in
                            Button {
                                if selectedMemberIds.contains(member.userId) {
                                    selectedMemberIds.remove(member.userId)
                                } else {
                                    selectedMemberIds.insert(member.userId)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedMemberIds.contains(member.userId) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(AppConstants.Colors.accessibleYellow)
                                        .font(.title3)

                                    ZStack {
                                        Circle()
                                            .fill(AppConstants.Colors.accessibleYellow.opacity(0.15))
                                            .frame(width: 36, height: 36)
                                        Text(member.initials)
                                            .font(.caption.bold())
                                            .foregroundColor(AppConstants.Colors.accessibleYellow)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(member.displayName)
                                            .font(.subheadline.bold())
                                            .foregroundColor(AppConstants.Colors.primaryText)
                                        HStack(spacing: 4) {
                                            Text(member.roleTitle)
                                                .font(.caption)
                                                .foregroundColor(AppConstants.Colors.secondaryText)
                                            Text("•")
                                                .font(.caption)
                                                .foregroundColor(AppConstants.Colors.secondaryText)
                                            Text(member.schoolName)
                                                .font(.caption)
                                                .foregroundColor(AppConstants.Colors.secondaryText)

                                            if member.role == "parent" {
                                                Text("Invite")
                                                    .font(.system(size: 9, weight: .semibold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1.5)
                                                    .background(Color.blue.opacity(0.18))
                                                    .foregroundColor(.blue)
                                                    .cornerRadius(4)
                                            }
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func labeledCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.bold()).foregroundColor(AppConstants.Colors.accessibleYellow)
            content().foregroundColor(AppConstants.Colors.primaryText).tint(AppConstants.Colors.accessibleYellow)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card)
        .cornerRadius(12)
    }

    @MainActor
    private func loadDirectory() async {
        await model.loadDirectory(excluding: appSession.profile?.id)
        if let myId = appSession.profile?.id {
            selectedMemberIds.remove(myId)
        }
    }

    private func createRoom() {
        guard accessPolicy.canCreateHQRoom else {
            accessErrorMessage = "Only an HQ Director can create this chat."
            return
        }
        accessErrorMessage = nil
        Task {
            let created = await model.create(
                name: roomName,
                description: roomDescription,
                participantIds: selectedMemberIds,
                profileImageData: selectedImageData
            )
            if created {
                onRoomCreated()
                dismiss()
            }
        }
    }
}
