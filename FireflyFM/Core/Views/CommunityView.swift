//
//  CommunityView.swift
//  FireflyFM
//

import SwiftUI
import UniformTypeIdentifiers

struct CommunityView: View {
    let school: School

    @EnvironmentObject private var appSession: AppSessionManager

    @State private var selectedTab: CommunityTab = .posts
    @State private var posts: [CommunityPost] = []
    @State private var events: [SchoolEvent] = []
    @State private var albums: [CommunityAlbum] = []
    @State private var members: [SchoolMember] = []
    @State private var profilesById: [UUID: UserProfile] = [:]
    @State private var showingPostComposer = false
    @State private var showingEventComposer = false
    @State private var showingAlbumComposer = false
    @State private var showingInviteSheet = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var canCompose: Bool {
        appSession.role?.canManageSchool == true || appSession.role == .teacher
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppConstants.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    communityHeader
                    actionRow
                    tabBar
                    tabContent

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 88)
            }
            .refreshable { await load() }

            if selectedTab != .info && canCompose {
                Button {
                    showComposerForCurrentTab()
                } label: {
                    Image(systemName: floatingButtonIcon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 62, height: 62)
                        .background(AppConstants.Colors.accessibleYellow)
                        .clipShape(Circle())
                        .shadow(color: AppConstants.Colors.accessibleYellow.opacity(0.28), radius: 12, y: 6)
                }
                .padding()
            }
        }
        .toolbarBackground(AppConstants.Colors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPostComposer) {
            CommunityPostComposerView(school: school) {
                Task { await loadPosts() }
            }
        }
        .sheet(isPresented: $showingEventComposer) {
            CommunityEventComposerView(school: school) {
                Task { await loadEvents() }
            }
        }
        .sheet(isPresented: $showingAlbumComposer) {
            CommunityAlbumComposerView(school: school) {
                Task { await loadAlbums() }
            }
        }
        .sheet(isPresented: $showingInviteSheet) {
            CommunityInviteSheet(school: school)
        }
        .task { await load() }
    }

    private var communityHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                SchoolAvatarView(school: school, size: 86)

                Spacer()

                HStack(spacing: 18) {
                    Image(systemName: "magnifyingglass")
                    Image(systemName: "bubble.left.and.bubble.right")
                    Image(systemName: "gearshape")
                }
                .font(.system(size: 23, weight: .semibold))
                .foregroundColor(.white.opacity(0.86))
            }

            if canCompose {
                Button {
                    showingPostComposer = true
                } label: {
                    HStack(spacing: 8) {
                        Text("Share a thought")
                            .font(.subheadline.bold())
                        Image(systemName: "pencil")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppConstants.Colors.card.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(style: StrokeStyle(lineWidth: 1.4, dash: [4, 4]))
                            .foregroundColor(.white.opacity(0.28))
                    )
                    .cornerRadius(18)
                }
                .buttonStyle(.plain)
            }

            Text(school.name)
                .font(.largeTitle.bold())
                .foregroundColor(.white)

            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text("Public")
                Text("·")
                Text("Admin FireflyFM")
            }
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.62))
        }
        .padding(.top, 8)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            NavigationLink {
                MemberSearchView(school: school)
            } label: {
                Label("\(members.count) Members", systemImage: "person.2.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CommunityActionButtonStyle())

            Button {
                showingInviteSheet = true
            } label: {
                Label("Invite", systemImage: "envelope.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CommunityActionButtonStyle())

            Button {
                Task { await queueReflectionPreview() }
            } label: {
                Image(systemName: "bell.fill")
                    .frame(width: 54)
            }
            .buttonStyle(CommunityActionButtonStyle())
        }
    }

    private var tabBar: some View {
        HStack {
            ForEach(CommunityTab.allCases) { tab in
                Button {
                    withAnimation(.snappy) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(tab.title)
                            .font(.headline)
                            .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.48))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(selectedTab == tab ? AppConstants.Colors.accessibleYellow : .clear)
                            .frame(height: 4)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if isLoading {
            ProgressView()
                .tint(AppConstants.Colors.accessibleYellow)
                .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            switch selectedTab {
            case .posts:
                postsContent
            case .events:
                eventsContent
            case .albums:
                albumsContent
            case .info:
                infoContent
            }
        }
    }

    private var postsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if posts.isEmpty {
                communityEmptyState(
                    icon: "square.and.pencil",
                    title: "Community Board",
                    message: "School-wide posts will appear here.",
                    actionTitle: canCompose ? "Write First Post" : nil,
                    action: { showingPostComposer = true }
                )
            } else {
                ForEach(posts) { post in
                    CommunityPostCard(post: post, profile: post.createdBy.flatMap { profilesById[$0] })
                }
            }
        }
    }

    private var eventsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if events.isEmpty {
                communityEmptyState(
                    icon: "calendar.badge.plus",
                    title: "No Events Yet",
                    message: "Events created here also live in the school's Events tab.",
                    actionTitle: canCompose ? "Create Event" : nil,
                    action: { showingEventComposer = true }
                )
            } else {
                ForEach(events.prefix(12)) { event in
                    CommunityEventCard(event: event, profile: event.createdBy.flatMap { profilesById[$0] })
                }
            }
        }
    }

    private var albumsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if albums.isEmpty {
                communityEmptyState(
                    icon: "photo.on.rectangle.angled",
                    title: "Albums",
                    message: "Shared school photo collections will appear here.",
                    actionTitle: canCompose ? "Create Album" : nil,
                    action: { showingAlbumComposer = true }
                )
            } else {
                ForEach(albums) { album in
                    CommunityAlbumCard(album: album)
                }
            }
        }
    }

    private var infoContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            communityInfoCard("School", text: school.name, icon: "building.2.fill")
            if let description = school.description, !description.isEmpty {
                communityInfoCard("Description", text: description, icon: "text.alignleft")
            }
            if let tourUrl = school.tourUrl, !tourUrl.isEmpty {
                communityInfoCard("Tour", text: tourUrl, icon: "calendar")
            }
            communityInfoCard("Privacy", text: "Posts, albums, events, and members are scoped to this school.", icon: "lock.fill")
        }
    }

    private var floatingButtonIcon: String {
        switch selectedTab {
        case .posts: "pencil"
        case .events: "calendar.badge.plus"
        case .albums: "photo.badge.plus"
        case .info: "pencil"
        }
    }

    private func communityEmptyState(icon: String, title: String, message: String, actionTitle: String?, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(.white.opacity(0.22))
            Text(title)
                .font(.title2.bold())
                .foregroundColor(.white)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.58))
                .multilineTextAlignment(.center)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(AppConstants.Colors.accessibleYellow)
                    .cornerRadius(22)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding()
    }

    private func communityInfoCard(_ title: String, text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.68))
            }
            Spacer()
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private func showComposerForCurrentTab() {
        switch selectedTab {
        case .posts: showingPostComposer = true
        case .events: showingEventComposer = true
        case .albums: showingAlbumComposer = true
        case .info: break
        }
    }

    private func queueReflectionPreview() async {
        await MainActor.run {
            errorMessage = "Today's Firefly Reflection queue is ready for server scheduling; APNs delivery comes after Apple credentials are configured."
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil

        do {
            async let loadedPosts = SchoolWorkflowService.shared.fetchCommunityPosts(schoolId: school.id)
            async let loadedEvents = SchoolWorkflowService.shared.fetchEvents(schoolId: school.id)
            async let loadedAlbums = SchoolWorkflowService.shared.fetchCommunityAlbums(schoolId: school.id)
            async let loadedMembers = SchoolService.shared.fetchMembers(schoolId: school.id)

            posts = try await loadedPosts
            events = try await loadedEvents
            albums = try await loadedAlbums
            members = try await loadedMembers

            let profileIds = Set(posts.compactMap(\.createdBy) + events.compactMap(\.createdBy))
            profilesById = try await ProfileService.shared.fetchProfiles(ids: Array(profileIds))
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load community", error)
            isLoading = false
        }
    }

    @MainActor
    private func loadPosts() async {
        do {
            posts = try await SchoolWorkflowService.shared.fetchCommunityPosts(schoolId: school.id)
            profilesById = try await ProfileService.shared.fetchProfiles(ids: Array(Set(posts.compactMap(\.createdBy) + events.compactMap(\.createdBy))))
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = AppErrorMessage.school("Could not load posts", error)
        }
    }

    @MainActor
    private func loadEvents() async {
        do {
            events = try await SchoolWorkflowService.shared.fetchEvents(schoolId: school.id)
            profilesById = try await ProfileService.shared.fetchProfiles(ids: Array(Set(posts.compactMap(\.createdBy) + events.compactMap(\.createdBy))))
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = AppErrorMessage.school("Could not load events", error)
        }
    }

    @MainActor
    private func loadAlbums() async {
        do {
            albums = try await SchoolWorkflowService.shared.fetchCommunityAlbums(schoolId: school.id)
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = AppErrorMessage.school("Could not load albums", error)
        }
    }
}

private enum CommunityTab: String, CaseIterable, Identifiable {
    case posts
    case events
    case albums
    case info

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct CommunityPostCard: View {
    let post: CommunityPost
    let profile: UserProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CommunityProfileAvatar(profile: profile, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile?.displayName ?? "School Member")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    if let createdAt = post.createdAt {
                        Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
            }
            Text(post.body)
                .font(.body)
                .foregroundColor(.white.opacity(0.78))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }
}

private struct CommunityEventCard: View {
    let event: SchoolEvent
    let profile: UserProfile?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(event.startAt.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2.bold())
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                Text(event.startAt.formatted(.dateTime.day()))
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }
            .frame(width: 52, height: 56)
            .background(AppConstants.Colors.background.opacity(0.48))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(event.allDay ? "All-day" : event.startAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                if let description = event.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.66))
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    CommunityProfileAvatar(profile: profile, size: 22)
                    Text(profile?.displayName ?? "School Staff")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }
}

private struct CommunityAlbumCard: View {
    let album: CommunityAlbum

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppConstants.Colors.background.opacity(0.5))
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "photo.on.rectangle")
                        .foregroundColor(AppConstants.Colors.accessibleYellow)
                )
            VStack(alignment: .leading, spacing: 6) {
                Text(album.title)
                    .font(.headline)
                    .foregroundColor(.white)
                if let description = album.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(2)
                }
                if let createdAt = album.createdAt {
                    Text(createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.42))
                }
            }
            Spacer()
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }
}

struct CommunityProfileAvatar: View {
    let profile: UserProfile?
    let size: CGFloat

    var body: some View {
        Group {
            if let avatarUrl = profile?.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        Circle()
            .fill(Color.white.opacity(0.14))
            .overlay(
                Text(profile?.initials ?? "?")
                    .font(.system(size: max(10, size * 0.34), weight: .bold))
                    .foregroundColor(.white)
            )
    }
}

private struct CommunityPostComposerView: View {
    @Environment(\.dismiss) private var dismiss

    let school: School
    var onSaved: () -> Void

    @State private var bodyText = ""
    @State private var imageURL: URL?
    @State private var showingImporter = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Post") {
                    TextField("Share a thought", text: $bodyText, axis: .vertical)
                        .lineLimit(5...10)
                    Button(imageURL?.lastPathComponent ?? "Attach image") {
                        showingImporter = true
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("New Post")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Posting" : "Post") { save() }
                        .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                imageURL = try? result.get().first
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await SchoolWorkflowService.shared.createCommunityPost(
                    schoolId: school.id,
                    body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                    imageURL: imageURL
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not create post", error)
                }
            }
        }
    }
}

private struct CommunityEventComposerView: View {
    @Environment(\.dismiss) private var dismiss

    let school: School
    var onSaved: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var allDay = false
    @State private var startAt = Date()
    @State private var endAt = Date().addingTimeInterval(3600)
    @State private var shareAsNotification = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                    Toggle("All-day", isOn: $allDay)
                    DatePicker("Starts", selection: $startAt, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $endAt, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    Toggle("Share as notification", isOn: $shareAsNotification)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("New Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let members = shareAsNotification ? try await SchoolService.shared.fetchMembers(schoolId: school.id) : []
                try await SchoolWorkflowService.shared.createEvent(
                    schoolId: school.id,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                    startAt: startAt,
                    endAt: endAt,
                    allDay: allDay,
                    invitedUserIds: members.map(\.id),
                    shareAsNotification: shareAsNotification
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not create event", error)
                }
            }
        }
    }
}

private struct CommunityAlbumComposerView: View {
    @Environment(\.dismiss) private var dismiss

    let school: School
    var onSaved: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var coverURL: URL?
    @State private var showingImporter = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Album") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                    Button(coverURL?.lastPathComponent ?? "Choose cover photo") {
                        showingImporter = true
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("New Album")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                coverURL = try? result.get().first
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await SchoolWorkflowService.shared.createCommunityAlbum(
                    schoolId: school.id,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                    coverURL: coverURL
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not create album", error)
                }
            }
        }
    }
}

private struct CommunityInviteSheet: View {
    @Environment(\.dismiss) private var dismiss

    let school: School

    @State private var selectedRole: SchoolRole = .parent
    @State private var invite: SchoolInvite?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var inviteURL: String? {
        invite.map { "fireflyfm://school?code=\($0.code)" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite") {
                    Picker("Role", selection: $selectedRole) {
                        Text("Parent").tag(SchoolRole.parent)
                        Text("Teacher").tag(SchoolRole.teacher)
                    }
                    Button(isSaving ? "Creating" : "Create invite link") {
                        createInvite()
                    }
                    .disabled(isSaving)
                }

                if let invite {
                    Section("Share") {
                        Text(inviteURL ?? invite.code)
                            .font(.footnote.monospaced())
                        ShareLink(item: inviteURL ?? invite.code) {
                            Label("Share invite", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("Invite Members")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func createInvite() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let created = try await SchoolService.shared.createInvite(schoolId: school.id, role: selectedRole, maxUses: 1)
                await MainActor.run {
                    invite = created
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not create invite", error)
                }
            }
        }
    }
}

struct MemberSearchView: View {
    let school: School

    @State private var query = ""
    @State private var members: [SchoolMember] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var filteredMembers: [SchoolMember] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return members }
        return members.filter {
            $0.displayName.lowercased().contains(trimmed)
            || $0.membership.role.title.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            VStack(spacing: 12) {
                TextField("Search members", text: $query)
                    .padding(12)
                    .background(AppConstants.Colors.card)
                    .cornerRadius(8)
                    .foregroundColor(.white)
                    .tint(AppConstants.Colors.accessibleYellow)
                    .padding(.horizontal)

                if isLoading {
                    ProgressView()
                        .tint(AppConstants.Colors.accessibleYellow)
                        .padding()
                } else if filteredMembers.isEmpty {
                    Text("No members found.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.56))
                        .padding()
                } else {
                    List(filteredMembers) { member in
                        HStack(spacing: 12) {
                            CommunityProfileAvatar(profile: member.profile, size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(member.displayName)
                                    .font(.headline)
                                Text(member.membership.role.title)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .listRowBackground(AppConstants.Colors.card)
                    }
                    .scrollContentBackground(.hidden)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Members")
        .task { await loadMembers() }
    }

    @MainActor
    private func loadMembers() async {
        isLoading = true
        errorMessage = nil
        do {
            members = try await SchoolService.shared.fetchMembers(schoolId: school.id)
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load members", error)
            isLoading = false
        }
    }
}

private struct CommunityActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.vertical, 15)
            .background(AppConstants.Colors.card.opacity(configuration.isPressed ? 0.72 : 1))
            .cornerRadius(8)
    }
}

#Preview {
    NavigationStack {
        CommunityView(school: School(id: UUID(), name: "Firefly Montessori", description: nil, tourUrl: nil, profileImageUrl: nil, createdAt: nil, updatedAt: nil))
            .environmentObject(AppSessionManager())
    }
}
