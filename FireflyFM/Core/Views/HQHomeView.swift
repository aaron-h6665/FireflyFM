//
//  HQHomeView.swift
//  FireflyFM
//

import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct HQHomeView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var schools: [School] = []
    @State private var newsletters: [NewsletterPost] = []
    @State private var newsletterSchoolNames: [UUID: String] = [:]
    @State private var showingProfile = false
    @State private var showingNewSchool = false
    @State private var showingEventPush = false
    @State private var editingSchool: School?
    @State private var deletingSchool: School?
    @State private var showingSignOutConfirmation = false
    @State private var isLoading = true
    @State private var isLoadingNewsletters = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        topBar
                        schoolSection
                        hqWorkspaceGrid
                        hqNewsletterSection

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                }
                .refreshable { await loadSchools() }

                if showingSignOutConfirmation {
                    SignOutConfirmationOverlay(
                        message: "You will need to sign in again to manage your schools.",
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
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
            .sheet(isPresented: $showingNewSchool) {
                NewSchoolCreationView {
                    Task { await loadSchools() }
                }
            }
            .sheet(isPresented: $showingEventPush) {
                HQEventPushView(schools: schools)
            }
            .sheet(item: $editingSchool) { school in
                SchoolEditView(school: school) { updated in
                    if let index = schools.firstIndex(where: { $0.id == updated.id }) {
                        schools[index] = updated
                    }
                    Task { await loadSchools() }
                }
            }
            .sheet(item: $deletingSchool) { school in
                SchoolDeletionConfirmationView(school: school) {
                    Task { await loadSchools() }
                }
            }
            .task(id: appSession.activeMembershipId) { await loadSchools() }
        }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 10) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Today")
                        .font(.title2.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                    Text("HQ overview")
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
                if let avatarUrl = appSession.profile?.avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        profilePlaceholder
                    }
                    .frame(width: AppConstants.Layout.minimumTapTarget, height: AppConstants.Layout.minimumTapTarget)
                    .clipShape(Circle())
                } else {
                    profilePlaceholder
                        .frame(width: AppConstants.Layout.minimumTapTarget, height: AppConstants.Layout.minimumTapTarget)
                }
            }
            .accessibilityLabel("Account menu")
        }
    }

    private var profilePlaceholder: some View {
        Circle()
            .fill(AppConstants.Colors.wingMist)
            .overlay(
                Text(appSession.profile?.initials ?? "HQ")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.brandNavy)
            )
    }

    private var schoolSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Schools")
                        .font(.title2.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                    Text("\(schools.count) school\(schools.count == 1 ? "" : "s") in your organization")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.secondaryText)
                }
                Spacer()
                Button {
                    showingNewSchool = true
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.bold())
                        .frame(width: AppConstants.Layout.minimumTapTarget, height: AppConstants.Layout.minimumTapTarget)
                        .background(AppConstants.Colors.primaryAction)
                        .foregroundColor(AppConstants.Colors.primaryActionText)
                        .clipShape(Circle())
                }
                .accessibilityLabel("New School")
            }

            if isLoading {
                ProgressView()
                    .tint(AppConstants.Colors.primaryAction)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else if schools.isEmpty {
                Button {
                    showingNewSchool = true
                } label: {
                    Label("Create your first school", systemImage: "building.2.crop.circle")
                        .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppConstants.Colors.primaryAction)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(schools.prefix(4).enumerated()), id: \.element.id) { index, school in
                        NavigationLink {
                            HQSchoolHubView(school: school)
                        } label: {
                            schoolRow(school)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit School", systemImage: "pencil") { editingSchool = school }
                            Button("Delete School", systemImage: "trash", role: .destructive) { deletingSchool = school }
                        }
                        if index < min(schools.count, 4) - 1 {
                            Divider().overlay(AppConstants.Colors.separator).padding(.leading, 66)
                        }
                    }
                }
                .background(AppConstants.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous)
                        .stroke(AppConstants.Colors.separator.opacity(0.65), lineWidth: 1)
                }

                NavigationLink {
                    HQSchoolsListView(schools: schools) {
                        Task { await loadSchools() }
                    }
                } label: {
                    HStack {
                        Text(schools.count > 4 ? "View all \(schools.count) schools" : "Manage schools")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.primaryAction)
                    .frame(minHeight: AppConstants.Layout.minimumTapTarget)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func schoolRow(_ school: School) -> some View {
        HStack(spacing: 12) {
            SchoolAvatarView(school: school, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(school.name)
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                Text(school.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                     ? school.description ?? ""
                     : "Open school overview")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.secondaryText)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
    }

    private var hqWorkspaceGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Operations")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.primaryText)

            VStack(spacing: 0) {
                NavigationLink {
                    HQOverviewView()
                } label: {
                    HQToolRow(title: "Overview", subtitle: "Records and exceptions by school", icon: "chart.bar.xaxis")
                }
                .buttonStyle(.plain)
                hqToolDivider

                NavigationLink {
                    ChildrenAttendanceWorkspace()
                } label: {
                    HQToolRow(title: "Children & Attendance", subtitle: "One cross-school roster and attendance view", icon: "person.2.crop.square.stack.fill")
                }
                .buttonStyle(.plain)
                hqToolDivider

                NavigationLink {
                    AssignmentsView(surface: .hqEducation)
                } label: {
                    HQToolRow(title: "Education", subtitle: "Assignments, training, and reviews", icon: "checklist.checked")
                }
                .buttonStyle(.plain)
                hqToolDivider

                Button {
                    showingEventPush = true
                } label: {
                    HQToolRow(title: "Event Push", subtitle: "Send an event to selected schools", icon: "calendar.badge.plus")
                }
                .buttonStyle(.plain)
            }
            .background(AppConstants.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous)
                    .stroke(AppConstants.Colors.separator.opacity(0.65), lineWidth: 1)
            }
        }
    }

    private var hqToolDivider: some View {
        Divider().overlay(AppConstants.Colors.separator).padding(.leading, 58)
    }

    private var hqNewsletterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Latest newsletters", systemImage: "newspaper.fill")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                Text("Across schools")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
            }

            if isLoadingNewsletters {
                ProgressView()
                    .tint(AppConstants.Colors.primaryAction)
                    .frame(maxWidth: .infinity, minHeight: 62)
            } else if newsletters.isEmpty {
                Text("No school newsletters yet")
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .background(AppConstants.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.controlRadius, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(newsletters.prefix(3).enumerated()), id: \.element.id) { index, post in
                        NavigationLink {
                            NewsletterDetailView(
                                post: post,
                                author: nil,
                                publicationName: newsletterSchoolNames[post.schoolId] ?? "School Newsletter",
                                canManage: false,
                                onEdit: {},
                                onDelete: {}
                            )
                        } label: {
                            TodayNewsletterRow(
                                post: post,
                                schoolName: newsletterSchoolNames[post.schoolId] ?? "School"
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
            }
        }
    }

    @MainActor
    private func loadSchools() async {
        isLoading = true
        isLoadingNewsletters = true
        errorMessage = nil

        do {
            let loadedSchools = try await SchoolService.shared.fetchSchoolsForHQ()
            schools = loadedSchools
            newsletterSchoolNames = Dictionary(uniqueKeysWithValues: loadedSchools.map { ($0.id, $0.name) })
            isLoading = false
            newsletters = await loadRecentNewsletters(for: loadedSchools)
            isLoadingNewsletters = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
            isLoadingNewsletters = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load schools", error)
            isLoading = false
            isLoadingNewsletters = false
        }
    }

    private func loadRecentNewsletters(for schools: [School]) async -> [NewsletterPost] {
        await withTaskGroup(of: [NewsletterPost].self) { group in
            for school in schools {
                group.addTask {
                    (try? await SchoolWorkflowService.shared.fetchNewsletters(schoolId: school.id)) ?? []
                }
            }

            var combined: [NewsletterPost] = []
            for await schoolPosts in group {
                combined.append(contentsOf: schoolPosts.prefix(3))
            }
            return combined.sorted {
                ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
        }
    }
}

private enum HQSchoolHubSection: String, CaseIterable, Identifiable {
    case operations = "Operations"
    case community = "Community"

    var id: String { rawValue }
}

private struct HQSchoolHubView: View {
    @State private var school: School
    @State private var selectedSection: HQSchoolHubSection = .operations

    init(school: School) {
        _school = State(initialValue: school)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    SchoolAvatarView(school: school, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(school.name)
                            .font(.title3.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Text("HQ school view")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
                    }
                    Spacer()
                }

                Picker("School section", selection: $selectedSection) {
                    ForEach(HQSchoolHubSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .background(AppConstants.Colors.background)

            switch selectedSection {
            case .operations:
                HQSchoolOperationsView(school: school) { updatedSchool in
                    school = updatedSchool
                }
            case .community:
                CommunityView(school: school)
                    .id(school.updatedAt ?? school.createdAt)
            }
        }
        .background(AppConstants.Colors.background.ignoresSafeArea())
        .navigationTitle(school.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HQSchoolOperationsView: View {
    let school: School
    var onSchoolUpdated: (School) -> Void

    @State private var members: [SchoolMember] = []
    @State private var pendingDirectorInvites: [RoleInvite] = []
    @State private var roster: [ChildRosterItem] = []
    @State private var requirements: [OnboardingRequirement] = []
    @State private var submissions: [DocumentSubmission] = []
    @State private var directorTemplate = OnboardingTemplateBundle(template: nil, requirements: [], attachments: [])
    @State private var directorProgress = OnboardingRoleProgress.empty
    @State private var showingSchoolEditor = false
    @State private var showingDirectorInvite = false
    @State private var cancellingDirectorInvite: RoleInvite?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var directors: [SchoolMember] {
        members
            .filter { $0.membership.role == .schoolDirector }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var directorRequirements: [OnboardingRequirement] {
        let directorIDs = Set(directors.map(\.membership.userId))
        return requirements.filter { requirement in
            requirement.targetRole == .schoolDirector
                || requirement.targetUserId.map(directorIDs.contains) == true
                || (requirement.targetRole == nil && requirement.targetUserId == nil)
        }
    }

    private var requirementsNeedingSubmission: Int {
        directorRequirements.filter { requirement in
            submissions.contains {
                $0.requirementId == requirement.id && $0.status == "verified"
            } == false
        }.count
    }

    private var changesRequested: Int {
        let relevantIDs = Set(directorRequirements.map(\.id))
        return submissions.filter {
            relevantIDs.contains($0.requirementId) && $0.status == "flagged"
        }.count
    }

    private var checkedInNow: Int {
        roster.filter(\.isCheckedIn).count
    }

    private var checkedOutToday: Int {
        roster.filter { $0.todayAttendance?.checkedOutAt != nil }.count
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading school operations")
                    .tint(AppConstants.Colors.accessibleYellow)
                    .foregroundColor(AppConstants.Colors.primaryText)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        schoolSummary
                        directorAssignment
                        peopleMetrics
                        attendanceMetrics

                        if let errorMessage {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                Button("Try Again") {
                                    Task { await load() }
                                }
                                .buttonStyle(HQSecondaryButtonStyle())
                            }
                        }
                    }
                    .padding()
                }
                .refreshable { await load() }
            }
        }
        .task(id: school.id) { await load() }
        .sheet(isPresented: $showingSchoolEditor) {
            SchoolEditView(school: school) { updatedSchool in
                onSchoolUpdated(updatedSchool)
            }
        }
        .sheet(isPresented: $showingDirectorInvite) {
            HQDirectorInviteSheet(school: school) {
                Task { await load() }
            }
        }
        .confirmationDialog(
            "Cancel this director invitation?",
            isPresented: Binding(
                get: { cancellingDirectorInvite != nil },
                set: { if $0 == false { cancellingDirectorInvite = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Cancel Invitation", role: .destructive) { cancelPendingDirectorInvite() }
            Button("Keep Invitation", role: .cancel) { cancellingDirectorInvite = nil }
        } message: {
            Text("The existing invitation link will stop working immediately. You can invite a different director afterward.")
        }
    }

    private var schoolSummary: some View {
        HStack(alignment: .top, spacing: 12) {
            SchoolAvatarView(school: school, size: 64)
            VStack(alignment: .leading, spacing: 5) {
                Text("School Operations")
                    .font(.title2.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                Text(school.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                     ? school.description ?? ""
                     : "No school description has been added yet.")
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.64))
            }
            Spacer()
            Button {
                showingSchoolEditor = true
            } label: {
                Image(systemName: "pencil")
                    .foregroundColor(AppConstants.Colors.brandNavy)
                    .padding(10)
                    .background(AppConstants.Colors.accessibleYellow)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Edit school")
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(10)
    }

    private var directorAssignment: some View {
        operationsCard(title: "Director Setup", icon: "person.crop.circle.badge.checkmark") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(directorTemplate.template?.status.title ?? "Not Created")
                        .font(.caption.bold())
                        .foregroundColor(directorTemplate.template?.status == .published ? .green : .orange)
                    Text("\(directorTemplate.requirements.count) onboarding requirement\(directorTemplate.requirements.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
                }
                Spacer()
                Text("\(directorProgress.onboardingCount) in setup")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
            }

            HStack(spacing: 8) {
                NavigationLink {
                    OnboardingTemplateBuilderView(school: school, role: .schoolDirector)
                } label: {
                    Label("Manage Template", systemImage: "square.and.pencil")
                        .font(.caption.bold())
                }
                .buttonStyle(HQSecondaryButtonStyle())

                NavigationLink {
                    OnboardingRecipientPreviewView(school: school, role: .schoolDirector, bundle: directorTemplate)
                } label: {
                    Label("Preview", systemImage: "eye")
                        .font(.caption.bold())
                }
                .buttonStyle(HQSecondaryButtonStyle())
                .disabled(directorTemplate.requirements.isEmpty)
            }

            HStack(spacing: 8) {
                Button {
                    showingDirectorInvite = true
                } label: {
                    Label("Invite Director", systemImage: "person.badge.plus")
                        .font(.caption.bold())
                }
                .buttonStyle(HQSecondaryButtonStyle())
                .disabled(
                    directorTemplate.hasPublishedVersion == false
                        || directors.isEmpty == false
                        || pendingDirectorInvites.isEmpty == false
                )

                NavigationLink {
                    AssignmentsView(surface: .documents)
                } label: {
                    Label("Review Submissions", systemImage: "tray.full")
                        .font(.caption.bold())
                }
                .buttonStyle(HQSecondaryButtonStyle())
            }

            if directors.isEmpty {
                Label("No school director is currently assigned", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
                Text("This school needs a director assignment before its local onboarding can be completed.")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
            } else {
                ForEach(directors) { director in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(AppConstants.Colors.accessibleYellow.opacity(0.2))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Text(director.profile?.initials ?? "SD")
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(director.displayName)
                                .font(.subheadline.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Text("School Director")
                                .font(.caption)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
                        }
                    }
                }
            }

            if pendingDirectorInvites.isEmpty == false {
                Divider()
                    .overlay(.white.opacity(0.14))
                Text("Pending Invitations")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))

                ForEach(pendingDirectorInvites) { invite in
                    HStack(spacing: 10) {
                        Image(systemName: "envelope.badge")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invite.displayName?.isEmpty == false ? invite.displayName ?? invite.email : invite.email)
                                .font(.subheadline.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Text(invite.email)
                                .font(.caption)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.55))
                        }
                        Spacer()
                        if let inviteURL = invite.inviteURL {
                            ShareLink(item: inviteURL) {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                            }
                            .accessibilityLabel("Share pending director invitation")
                        }
                        Button(role: .destructive) {
                            cancellingDirectorInvite = invite
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                        .accessibilityLabel("Cancel pending director invitation")
                    }
                }
            }
        }
    }

    private var peopleMetrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("People")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricCard("Directors", count: directors.count, icon: "person.crop.circle.badge.checkmark")
                metricCard("Teachers", count: memberCount(for: .teacher), icon: "person.2.fill")
                metricCard("Parents", count: memberCount(for: .parent), icon: "figure.2.and.child.holdinghands")
                metricCard("Children", count: roster.count, icon: "figure.child")
            }
        }
    }

    private var attendanceMetrics: some View {
        operationsCard(title: "Today's Attendance", icon: "checkmark.circle.fill") {
            HStack(spacing: 12) {
                compactMetric(title: "Checked In", value: checkedInNow, color: .green)
                compactMetric(title: "Checked Out", value: checkedOutToday, color: .blue)
                compactMetric(title: "Not Arrived", value: max(0, roster.count - checkedInNow - checkedOutToday), color: .gray)
            }
        }
    }

    private var onboardingExceptions: some View {
        operationsCard(title: "Director Onboarding", icon: "checklist") {
            if directorRequirements.isEmpty {
                Label("No director onboarding requirements configured", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundColor(.green)
            } else {
                HStack(spacing: 12) {
                    compactMetric(title: "Need Submission", value: requirementsNeedingSubmission, color: requirementsNeedingSubmission == 0 ? .green : .orange)
                    compactMetric(title: "Changes Requested", value: changesRequested, color: changesRequested == 0 ? .green : .red)
                }
            }
            Text("Detailed document work remains in Documents; this card only surfaces school-level onboarding exceptions.")
                .font(.caption)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.56))
        }
    }

    private func memberCount(for role: SchoolRole) -> Int {
        members.filter { $0.membership.role == role }.count
    }

    private func metricCard(_ title: String, count: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            Text("\(count)")
                .font(.title2.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
            Text(title)
                .font(.caption)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(10)
    }

    private func compactMetric(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.title3.bold())
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func operationsCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card)
        .cornerRadius(10)
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil

        do {
            async let loadedMembers = SchoolService.shared.fetchMembers(schoolId: school.id)
            async let loadedDirectorInvites = SchoolService.shared.fetchPendingDirectorInvites(schoolId: school.id)
            async let loadedRoster = SchoolWorkflowService.shared.fetchChildRoster(schoolId: school.id)
            async let loadedRequirements = SchoolWorkflowService.shared.fetchOnboardingRequirements(schoolId: school.id)
            async let loadedSubmissions = SchoolWorkflowService.shared.fetchDocumentSubmissions(schoolId: school.id)
            async let loadedDirectorTemplate = SchoolWorkflowService.shared.fetchOnboardingTemplate(schoolId: school.id, role: .schoolDirector)
            async let loadedDirectorProgress = SchoolWorkflowService.shared.fetchOnboardingRoleProgress(schoolId: school.id, role: .schoolDirector)

            (members, pendingDirectorInvites, roster, requirements, submissions, directorTemplate, directorProgress) = try await (
                loadedMembers,
                loadedDirectorInvites,
                loadedRoster,
                loadedRequirements,
                loadedSubmissions,
                loadedDirectorTemplate,
                loadedDirectorProgress
            )
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load school operations", error)
            isLoading = false
        }
    }

    private func cancelPendingDirectorInvite() {
        guard let invite = cancellingDirectorInvite else { return }
        cancellingDirectorInvite = nil
        Task {
            do {
                try await SchoolService.shared.cancelDirectorInvite(inviteId: invite.id)
                await load()
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not cancel director invitation", error)
                }
            }
        }
    }
}

struct HQDirectorInviteSheet: View {
    @Environment(\.dismiss) private var dismiss

    let school: School
    var onInvited: () -> Void

    @State private var directorName = ""
    @State private var directorEmail = ""
    @State private var createdInvite: SchoolCreationResult?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var normalizedEmail: String {
        directorEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canInvite: Bool {
        normalizedEmail.contains("@") && normalizedEmail.contains(".") && isSaving == false
    }

    private var createdInviteURL: URL? {
        guard let value = createdInvite?.inviteUrl else { return nil }
        return URL(string: value)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Assign a School Director")
                                .font(.title2.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Text("Send an email-bound invitation for \(school.name). Existing FireflyFM accounts can accept the same link; new directors can create an account first.")
                                .font(.subheadline)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.65))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Director Name (optional)")
                                .font(.caption.bold())
                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                            TextField("Full name", text: $directorName)
                                .textContentType(.name)
                                .padding(12)
                                .background(AppConstants.Colors.card)
                                .cornerRadius(10)
                                .foregroundColor(AppConstants.Colors.primaryText)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Director Email")
                                .font(.caption.bold())
                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                            TextField("director@example.com", text: $directorEmail)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(AppConstants.Colors.card)
                                .cornerRadius(10)
                                .foregroundColor(AppConstants.Colors.primaryText)
                        }

                        if let createdInviteURL {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Director invitation created", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Text("The invitation remains pending until the director signs in with \(normalizedEmail) and accepts it.")
                                    .font(.caption)
                                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                                ShareLink(item: createdInviteURL) {
                                    Label("Share Invitation", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(HQPrimaryButtonStyle())
                            }
                            .padding()
                            .background(AppConstants.Colors.card)
                            .cornerRadius(10)
                        } else {
                            Button {
                                createInvite()
                            } label: {
                                Label(isSaving ? "Creating Invitation" : "Create Invitation", systemImage: "envelope.badge")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(HQPrimaryButtonStyle())
                            .disabled(canInvite == false)
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
            .navigationTitle("Director Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(createdInvite == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
    }

    private func createInvite() {
        guard canInvite else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let result = try await SchoolService.shared.createDirectorInvite(
                    schoolId: school.id,
                    directorEmail: normalizedEmail,
                    directorName: directorName
                )
                await MainActor.run {
                    createdInvite = result
                    isSaving = false
                    onInvited()
                }
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorMessage.school("Could not create director invitation", error)
                    isSaving = false
                }
            }
        }
    }
}

private struct SchoolCircleButton: View {
    let school: School

    var body: some View {
        VStack(spacing: 8) {
            SchoolAvatarView(school: school, size: 78)
            Text(school.name)
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.86))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 92)
        }
    }
}

struct SchoolAvatarView: View {
    let school: School
    let size: CGFloat

    var body: some View {
        Group {
            if let profileImageUrl = school.profileImageUrl, let url = URL(string: profileImageUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarFallback
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(AppConstants.Colors.fireflyBlue.opacity(0.28), lineWidth: 1))
    }

    private var avatarFallback: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [AppConstants.Colors.wingMist, AppConstants.Colors.wingBlue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(initials)
                    .font(.system(size: max(16, size * 0.28), weight: .bold))
                    .foregroundColor(AppConstants.Colors.primaryText)
            )
    }

    private var initials: String {
        let parts = school.name.split(separator: " ").prefix(2).compactMap(\.first)
        let value = String(parts).uppercased()
        return value.isEmpty ? "S" : value
    }
}

private struct HQToolRow: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.bold())
                .foregroundColor(AppConstants.Colors.brandNavy)
                .frame(width: 34, height: 34)
                .background(AppConstants.Colors.wingMist)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.secondaryText)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct HQSchoolsListView: View {
    @State var schools: [School]
    var onChanged: () -> Void

    @State private var query = ""
    @State private var showingNewSchool = false
    @State private var editingSchool: School?
    @State private var deletingSchool: School?

    private var filteredSchools: [School] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return schools }
        return schools.filter {
            $0.name.lowercased().contains(trimmed)
            || ($0.description ?? "").lowercased().contains(trimmed)
        }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FireflySearchField(placeholder: "Search schools", text: $query)

                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(filteredSchools) { school in
                            NavigationLink {
                                HQSchoolHubView(school: school)
                            } label: {
                                SchoolCircleButton(school: school)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    editingSchool = school
                                } label: {
                                    Label("Edit School", systemImage: "pencil")
                                }
                                Button {
                                    editingSchool = school
                                } label: {
                                    Label("Change Picture", systemImage: "photo")
                                }
                                Button(role: .destructive) {
                                    deletingSchool = school
                                } label: {
                                    Label("Delete School", systemImage: "trash")
                                }
                            }
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.55)
                                    .onEnded { _ in editingSchool = school }
                            )
                        }

                        Button {
                            showingNewSchool = true
                        } label: {
                            SchoolCreateGridTile()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Schools")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingNewSchool = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            }
        }
        .sheet(isPresented: $showingNewSchool) {
            NewSchoolCreationView {
                showingNewSchool = false
                onChanged()
            }
        }
        .sheet(item: $editingSchool) { school in
            SchoolEditView(school: school) { updated in
                if let index = schools.firstIndex(where: { $0.id == updated.id }) {
                    schools[index] = updated
                }
                onChanged()
            }
        }
        .sheet(item: $deletingSchool) { school in
            SchoolDeletionConfirmationView(school: school) {
                schools.removeAll { $0.id == school.id }
                onChanged()
            }
        }
    }
}

private struct SchoolCreateGridTile: View {
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(AppConstants.Colors.card)
                .frame(width: 78, height: 78)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AppConstants.Colors.accessibleYellow)
                )
                .overlay(Circle().stroke(AppConstants.Colors.accessibleYellow.opacity(0.28), lineWidth: 2))
            Text("Create")
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.78))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 92)
        }
    }
}

struct FireflySearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
                        .allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(AppConstants.Colors.primaryText)
                    .tint(AppConstants.Colors.accessibleYellow)
            }
        }
        .padding(12)
        .background(AppConstants.Colors.card)
        .cornerRadius(10)
    }
}

struct SchoolEditView: View {
    @Environment(\.dismiss) private var dismiss
    let school: School
    var onSaved: (School) -> Void

    @State private var name: String
    @State private var description: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(school: School, onSaved: @escaping (School) -> Void) {
        self.school = school
        self.onSaved = onSaved
        _name = State(initialValue: school.name)
        _description = State(initialValue: school.description ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        ZStack(alignment: .bottomTrailing) {
                            if let selectedImageData, let image = UIImage(data: selectedImageData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 112, height: 112)
                                    .clipShape(Circle())
                            } else {
                                SchoolAvatarView(school: school, size: 112)
                            }

                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AppConstants.Colors.brandNavy)
                                    .frame(width: 34, height: 34)
                                    .background(AppConstants.Colors.accessibleYellow)
                                    .clipShape(Circle())
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("School Name")
                                .font(.caption.bold())
                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                            TextField("School name", text: $name)
                                .padding(12)
                                .background(AppConstants.Colors.card)
                                .cornerRadius(10)
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .tint(AppConstants.Colors.accessibleYellow)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.caption.bold())
                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                            TextField("School description", text: $description, axis: .vertical)
                                .lineLimit(3...5)
                                .padding(12)
                                .background(AppConstants.Colors.card)
                                .cornerRadius(10)
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .tint(AppConstants.Colors.accessibleYellow)
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
            .navigationTitle("Edit School")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    selectedImageData = try? await newValue?.loadTransferable(type: Data.self)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                var profileImageUrl = school.profileImagePath == nil ? school.profileImageUrl : nil
                var profileImagePath = school.profileImagePath
                if let selectedImageData {
                    profileImagePath = try await SchoolService.shared.uploadSchoolProfileImage(data: selectedImageData, schoolId: school.id)
                    profileImageUrl = nil
                }
                let updated = try await SchoolService.shared.updateSchool(
                    schoolId: school.id,
                    name: name,
                    description: description,
                    tourUrl: school.tourUrl,
                    profileImageUrl: profileImageUrl,
                    profileImagePath: profileImagePath
                )
                await MainActor.run {
                    isSaving = false
                    onSaved(updated)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not update school", error)
                }
            }
        }
    }
}

private struct SchoolDeletionConfirmationView: View {
    @Environment(\.dismiss) private var dismiss

    let school: School
    var onDeleted: () -> Void

    @State private var confirmationName = ""
    @State private var isDeleting = false
    @State private var showingFinalConfirmation = false
    @State private var archiveId: UUID?
    @State private var errorMessage: String?

    private var canDelete: Bool {
        confirmationName == school.name && !isDeleting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundColor(.red.opacity(0.9))
                            Text("Delete \(school.name)?")
                                .font(.title.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .multilineTextAlignment(.center)
                            Text("This archives a server-side JSON backup first, then removes the school and its related records from the active app. This should only be used for test schools or deliberate cleanup.")
                                .font(.subheadline)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.68))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Type the exact school name to confirm")
                                .font(.caption.bold())
                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                            Text(school.name)
                                .font(.footnote.monospaced())
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
                            TextField("Exact school name", text: $confirmationName)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(AppConstants.Colors.card)
                                .cornerRadius(10)
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .tint(AppConstants.Colors.accessibleYellow)
                        }

                        if let archiveId {
                            Label("Backup saved: \(archiveId.uuidString)", systemImage: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(.green)
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
            .navigationTitle("Delete School")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isDeleting ? "Deleting" : "Delete") {
                        showingFinalConfirmation = true
                    }
                        .disabled(!canDelete)
                        .foregroundColor(canDelete ? .red : .gray)
                }
            }
            .confirmationDialog(
                "Archive backup and delete \(school.name)?",
                isPresented: $showingFinalConfirmation,
                titleVisibility: .visible
            ) {
                Button("Archive Backup and Delete", role: .destructive) {
                    deleteSchool()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will create a JSON backup, then remove the school from the active app for every user.")
            }
        }
    }

    private func deleteSchool() {
        isDeleting = true
        errorMessage = nil

        Task {
            do {
                let savedArchiveId = try await SchoolService.shared.archiveAndDeleteSchool(
                    school: school,
                    confirmationName: confirmationName
                )
                await MainActor.run {
                    archiveId = savedArchiveId
                    isDeleting = false
                    onDeleted()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = AppErrorMessage.school("Could not delete school", error)
                }
            }
        }
    }
}

private struct NewSchoolCreationView: View {
    @Environment(\.dismiss) private var dismiss

    var onCreated: () -> Void

    @State private var schoolName = ""
    @State private var result: School?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("School") {
                    TextField("School name", text: $schoolName)
                }

                if let result {
                    Section("Next Step") {
                        Label("\(result.name) was created", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Open My Schools → \(result.name) → Operations → Director Setup. Publish the template before inviting the director.")
                            .font(.footnote)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("New School")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onCreated()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Creating" : "Create") { create() }
                        .disabled(schoolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || result != nil)
                }
            }
        }
    }

    private func create() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let created = try await SchoolService.shared.createSchoolForOnboarding(name: schoolName)
                await MainActor.run {
                    result = created
                    isSaving = false
                    onCreated()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not create school", error)
                }
            }
        }
    }
}

private enum HQEventPushTarget: String, CaseIterable, Identifiable {
    case all
    case selected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Schools"
        case .selected: "Choose"
        }
    }
}

private struct HQEventPushView: View {
    @Environment(\.dismiss) private var dismiss

    let schools: [School]

    @State private var target: HQEventPushTarget = .all
    @State private var selectedSchoolIds: Set<UUID> = []
    @State private var title = ""
    @State private var description = ""
    @State private var allDay = false
    @State private var startAt = Date()
    @State private var endAt = Date().addingTimeInterval(3600)
    @State private var isSaving = false
    @State private var confirmationMessage: String?
    @State private var errorMessage: String?

    private var destinationSchools: [School] {
        switch target {
        case .all:
            return schools
        case .selected:
            return schools.filter { selectedSchoolIds.contains($0.id) }
        }
    }

    private var canSave: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && destinationSchools.isEmpty == false
            && isSaving == false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Push Event")
                                .font(.largeTitle.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Text("Create the same calendar event for all schools or a selected group. When enabled, each school receives its own notification record.")
                                .font(.subheadline)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
                        }

                        Picker("Target", selection: $target) {
                            ForEach(HQEventPushTarget.allCases) { target in
                                Text(target.title).tag(target)
                            }
                        }
                        .pickerStyle(.segmented)

                        if target == .selected {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Schools")
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                                ForEach(schools) { school in
                                    Toggle(isOn: Binding(
                                        get: { selectedSchoolIds.contains(school.id) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedSchoolIds.insert(school.id)
                                            } else {
                                                selectedSchoolIds.remove(school.id)
                                            }
                                        }
                                    )) {
                                        Text(school.name)
                                            .foregroundColor(AppConstants.Colors.primaryText)
                                    }
                                    .tint(AppConstants.Colors.accessibleYellow)
                                }
                            }
                            .padding()
                            .background(AppConstants.Colors.card)
                            .cornerRadius(10)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Event title", text: $title)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .tint(AppConstants.Colors.accessibleYellow)

                            TextField("Description", text: $description, axis: .vertical)
                                .lineLimit(3...6)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .tint(AppConstants.Colors.accessibleYellow)

                            Toggle("All-day", isOn: $allDay)
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .tint(AppConstants.Colors.accessibleYellow)
                            DatePicker("Starts", selection: $startAt, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                                .foregroundColor(AppConstants.Colors.primaryText)
                            DatePicker("Ends", selection: $endAt, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Label("Each school will receive an event notification.", systemImage: "bell.fill")
                                .font(.footnote)
                                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
                        }
                        .padding()
                        .background(AppConstants.Colors.card)
                        .cornerRadius(10)

                        Text("\(destinationSchools.count) school\(destinationSchools.count == 1 ? "" : "s") selected")
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.accessibleYellow)

                        if let confirmationMessage {
                            Text(confirmationMessage)
                                .font(.caption)
                                .foregroundColor(.green)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Pushing" : "Push") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        confirmationMessage = nil

        let selected = destinationSchools
        Task {
            do {
                for school in selected {
                    try await SchoolWorkflowService.shared.createEvent(
                        schoolId: school.id,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description.trimmingCharacters(in: .whitespacesAndNewlines),
                        startAt: startAt,
                        endAt: endAt,
                        allDay: allDay
                    )
                }

                await MainActor.run {
                    isSaving = false
                    confirmationMessage = "Event pushed to \(selected.count) school\(selected.count == 1 ? "" : "s")."
                    title = ""
                    description = ""
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not push event", error)
                }
            }
        }
    }
}

private struct HQPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(AppConstants.Colors.primaryActionText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppConstants.Colors.primaryAction.opacity(configuration.isPressed ? 0.72 : 1))
            .cornerRadius(8)
    }
}

private struct HQSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(AppConstants.Colors.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppConstants.Colors.card.opacity(configuration.isPressed ? 0.72 : 1))
            .cornerRadius(8)
    }
}

struct HQOverviewView: View {
    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("HQ Overview")
                        .font(.largeTitle.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                    Text("A flexible dashboard shell for check-ins, fire drill records, incident reports, school payment setup, EEC licenses, and date/school filters.")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.68))

                    ForEach(["Check-in / Check-out", "Fire Drills", "Incident Reports", "School Payment Setup", "EEC Licenses"], id: \.self) { title in
                        HStack {
                            Image(systemName: "chart.xyaxis.line")
                                .foregroundColor(AppConstants.Colors.accessibleYellow)
                            Text(title)
                                .font(.headline)
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Spacer()
                            Text("Ready")
                                .font(.caption.bold())
                                .foregroundColor(AppConstants.Colors.brandNavy)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppConstants.Colors.accessibleYellow)
                                .clipShape(Capsule())
                        }
                        .padding()
                        .background(AppConstants.Colors.card)
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppConstants.Colors.card, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct EducationAssignmentView: View {
    @State private var schools: [School] = []
    @State private var selectedSchoolId: UUID?
    @State private var resources: [CurriculumResource] = []
    @State private var assignments: [TrainingAssignment] = []
    @State private var members: [SchoolMember] = []
    @State private var curriculumReceipts: [CurriculumReadReceipt] = []
    @State private var trainingReceipts: [TrainingReadReceipt] = []
    @State private var selectedTab: EducationTab = .training
    @State private var showingCurriculumComposer = false
    @State private var showingTrainingComposer = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var selectedSchool: School? {
        schools.first { $0.id == selectedSchoolId }
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Education")
                            .font(.largeTitle.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Text("Canvas-style curriculum resources and training assignments for teachers and school directors.")
                            .font(.subheadline)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
                    }

                    if schools.isEmpty && !isLoading {
                        educationPanel("No schools found.", icon: "building.2")
                    } else {
                        Picker("School", selection: Binding(
                            get: { selectedSchoolId ?? schools.first?.id },
                            set: { selectedSchoolId = $0 }
                        )) {
                            ForEach(schools) { school in
                                Text(school.name).tag(Optional(school.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppConstants.Colors.accessibleYellow)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppConstants.Colors.card)
                        .cornerRadius(10)
                    }

                    Picker("Education Type", selection: $selectedTab) {
                        ForEach(EducationTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    if isLoading {
                        ProgressView()
                            .tint(AppConstants.Colors.accessibleYellow)
                    } else if selectedTab == .training {
                        trainingContent
                    } else {
                        curriculumContent
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
        .navigationTitle("Education")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    showingCurriculumComposer = true
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                Button {
                    showingTrainingComposer = true
                } label: {
                    Image(systemName: "person.badge.clock")
                }
            }
        }
        .sheet(isPresented: $showingCurriculumComposer) {
            if let selectedSchool {
                HQEducationMaterialComposer(
                    school: selectedSchool,
                    members: members,
                    mode: .curriculum
                ) {
                    Task { await loadSchoolContent() }
                }
            }
        }
        .sheet(isPresented: $showingTrainingComposer) {
            if let selectedSchool {
                HQEducationMaterialComposer(
                    school: selectedSchool,
                    members: members,
                    mode: .training
                ) {
                    Task { await loadSchoolContent() }
                }
            }
        }
        .task { await loadSchools() }
        .onChange(of: selectedSchoolId) { _, _ in
            Task { await loadSchoolContent() }
        }
        .refreshable { await loadSchoolContent() }
    }

    private var trainingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Training Assignments")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                Button {
                    showingTrainingComposer = true
                } label: {
                    Label("Assign", systemImage: "plus")
                }
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            }

            if assignments.isEmpty {
                educationPanel("No training assignments yet.", icon: "graduationcap")
            } else {
                ForEach(assignments) { assignment in
                    EducationMaterialCard(
                        title: assignment.title,
                        subtitle: assignment.description,
                        materialType: assignment.materialType,
                        materialUrl: assignment.materialUrl,
                        fileName: assignment.fileName,
                        createdAt: assignment.createdAt,
                        checkedCount: trainingReceipts.filter { $0.assignmentId == assignment.id }.count,
                        onOpenFile: { openFile(path: assignment.filePath) },
                        onOpenLink: { openLink(assignment.materialUrl) }
                    )
                }
            }
        }
    }

    private var curriculumContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Curriculum Materials")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                Button {
                    showingCurriculumComposer = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            }

            if resources.isEmpty {
                educationPanel("No curriculum materials yet.", icon: "books.vertical")
            } else {
                ForEach(resources) { resource in
                    EducationMaterialCard(
                        title: resource.title,
                        subtitle: resource.description,
                        materialType: resource.materialType,
                        materialUrl: resource.materialUrl,
                        fileName: resource.fileName,
                        createdAt: resource.createdAt,
                        checkedCount: curriculumReceipts.filter { $0.resourceId == resource.id }.count,
                        onOpenFile: { openFile(path: resource.filePath) },
                        onOpenLink: { openLink(resource.materialUrl) }
                    )
                }
            }
        }
    }

    private func educationPanel(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(AppConstants.Colors.accessibleYellow)
            Text(text)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
            Spacer()
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    @MainActor
    private func loadSchools() async {
        isLoading = true
        errorMessage = nil
        do {
            schools = try await SchoolService.shared.fetchSchoolsForHQ()
            if selectedSchoolId == nil {
                selectedSchoolId = schools.first?.id
            }
            await loadSchoolContent()
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load schools", error)
            isLoading = false
        }
    }

    @MainActor
    private func loadSchoolContent() async {
        guard let schoolId = selectedSchoolId else {
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            async let loadedResources = SchoolWorkflowService.shared.fetchCurriculumResources(schoolId: schoolId)
            async let loadedAssignments = SchoolWorkflowService.shared.fetchTrainingAssignments(schoolId: schoolId)
            async let loadedMembers = SchoolService.shared.fetchMembers(schoolId: schoolId)
            async let loadedCurriculumReceipts = SchoolWorkflowService.shared.fetchCurriculumReadReceipts(schoolId: schoolId)
            async let loadedTrainingReceipts = SchoolWorkflowService.shared.fetchTrainingReadReceipts(schoolId: schoolId)
            resources = try await loadedResources
            assignments = try await loadedAssignments
            members = try await loadedMembers
            curriculumReceipts = try await loadedCurriculumReceipts
            trainingReceipts = try await loadedTrainingReceipts
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load education materials", error)
            isLoading = false
        }
    }

    private func openFile(path: String?) {
        guard let path else { return }
        Task {
            do {
                let url = try await SchoolService.shared.signedPrivateFileURL(path: path)
                await MainActor.run { UIApplication.shared.open(url) }
            } catch {
                await MainActor.run { errorMessage = AppErrorMessage.school("Could not open file", error) }
            }
        }
    }

    private func openLink(_ value: String?) {
        guard let value, let url = URL(string: value) else { return }
        UIApplication.shared.open(url)
    }
}

private enum EducationTab: String, CaseIterable, Identifiable {
    case training
    case curriculum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .training: "Training"
        case .curriculum: "Curriculum"
        }
    }
}

private enum EducationComposerMode {
    case curriculum
    case training

    var title: String {
        switch self {
        case .curriculum: "Curriculum Material"
        case .training: "Training Assignment"
        }
    }
}

private struct EducationMaterialCard: View {
    let title: String
    let subtitle: String?
    let materialType: String?
    let materialUrl: String?
    let fileName: String?
    let createdAt: Date?
    let checkedCount: Int
    let onOpenFile: () -> Void
    let onOpenLink: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                Text("\(checkedCount) checked")
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.brandNavy)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppConstants.Colors.accessibleYellow)
                    .clipShape(Capsule())
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
            }

            HStack(spacing: 8) {
                if let fileName {
                    Button {
                        onOpenFile()
                    } label: {
                        Label(fileName, systemImage: "paperclip")
                    }
                }

                if materialUrl?.isEmpty == false {
                    Button {
                        onOpenLink()
                    } label: {
                        Label("Open Link", systemImage: "link")
                    }
                }
            }
            .font(.caption.bold())
            .foregroundColor(AppConstants.Colors.accessibleYellow)

            if let createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.42))
            }
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private var icon: String {
        switch materialType {
        case "article": "doc.text.fill"
        case "link": "link"
        case "image": "photo.fill"
        case "video": "video.fill"
        default: "doc.fill"
        }
    }
}

private struct HQEducationMaterialComposer: View {
    @Environment(\.dismiss) private var dismiss

    let school: School
    let members: [SchoolMember]
    let mode: EducationComposerMode
    var onSaved: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var materialType = "article"
    @State private var materialUrl = ""
    @State private var dueAt = Date().addingTimeInterval(7 * 24 * 60 * 60)
    @State private var selectedRecipientIds = Set<UUID>()
    @State private var selectedFileURL: URL?
    @State private var showingImporter = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var eligibleRecipients: [SchoolMember] {
        members.filter { $0.membership.role == .teacher || $0.membership.role == .schoolDirector }
    }

    private var canSave: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && (mode == .curriculum || !selectedRecipientIds.isEmpty)
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(mode.title) {
                    TextField("Title", text: $title)
                    TextField("Instructions or notes", text: $description, axis: .vertical)
                    Picker("Material Type", selection: $materialType) {
                        Text("Article").tag("article")
                        Text("Link").tag("link")
                        Text("Picture").tag("image")
                        Text("Video").tag("video")
                        Text("File").tag("file")
                        Text("Mixed").tag("mixed")
                    }
                    TextField("Article/video/link URL", text: $materialUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button(selectedFileURL?.lastPathComponent ?? "Attach file, picture, or video") {
                        showingImporter = true
                    }
                    if mode == .training {
                        DatePicker("Due", selection: $dueAt)
                    }
                }

                if mode == .training {
                    Section("Recipients") {
                        Button("Select All Teachers and Directors") {
                            selectedRecipientIds = Set(eligibleRecipients.map(\.id))
                        }
                        ForEach(eligibleRecipients) { member in
                            Toggle("\(member.displayName) · \(member.membership.role.title)", isOn: Binding(
                                get: { selectedRecipientIds.contains(member.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedRecipientIds.insert(member.id)
                                    } else {
                                        selectedRecipientIds.remove(member.id)
                                    }
                                }
                            ))
                        }
                    }
                }

                Section("Check After Reading") {
                    Text("Recipients will be able to mark this material as read. Directors can review check counts from this Education view.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                selectedFileURL = try? result.get().first
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        let cleanUrl = materialUrl.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                switch mode {
                case .curriculum:
                    try await SchoolWorkflowService.shared.createCurriculumResource(
                        schoolId: school.id,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                        fileURL: selectedFileURL,
                        materialUrl: cleanUrl.isEmpty ? nil : cleanUrl,
                        materialType: materialType
                    )
                case .training:
                    try await SchoolWorkflowService.shared.createTrainingAssignment(
                        schoolId: school.id,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
                        fileURL: selectedFileURL,
                        teacherIds: Array(selectedRecipientIds),
                        materialUrl: cleanUrl.isEmpty ? nil : cleanUrl,
                        materialType: materialType,
                        dueAt: dueAt
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
                    errorMessage = AppErrorMessage.school("Could not save education material", error)
                }
            }
        }
    }
}

#Preview {
    HQHomeView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
        .environmentObject(AppSessionManager())
}
