import SwiftUI

struct SchoolDirectorTodayView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var model = SchoolDirectorTodayModel()
    @State private var showingProfile = false
    @State private var showingSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            FireflyScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingLarge) {
                        TodayHeader(
                            title: "Today",
                            onProfile: { showingProfile = true },
                            onSignOut: { showingSignOutConfirmation = true }
                        )

                        schoolOperations
                            .redacted(reason: model.phase.isLoading ? .placeholder : [])

                        upcomingEvents

                        if let school = appSession.activeSchool {
                            SchoolDirectorNewsletterSection(school: school)
                        }

                        if case .failed(let message) = model.phase {
                            FireflyInlineError(message: message)
                        }
                    }
                    .padding(FireflyTheme.Layout.cardPadding)
                }
                .refreshable { await load() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingProfile) { ProfileView() }
            .overlay { signOutOverlay }
            .task(id: appSession.activeSchool?.id) { await load() }
        }
    }

    private var schoolOperations: some View {
        VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingMedium) {
            TodaySectionIntro(
                title: "School operations",
                message: "Roster, attendance, and the items that need your attention today."
            )

            NavigationLink {
                ChildrenAttendanceWorkspace()
            } label: {
                FireflySectionCard {
                    VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingMedium) {
                        HStack(spacing: FireflyTheme.Layout.spacingMedium) {
                            Image(systemName: "person.2.crop.square.stack.fill")
                                .font(.title3)
                                .foregroundColor(FireflyTheme.Colors.brandNavy)
                                .frame(width: 42, height: 42)
                                .background(FireflyTheme.Colors.wingMist)
                                .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.controlRadius))
                            VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingXSmall) {
                                Text("Children & Attendance")
                                    .font(.headline)
                                    .foregroundColor(FireflyTheme.Colors.primaryText)
                                Text("One roster for profiles, check-in, and history")
                                    .font(.caption)
                                    .foregroundColor(FireflyTheme.Colors.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(FireflyTheme.Colors.secondaryText)
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 0) { metrics }
                            VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingSmall) { metrics }
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            if let school = appSession.activeSchool {
                WorkspaceLink(
                    title: "People & Access",
                    subtitle: "Invites, connections, and onboarding",
                    systemImage: "person.badge.key.fill",
                    destination: OnboardingManagementView(school: school, mode: .schoolDirector)
                )
            }

            WorkspaceLink(
                title: "Assignments & Training",
                subtitle: "Manage school work and complete assigned training",
                systemImage: "checklist.checked",
                destination: AssignmentsView(filter: .all)
            )
        }
    }

    @ViewBuilder
    private var metrics: some View {
        MetricValue(title: "Roster", value: model.roster.count)
        Divider().frame(height: 30)
        MetricValue(title: "Checked in", value: model.checkedInCount)
        Divider().frame(height: 30)
        MetricValue(title: "Need review", value: model.reviewItems.count)
    }

    private var upcomingEvents: some View {
        VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingSmall) {
            Label("Upcoming", systemImage: "calendar")
                .font(.headline)
                .foregroundColor(FireflyTheme.Colors.primaryText)

            if model.upcomingEvents.isEmpty {
                FireflyEmptyState(title: "No upcoming events", systemImage: "calendar")
            } else {
                ForEach(model.upcomingEvents.prefix(3)) { event in
                    EventSummaryRow(event: event)
                }
            }
        }
    }

    @ViewBuilder
    private var signOutOverlay: some View {
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

    private func load() async {
        guard let schoolId = appSession.activeSchool?.id else { return }
        await model.load(schoolId: schoolId)
    }
}

private struct MetricValue: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingXSmall) {
            Text("\(value)")
                .font(.headline)
                .foregroundColor(FireflyTheme.Colors.primaryText)
            Text(title)
                .font(.caption2)
                .foregroundColor(FireflyTheme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct EventSummaryRow: View {
    let event: SchoolEvent

    var body: some View {
        HStack(spacing: FireflyTheme.Layout.spacingMedium) {
            VStack {
                Text(event.startAt.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption2.bold())
                Text(event.startAt.formatted(.dateTime.day()))
                    .font(.title3.bold())
            }
            .foregroundColor(FireflyTheme.Colors.brandNavy)
            .frame(width: 48, height: 52)
            .background(FireflyTheme.Colors.wingMist)
            .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.controlRadius))

            VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingXSmall) {
                Text(event.title)
                    .font(.subheadline.bold())
                    .foregroundColor(FireflyTheme.Colors.primaryText)
                Text(event.startAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundColor(FireflyTheme.Colors.secondaryText)
            }
            Spacer()
        }
        .padding(FireflyTheme.Layout.controlPadding)
        .background(FireflyTheme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.cardRadius))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SchoolDirectorTodayView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
        .environmentObject(AppSessionManager())
}
