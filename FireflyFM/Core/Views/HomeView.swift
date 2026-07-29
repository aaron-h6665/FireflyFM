//
//  HomeView.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct HomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var notificationInbox: NotificationInboxStore

    @State private var newsletters: [NewsletterPost] = []
    @State private var newsletterAuthors: [UUID: UserProfile] = [:]
    @State private var upcomingEvents: [SchoolEvent] = []
    @State private var communityPosts: [CommunityPost] = []
    @State private var communityAuthors: [UUID: UserProfile] = [:]
    @State private var children: [Child] = []
    @State private var directorRoster: [ChildRosterItem] = []
    @State private var inboxItems: [AssignmentInboxItem] = []
    @State private var reviewItems: [AssignmentInboxItem] = []
    @State private var isLoading = false
    @State private var isDashboardLoading = false
    @State private var showingProfile = false
    @State private var showingNewsletterComposer = false
    @State private var editingNewsletter: NewsletterPost?
    @State private var newsletterPendingDeletion: NewsletterPost?
    @State private var isDeletingNewsletter = false
    @State private var showingSignOutConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if appSession.role == .schoolDirector {
                            directorTodaySection
                            upcomingSection
                            newsletterSection
                        } else {
                            upNextCard
                            roleSummary
                            upcomingSection
                            communityActivitySection
                            workspaceStrip
                            newsletterSection
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await loadDashboard()
                }

                if showingSignOutConfirmation {
                    SignOutConfirmationOverlay(
                        message: "You will need to sign in again to access your school workspace.",
                        onCancel: { showingSignOutConfirmation = false },
                        onSignOut: {
                            showingSignOutConfirmation = false
                            Task { await authManager.signOut() }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(2)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
            .sheet(isPresented: $showingNewsletterComposer) {
                NewsletterComposerView(post: nil) {
                    Task { await loadNewsletters() }
                }
            }
            .sheet(item: $editingNewsletter) { post in
                NewsletterComposerView(post: post) {
                    Task { await loadNewsletters() }
                }
            }
            .alert(
                "Delete newsletter?",
                isPresented: Binding(
                    get: { newsletterPendingDeletion != nil },
                    set: { if $0 == false { newsletterPendingDeletion = nil } }
                ),
                presenting: newsletterPendingDeletion
            ) { post in
                Button("Delete", role: .destructive) {
                    Task { await deleteNewsletter(post) }
                }
                Button("Cancel", role: .cancel) {
                    newsletterPendingDeletion = nil
                }
            } message: { post in
                Text("“\(post.title)” and its attachments will be permanently deleted.")
            }
            .task(id: appSession.activeMembershipId) {
                await loadDashboard()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 10) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appSession.role == .schoolDirector ? "Today" : "FireflyFM")
                            .font(.title2.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Text(appSession.activeSchool?.name ?? "Your school")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.secondaryText)
                    }
                }

                Spacer()

                NotificationBellButton()

                Menu {
                    Button("Profile", systemImage: "person.crop.circle") {
                        showingProfile = true
                    }
                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        showingSignOutConfirmation = true
                    }
                } label: {
                    if let avatarURL = appSession.profile?.avatarUrl.flatMap(URL.init(string:)) {
                        AsyncImage(url: avatarURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            avatarPlaceholder
                        }
                        .frame(width: AppConstants.Layout.minimumTapTarget, height: AppConstants.Layout.minimumTapTarget)
                        .clipShape(Circle())
                    } else {
                        avatarPlaceholder
                    }
                }
                .accessibilityLabel("Account menu")
            }

            if appSession.canSwitchSchools {
                Picker("Active School", selection: Binding(
                    get: { appSession.activeMembershipId ?? appSession.memberships.first?.membership.id },
                    set: { newValue in
                        if let newValue,
                           let context = appSession.memberships.first(where: { $0.membership.id == newValue }) {
                            appSession.switchActiveMembership(to: context.membership.id)
                        }
                    }
                )) {
                    ForEach(appSession.memberships) { context in
                        Text(context.school.name).tag(Optional(context.membership.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(AppConstants.Colors.primaryAction)
            }
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(AppConstants.Colors.wingMist)
            .frame(width: AppConstants.Layout.minimumTapTarget, height: AppConstants.Layout.minimumTapTarget)
            .overlay {
                Text(appSession.profile?.initials ?? "FF")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.brandNavy)
            }
    }

    private var upNextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Up next", systemImage: "sparkles")
                .font(.caption.bold())
                .textCase(.uppercase)
            Text(upNextTitle)
                .font(.title3.bold())
            Text(upNextSubtitle)
                .font(.subheadline)
                .opacity(0.78)
        }
        .foregroundStyle(AppConstants.Colors.brandNavy)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.fireflyGlow)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var upNextTitle: String {
        if let unread = notificationInbox.notifications.first(where: { $0.readAt == nil }) {
            return unread.title
        }
        if let assignment = inboxItems.first(where: { !isAssignmentComplete($0) }) {
            return assignment.title
        }
        if let event = upcomingEvents.first {
            return event.title
        }
        return "You’re all caught up"
    }

    private var upNextSubtitle: String {
        if let unread = notificationInbox.notifications.first(where: { $0.readAt == nil }) {
            return unread.body
        }
        if let assignment = inboxItems.first(where: { !isAssignmentComplete($0) }) {
            if let dueAt = assignment.dueAt {
                return "Due \(dueAt.formatted(date: .abbreviated, time: .shortened))"
            }
            return "Open Work when you’re ready to continue."
        }
        if let event = upcomingEvents.first {
            return event.startAt.formatted(date: .abbreviated, time: .shortened)
        }
        return "There are no urgent actions right now."
    }

    private var roleSummary: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    summaryCard(title: summaryLeftTitle, value: summaryLeftValue, icon: summaryLeftIcon)
                    summaryCard(title: summaryRightTitle, value: summaryRightValue, icon: summaryRightIcon)
                }
            } else {
                HStack(spacing: 12) {
                    summaryCard(title: summaryLeftTitle, value: summaryLeftValue, icon: summaryLeftIcon)
                    summaryCard(title: summaryRightTitle, value: summaryRightValue, icon: summaryRightIcon)
                }
            }
        }
        .redacted(reason: isDashboardLoading ? .placeholder : [])
    }

    private var directorTodaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("School operations")
                    .font(.title2.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                Text("Roster, attendance, and the items that need your attention today.")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
            }

            NavigationLink {
                ChildrenAttendanceWorkspace()
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.crop.square.stack.fill")
                            .font(.title3)
                            .foregroundColor(AppConstants.Colors.brandNavy)
                            .frame(width: 42, height: 42)
                            .background(AppConstants.Colors.wingMist)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Children & Attendance")
                                .font(.headline)
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Text("One roster for profiles, check-in, and history")
                                .font(.caption)
                                .foregroundColor(AppConstants.Colors.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.secondaryText)
                    }

                    HStack(spacing: 0) {
                        directorMetric("Roster", value: directorRoster.count)
                        Divider().frame(height: 30)
                        directorMetric("Checked in", value: directorRoster.filter(\.isCheckedIn).count)
                        Divider().frame(height: 30)
                        directorMetric("Need review", value: reviewItems.count)
                    }
                }
                .padding()
                .background(AppConstants.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous)
                        .stroke(AppConstants.Colors.separator.opacity(0.65), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            if let school = appSession.activeSchool {
                directorQuickLink(
                    title: "People & Access",
                    subtitle: "Invites, connections, and onboarding",
                    icon: "person.badge.key.fill",
                    destination: OnboardingManagementView(school: school, mode: .schoolDirector)
                )
            }
            directorQuickLink(
                title: "Assignments & Training",
                subtitle: "Manage school work and complete assigned training",
                icon: "checklist.checked",
                destination: AssignmentsView(filter: .all)
            )
        }
        .redacted(reason: isDashboardLoading ? .placeholder : [])
    }

    private func directorMetric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.primaryText)
            Text(title)
                .font(.caption2)
                .foregroundColor(AppConstants.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func directorQuickLink<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        destination: Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(AppConstants.Colors.primaryAction)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.bold()).foregroundColor(AppConstants.Colors.primaryText)
                    Text(subtitle).font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.secondaryText)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 62)
            .background(AppConstants.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func summaryCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AppConstants.Colors.fireflyBlue)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(AppConstants.Colors.primaryText)
            Text(title)
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
    }

    private var summaryLeftTitle: String {
        switch appSession.role {
        case .parent: "Children"
        case .teacher: "Children today"
        case .schoolDirector: "Active children"
        case .hqDirector: "Schools"
        case .none: "Community"
        }
    }

    private var summaryLeftValue: String {
        appSession.role == .hqDirector ? "—" : "\(children.count)"
    }

    private var summaryLeftIcon: String {
        appSession.role == .hqDirector ? "building.2" : "figure.2.and.child.holdinghands"
    }

    private var summaryRightTitle: String {
        appSession.role?.canManageSchool == true ? "Needs review" : "Pending work"
    }

    private var summaryRightValue: String {
        appSession.role?.canManageSchool == true ? "\(reviewItems.count)" : "\(inboxItems.filter { !isAssignmentComplete($0) }.count)"
    }

    private var summaryRightIcon: String {
        appSession.role?.canManageSchool == true ? "checkmark.seal" : "checklist"
    }

    private func isAssignmentComplete(_ item: AssignmentInboxItem) -> Bool {
        [.accepted, .excused, .reviewed].contains(item.completionStatus)
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Upcoming", systemImage: "calendar")
            if upcomingEvents.isEmpty {
                emptyPanel("No upcoming events.")
            } else {
                ForEach(upcomingEvents.prefix(3)) { event in
                    HStack(spacing: 12) {
                        VStack {
                            Text(event.startAt.formatted(.dateTime.month(.abbreviated)))
                                .font(.caption2.bold())
                            Text(event.startAt.formatted(.dateTime.day()))
                                .font(.title3.bold())
                        }
                        .foregroundStyle(AppConstants.Colors.brandNavy)
                        .frame(width: 48, height: 52)
                        .background(AppConstants.Colors.wingMist)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title).font(.subheadline.bold())
                            Text(event.startAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(AppConstants.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
                }
            }
        }
    }

    private var communityActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("Recent Community activity", systemImage: "person.3")
                Spacer()
                Text("Quick conversations")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
            }
            if let post = communityPosts.first {
                if let school = appSession.activeSchool {
                    NavigationLink {
                        CommunityView(school: school)
                    } label: {
                        CommunityPostCard(
                            post: post,
                            profile: post.createdBy.flatMap { communityAuthors[$0] }
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                emptyPanel("No Community posts yet.")
            }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(AppConstants.Colors.primaryText)
    }

    private var workspaceStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workspaces")
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(workspaces) { workspace in
                        NavigationLink {
                            workspace.destination
                        } label: {
                            WorkspaceCard(workspace: workspace)
                        }
                    }
                }
            }
        }
    }

    private var newsletterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Newsletters")
                        .font(.title2.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                    Text("Stories, photos, and updates from your school")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.secondaryText)
                }
                Spacer()
                if appSession.role?.canManageSchool == true {
                    Button {
                        showingNewsletterComposer = true
                    } label: {
                        Label("Write", systemImage: "square.and.pencil")
                            .font(.subheadline.bold())
                            .frame(minHeight: AppConstants.Layout.minimumTapTarget)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppConstants.Colors.primaryAction)
                }
            }

            if isLoading {
                ProgressView().tint(AppConstants.Colors.accessibleYellow)
            } else if newsletters.isEmpty {
                emptyPanel("No newsletters yet")
            } else if appSession.role == .schoolDirector {
                VStack(spacing: 0) {
                    ForEach(Array(newsletters.prefix(3).enumerated()), id: \.element.id) { index, post in
                        NavigationLink {
                            NewsletterDetailView(
                                post: post,
                                author: post.createdBy.flatMap { newsletterAuthors[$0] },
                                publicationName: appSession.activeSchool?.name ?? "School Newsletter",
                                canManage: true,
                                onEdit: { editingNewsletter = post },
                                onDelete: { newsletterPendingDeletion = post }
                            )
                        } label: {
                            TodayNewsletterRow(
                                post: post,
                                schoolName: appSession.activeSchool?.name ?? "School"
                            )
                        }
                        .buttonStyle(.plain)
                        if index < min(newsletters.count, 3) - 1 {
                            Divider().overlay(AppConstants.Colors.separator).padding(.leading, 58)
                        }
                    }
                }
                .background(AppConstants.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous)
                        .stroke(AppConstants.Colors.separator.opacity(0.65), lineWidth: 1)
                }
            } else {
                ForEach(newsletters.prefix(3)) { post in
                    ZStack(alignment: .topTrailing) {
                        NavigationLink {
                            NewsletterDetailView(
                                post: post,
                                author: post.createdBy.flatMap { newsletterAuthors[$0] },
                                publicationName: appSession.activeSchool?.name ?? "School Newsletter",
                                canManage: appSession.role?.canManageSchool == true,
                                onEdit: { editingNewsletter = post },
                                onDelete: { newsletterPendingDeletion = post }
                            )
                        } label: {
                            NewsletterStoryCard(
                                post: post,
                                author: post.createdBy.flatMap { newsletterAuthors[$0] },
                                publicationName: appSession.activeSchool?.name ?? "School Newsletter"
                            )
                        }
                        .buttonStyle(.plain)

                        if appSession.role?.canManageSchool == true {
                            newsletterActions(for: post)
                                .padding(10)
                                .zIndex(1)
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
    }

    private func newsletterActions(for post: NewsletterPost) -> some View {
        Menu {
            Button("Edit", systemImage: "pencil") {
                editingNewsletter = post
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                newsletterPendingDeletion = post
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
                .frame(width: AppConstants.Layout.minimumTapTarget, height: AppConstants.Layout.minimumTapTarget)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Actions for \(post.title)")
        .disabled(isDeletingNewsletter)
    }

    private var workspaces: [WorkspaceItem] {
        switch appSession.role {
        case .parent:
            return [
                WorkspaceItem(title: "Children", subtitle: "Profiles and records", icon: "figure.2.and.child.holdinghands", destination: AnyView(ChildrenView())),
                WorkspaceItem(title: "Family Requests", subtitle: "Absence, pickup, and school needs", icon: "person.crop.circle.badge.questionmark", destination: AnyView(FamilyRequestsView())),
                WorkspaceItem(title: "Paperwork", subtitle: "Forms and school requests", icon: "doc.text.fill", destination: AnyView(AssignmentsView(filter: .all))),
                WorkspaceItem(title: "Payments", subtitle: "Invoices and receipts", icon: "creditcard.fill", destination: AnyView(PaymentsView()))
            ]
        case .teacher:
            return [
                WorkspaceItem(title: "Training & Curriculum", subtitle: "Required learning and feedback", icon: "graduationcap.fill", destination: AnyView(AssignmentsView(filter: .learning))),
                WorkspaceItem(title: "Children", subtitle: "Roster and profiles", icon: "figure.2.and.child.holdinghands", destination: AnyView(ChildrenView())),
                WorkspaceItem(title: "Attendance", subtitle: "Arrival, departure, and history", icon: "calendar.badge.checkmark", destination: AnyView(AttendanceView())),
                WorkspaceItem(title: "Care Today", subtitle: "Meals, naps, health, and notes", icon: "heart.text.square.fill", destination: AnyView(CareTodayView())),
                WorkspaceItem(title: "Family Requests", subtitle: "Parent needs routed to school staff", icon: "person.crop.circle.badge.questionmark", destination: AnyView(FamilyRequestsView()))
            ]
        case .schoolDirector:
            return [
                WorkspaceItem(title: "Assignments & Training", subtitle: "Assign, complete, and review", icon: "checklist.checked", destination: AnyView(AssignmentsView(filter: .all))),
                WorkspaceItem(title: "Children & Attendance", subtitle: "Roster, check-in, and history", icon: "person.2.crop.square.stack.fill", destination: AnyView(ChildrenAttendanceWorkspace())),
                WorkspaceItem(
                    title: "Onboarding",
                    subtitle: "Templates, invites, and reviews",
                    icon: "person.badge.key.fill",
                    destination: AnyView(
                        Group {
                            if let school = appSession.activeSchool {
                                OnboardingManagementView(school: school, mode: .schoolDirector)
                            } else {
                                ProgressView()
                            }
                        }
                    )
                )
            ]
        case .hqDirector:
            return [
                WorkspaceItem(title: "Training & Curriculum", subtitle: "Cross-school learning and reviews", icon: "graduationcap.fill", destination: AnyView(AssignmentsView(filter: .learning, schoolSelection: .selectable))),
                WorkspaceItem(title: "Children & Attendance", subtitle: "Cross-school roster and history", icon: "person.2.crop.square.stack.fill", destination: AnyView(ChildrenAttendanceWorkspace()))
            ]
        case .none:
            return []
        }
    }

    private func emptyPanel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppConstants.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
    }

    @MainActor
    private func loadDashboard() async {
        guard let schoolId = appSession.activeSchool?.id,
              let membershipId = appSession.activeMembershipId else { return }
        isDashboardLoading = true
        async let notices: Void = loadNewsletters(schoolId: schoolId, membershipId: membershipId)
        async let events: Void = loadEvents(schoolId: schoolId, membershipId: membershipId)
        async let posts: Void = loadCommunity(schoolId: schoolId, membershipId: membershipId)
        async let roster: Void = loadChildren(schoolId: schoolId, membershipId: membershipId)
        async let work: Void = loadWork(schoolId: schoolId, membershipId: membershipId)
        async let notifications: Void = notificationInbox.refresh()
        _ = await (notices, events, posts, roster, work, notifications)
        guard appSession.activeMembershipId == membershipId else { return }
        isDashboardLoading = false
    }

    @MainActor
    private func loadNewsletters(schoolId: UUID? = nil, membershipId: UUID? = nil) async {
        guard let schoolId = schoolId ?? appSession.activeSchool?.id else { return }
        let membershipId = membershipId ?? appSession.activeMembershipId
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await SchoolWorkflowService.shared.fetchNewsletters(schoolId: schoolId)
            let authors = (try? await ProfileService.shared.fetchProfiles(ids: loaded.compactMap(\.createdBy))) ?? [:]
            guard appSession.activeMembershipId == membershipId else { return }
            newsletters = loaded
            newsletterAuthors = authors
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load newsletters", error)
            isLoading = false
        }
    }

    @MainActor
    private func deleteNewsletter(_ post: NewsletterPost) async {
        guard isDeletingNewsletter == false else { return }
        isDeletingNewsletter = true
        errorMessage = nil
        do {
            try await SchoolWorkflowService.shared.deleteNewsletter(post)
            newsletters.removeAll { $0.id == post.id }
            newsletterPendingDeletion = nil
        } catch {
            errorMessage = AppErrorMessage.school("Could not delete newsletter", error)
        }
        isDeletingNewsletter = false
    }

    @MainActor
    private func loadEvents(schoolId: UUID, membershipId: UUID) async {
        let loaded = (try? await SchoolWorkflowService.shared.fetchEvents(schoolId: schoolId)) ?? []
        guard appSession.activeMembershipId == membershipId else { return }
        upcomingEvents = loaded.filter { $0.endAt ?? $0.startAt >= Date() }.prefix(5).map { $0 }
    }

    @MainActor
    private func loadCommunity(schoolId: UUID, membershipId: UUID) async {
        let loaded = (try? await SchoolWorkflowService.shared.fetchCommunityPosts(schoolId: schoolId)) ?? []
        let authors = (try? await ProfileService.shared.fetchProfiles(ids: loaded.compactMap(\.createdBy))) ?? [:]
        guard appSession.activeMembershipId == membershipId else { return }
        communityPosts = loaded
        communityAuthors = authors
    }

    @MainActor
    private func loadChildren(schoolId: UUID, membershipId: UUID) async {
        if appSession.role == .schoolDirector {
            let loadedRoster = (try? await SchoolWorkflowService.shared.fetchChildRoster(schoolId: schoolId)) ?? []
            guard appSession.activeMembershipId == membershipId else { return }
            directorRoster = loadedRoster
            children = loadedRoster.map(\.child)
            return
        }
        let loaded = (try? await SchoolWorkflowService.shared.fetchChildren(schoolId: schoolId)) ?? []
        guard appSession.activeMembershipId == membershipId else { return }
        directorRoster = []
        children = loaded
    }

    @MainActor
    private func loadWork(schoolId: UUID, membershipId: UUID) async {
        async let inbox = try? SchoolWorkflowService.shared.fetchAssignmentInbox()
        async let review = try? SchoolWorkflowService.shared.fetchAssignmentReviewQueue(schoolId: schoolId)
        let (loadedInbox, loadedReview) = await (inbox, review)
        guard appSession.activeMembershipId == membershipId else { return }
        inboxItems = loadedInbox ?? []
        reviewItems = loadedReview ?? []
    }
}

private struct WorkspaceItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let destination: AnyView
}

private struct WorkspaceCard: View {
    let workspace: WorkspaceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: workspace.icon)
                .font(.title2)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            Text(workspace.title)
                .font(.subheadline.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
                .lineLimit(1)
            Text(workspace.subtitle)
                .font(.caption)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
                .lineLimit(2)
        }
        .frame(width: 148, alignment: .leading)
        .frame(minHeight: 112, alignment: .topLeading)
        .padding(12)
        .background(AppConstants.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
    }
}

struct TodaySchoolNewsletterSection: View {
    let school: School

    @State private var posts: [NewsletterPost] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Newsletters", systemImage: "newspaper.fill")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                Text(school.name)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                    .lineLimit(1)
            }

            if isLoading {
                ProgressView()
                    .tint(AppConstants.Colors.primaryAction)
                    .frame(maxWidth: .infinity, minHeight: 62)
            } else if posts.isEmpty {
                Text("No newsletters yet")
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .background(AppConstants.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.controlRadius, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(posts.prefix(2).enumerated()), id: \.element.id) { index, post in
                        NavigationLink {
                            NewsletterDetailView(
                                post: post,
                                author: nil,
                                publicationName: school.name,
                                canManage: false,
                                onEdit: {},
                                onDelete: {}
                            )
                        } label: {
                            TodayNewsletterRow(post: post, schoolName: school.name)
                        }
                        .buttonStyle(.plain)
                        if index < min(posts.count, 2) - 1 {
                            Divider().overlay(AppConstants.Colors.separator).padding(.leading, 58)
                        }
                    }
                }
                .background(AppConstants.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous)
                        .stroke(AppConstants.Colors.separator.opacity(0.65), lineWidth: 1)
                }
            }
        }
        .task(id: school.id) {
            isLoading = true
            posts = (try? await SchoolWorkflowService.shared.fetchNewsletters(schoolId: school.id)) ?? []
            isLoading = false
        }
    }
}

struct TodayNewsletterRow: View {
    let post: NewsletterPost
    let schoolName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: post.media.isEmpty ? "newspaper" : "photo.on.rectangle")
                .font(.subheadline.bold())
                .foregroundColor(AppConstants.Colors.brandNavy)
                .frame(width: 38, height: 38)
                .background(AppConstants.Colors.wingMist)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(post.title)
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(schoolName).lineLimit(1)
                    if let createdAt = post.createdAt {
                        Text("•")
                        Text(createdAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.caption)
                .foregroundColor(AppConstants.Colors.secondaryText)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.secondaryText)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }
}

private struct NewsletterStoryCard: View {
    let post: NewsletterPost
    let author: UserProfile?
    let publicationName: String

    private var featuredMedia: NewsletterMedia? {
        post.media.first(where: \.isVisual)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let featuredMedia {
                NewsletterHeroPreview(media: featuredMedia)
                    .aspectRatio(16 / 9, contentMode: .fit)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("SCHOOL NEWSLETTER")
                    .font(.caption2.bold())
                    .tracking(1.1)
                    .foregroundColor(AppConstants.Colors.primaryAction)

                Text(post.title)
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .foregroundColor(AppConstants.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(newsletterExcerptAttributedString(post.body))
                    .font(.subheadline)
                    .lineSpacing(3)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                    .lineLimit(3)

                HStack(spacing: 10) {
                    NewsletterAuthorAvatar(profile: author, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(author?.displayName ?? publicationName)
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        if let createdAt = post.createdAt {
                            Text(createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundColor(AppConstants.Colors.secondaryText)
                        }
                    }

                    Spacer()

                    if post.media.isEmpty == false {
                        Label("\(post.media.count)", systemImage: "paperclip")
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.secondaryText)
                    }
                    Image(systemName: "arrow.right")
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.primaryAction)
                }
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

struct NewsletterDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let post: NewsletterPost
    let author: UserProfile?
    let publicationName: String
    let canManage: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var featuredMedia: NewsletterMedia? {
        post.media.first(where: \.isVisual)
    }

    private var remainingMedia: [NewsletterMedia] {
        guard let featuredMedia else { return post.media }
        return post.media.filter { $0.id != featuredMedia.id }
    }

    private var paragraphs: [String] {
        post.body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(publicationName.uppercased())
                        .font(.caption.bold())
                        .tracking(1.2)
                        .foregroundColor(AppConstants.Colors.primaryAction)

                    Text(post.title)
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                        .foregroundColor(AppConstants.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        NewsletterAuthorAvatar(profile: author, size: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(author?.displayName ?? "School Team")
                                .font(.subheadline.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                            if let createdAt = post.createdAt {
                                Text(createdAt.formatted(date: .long, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(AppConstants.Colors.secondaryText)
                            }
                        }
                    }

                    Divider().overlay(AppConstants.Colors.separator)

                    if let featuredMedia {
                        NewsletterMediaBlock(media: featuredMedia, isHero: true)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            NewsletterParagraphView(markdown: paragraph)
                        }
                    }

                    if remainingMedia.isEmpty == false {
                        Divider().overlay(AppConstants.Colors.separator)
                        Text("Media & attachments")
                            .font(.title3.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        ForEach(remainingMedia) { media in
                            NewsletterMediaBlock(media: media, isHero: false)
                        }
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Newsletter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Edit Newsletter", systemImage: "pencil") {
                            onEdit()
                        }
                        Button("Delete Newsletter", systemImage: "trash", role: .destructive) {
                            dismiss()
                            onDelete()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Newsletter actions")
                }
            }
        }
    }
}

private struct NewsletterParagraphView: View {
    let markdown: String

    var body: some View {
        Text(newsletterPlainText(markdown))
            .font(.system(.body, design: .serif))
            .lineSpacing(7)
            .foregroundColor(AppConstants.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

func newsletterPlainText(_ text: String) -> String {
    var plainText = text
    let replacements = [
        ("(?m)^#{1,6}[ \\t]+", ""),
        ("\\[([^\\]]+)\\]\\([^\\n)]+\\)", "$1"),
        ("\\*\\*([^*\\n]+)\\*\\*", "$1"),
        ("__([^_\\n]+)__", "$1"),
        ("(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)", "$1"),
        ("(?<!_)_([^_\\n]+)_(?!_)", "$1")
    ]
    for (pattern, replacement) in replacements {
        plainText = plainText.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: .regularExpression
        )
    }
    return plainText
}

private func newsletterExcerptAttributedString(_ text: String) -> String {
    newsletterPlainText(text)
}

private struct NewsletterHeroPreview: View {
    let media: NewsletterMedia

    @State private var signedURL: URL?

    var body: some View {
        ZStack {
            Rectangle().fill(AppConstants.Colors.raised)

            if media.isImage, let signedURL {
                AsyncImage(url: signedURL) { image in
                    GeometryReader { proxy in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    }
                } placeholder: {
                    ProgressView().tint(AppConstants.Colors.primaryAction)
                }
                .accessibilityLabel(media.accessibilityDescription)
            } else if media.isVideo {
                VStack(spacing: 10) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                    Text(media.displayName)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                .foregroundColor(AppConstants.Colors.primaryAction)
                .padding()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(media.accessibilityDescription)
            } else {
                ProgressView().tint(AppConstants.Colors.primaryAction)
            }
        }
        .clipped()
        .task(id: media.filePath) {
            guard media.isImage else { return }
            signedURL = try? await SchoolService.shared.signedPrivateFileURL(path: media.filePath)
        }
    }
}

private struct NewsletterMediaBlock: View {
    @Environment(\.openURL) private var openURL

    let media: NewsletterMedia
    let isHero: Bool

    @State private var signedURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Group {
                if media.isImage {
                    if let destination = media.linkDestination {
                        Button {
                            openURL(destination)
                        } label: {
                            imageContent
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(9)
                                        .background(.black.opacity(0.58), in: Circle())
                                        .padding(10)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the attached link")
                    } else {
                        imageContent
                    }
                } else if media.isVideo, let signedURL {
                    NewsletterVideoPlayer(url: signedURL)
                        .frame(minHeight: isHero ? 250 : 210)
                        .accessibilityLabel(media.accessibilityDescription)
                } else if media.isVideo {
                    mediaPlaceholder(icon: "video.fill")
                } else {
                    Button {
                        if let signedURL { openURL(signedURL) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "doc.fill")
                                .font(.title2)
                                .foregroundColor(AppConstants.Colors.primaryAction)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(media.displayName)
                                    .font(.subheadline.bold())
                                    .foregroundColor(AppConstants.Colors.primaryText)
                                Text("Open attachment")
                                    .font(.caption)
                                    .foregroundColor(AppConstants.Colors.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(AppConstants.Colors.primaryAction)
                        }
                        .padding(16)
                        .background(AppConstants.Colors.card)
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(signedURL == nil)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.controlRadius, style: .continuous))

            if let caption = media.caption?.trimmingCharacters(in: .whitespacesAndNewlines), caption.isEmpty == false {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if media.isImage == false, let destination = media.linkDestination {
                Link(destination: destination) {
                    Label("Open related link", systemImage: "arrow.up.right")
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.primaryAction)
                }
            }
        }
        .frame(maxWidth: media.resolvedLayout.maximumWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: media.resolvedLayout == .wide ? .leading : .center)
        .task(id: media.filePath) {
            signedURL = try? await SchoolService.shared.signedPrivateFileURL(path: media.filePath)
        }
    }

    private var imageContent: some View {
        AsyncImage(url: signedURL) { image in
            image
                .resizable()
                .scaledToFit()
        } placeholder: {
            mediaPlaceholder(icon: "photo")
        }
        .accessibilityLabel(media.accessibilityDescription)
    }

    private func mediaPlaceholder(icon: String) -> some View {
        ZStack {
            Rectangle()
                .fill(AppConstants.Colors.raised)
                .aspectRatio(16 / 9, contentMode: .fit)
            ProgressView()
                .tint(AppConstants.Colors.primaryAction)
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(AppConstants.Colors.primaryAction.opacity(0.35))
                .offset(y: 34)
        }
    }
}

private struct NewsletterVideoPlayer: View {
    let url: URL

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(AppConstants.Colors.primaryAction)
            }
        }
        .background(Color.black)
        .task(id: url) {
            player = AVPlayer(url: url)
        }
        .onDisappear {
            player?.pause()
        }
    }
}

private struct NewsletterAuthorAvatar: View {
    let profile: UserProfile?
    let size: CGFloat

    var body: some View {
        Group {
            if let url = profile?.avatarUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(AppConstants.Colors.wingMist)
            .overlay {
                Text(profile?.initials ?? "FF")
                    .font(.system(size: max(10, size * 0.3), weight: .bold))
                    .foregroundColor(AppConstants.Colors.brandNavy)
            }
    }
}

private extension NewsletterMedia {
    var isImage: Bool { contentType?.hasPrefix("image/") == true }
    var isVideo: Bool { contentType?.hasPrefix("video/") == true }
    var isVisual: Bool { isImage || isVideo }
    var displayName: String {
        guard let fileName, fileName.isEmpty == false else { return "Attachment" }
        return fileName
    }

    var accessibilityDescription: String {
        let trimmed = altText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? displayName : trimmed
    }

    var resolvedLayout: NewsletterMediaLayout { layout ?? .wide }

    var linkDestination: URL? {
        normalizedNewsletterWebURL(linkURL ?? "")
    }
}

private func normalizedNewsletterWebURL(_ rawValue: String) -> URL? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return nil }
    let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard let components = URLComponents(string: candidate),
          ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
          components.host?.isEmpty == false else { return nil }
    return components.url
}

private extension NewsletterMediaLayout {
    var maximumWidth: CGFloat {
        switch self {
        case .wide: .infinity
        case .inset: 560
        case .compact: 360
        }
    }
}

private struct NewsletterMediaDraft: Identifiable {
    let id: UUID
    let existingFilePath: String?
    let data: Data?
    let fileName: String
    let contentType: String?
    var altText: String
    var caption: String
    var layout: NewsletterMediaLayout
    var linkURL: String

    init(data: Data, fileName: String, contentType: String?) {
        id = UUID()
        existingFilePath = nil
        self.data = data
        self.fileName = fileName
        self.contentType = contentType
        altText = ""
        caption = ""
        layout = .wide
        linkURL = ""
    }

    init(media: NewsletterMedia) {
        id = media.id
        existingFilePath = media.filePath
        data = nil
        fileName = media.displayName
        contentType = media.contentType
        altText = media.altText ?? ""
        caption = media.caption ?? ""
        layout = media.resolvedLayout
        linkURL = media.linkURL ?? ""
    }

    var isImage: Bool { contentType?.hasPrefix("image/") == true }
    var isVideo: Bool { contentType?.hasPrefix("video/") == true }
    var isVisual: Bool { isImage || isVideo }
    var hasInvalidLink: Bool {
        let trimmed = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty == false && normalizedNewsletterWebURL(trimmed) == nil
    }
    var linkDestination: URL? { normalizedNewsletterWebURL(linkURL) }

    var previewMedia: NewsletterMedia? {
        guard let existingFilePath else { return nil }
        return NewsletterMedia(
            id: id,
            fileName: fileName,
            filePath: existingFilePath,
            contentType: contentType,
            altText: altText,
            caption: caption,
            sortOrder: 0,
            layout: layout,
            linkURL: linkURL
        )
    }

    var retainedMedia: NewsletterMedia? { previewMedia }

    var upload: NewsletterMediaUpload? {
        guard let data else { return nil }
        return NewsletterMediaUpload(
            data: data,
            fileName: fileName,
            contentType: contentType,
            altText: altText,
            caption: caption,
            layout: layout,
            linkURL: linkURL
        )
    }
}

private struct NewsletterComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    let post: NewsletterPost?
    var onSaved: () -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var mediaDrafts: [NewsletterMediaDraft]
    @State private var showingFileImporter = false
    @State private var showingPreview = false
    @State private var isPreparingMedia = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    @MainActor
    init(post: NewsletterPost?, onSaved: @escaping () -> Void) {
        self.post = post
        self.onSaved = onSaved
        _title = State(initialValue: post?.title ?? "")
        _bodyText = State(initialValue: post.map { newsletterPlainText($0.body) } ?? "")
        _mediaDrafts = State(initialValue: post?.media.map(NewsletterMediaDraft.init(media:)) ?? [])
    }

    private var canPost: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && mediaDrafts.contains(where: \.hasInvalidLink) == false
            && isPreparingMedia == false
            && isSaving == false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(post == nil ? "Write an update" : "Edit this story")
                            .font(.system(.title2, design: .serif, weight: .bold))
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Text("Use a clear headline, readable paragraphs, and media that adds useful context.")
                            .font(.subheadline)
                            .foregroundColor(AppConstants.Colors.secondaryText)

                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Headline", text: $title, axis: .vertical)
                                .font(.system(.title2, design: .serif, weight: .bold))
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .textInputAutocapitalization(.sentences)

                            Divider().overlay(AppConstants.Colors.separator)

                            ZStack(alignment: .topLeading) {
                                if bodyText.isEmpty {
                                    Text("Tell your school community what happened…")
                                        .font(.body)
                                        .foregroundColor(AppConstants.Colors.secondaryText.opacity(0.75))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                                TextEditor(text: $bodyText)
                                    .font(.body)
                                    .lineSpacing(5)
                                    .foregroundColor(AppConstants.Colors.primaryText)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 220)
                            }
                        }
                        .padding(16)
                        .background(AppConstants.Colors.card)
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Media & attachments")
                                .font(.headline)
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Text("Add up to 10 photos, videos, or files. The first photo or video becomes the cover; the rest appear with the story. Include alt text for accessibility.")
                                .font(.caption)
                                .foregroundColor(AppConstants.Colors.secondaryText)

                            HStack(spacing: 10) {
                                PhotosPicker(
                                    selection: $selectedMediaItems,
                                    maxSelectionCount: max(1, 10 - mediaDrafts.count),
                                    matching: .any(of: [.images, .videos])
                                ) {
                                    Label("Photos & video", systemImage: "photo.on.rectangle.angled")
                                        .frame(maxWidth: .infinity, minHeight: AppConstants.Layout.minimumTapTarget)
                                }
                                .buttonStyle(.bordered)
                                .disabled(mediaDrafts.count >= 10 || isPreparingMedia)

                                Button {
                                    showingFileImporter = true
                                } label: {
                                    Label("Files", systemImage: "paperclip")
                                        .frame(maxWidth: .infinity, minHeight: AppConstants.Layout.minimumTapTarget)
                                }
                                .buttonStyle(.bordered)
                                .disabled(mediaDrafts.count >= 10 || isPreparingMedia)
                            }
                            .tint(AppConstants.Colors.primaryAction)

                            if isPreparingMedia {
                                ProgressView("Preparing media")
                                    .tint(AppConstants.Colors.primaryAction)
                                    .foregroundColor(AppConstants.Colors.primaryText)
                            }

                            ForEach($mediaDrafts) { $draft in
                                NewsletterComposerMediaRow(draft: $draft) {
                                    mediaDrafts.removeAll { $0.id == draft.id }
                                }
                            }
                        }
                        .padding(16)
                        .background(AppConstants.Colors.card)
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))

                        Button {
                            showingPreview = true
                        } label: {
                            Label("Preview Newsletter", systemImage: "eye.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: AppConstants.Layout.minimumTapTarget)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppConstants.Colors.primaryAction)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.controlRadius, style: .continuous))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(post == nil ? "New Newsletter" : "Edit Newsletter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : (post == nil ? "Post" : "Save")) { save() }
                        .disabled(canPost == false)
                }
            }
            .onChange(of: selectedMediaItems) { _, items in
                guard items.isEmpty == false else { return }
                Task { await prepareSelectedMedia(items) }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                Task { await prepareSelectedFiles(result) }
            }
            .sheet(isPresented: $showingPreview) {
                NavigationStack {
                    NewsletterDraftPreview(
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        bodyText: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                        mediaDrafts: mediaDrafts,
                        publicationName: appSession.activeSchool?.name ?? "School Newsletter"
                    )
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingPreview = false }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func prepareSelectedMedia(_ items: [PhotosPickerItem]) async {
        isPreparingMedia = true
        errorMessage = nil
        defer {
            isPreparingMedia = false
            selectedMediaItems = []
        }

        do {
            let remaining = max(0, 10 - mediaDrafts.count)
            for item in items.prefix(remaining) {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let type = item.supportedContentTypes.first
                let contentType = type?.preferredMIMEType ?? "image/jpeg"
                let ext = type?.preferredFilenameExtension ?? (contentType.hasPrefix("video/") ? "mov" : "jpg")
                let prefix = contentType.hasPrefix("video/") ? "video" : "photo"
                mediaDrafts.append(NewsletterMediaDraft(
                    data: data,
                    fileName: "\(prefix)-\(UUID().uuidString).\(ext)",
                    contentType: contentType
                ))
            }
        } catch {
            errorMessage = AppErrorMessage.school("Could not prepare selected media", error)
        }
    }

    @MainActor
    private func prepareSelectedFiles(_ result: Result<[URL], Error>) async {
        isPreparingMedia = true
        errorMessage = nil
        defer { isPreparingMedia = false }

        do {
            let urls = try result.get()
            let remaining = max(0, 10 - mediaDrafts.count)
            for url in urls.prefix(remaining) {
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing { url.stopAccessingSecurityScopedResource() }
                }
                let data = try Data(contentsOf: url)
                let type = UTType(filenameExtension: url.pathExtension)
                mediaDrafts.append(NewsletterMediaDraft(
                    data: data,
                    fileName: url.lastPathComponent.isEmpty ? "Attachment" : url.lastPathComponent,
                    contentType: type?.preferredMIMEType ?? "application/octet-stream"
                ))
            }
        } catch {
            errorMessage = AppErrorMessage.school("Could not prepare selected files", error)
        }
    }

    private func save() {
        guard let schoolId = appSession.activeSchool?.id else { return }
        isSaving = true
        errorMessage = nil
        let uploads = mediaDrafts.compactMap(\.upload)
        let retainedMedia = mediaDrafts.compactMap(\.retainedMedia)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = newsletterPlainText(bodyText).trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                if let post {
                    try await SchoolWorkflowService.shared.updateNewsletter(
                        post: post,
                        title: cleanTitle,
                        body: cleanBody,
                        retainedMedia: retainedMedia,
                        newMedia: uploads
                    )
                } else {
                    try await SchoolWorkflowService.shared.createNewsletter(
                        schoolId: schoolId,
                        title: cleanTitle,
                        body: cleanBody,
                        media: uploads
                    )
                }
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school(
                        post == nil ? "Could not post newsletter" : "Could not update newsletter",
                        error
                    )
                }
            }
        }
    }
}

private struct NewsletterDraftPreview: View {
    let title: String
    let bodyText: String
    let mediaDrafts: [NewsletterMediaDraft]
    let publicationName: String

    private var featuredMedia: NewsletterMediaDraft? {
        mediaDrafts.first(where: \.isVisual)
    }

    private var remainingMedia: [NewsletterMediaDraft] {
        guard let featuredMedia else { return mediaDrafts }
        return mediaDrafts.filter { $0.id != featuredMedia.id }
    }

    private var paragraphs: [String] {
        bodyText
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text(publicationName.uppercased())
                            .font(.caption.bold())
                            .tracking(1.2)
                            .foregroundColor(AppConstants.Colors.primaryAction)
                        Spacer()
                        Label("Preview", systemImage: "eye")
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.secondaryText)
                    }

                    Text(title)
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                        .foregroundColor(AppConstants.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Label("Unpublished draft", systemImage: "pencil.line")
                        .font(.subheadline.bold())
                        .foregroundColor(AppConstants.Colors.secondaryText)

                    Divider().overlay(AppConstants.Colors.separator)

                    if let featuredMedia {
                        NewsletterDraftMediaPreview(draft: featuredMedia, isHero: true)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            NewsletterParagraphView(markdown: paragraph)
                        }
                    }

                    if remainingMedia.isEmpty == false {
                        Divider().overlay(AppConstants.Colors.separator)
                        Text("Media & attachments")
                            .font(.title3.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        ForEach(remainingMedia) { draft in
                            NewsletterDraftMediaPreview(draft: draft, isHero: false)
                        }
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Newsletter Preview")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NewsletterDraftMediaPreview: View {
    let draft: NewsletterMediaDraft
    let isHero: Bool

    var body: some View {
        Group {
            if let existingMedia = draft.previewMedia {
                NewsletterMediaBlock(media: existingMedia, isHero: isHero)
            } else {
                localMedia
            }
        }
    }

    private var localMedia: some View {
        VStack(alignment: .leading, spacing: 9) {
            mediaContent
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.controlRadius, style: .continuous))

            if draft.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                Text(draft.caption)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if draft.isImage == false, let destination = draft.linkDestination {
                Link(destination: destination) {
                    Label("Open related link", systemImage: "arrow.up.right")
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.primaryAction)
                }
            }
        }
        .frame(maxWidth: draft.layout.maximumWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: draft.layout == .wide ? .leading : .center)
    }

    @ViewBuilder
    private var mediaContent: some View {
        if draft.isImage, let data = draft.data, let image = UIImage(data: data) {
            if let destination = draft.linkDestination {
                Link(destination: destination) {
                    localImage(image)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "arrow.up.right")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(9)
                                .background(.black.opacity(0.58), in: Circle())
                                .padding(10)
                        }
                }
                .accessibilityHint("Opens the attached link")
            } else {
                localImage(image)
            }
        } else if draft.isVideo {
            ZStack {
                Color.black
                VStack(spacing: 10) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                    Text(draft.fileName)
                        .font(.caption.bold())
                        .lineLimit(2)
                    Text("Playable after publishing")
                        .font(.caption2)
                }
                .foregroundColor(.white)
                .padding()
            }
            .aspectRatio(16 / 9, contentMode: .fit)
        } else {
            HStack(spacing: 14) {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundColor(AppConstants.Colors.primaryAction)
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.fileName)
                        .font(.subheadline.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                    Text("Attachment will be available after publishing")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.secondaryText)
                }
                Spacer()
            }
            .padding(16)
            .background(AppConstants.Colors.card)
        }
    }

    private func localImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .accessibilityLabel(draft.altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? draft.fileName : draft.altText)
    }
}

private struct NewsletterComposerMediaRow: View {
    @Binding var draft: NewsletterMediaDraft
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                preview
                    .frame(width: 72, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.fileName)
                        .font(.subheadline.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                        .lineLimit(2)
                    Text(draft.contentType ?? "Attachment")
                        .font(.caption2)
                        .foregroundColor(AppConstants.Colors.secondaryText)
                }

                Spacer()

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: AppConstants.Layout.minimumTapTarget, height: AppConstants.Layout.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(draft.fileName)")
            }

            if draft.isVisual {
                Picker("Media size", selection: $draft.layout) {
                    ForEach(NewsletterMediaLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Alt text — describe what readers should know", text: $draft.altText, axis: .vertical)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)

                TextField("Click-through link (optional)", text: $draft.linkURL)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                if draft.hasInvalidLink {
                    Text("Enter a valid website address, such as example.com")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            TextField("Caption (optional)", text: $draft.caption, axis: .vertical)
                .font(.caption)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var preview: some View {
        if draft.isImage, let data = draft.data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else if draft.isImage, let media = draft.previewMedia {
            NewsletterHeroPreview(media: media)
        } else {
            ZStack {
                AppConstants.Colors.raised
                Image(systemName: draft.isVideo ? "video.fill" : "doc.fill")
                    .font(.title2)
                    .foregroundColor(AppConstants.Colors.primaryAction)
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
        .environmentObject(AppSessionManager())
}
