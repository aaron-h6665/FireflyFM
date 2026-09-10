//
//  CommunityView.swift
//  FireflyFM
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import UIKit
import AVKit

struct CommunityView: View {
    let school: School

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var displaySchool: School
    @State private var selectedTab: CommunityTab = .posts
    @State private var model = CommunityModel()
    @State private var eventModel = EventCatalogModel()
    @State private var eventDisplayMode: EventDisplayMode = .list
    @State private var eventDisplayMonth = Date()
    @State private var eventSelectedDate = Date()
    @State private var showingPostComposer = false
    @State private var showingEventComposer = false
    @State private var showingAlbumComposer = false
    @State private var showingPhotoUpload = false
    @State private var showingInviteSheet = false
    @State private var showingCommunitySearch = false
    @State private var showingSchoolChats = false
    @State private var showingSchoolSettings = false
    @State private var editingPost: CommunityPost?
    @State private var editingEvent: SchoolEvent?
    @State private var deletingEvent: SchoolEvent?

    init(school: School) {
        self.school = school
        _displaySchool = State(initialValue: school)
    }

    private var canCompose: Bool {
        appSession.accessContext(selectedSchoolId: school.id).has(.composeCommunity)
    }

    private var canManageSchool: Bool {
        let context = appSession.accessContext(selectedSchoolId: school.id)
        return context.has(.manageMemberOnboarding) || context.has(.manageSchools)
    }

    private var events: [SchoolEvent] { eventModel.events }
    private var members: [SchoolMember] { eventModel.members }
    private var posts: [CommunityPost] { model.posts }
    private var albums: [CommunityAlbum] { model.albums }
    private var albumMediaById: [UUID: [CommunityAlbumMedia]] { model.albumMediaById }
    private var directory: [SchoolDirectoryEntry] { model.directory }
    private var profilesById: [UUID: UserProfile] { model.profilesById }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppConstants.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    communityHeader
                    actionRow
                    tabBar
                    tabContent

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    if let message = eventModel.mutationError {
                        FireflyInlineError(message: message)
                    }
                    if case .failed(let message) = eventModel.phase {
                        FireflyInlineError(message: message)
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
                        .foregroundColor(AppConstants.Colors.brandNavy)
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
            CommunityPostComposerView(school: displaySchool, events: events) {
                Task { await loadPosts() }
            }
        }
        .sheet(isPresented: $showingEventComposer) {
            SchoolEventEditorView(schoolId: displaySchool.id, members: members, event: nil) {
                Task { await loadEvents() }
            }
        }
        .sheet(isPresented: $showingAlbumComposer) {
            CommunityAlbumComposerView(school: displaySchool, albums: albums) {
                Task { await loadAlbums() }
            }
        }
        .sheet(isPresented: $showingPhotoUpload) {
            CommunityAlbumComposerView(school: displaySchool, albums: albums, startsWithPhotoPicker: true) {
                Task { await loadAlbums() }
            }
        }
        .sheet(isPresented: $showingInviteSheet) {
            CommunityInviteSheet(school: displaySchool)
        }
        .sheet(isPresented: $showingCommunitySearch) {
            CommunitySearchView(
                school: displaySchool,
                posts: posts,
                events: events,
                albums: albums,
                directory: directory,
                profilesById: profilesById
            )
        }
        .sheet(isPresented: $showingSchoolChats) {
            SchoolChatRoomsView(school: displaySchool)
        }
        .sheet(isPresented: $showingSchoolSettings) {
            if canManageSchool {
                SchoolEditView(school: displaySchool) { updated in
                    displaySchool = updated
                }
            } else {
                SchoolInfoSheet(school: displaySchool)
            }
        }
        .sheet(item: $editingPost) { post in
            CommunityPostEditorView(post: post, events: events) {
                Task { await loadPosts() }
            }
        }
        .sheet(item: $editingEvent) { event in
            SchoolEventEditorView(schoolId: event.schoolId, members: members, event: event) {
                Task { await loadEvents() }
            }
        }
        .confirmationDialog(
            "Delete this event?",
            isPresented: Binding(
                get: { deletingEvent != nil },
                set: { if !$0 { deletingEvent = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Event", role: .destructive) {
                deletePendingEvent()
            }
            Button("Cancel", role: .cancel) {
                deletingEvent = nil
            }
        } message: {
            Text("This removes the event from the school calendar for everyone.")
        }
        .task(id: appSession.activeMembershipId) {
            await load()
            await startCommunityPostsChannel()
        }
        .onDisappear {
            Task { await stopCommunityPostsChannel() }
        }
    }

    private var communityHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                SchoolAvatarView(school: displaySchool, size: 86)

                Spacer()

                HStack(spacing: 18) {
                    Button {
                        showingCommunitySearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    Button {
                        showingSchoolChats = true
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right")
                    }
                    Button {
                        showingSchoolSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                .font(.system(size: 23, weight: .semibold))
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.86))
                .buttonStyle(.plain)
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
                    .foregroundColor(AppConstants.Colors.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppConstants.Colors.card.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(style: StrokeStyle(lineWidth: 1.4, dash: [4, 4]))
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.28))
                    )
                    .cornerRadius(18)
                }
                .buttonStyle(.plain)
            }

            Text(displaySchool.name)
                .font(.largeTitle.bold())
                .foregroundColor(AppConstants.Colors.primaryText)

            Label("Private school community", systemImage: "lock.fill")
            .font(.subheadline)
            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
        }
        .padding(.top, 8)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            NavigationLink {
                MemberSearchView(school: displaySchool)
            } label: {
                Label("\(directory.count) Members", systemImage: "person.2.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CommunityActionButtonStyle())

            if canManageSchool {
                Button {
                    showingInviteSheet = true
                } label: {
                    Label("Invite", systemImage: "envelope.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CommunityActionButtonStyle())
            }

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
            ForEach(CommunityTab.navigationCases) { tab in
                Button {
                    if reduceMotion {
                        selectedTab = tab
                    } else {
                        withAnimation(.snappy) {
                            selectedTab = tab
                        }
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(tab.title)
                            .font(.headline)
                            .foregroundColor(selectedTab == tab ? AppConstants.Colors.primaryAction : AppConstants.Colors.secondaryText)
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
        if model.phase.isLoading {
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
                    Button {
                        if canCompose {
                            editingPost = post
                        }
                    } label: {
                        CommunityPostCard(post: post, profile: post.createdBy.flatMap { profilesById[$0] })
                    }
                    .buttonStyle(.plain)
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
                Picker("Event View", selection: $eventDisplayMode) {
                    Text("List").tag(EventDisplayMode.list)
                    Text("Calendar").tag(EventDisplayMode.calendar)
                }
                .pickerStyle(.segmented)

                if eventDisplayMode == .list {
                    ForEach(communityMonthGroups(for: events)) { group in
                        communityMonthSection(group)
                    }
                } else {
                    CalendarMonthView(
                        displayMonth: $eventDisplayMonth,
                        selectedDate: $eventSelectedDate,
                        events: events
                    )

                    let monthEvents = events.filter { Calendar.current.isDate($0.startAt, equalTo: eventDisplayMonth, toGranularity: .month) }
                    if monthEvents.isEmpty {
                        communityInfoCard("No events", text: "No events in \(eventDisplayMonth.formatted(.dateTime.month(.wide))).", icon: "calendar")
                    } else {
                        ForEach(communityMonthGroups(for: monthEvents)) { group in
                            communityMonthSection(group)
                        }
                    }
                }
            }
        }
    }

    private var albumsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if canCompose {
                HStack(spacing: 10) {
                    Button {
                        showingAlbumComposer = true
                    } label: {
                        Label("Create Album", systemImage: "rectangle.stack.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CommunityActionButtonStyle())

                    Button {
                        showingPhotoUpload = true
                    } label: {
                        Label("Add Photos", systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CommunityActionButtonStyle())
                }
            }

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
                    NavigationLink {
                        CommunityAlbumDetailView(
                            school: displaySchool,
                            album: album,
                            initialMedia: albumMediaById[album.id] ?? [],
                            canAddMedia: canCompose
                        ) {
                            Task { await loadAlbums() }
                        }
                    } label: {
                        CommunityAlbumCard(album: album, media: albumMediaById[album.id] ?? [])
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var infoContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            communityInfoCard("School", text: displaySchool.name, icon: "building.2.fill")
            if let description = displaySchool.description, !description.isEmpty {
                communityInfoCard("Description", text: description, icon: "text.alignleft")
            }
            if let tourUrl = displaySchool.tourUrl, !tourUrl.isEmpty {
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
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.22))
            Text(title)
                .font(.title2.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
                .multilineTextAlignment(.center)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.brandNavy)
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
                    .foregroundColor(AppConstants.Colors.primaryText)
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.68))
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

    private func communityMonthSection(_ group: EventMonthGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title)
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            ForEach(group.events) { event in
                Button {
                    if canCompose {
                        editingEvent = event
                    }
                } label: {
                    EventCardView(event: event, creator: event.createdBy.flatMap { profilesById[$0] })
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if canCompose {
                        Button {
                            editingEvent = event
                        } label: {
                            Label("Edit Event", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deletingEvent = event
                        } label: {
                            Label("Delete Event", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func communityMonthGroups(for events: [SchoolEvent]) -> [EventMonthGroup] {
        eventModel.monthGroups(for: events)
    }

    private func queueReflectionPreview() async {
        await MainActor.run {
            model.showMessage("Today's Firefly Reflection queue is ready for server scheduling; APNs delivery comes after Apple credentials are configured.")
        }
    }

    private func deletePendingEvent() {
        guard let event = deletingEvent else { return }
        deletingEvent = nil
        Task { await eventModel.delete(event) }
    }

    @MainActor
    private func load() async {
        await eventModel.load(schoolId: school.id, canManage: canCompose, includeArchived: false)
        await model.load(schoolId: school.id, events: events)
    }

    @MainActor
    private func loadPosts() async {
        await model.loadPosts(events: events)
    }

    @MainActor
    private func startCommunityPostsChannel() async {
        await model.startRealtime()
    }

    @MainActor
    private func stopCommunityPostsChannel() async {
        await model.stopRealtime()
    }

    @MainActor
    private func loadEvents() async {
        await eventModel.load(schoolId: school.id, canManage: canCompose, includeArchived: false)
        await model.refreshProfiles(events: events)
    }

    @MainActor
    private func loadAlbums() async {
        await model.loadAlbums()
    }

    @MainActor
    private func refreshAuthorProfiles() async {
        await model.refreshProfiles(events: events)
    }
}

private enum CommunityTab: String, CaseIterable, Identifiable {
    case posts
    case events
    case albums
    case info

    var id: String { rawValue }
    static let navigationCases: [CommunityTab] = [.posts, .albums, .info]

    var title: String {
        switch self {
        case .posts: "Feed"
        case .events: "Events"
        case .albums: "Albums"
        case .info: "About"
        }
    }
}

struct CommunityPostCard: View {
    let post: CommunityPost
    let profile: UserProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imagePath = post.imagePath ?? (post.attachmentType?.hasPrefix("image/") == true ? post.attachmentPath : nil) {
                CommunityPostImage(path: imagePath, accessibilityLabel: post.attachmentName ?? "Community post image")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("COMMUNITY UPDATE")
                    .font(.caption2.bold())
                    .tracking(1.1)
                    .foregroundColor(AppConstants.Colors.primaryAction)

                HStack(spacing: 10) {
                    CommunityProfileAvatar(profile: profile, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile?.displayName ?? "School Member")
                            .font(.subheadline.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        if let createdAt = post.createdAt {
                            Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.45))
                        }
                    }
                    Spacer()
                }

                Text(post.body)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(5)
                    .foregroundColor(AppConstants.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if post.imagePath == nil,
                   post.attachmentType?.hasPrefix("image/") != true,
                   let attachmentName = post.attachmentName ?? post.attachmentPath?.split(separator: "/").last.map(String.init) {
                    Label(attachmentName, systemImage: post.attachmentType?.hasPrefix("video/") == true ? "video.fill" : "paperclip")
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.primaryAction)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppConstants.Colors.raised)
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.controlRadius, style: .continuous))
                }

                if let pollQuestion = post.pollQuestion, !pollQuestion.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(pollQuestion, systemImage: "chart.bar.doc.horizontal")
                            .font(.subheadline.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        ForEach(post.pollOptions ?? [], id: \.self) { option in
                            Text(option)
                                .font(.caption)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(AppConstants.Colors.raised)
                                .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.controlRadius, style: .continuous))
                        }
                    }
                }

                HStack(spacing: 8) {
                    if post.linkedEventId != nil {
                        Label("Event", systemImage: "calendar")
                    }
                    if let scheduledAt = post.scheduledAt {
                        Label(scheduledAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    }
                }
                .font(.caption2.bold())
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.48))
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous)
                .stroke(AppConstants.Colors.separator.opacity(0.7), lineWidth: 1)
        }
    }
}

private struct CommunityPostImage: View {
    let path: String
    let accessibilityLabel: String

    @State private var signedURL: URL?
    private let client = CommunityWorkflowClient.live

    var body: some View {
        AsyncImage(url: signedURL) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            ZStack {
                AppConstants.Colors.raised
                ProgressView().tint(AppConstants.Colors.primaryAction)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .accessibilityLabel(accessibilityLabel)
        .task(id: path) {
            signedURL = try? await client.signedURL(path)
        }
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
                    .foregroundColor(AppConstants.Colors.primaryText)
            }
            .frame(width: 52, height: 56)
            .background(AppConstants.Colors.background.opacity(0.48))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Text(event.allDay ? "All-day" : event.startAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                if let description = event.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    CommunityProfileAvatar(profile: profile, size: 22)
                    Text(profile?.displayName ?? "School Staff")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.5))
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
    let media: [CommunityAlbumMedia]

    var body: some View {
        HStack(spacing: 12) {
            CommunityAlbumMosaicView(media: Array(media.recencySorted().prefix(9)), size: 78)
            VStack(alignment: .leading, spacing: 6) {
                Text(album.title)
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                if let description = album.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                        .lineLimit(2)
                }
                if let createdAt = album.createdAt {
                    Text(createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.42))
                }
                Text("\(media.count) item\(media.count == 1 ? "" : "s")")
                    .font(.caption2.bold())
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.35))
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }
}

private struct CommunityAlbumMosaicView: View {
    let media: [CommunityAlbumMedia]
    let size: CGFloat

    private var cellSize: CGFloat {
        (size - 4) / 3
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        Group {
                            if index < media.count {
                                CommunityMediaThumbnail(media: media[index])
                            } else {
                                Rectangle()
                                    .fill(AppConstants.Colors.background.opacity(0.48))
                            }
                        }
                        .frame(width: cellSize, height: cellSize)
                        .clipped()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct CommunityMediaThumbnail: View {
    let media: CommunityAlbumMedia

    @State private var signedURL: URL?
    private let client = CommunityWorkflowClient.live

    private var isImage: Bool {
        media.contentType?.hasPrefix("image/") != false
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(AppConstants.Colors.background.opacity(0.56))

            if isImage, let signedURL {
                AsyncImage(url: signedURL) { image in
                    GeometryReader { proxy in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    }
                } placeholder: {
                    ProgressView()
                        .tint(AppConstants.Colors.accessibleYellow)
                }
            } else {
                Image(systemName: isImage ? "photo" : "video.fill")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
            }
        }
        .clipped()
        .task(id: media.filePath) {
            guard isImage else { return }
            signedURL = try? await client.signedURL(media.filePath)
        }
    }
}

struct CommunityAlbumDetailView: View {
    let school: School
    let album: CommunityAlbum
    let initialMedia: [CommunityAlbumMedia]
    let canAddMedia: Bool
    var onChanged: () -> Void

    @State private var media: [CommunityAlbumMedia]
    @State private var sortNewestFirst = true
    @State private var viewingMedia: CommunityAlbumMedia?
    @State private var pendingDeleteMedia: CommunityAlbumMedia?
    @State private var showingAddPhotos = false
    @State private var errorMessage: String?
    private let client = CommunityWorkflowClient.live

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var sortedMedia: [CommunityAlbumMedia] {
        media.recencySorted(newestFirst: sortNewestFirst)
    }

    init(
        school: School,
        album: CommunityAlbum,
        initialMedia: [CommunityAlbumMedia],
        canAddMedia: Bool,
        onChanged: @escaping () -> Void
    ) {
        self.school = school
        self.album = album
        self.initialMedia = initialMedia
        self.canAddMedia = canAddMedia
        self.onChanged = onChanged
        _media = State(initialValue: initialMedia)
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CommunityAlbumMosaicView(media: Array(sortedMedia.prefix(9)), size: 160)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(album.title)
                            .font(.largeTitle.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        if let description = album.description, !description.isEmpty {
                            Text(description)
                                .font(.subheadline)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.68))
                        }
                        Text("\(media.count) photo/video item\(media.count == 1 ? "" : "s")")
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.accessibleYellow)
                    }

                    if media.isEmpty == false {
                        Picker("Sort", selection: $sortNewestFirst) {
                            Text("Newest").tag(true)
                            Text("Oldest").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }

                    if media.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 40))
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.24))
                            Text("No photos yet")
                                .font(.headline)
                                .foregroundColor(AppConstants.Colors.primaryText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(sortedMedia) { item in
                                Button {
                                    viewingMedia = item
                                } label: {
                                    CommunityMediaTile(media: item)
                                        .aspectRatio(1, contentMode: .fit)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        saveToPhotos(item)
                                    } label: {
                                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                                    }

                                    if canAddMedia {
                                        Button(role: .destructive) {
                                            pendingDeleteMedia = item
                                        } label: {
                                            Label("Delete Photo", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canAddMedia {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddPhotos = true
                    } label: {
                        Image(systemName: "photo.badge.plus")
                            .foregroundColor(AppConstants.Colors.accessibleYellow)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddPhotos) {
            CommunityAlbumAddMediaView(school: school, album: album) {
                Task { await loadMedia() }
                onChanged()
            }
        }
        .sheet(item: $viewingMedia) { item in
            CommunityMediaViewer(media: item)
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: Binding(
                get: { pendingDeleteMedia != nil },
                set: { if !$0 { pendingDeleteMedia = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Photo", role: .destructive) {
                deletePendingMedia()
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteMedia = nil
            }
        } message: {
            Text("This removes it from the album for everyone in the school.")
        }
        .task { await loadMedia() }
    }

    @MainActor
    private func loadMedia() async {
        do {
            media = try await client.fetchAlbumMedia(album.id)
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = AppErrorMessage.school("Could not load album photos", error)
        }
    }

    private func deletePendingMedia() {
        guard let item = pendingDeleteMedia else { return }
        pendingDeleteMedia = nil
        Task {
            do {
                try await client.deleteAlbumMedia(item)
                await MainActor.run {
                    media.removeAll { $0.id == item.id }
                    onChanged()
                }
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not delete photo", error)
                }
            }
        }
    }

    private func saveToPhotos(_ item: CommunityAlbumMedia) {
        errorMessage = nil
        Task {
            do {
                let url = try await client.signedURL(item.filePath)
                try await MediaLibrarySaver.save(
                    remoteURL: url,
                    contentType: item.contentType,
                    fileName: item.fileName
                )
                await MainActor.run { errorMessage = nil }
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not save media to Photos", error)
                }
            }
        }
    }
}

private struct CommunityMediaTile: View {
    let media: CommunityAlbumMedia

    @State private var signedURL: URL?
    private let client = CommunityWorkflowClient.live

    private var isImage: Bool {
        media.contentType?.hasPrefix("image/") != false
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppConstants.Colors.card)

            if isImage, let signedURL {
                AsyncImage(url: signedURL) { image in
                    GeometryReader { proxy in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    }
                } placeholder: {
                    ProgressView()
                        .tint(AppConstants.Colors.accessibleYellow)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: isImage ? "photo" : "video.fill")
                        .font(.title3)
                    Text(media.fileName ?? (isImage ? "Photo" : "Video"))
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(AppConstants.Colors.accessibleYellow)
                .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: media.filePath) {
            guard isImage else { return }
            signedURL = try? await client.signedURL(media.filePath)
        }
    }
}

private struct CommunityMediaViewer: View {
    let media: CommunityAlbumMedia

    @Environment(\.dismiss) private var dismiss
    @State private var signedURL: URL?
    @State private var videoPlayer: AVPlayer?
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let client = CommunityWorkflowClient.live

    private var isImage: Bool {
        media.contentType?.hasPrefix("image/") != false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if isImage, let signedURL {
                    AsyncImage(url: signedURL) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        ProgressView()
                            .tint(AppConstants.Colors.accessibleYellow)
                    }
                    .padding()
                } else if let videoPlayer {
                    VideoPlayer(player: videoPlayer)
                        .padding()
                } else {
                    ProgressView()
                        .tint(AppConstants.Colors.accessibleYellow)
                }
            }
            .navigationTitle(media.fileName ?? "Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppConstants.Colors.primaryText)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        saveToPhotos()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(signedURL == nil || isSaving)
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                }
            }
            .alert("Could not save media", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
        .task(id: media.filePath) {
            signedURL = try? await client.signedURL(media.filePath)
            if !isImage, let signedURL {
                try? AudioPlaybackSession.activate()
                videoPlayer = AVPlayer(url: signedURL)
            }
        }
    }

    private func saveToPhotos() {
        guard let signedURL else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await MediaLibrarySaver.save(
                    remoteURL: signedURL,
                    contentType: media.contentType,
                    fileName: media.fileName
                )
                await MainActor.run { isSaving = false }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not save media to Photos", error)
                }
            }
        }
    }
}

private struct CommunityAlbumAddMediaView: View {
    @Environment(\.dismiss) private var dismiss

    let school: School
    let album: CommunityAlbum
    var onSaved: () -> Void

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var uploads: [CommunityMediaUpload] = []
    @State private var isLoadingMedia = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let client = CommunityWorkflowClient.live

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(album.title)
                            .font(.title.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Text("Add up to 100 photos or videos to this album.")
                            .font(.subheadline)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))

                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: 100,
                            matching: .any(of: [.images, .videos])
                        ) {
                            Label("Select Photos or Videos", systemImage: "photo.on.rectangle.angled")
                                .font(.headline)
                                .foregroundColor(AppConstants.Colors.brandNavy)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppConstants.Colors.accessibleYellow)
                                .cornerRadius(12)
                        }

                        HStack {
                            Image(systemName: uploads.isEmpty ? "photo" : "checkmark.circle.fill")
                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                            Text(uploads.isEmpty ? "No media selected" : "\(uploads.count) selected")
                                .font(.subheadline.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Spacer()
                        }
                        .padding()
                        .background(AppConstants.Colors.card)
                        .cornerRadius(10)

                        if uploads.isEmpty == false {
                            CommunitySelectedUploadGrid(
                                uploads: uploads,
                                onRemove: removeSelectedMedia,
                                onClear: { selectedItems.removeAll() }
                            )
                        }

                        if isLoadingMedia {
                            ProgressView("Preparing media")
                                .tint(AppConstants.Colors.accessibleYellow)
                                .foregroundColor(AppConstants.Colors.primaryText)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Add Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Uploading" : "Upload") { save() }
                        .disabled(uploads.isEmpty || isLoadingMedia || isSaving)
                }
            }
            .onChange(of: selectedItems) { _, newValue in
                Task { await loadSelectedMedia(newValue) }
            }
        }
    }

    private func loadSelectedMedia(_ items: [PhotosPickerItem]) async {
        await MainActor.run {
            isLoadingMedia = true
            errorMessage = nil
        }

        do {
            var loaded: [CommunityMediaUpload] = []
            for item in items.prefix(100) {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let type = item.supportedContentTypes.first
                let contentType = type?.preferredMIMEType ?? "image/jpeg"
                let ext = type?.preferredFilenameExtension ?? (contentType.hasPrefix("video/") ? "mov" : "jpg")
                let prefix = contentType.hasPrefix("video/") ? "video" : "photo"
                loaded.append(CommunityMediaUpload(
                    data: data,
                    fileName: "\(prefix)-\(UUID().uuidString).\(ext)",
                    contentType: contentType
                ))
            }

            await MainActor.run {
                uploads = loaded
                isLoadingMedia = false
            }
        } catch {
            await MainActor.run {
                isLoadingMedia = false
                errorMessage = AppErrorMessage.school("Could not prepare selected media", error)
            }
        }
    }

    private func removeSelectedMedia(at index: Int) {
        guard selectedItems.indices.contains(index) else { return }
        selectedItems.remove(at: index)
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await client.addAlbumMedia(school.id, album, uploads)
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not upload photos", error)
                }
            }
        }
    }
}

private struct CommunitySelectedUploadGrid: View {
    let uploads: [CommunityMediaUpload]
    var onRemove: ((Int) -> Void)?
    var onClear: (() -> Void)?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Selected Photos")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                Spacer()
                if let onClear {
                    Button("Clear All", role: .destructive) {
                        onClear()
                    }
                    .font(.caption.bold())
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(uploads.enumerated()), id: \.offset) { index, upload in
                    ZStack(alignment: .topTrailing) {
                        CommunityUploadPreview(upload: upload)
                            .aspectRatio(1, contentMode: .fit)

                        if let onRemove {
                            Button {
                                onRemove(index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color.black.opacity(0.72))
                            }
                            .padding(4)
                            .accessibilityLabel("Deselect \(upload.fileName)")
                        }
                    }
                }
            }
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(10)
    }
}

private struct CommunityUploadPreview: View {
    let upload: CommunityMediaUpload

    private var isImage: Bool {
        upload.contentType?.hasPrefix("image/") != false
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppConstants.Colors.background.opacity(0.58))

            if isImage, let image = UIImage(data: upload.data) {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: isImage ? "photo" : "video.fill")
                        .font(.title3)
                    Text(upload.fileName)
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(AppConstants.Colors.accessibleYellow)
                .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension Array where Element == CommunityAlbumMedia {
    func recencySorted(newestFirst: Bool = true) -> [CommunityAlbumMedia] {
        sorted {
            let left = $0.createdAt ?? .distantPast
            let right = $1.createdAt ?? .distantPast
            return newestFirst ? left > right : left < right
        }
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
            .fill(AppConstants.Colors.raised)
            .overlay(
                Text(profile?.initials ?? "?")
                    .font(.system(size: max(10, size * 0.34), weight: .bold))
                    .foregroundColor(AppConstants.Colors.primaryText)
            )
    }
}

private struct DirectoryAvatar: View {
    let entry: SchoolDirectoryEntry
    let size: CGFloat

    var body: some View {
        Group {
            if let avatarURL = entry.avatarUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: { fallback }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        Circle()
            .fill(AppConstants.Colors.raised)
            .overlay(
                Text(entry.displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
                    .font(.system(size: max(10, size * 0.32), weight: .bold))
                    .foregroundColor(AppConstants.Colors.primaryText)
            )
    }
}

private struct CommunitySearchView: View {
    let school: School
    let posts: [CommunityPost]
    let events: [SchoolEvent]
    let albums: [CommunityAlbum]
    let directory: [SchoolDirectoryEntry]
    let profilesById: [UUID: UserProfile]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredPosts: [CommunityPost] {
        guard !trimmedQuery.isEmpty else { return [] }
        return posts.filter { $0.body.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private var filteredEvents: [SchoolEvent] {
        guard !trimmedQuery.isEmpty else { return [] }
        return events.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedQuery)
                || ($0.description?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }

    private var filteredAlbums: [CommunityAlbum] {
        guard !trimmedQuery.isEmpty else { return [] }
        return albums.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedQuery)
                || ($0.description?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }

    private var filteredMembers: [SchoolDirectoryEntry] {
        guard !trimmedQuery.isEmpty else { return [] }
        return directory.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.schoolRole.title.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        FireflySearchField(placeholder: "Search \(school.name)", text: $query)

                        if trimmedQuery.isEmpty {
                            searchEmptyState("Search posts, events, albums, and members.", icon: "magnifyingglass")
                        } else if filteredPosts.isEmpty && filteredEvents.isEmpty && filteredAlbums.isEmpty && filteredMembers.isEmpty {
                            searchEmptyState("No results found.", icon: "questionmark.folder")
                        } else {
                            if filteredPosts.isEmpty == false {
                                searchSection("Posts") {
                                    ForEach(filteredPosts) { post in
                                        CommunitySearchRow(
                                            icon: "text.bubble.fill",
                                            title: post.body,
                                            subtitle: post.createdAt?.formatted(date: .abbreviated, time: .shortened)
                                        )
                                    }
                                }
                            }

                            if filteredEvents.isEmpty == false {
                                searchSection("Events") {
                                    ForEach(filteredEvents) { event in
                                        CommunitySearchRow(
                                            icon: "calendar",
                                            title: event.title,
                                            subtitle: event.startAt.formatted(date: .abbreviated, time: .shortened)
                                        )
                                    }
                                }
                            }

                            if filteredAlbums.isEmpty == false {
                                searchSection("Albums") {
                                    ForEach(filteredAlbums) { album in
                                        CommunitySearchRow(
                                            icon: "photo.on.rectangle",
                                            title: album.title,
                                            subtitle: album.description
                                        )
                                    }
                                }
                            }

                            if filteredMembers.isEmpty == false {
                                searchSection("Members") {
                                    ForEach(filteredMembers) { member in
                                        HStack(spacing: 12) {
                                            DirectoryAvatar(entry: member, size: 34)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(member.displayName)
                                                    .font(.subheadline.bold())
                                                    .foregroundColor(AppConstants.Colors.primaryText)
                                                Text(member.schoolRole.title)
                                                    .font(.caption)
                                                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
                                            }
                                            Spacer()
                                        }
                                        .padding()
                                        .background(AppConstants.Colors.card)
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func searchEmptyState(_ message: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.24))
            Text(message)
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private func searchSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            content()
        }
    }
}

private struct CommunitySearchRow: View {
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }
}

private struct SchoolInfoSheet: View {
    let school: School

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    SchoolAvatarView(school: school, size: 96)
                    Text(school.name)
                        .font(.largeTitle.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                    if let description = school.description, !description.isEmpty {
                        CommunitySearchRow(icon: "text.alignleft", title: "Description", subtitle: description)
                    }
                    CommunitySearchRow(
                        icon: "lock.fill",
                        title: "School privacy",
                        subtitle: "Posts, albums, events, chats, and member lists stay scoped to this school."
                    )
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("School Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SchoolChatRoomsView: View {
    let school: School

    @EnvironmentObject private var appSession: AppSessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var model = ChatRoomListModel()
    @State private var showingCreateChat = false
    @State private var roomPendingLeave: ChatRoomListItem?

    private var accessPolicy: ChatAccessPolicy {
        ChatAccessPolicy(context: appSession.accessContext(selectedSchoolId: school.id))
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            FireflyScreen {
                VStack(spacing: FireflyTheme.Layout.spacingMedium) {
                    FireflySearchField(placeholder: "Search chats", text: $model.searchText)
                        .padding(.horizontal)

                    if model.phase.isLoading {
                        Spacer()
                        ProgressView().tint(FireflyTheme.Colors.primaryAction)
                        Spacer()
                    } else if model.filteredRoomItems.isEmpty {
                        Spacer()
                        FireflyEmptyState(
                            title: "No school chats found",
                            systemImage: "bubble.left.and.bubble.right.fill"
                        )
                        .padding(.horizontal)
                        Spacer()
                    } else {
                        List(model.filteredRoomItems) { item in
                            NavigationLink {
                                ChatRoomScreen(room: item.room) {
                                    Task { await model.load() }
                                }
                            } label: {
                                ChatRoomRow(item: item)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if accessPolicy.canLeave(room: item.room) {
                                    Button(role: .destructive) {
                                        roomPendingLeave = item
                                    } label: {
                                        Label("Leave", systemImage: "rectangle.portrait.and.arrow.right.fill")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .refreshable { await model.load() }
                    }

                    if let message = model.mutationError {
                        FireflyInlineError(message: message)
                            .padding(.horizontal)
                    }
                    if case .failed(let message) = model.phase {
                        FireflyInlineError(message: message)
                            .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("\(school.name) Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if accessPolicy.canCreateSchoolRoom {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            showingCreateChat = true
                        } label: {
                            Image(systemName: "message.badge.plus")
                                .foregroundColor(FireflyTheme.Colors.primaryAction)
                        }
                        .accessibilityLabel("Create chat")
                    }
                }
            }
            .sheet(isPresented: $showingCreateChat) {
                CreateChatRoomView(fixedSchool: school) {
                    Task { await model.load() }
                }
            }
            .confirmationDialog(
                "Leave \(roomPendingLeave?.room.name ?? "this room")?",
                isPresented: Binding(
                    get: { roomPendingLeave != nil },
                    set: { if !$0 { roomPendingLeave = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Leave Room", role: .destructive) {
                    guard let item = roomPendingLeave else { return }
                    roomPendingLeave = nil
                    Task { await model.leave(item) }
                }
                Button("Cancel", role: .cancel) { roomPendingLeave = nil }
            } message: {
                Text("You will immediately lose access to this chat and its message history.")
            }
            .task(id: school.id) {
                await model.start(
                    schoolId: school.id,
                    includeAllSchoolRooms: accessPolicy.canOverseeSchoolRooms,
                    membershipScope: school.id.uuidString
                )
            }
            .onDisappear {
                Task { await model.stop() }
            }
        }
    }
}
private struct CommunityPostEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let post: CommunityPost
    let events: [SchoolEvent]
    var onSaved: () -> Void

    @State private var bodyText: String
    @State private var selectedEventId: UUID?
    @State private var schedulePost: Bool
    @State private var scheduledAt: Date
    @State private var pollQuestion: String
    @State private var pollOptions: [String]
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let client = CommunityWorkflowClient.live

    init(post: CommunityPost, events: [SchoolEvent], onSaved: @escaping () -> Void) {
        self.post = post
        self.events = events
        self.onSaved = onSaved
        _bodyText = State(initialValue: post.body)
        _selectedEventId = State(initialValue: post.linkedEventId)
        _schedulePost = State(initialValue: post.scheduledAt != nil)
        _scheduledAt = State(initialValue: post.scheduledAt ?? Date().addingTimeInterval(3600))
        _pollQuestion = State(initialValue: post.pollQuestion ?? "")
        _pollOptions = State(initialValue: post.pollOptions?.isEmpty == false ? post.pollOptions! : ["", ""])
    }

    private var canSave: Bool {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && isSaving == false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TextEditor(text: $bodyText)
                            .scrollContentBackground(.hidden)
                            .foregroundColor(AppConstants.Colors.primaryText)
                            .frame(minHeight: 170)
                            .padding(10)
                            .background(AppConstants.Colors.card)
                            .cornerRadius(12)

                        if events.isEmpty == false {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Linked Event")
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                                Picker("Linked Event", selection: Binding(
                                    get: { selectedEventId },
                                    set: { selectedEventId = $0 }
                                )) {
                                    Text("None").tag(Optional<UUID>.none)
                                    ForEach(events.prefix(24)) { event in
                                        Text(event.title).tag(Optional(event.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(AppConstants.Colors.accessibleYellow)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppConstants.Colors.card)
                                .cornerRadius(10)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Poll")
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                                Spacer()
                                Button {
                                    pollQuestion = ""
                                    pollOptions = ["", ""]
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.52))
                                }
                            }

                            TextField("Question", text: $pollQuestion)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                                .foregroundColor(AppConstants.Colors.primaryText)

                            ForEach(pollOptions.indices, id: \.self) { index in
                                TextField("Option \(index + 1)", text: $pollOptions[index])
                                    .textFieldStyle(.plain)
                                    .padding(10)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(8)
                                    .foregroundColor(AppConstants.Colors.primaryText)
                            }

                            Button {
                                pollOptions.append("")
                            } label: {
                                Label("Add Option", systemImage: "plus")
                            }
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.accessibleYellow)
                        }
                        .padding()
                        .background(AppConstants.Colors.card)
                        .cornerRadius(10)

                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Schedule post", isOn: $schedulePost)
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .tint(AppConstants.Colors.accessibleYellow)
                            if schedulePost {
                                DatePicker("Post at", selection: $scheduledAt)
                                    .foregroundColor(AppConstants.Colors.primaryText)
                            }
                        }
                        .padding()
                        .background(AppConstants.Colors.card)
                        .cornerRadius(10)

                        if let attachmentName = post.attachmentName {
                            CommunitySearchRow(icon: "paperclip", title: attachmentName, subtitle: "Attachments stay attached to the edited post.")
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Edit Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        let cleanedPollOptions = pollOptions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let cleanedPollQuestion = pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                try await client.updatePost(CommunityPostUpdateRequest(
                    postId: post.id,
                    body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                    linkedEventId: selectedEventId,
                    pollQuestion: cleanedPollQuestion.isEmpty ? nil : cleanedPollQuestion,
                    pollOptions: cleanedPollOptions,
                    scheduledAt: schedulePost ? scheduledAt : nil
                ))
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not update post", error)
                }
            }
        }
    }
}

private struct CommunityPostComposerView: View {
    @Environment(\.dismiss) private var dismiss

    let school: School
    let events: [SchoolEvent]
    var onSaved: () -> Void

    @State private var bodyText = ""
    @State private var selectedMediaItem: PhotosPickerItem?
    @State private var attachment: CommunityMediaUpload?
    @State private var showingFileImporter = false
    @State private var showingMoreActions = false
    @State private var showingPoll = false
    @State private var selectedEventId: UUID?
    @State private var schedulePost = false
    @State private var scheduledAt = Date().addingTimeInterval(3600)
    @State private var pollQuestion = ""
    @State private var pollOptions = ["", ""]
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let client = CommunityWorkflowClient.live

    private var canPost: Bool {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || attachment != nil
            || pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextEditor(text: $bodyText)
                                .scrollContentBackground(.hidden)
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .frame(minHeight: 150)
                                .padding(10)
                                .background(AppConstants.Colors.card)
                                .cornerRadius(12)
                                .overlay(alignment: .topLeading) {
                                    if bodyText.isEmpty {
                                        Text("Share a thought")
                                            .font(.body)
                                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.38))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 18)
                                            .allowsHitTesting(false)
                                    }
                                }

                            composerActionRow
                        }

                        if let attachment {
                            composerInfoPanel(
                                icon: attachment.contentType?.hasPrefix("video/") == true ? "video.fill" : "paperclip",
                                title: attachment.fileName,
                                subtitle: attachment.contentType ?? "Attachment"
                            )
                        }

                        if selectedEventId != nil {
                            composerInfoPanel(icon: "calendar", title: "Event linked", subtitle: selectedEventTitle ?? "School event")
                        }

                        if showingPoll {
                            pollEditor
                        }

                        if schedulePost {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Schedule")
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                                DatePicker("Post at", selection: $scheduledAt)
                                    .foregroundColor(AppConstants.Colors.primaryText)
                            }
                            .padding()
                            .background(AppConstants.Colors.card)
                            .cornerRadius(10)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Posting" : "Post") { save() }
                        .disabled(!canPost || isSaving)
                }
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                do {
                    if let url = try result.get().first {
                        attachment = try makeUpload(from: url)
                    }
                } catch {
                    errorMessage = AppErrorMessage.school("Could not attach file", error)
                }
            }
            .onChange(of: selectedMediaItem) { _, newValue in
                Task { await loadMediaItem(newValue) }
            }
            .sheet(isPresented: $showingMoreActions) {
                CommunityPostMoreActionsView(
                    events: events,
                    selectedEventId: $selectedEventId,
                    schedulePost: $schedulePost,
                    scheduledAt: $scheduledAt,
                    showingPoll: $showingPoll,
                    onAttachFile: {
                        showingMoreActions = false
                        showingFileImporter = true
                    }
                )
            }
        }
    }

    private var composerActionRow: some View {
        HStack(spacing: 18) {
            PhotosPicker(selection: $selectedMediaItem, matching: .any(of: [.images, .videos])) {
                Image(systemName: "photo.on.rectangle")
            }
            Button {
                showingFileImporter = true
            } label: {
                Image(systemName: "doc")
            }
            Button {
                showingPoll = true
            } label: {
                Image(systemName: "chart.bar.doc.horizontal")
            }
            if events.isEmpty == false {
                Menu {
                    ForEach(events.prefix(12)) { event in
                        Button(event.title) {
                            selectedEventId = event.id
                        }
                    }
                    Button("Clear Event", role: .destructive) {
                        selectedEventId = nil
                    }
                } label: {
                    Image(systemName: "calendar.badge.plus")
                }
            }
            Button {
                showingMoreActions = true
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            Spacer()
        }
        .font(.system(size: 22, weight: .semibold))
        .foregroundColor(AppConstants.Colors.accessibleYellow)
        .padding(.horizontal, 4)
    }

    private var pollEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Poll")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                Spacer()
                Button {
                    showingPoll = false
                    pollQuestion = ""
                    pollOptions = ["", ""]
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.5))
                }
            }

            TextField("Question", text: $pollQuestion)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)
                .foregroundColor(AppConstants.Colors.primaryText)

            ForEach(pollOptions.indices, id: \.self) { index in
                TextField("Option \(index + 1)", text: $pollOptions[index])
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                    .foregroundColor(AppConstants.Colors.primaryText)
            }

            Button {
                pollOptions.append("")
            } label: {
                Label("Add Option", systemImage: "plus")
            }
            .font(.caption.bold())
            .foregroundColor(AppConstants.Colors.accessibleYellow)
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(10)
    }

    private var selectedEventTitle: String? {
        guard let selectedEventId else { return nil }
        return events.first(where: { $0.id == selectedEventId })?.title
    }

    private func composerInfoPanel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
            }
            Spacer()
            Button {
                if icon == "calendar" {
                    selectedEventId = nil
                } else {
                    attachment = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.45))
            }
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(10)
    }

    private func loadMediaItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let type = item.supportedContentTypes.first
            let ext = type?.preferredFilenameExtension ?? "jpg"
            let contentType = type?.preferredMIMEType ?? "image/jpeg"
            let prefix = contentType.hasPrefix("video/") ? "video" : "photo"
            await MainActor.run {
                attachment = CommunityMediaUpload(
                    data: data,
                    fileName: "\(prefix)-\(UUID().uuidString).\(ext)",
                    contentType: contentType
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = AppErrorMessage.school("Could not attach photo or video", error)
            }
        }
    }

    private func makeUpload(from url: URL) throws -> CommunityMediaUpload {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
        return CommunityMediaUpload(
            data: data,
            fileName: url.lastPathComponent.isEmpty ? "Attachment" : url.lastPathComponent,
            contentType: contentType
        )
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await client.createPost(CommunityPostCreateRequest(
                    schoolId: school.id,
                    body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                    attachment: attachment,
                    linkedEventId: selectedEventId,
                    pollQuestion: pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines),
                    pollOptions: pollOptions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                    scheduledAt: schedulePost ? scheduledAt : nil
                ))
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

private struct CommunityPostMoreActionsView: View {
    let events: [SchoolEvent]
    @Binding var selectedEventId: UUID?
    @Binding var schedulePost: Bool
    @Binding var scheduledAt: Date
    @Binding var showingPoll: Bool
    var onAttachFile: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Actions") {
                    Button {
                        showingPoll = true
                        dismiss()
                    } label: {
                        Label("Create Poll", systemImage: "chart.bar.doc.horizontal")
                    }
                    Button {
                        onAttachFile()
                        dismiss()
                    } label: {
                        Label("Attach File", systemImage: "doc.badge.plus")
                    }
                    Toggle(isOn: $schedulePost) {
                        Label("Schedule Post", systemImage: "clock")
                    }
                    if schedulePost {
                        DatePicker("Post at", selection: $scheduledAt)
                    }
                }

                if events.isEmpty == false {
                    Section("Link Event") {
                        ForEach(events.prefix(12)) { event in
                            Button {
                                selectedEventId = event.id
                                dismiss()
                            } label: {
                                HStack {
                                    Text(event.title)
                                    Spacer()
                                    if selectedEventId == event.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        if selectedEventId != nil {
                            Button("Clear Linked Event", role: .destructive) {
                                selectedEventId = nil
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Post Actions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct CommunityAlbumComposerView: View {
    @Environment(\.dismiss) private var dismiss

    let school: School
    let albums: [CommunityAlbum]
    var startsWithPhotoPicker = false
    var onSaved: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var destination: AlbumUploadDestination = .newAlbum
    @State private var selectedAlbumId: UUID?
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var uploads: [CommunityMediaUpload] = []
    @State private var isSaving = false
    @State private var isLoadingMedia = false
    @State private var errorMessage: String?
    private let client = CommunityWorkflowClient.live

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Destination", selection: $destination) {
                            Text("New Album").tag(AlbumUploadDestination.newAlbum)
                            Text("Existing").tag(AlbumUploadDestination.existingAlbum)
                            Text("All Photos").tag(AlbumUploadDestination.allPhotos)
                        }
                        .pickerStyle(.segmented)

                        if destination == .newAlbum {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("Album title", text: $title)
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(AppConstants.Colors.card)
                                    .cornerRadius(10)
                                    .foregroundColor(AppConstants.Colors.primaryText)
                                TextField("Description", text: $description, axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(AppConstants.Colors.card)
                                    .cornerRadius(10)
                                    .foregroundColor(AppConstants.Colors.primaryText)
                            }
                        } else if destination == .existingAlbum {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Choose Album")
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                                Picker("Album", selection: Binding(
                                    get: { selectedAlbumId ?? albums.first?.id },
                                    set: { selectedAlbumId = $0 }
                                )) {
                                    ForEach(albums) { album in
                                        Text(album.title).tag(Optional(album.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(AppConstants.Colors.accessibleYellow)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(AppConstants.Colors.card)
                                .cornerRadius(10)
                            }
                        } else {
                            communityDestinationPanel(
                                title: "All Photos",
                                message: "Selected photos and videos will be added to the school's shared All Photos album."
                            )
                        }

                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: 100,
                            matching: .any(of: [.images, .videos])
                        ) {
                            Label("Select Photos or Videos", systemImage: "photo.on.rectangle.angled")
                                .font(.headline)
                                .foregroundColor(AppConstants.Colors.brandNavy)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppConstants.Colors.accessibleYellow)
                                .cornerRadius(12)
                        }

                        communityDestinationPanel(
                            title: uploads.isEmpty ? "No media selected" : "\(uploads.count) selected",
                            message: "You can add up to 100 photos or videos at a time."
                        )

                        if uploads.isEmpty == false {
                            CommunitySelectedUploadGrid(
                                uploads: uploads,
                                onRemove: removeSelectedMedia,
                                onClear: { selectedItems.removeAll() }
                            )
                        }

                        if isLoadingMedia {
                            ProgressView("Preparing media")
                                .tint(AppConstants.Colors.accessibleYellow)
                                .foregroundColor(AppConstants.Colors.primaryText)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(startsWithPhotoPicker ? "Add Photos" : "New Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") { save() }
                        .disabled(!canSave || isSaving || isLoadingMedia)
                }
            }
            .onAppear {
                if startsWithPhotoPicker {
                    destination = .allPhotos
                }
                if selectedAlbumId == nil {
                    selectedAlbumId = albums.first?.id
                }
            }
            .onChange(of: selectedItems) { _, newValue in
                Task { await loadSelectedMedia(newValue) }
            }
        }
    }

    private var canSave: Bool {
        switch destination {
        case .newAlbum:
            return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .existingAlbum:
            return selectedAlbumId != nil && uploads.isEmpty == false
        case .allPhotos:
            return uploads.isEmpty == false
        }
    }

    private func communityDestinationPanel(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
            Text(message)
                .font(.caption)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(10)
    }

    private func loadSelectedMedia(_ items: [PhotosPickerItem]) async {
        await MainActor.run {
            isLoadingMedia = true
            errorMessage = nil
        }

        do {
            var loaded: [CommunityMediaUpload] = []
            for item in items.prefix(100) {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let type = item.supportedContentTypes.first
                let contentType = type?.preferredMIMEType ?? "image/jpeg"
                let ext = type?.preferredFilenameExtension ?? (contentType.hasPrefix("video/") ? "mov" : "jpg")
                let prefix = contentType.hasPrefix("video/") ? "video" : "photo"
                loaded.append(CommunityMediaUpload(
                    data: data,
                    fileName: "\(prefix)-\(UUID().uuidString).\(ext)",
                    contentType: contentType
                ))
            }
            await MainActor.run {
                uploads = loaded
                isLoadingMedia = false
            }
        } catch {
            await MainActor.run {
                isLoadingMedia = false
                errorMessage = AppErrorMessage.school("Could not prepare selected media", error)
            }
        }
    }

    private func removeSelectedMedia(at index: Int) {
        guard selectedItems.indices.contains(index) else { return }
        selectedItems.remove(at: index)
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                switch destination {
                case .newAlbum:
                    _ = try await client.createAlbum(CommunityAlbumCreateRequest(
                        schoolId: school.id,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                        media: uploads
                    ))
                case .existingAlbum:
                    guard let album = albums.first(where: { $0.id == selectedAlbumId }) else {
                        throw SchoolWorkflowError.notFound
                    }
                    try await client.addAlbumMedia(school.id, album, uploads)
                case .allPhotos:
                    let album = try await client.ensureAllPhotosAlbum(school.id)
                    try await client.addAlbumMedia(school.id, album, uploads)
                }
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

private enum AlbumUploadDestination: String, CaseIterable, Hashable {
    case newAlbum
    case existingAlbum
    case allPhotos
}

private struct CommunityInviteSheet: View {
    @Environment(\.dismiss) private var dismiss

    let school: School

    @State private var selectedRole: SchoolRole = .parent
    @State private var invite: SchoolInvite?
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let client = CommunityWorkflowClient.live

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
                let created = try await client.createInvite(school.id, selectedRole)
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
    @State private var members: [SchoolDirectoryEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let client = CommunityWorkflowClient.live

    private var filteredMembers: [SchoolDirectoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return members }
        return members.filter {
            $0.displayName.lowercased().contains(trimmed)
            || $0.schoolRole.title.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            VStack(spacing: 12) {
                FireflySearchField(placeholder: "Search members", text: $query)
                    .padding(.horizontal)

                if isLoading {
                    ProgressView()
                        .tint(AppConstants.Colors.accessibleYellow)
                        .padding()
                } else if filteredMembers.isEmpty {
                    Text("No members found.")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.56))
                        .padding()
                } else {
                    List(filteredMembers) { member in
                        HStack(spacing: 12) {
                            DirectoryAvatar(entry: member, size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(member.displayName)
                                    .font(.headline)
                                    .foregroundColor(AppConstants.Colors.primaryText)
                                Text(member.schoolRole.title)
                                    .font(.caption)
                                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
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
            members = try await client.fetchDirectory(school.id)
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
            .foregroundColor(AppConstants.Colors.primaryText)
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
