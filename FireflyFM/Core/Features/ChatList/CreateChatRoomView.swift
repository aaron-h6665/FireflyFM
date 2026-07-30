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
    @State private var model = CreateChatRoomModel()
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var memberSearch = ""
    @State private var roleFilter = "all"
    @State private var accessErrorMessage: String?

    var fixedSchool: School?
    var onRoomCreated: () -> Void

    private var accessPolicy: ChatAccessPolicy {
        ChatAccessPolicy(context: appSession.accessContext(selectedSchoolId: selectedSchoolId))
    }

    private var filteredDirectory: [SchoolDirectoryEntry] {
        let query = memberSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.directory.filter { member in
            (roleFilter == "all" || member.schoolRole.rawValue == roleFilter)
                && (query.isEmpty || member.displayName.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        roomPhotoPicker
                        schoolPicker
                        roomFields
                        memberPicker

                        if let errorMessage = model.errorMessage ?? accessErrorMessage {
                            Text(errorMessage).font(.caption).foregroundColor(.red)
                        }
                    }
                    .padding()
                }

                if model.isCreating {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView("Creating room…")
                        .padding()
                        .background(AppConstants.Colors.card)
                        .cornerRadius(12)
                        .tint(AppConstants.Colors.accessibleYellow)
                }
            }
            .navigationTitle("New School Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createRoom() }
                        .fontWeight(.bold)
                        .disabled(roomName.trimmed.isEmpty || model.isCreating || selectedSchoolId == nil)
                }
            }
            .task(id: selectedSchoolId) { await loadDirectory() }
            .onAppear {
                selectedMembershipId = appSession.activeMembershipId
                if accessPolicy.canCreateSchoolRoom == false {
                    accessErrorMessage = "Only a school director can create and manage group chats."
                }
            }
        }
    }

    private var roomPhotoPicker: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            ZStack {
                Circle().fill(AppConstants.Colors.card).frame(width: 104, height: 104)
                if let selectedImage {
                    selectedImage.resizable().scaledToFill().frame(width: 104, height: 104).clipShape(Circle())
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.title)
                        Text("Room photo").font(.caption)
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

    @ViewBuilder
    private var schoolPicker: some View {
        if let fixedSchool {
            labeledCard("School") {
                HStack { SchoolAvatarView(school: fixedSchool, size: 34); Text(fixedSchool.name).font(.headline); Spacer() }
            }
        } else if appSession.canSwitchSchools {
            labeledCard("School") {
                Picker("School", selection: $selectedMembershipId) {
                    ForEach(appSession.memberships.filter { $0.membership.role.has(.createSchoolChats) }) { context in
                        Text(context.school.name).tag(Optional(context.membership.id))
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var roomFields: some View {
        VStack(spacing: 14) {
            labeledCard("Room name") {
                TextField("Family updates, Garden project…", text: $roomName)
            }
            labeledCard("Description") {
                TextField("What is this group for?", text: $roomDescription, axis: .vertical).lineLimit(2...5)
            }
        }
    }

    private var memberPicker: some View {
        labeledCard("Members · \(selectedMemberIds.count) selected") {
            VStack(spacing: 12) {
                TextField("Search parents and teachers", text: $memberSearch)
                    .textFieldStyle(.roundedBorder)
                Picker("Role", selection: $roleFilter) {
                    Text("All").tag("all")
                    Text("Teachers").tag(SchoolRole.teacher.rawValue)
                    Text("Parents").tag(SchoolRole.parent.rawValue)
                    Text("Directors").tag(SchoolRole.schoolDirector.rawValue)
                }
                .pickerStyle(.segmented)

                if model.directoryPhase.isLoading {
                    ProgressView().tint(AppConstants.Colors.accessibleYellow)
                } else {
                    ForEach(filteredDirectory) { member in
                        Button {
                            if selectedMemberIds.contains(member.id) { selectedMemberIds.remove(member.id) }
                            else { selectedMemberIds.insert(member.id) }
                        } label: {
                            HStack {
                                Image(systemName: selectedMemberIds.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                                VStack(alignment: .leading) {
                                    Text(member.displayName).foregroundColor(AppConstants.Colors.primaryText)
                                    Text(member.schoolRole.title).font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
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
        guard let schoolId = selectedSchoolId else { return }
        await model.loadDirectory(schoolId: schoolId, excluding: appSession.profile?.id)
        if let myId = appSession.profile?.id { selectedMemberIds.remove(myId) }
    }

    private func createRoom() {
        guard accessPolicy.canCreateSchoolRoom, let schoolId = selectedSchoolId else {
            accessErrorMessage = "Only a school director can create a chat."
            return
        }
        accessErrorMessage = nil
        Task {
            let created = await model.create(
                schoolId: schoolId,
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

    private var selectedSchoolId: UUID? {
        if let fixedSchool { return fixedSchool.id }
        guard let selectedMembershipId else { return appSession.activeSchool?.id }
        return appSession.memberships.first(where: { $0.membership.id == selectedMembershipId })?.school.id
    }
}

#Preview { CreateChatRoomView(onRoomCreated: {}) }
