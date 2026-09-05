//
//  HQSchoolsView.swift
//  FireflyFM
//

import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct HQSchoolsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var model = HQSchoolsModel()
    @State private var showingProfile = false
    @State private var showingNewSchool = false
    @State private var showingEventPush = false
    @State private var editingSchool: School?
    @State private var deletingSchool: School?
    @State private var showingSignOutConfirmation = false
    private var schools: [School] { model.schools }
    private var newsletters: [NewsletterPost] { model.newsletters }
    private var newsletterSchoolNames: [UUID: String] { model.newsletterSchoolNames }
    private var isLoading: Bool { model.phase.isLoading }
    private var isLoadingNewsletters: Bool { model.isLoadingNewsletters }
    private var errorMessage: String? { model.errorMessage }

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
                    model.replace(updated)
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
                    Text("Schools")
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
                    AssignmentsView(filter: .learning, schoolSelection: .selectable)
                } label: {
                    HQToolRow(title: "Training & Curriculum", subtitle: "Staff learning and reviews across schools", icon: "graduationcap.fill")
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
        await model.load()
    }
}

private enum HQSchoolHubSection: String, CaseIterable, Identifiable {
    case operations = "Operations"
    case community = "Community"

    var id: String { rawValue }
}

struct HQSchoolHubView: View {
    @State private var school: School
    @State private var selectedSection: HQSchoolHubSection = .operations
    @State private var showingSchoolEditor = false

    init(school: School) {
        _school = State(initialValue: school)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
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
                HQSchoolOperationsView(school: school)
            case .community:
                CommunityView(school: school)
                    .id(school.updatedAt ?? school.createdAt)
            }
        }
        .background(AppConstants.Colors.background.ignoresSafeArea())
        .navigationTitle(school.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingSchoolEditor = true } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit school details")
            }
        }
        .sheet(isPresented: $showingSchoolEditor) {
            SchoolEditView(school: school) { updatedSchool in
                school = updatedSchool
            }
        }
    }
}

private struct HQSchoolOperationsView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    let school: School

    @State private var model = HQSchoolOperationsModel()
    @State private var paymentsModel = PaymentsModel()
    @State private var showingDirectorInvite = false
    @State private var showingZelleSettings = false
    @State private var cancellingDirectorInvite: RoleInvite?
    private var members: [SchoolMember] { model.members }
    private var pendingDirectorInvites: [RoleInvite] { model.pendingDirectorInvites }
    private var roster: [ChildRosterItem] { model.roster }
    private var directorTemplate: OnboardingTemplateBundle { model.directorTemplate }
    private var directorProgress: OnboardingRoleProgress { model.directorProgress }
    private var isLoading: Bool { model.phase.isLoading }
    private var errorMessage: String? { model.errorMessage }
    private var paymentPolicy: PaymentAccessPolicy {
        PaymentAccessPolicy(context: appSession.accessContext(selectedSchoolId: school.id))
    }

    private var directors: [SchoolMember] {
        model.directors
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
        .sheet(isPresented: $showingDirectorInvite) {
            HQDirectorInviteSheet(school: school) {
                Task { await load() }
            }
        }
        .sheet(isPresented: $showingZelleSettings) {
            ZelleProfileEditorView(
                schoolId: school.id,
                profile: paymentsModel.profile,
                model: paymentsModel,
                policy: paymentPolicy
            ) {
                Task { await paymentsModel.loadProfile(schoolId: school.id, policy: paymentPolicy) }
            }
        }
        .overlay {
            if let invite = cancellingDirectorInvite {
                InvitationCancellationOverlay(
                    email: invite.email,
                    onKeep: { cancellingDirectorInvite = nil },
                    onCancelInvitation: cancelPendingDirectorInvite
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }

    private var directorAssignment: some View {
        operationsCard(title: "Director Setup", icon: "person.crop.circle.badge.checkmark") {
            HStack(alignment: .firstTextBaseline) {
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

            Text("Publish the setup checklist, generate an email-bound invitation code, then review the director's submission before full access unlocks.")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                NavigationLink {
                    OnboardingTemplateBuilderView(school: school, role: .schoolDirector)
                } label: {
                    directorActionCard("Manage Template", icon: "square.and.pencil")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    OnboardingRecipientPreviewView(school: school, role: .schoolDirector, bundle: directorTemplate)
                } label: {
                    directorActionCard("Preview as Director", icon: "eye.fill")
                }
                .buttonStyle(.plain)
                .disabled(directorTemplate.requirements.isEmpty)

                Button {
                    showingZelleSettings = true
                } label: {
                    directorActionCard("Set Zelle Instructions", icon: "dollarsign.circle.fill")
                }
                .buttonStyle(.plain)

                Button {
                    showingDirectorInvite = true
                } label: {
                    directorActionCard("Generate Invite Code", icon: "person.badge.key.fill")
                }
                .buttonStyle(.plain)
                .disabled(
                    directorTemplate.hasPublishedVersion == false
                        || directors.isEmpty == false
                        || pendingDirectorInvites.isEmpty == false
                )

                NavigationLink {
                    AssignmentsView(filter: .documents, scopedSchool: school, reviewOnly: true)
                } label: {
                    directorActionCard(
                        "Review Submissions",
                        icon: "tray.full.fill",
                        badge: directorProgress.needsReviewCount
                    )
                }
                .buttonStyle(.plain)
            }

            if directorTemplate.hasPublishedVersion == false {
                Label("Publish at least one setup requirement before generating an invitation code.", systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
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
                        Button {
                            cancellingDirectorInvite = invite
                        } label: {
                            Text("Cancel Invitation")
                                .font(.caption.bold())
                                .foregroundColor(.red)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.12))
                                .cornerRadius(8)
                        }
                        .accessibilityLabel("Cancel pending director invitation")
                    }
                }
            }
        }
    }

    private func directorActionCard(_ title: String, icon: String, badge: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                Spacer()
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.brandNavy)
                        .padding(6)
                        .background(.orange)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.36))
                }
            }
            Text(title)
                .font(.subheadline.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .padding()
        .background(AppConstants.Colors.background.opacity(0.54))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppConstants.Colors.separator.opacity(0.75), lineWidth: 1)
        }
        .cornerRadius(10)
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
        await model.load(schoolId: school.id)
        await paymentsModel.loadProfile(schoolId: school.id, policy: paymentPolicy)
    }

    private func cancelPendingDirectorInvite() {
        guard let invite = cancellingDirectorInvite else { return }
        cancellingDirectorInvite = nil
        Task {
            await model.cancel(inviteId: invite.id, schoolId: school.id)
        }
    }
}

private struct InvitationCancellationOverlay: View {
    let email: String
    let onKeep: () -> Void
    let onCancelInvitation: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture(perform: onKeep)

            VStack(spacing: 16) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.red)

                VStack(spacing: 6) {
                    Text("Cancel invitation?")
                        .font(.title3.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                    Text("The invitation code for \(email) will stop working immediately.")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.64))
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    Button("Keep Invitation", action: onKeep)
                        .font(.subheadline.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppConstants.Colors.background.opacity(0.72))
                        .cornerRadius(8)

                    Button("Cancel Invitation", action: onCancelInvitation)
                        .font(.subheadline.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.82))
                        .cornerRadius(8)
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(AppConstants.Colors.card)
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .cornerRadius(18)
            .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
            .padding()
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
    @State private var copiedCode = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let client = HQSchoolWorkflowClient.live

    private var normalizedEmail: String {
        directorEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canInvite: Bool {
        normalizedEmail.contains("@") && normalizedEmail.contains(".") && isSaving == false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Generate Director Invitation")
                                .font(.title2.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Text("Create a one-time code for \(school.name). It only works after the director signs in with the email below.")
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

                        if let createdInvite {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Invitation code ready", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Text(createdInvite.inviteToken)
                                    .font(.caption.monospaced().bold())
                                    .foregroundColor(AppConstants.Colors.primaryText)
                                    .textSelection(.enabled)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AppConstants.Colors.background.opacity(0.64))
                                    .cornerRadius(8)

                                Button {
                                    UIPasteboard.general.string = createdInvite.inviteToken
                                    copiedCode = true
                                } label: {
                                    Label(copiedCode ? "Code Copied" : "Copy Invitation Code", systemImage: copiedCode ? "checkmark" : "doc.on.doc")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(HQPrimaryButtonStyle())

                                if let inviteURL = createdInvite.shareInviteURL {
                                    ShareLink(item: inviteURL) {
                                        Label("Share Invitation Link", systemImage: "square.and.arrow.up")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(HQSecondaryButtonStyle())
                                }

                                Text("Next: the director signs in as \(normalizedEmail), chooses Accept an Invitation, pastes this code, and confirms. Their setup checklist is created only after acceptance.")
                                    .font(.caption)
                                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.62))
                                Text("Copy the code now. For security, FireflyFM stores only its fingerprint and cannot show the same code again after this screen closes.")
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                            }
                            .padding()
                            .background(AppConstants.Colors.card)
                            .cornerRadius(10)
                        } else {
                            Button {
                                createInvite()
                            } label: {
                                Label(isSaving ? "Generating Code" : "Generate Invitation Code", systemImage: "person.badge.key.fill")
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
            .navigationTitle("Invite Director")
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
                let result = try await client.createDirectorInvite(school.id, normalizedEmail, directorName)
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
    private let client = HQSchoolWorkflowClient.live

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
                    profileImagePath = try await client.uploadSchoolImage(selectedImageData, school.id)
                    profileImageUrl = nil
                }
                let updated = try await client.updateSchool(HQSchoolUpdateRequest(
                    schoolId: school.id,
                    name: name,
                    description: description,
                    tourURL: school.tourUrl,
                    profileImageURL: profileImageUrl,
                    profileImagePath: profileImagePath
                ))
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
    private let client = HQSchoolWorkflowClient.live

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
                let savedArchiveId = try await client.archiveAndDelete(school, confirmationName)
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
    private let client = HQSchoolWorkflowClient.live

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
                let created = try await client.createSchool(schoolName)
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
    private let client = HQSchoolWorkflowClient.live

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
                    try await client.createEvent(HQEventPushRequest(
                        schoolId: school.id,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description.trimmingCharacters(in: .whitespacesAndNewlines),
                        startAt: startAt,
                        endAt: endAt,
                        allDay: allDay
                    ))
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

#Preview {
    HQSchoolsView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
        .environmentObject(AppSessionManager())
}
