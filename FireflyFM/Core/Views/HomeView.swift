//
//  HomeView.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var notificationInbox: NotificationInboxStore

    @State private var newsletters: [NewsletterPost] = []
    @State private var upcomingEvents: [SchoolEvent] = []
    @State private var communityPosts: [CommunityPost] = []
    @State private var children: [Child] = []
    @State private var inboxItems: [AssignmentInboxItem] = []
    @State private var reviewItems: [AssignmentInboxItem] = []
    @State private var isLoading = false
    @State private var isDashboardLoading = false
    @State private var showingProfile = false
    @State private var showingNewsletterComposer = false
    @State private var showingSignOutConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        upNextCard
                        roleSummary
                        upcomingSection
                        communityActivitySection
                        workspaceStrip
                        newsletterSection
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
                NewsletterComposerView {
                    Task { await loadNewsletters() }
                }
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
                        Text("FireflyFM")
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
            sectionHeader("Recent Community activity", systemImage: "person.3")
            if let post = communityPosts.first {
                Text(post.body)
                    .font(.subheadline)
                    .foregroundStyle(AppConstants.Colors.primaryText)
                    .lineLimit(4)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppConstants.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Newsletters")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                if appSession.role?.canManageSchool == true {
                    Button {
                        showingNewsletterComposer = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                }
            }

            if isLoading {
                ProgressView().tint(AppConstants.Colors.accessibleYellow)
            } else if newsletters.isEmpty {
                emptyPanel("No newsletters yet")
            } else {
                ForEach(newsletters) { post in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(post.title)
                            .font(.headline)
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Text(post.body)
                            .font(.subheadline)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
                        if let createdAt = post.createdAt {
                            Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.45))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppConstants.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var workspaces: [WorkspaceItem] {
        switch appSession.role {
        case .parent:
            return [
                WorkspaceItem(title: "Work", subtitle: "Assignments and feedback", icon: "checklist.checked", destination: AnyView(AssignmentsView(surface: .all))),
                WorkspaceItem(title: "Children", subtitle: "Profiles and records", icon: "figure.2.and.child.holdinghands", destination: AnyView(ChildrenView())),
                WorkspaceItem(title: "Payments", subtitle: "Invoices and receipts", icon: "creditcard.fill", destination: AnyView(PaymentsView()))
            ]
        case .teacher:
            return [
                WorkspaceItem(title: "Work", subtitle: "Assignments and feedback", icon: "checklist.checked", destination: AnyView(AssignmentsView(surface: .all))),
                WorkspaceItem(title: "Children", subtitle: "Check-in and activity", icon: "figure.2.and.child.holdinghands", destination: AnyView(ChildrenView()))
            ]
        case .schoolDirector:
            return [
                WorkspaceItem(title: "Work", subtitle: "Assign, submit, and review", icon: "checklist.checked", destination: AnyView(AssignmentsView(surface: .all))),
                WorkspaceItem(title: "Children", subtitle: "Attendance and logs", icon: "figure.2.and.child.holdinghands", destination: AnyView(ChildrenView())),
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
                WorkspaceItem(title: "Work", subtitle: "Assignments and reviews", icon: "checklist.checked", destination: AnyView(AssignmentsView(surface: .all))),
                WorkspaceItem(title: "Children", subtitle: "Cross-school records", icon: "figure.2.and.child.holdinghands", destination: AnyView(ChildrenView()))
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
            guard appSession.activeMembershipId == membershipId else { return }
            newsletters = loaded
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load newsletters", error)
            isLoading = false
        }
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
        guard appSession.activeMembershipId == membershipId else { return }
        communityPosts = loaded
    }

    @MainActor
    private func loadChildren(schoolId: UUID, membershipId: UUID) async {
        let loaded = (try? await SchoolWorkflowService.shared.fetchChildren(schoolId: schoolId)) ?? []
        guard appSession.activeMembershipId == membershipId else { return }
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

private struct NewsletterComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    var onSaved: () -> Void

    @State private var title = ""
    @State private var bodyText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Newsletter") {
                    TextField("Title", text: $title)
                    TextField("Body", text: $bodyText, axis: .vertical)
                        .lineLimit(5...10)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("New Newsletter")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Post") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        guard let schoolId = appSession.activeSchool?.id else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await SchoolWorkflowService.shared.createNewsletter(
                    schoolId: schoolId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not post newsletter", error)
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
        .environmentObject(AppSessionManager())
}
