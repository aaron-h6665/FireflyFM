import SwiftUI

struct HQDirectorTodayView: View {
    @EnvironmentObject private var authManager: AuthManager

    @State private var model = HQDirectorTodayModel()
    @State private var showingProfile = false
    @State private var showingSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            FireflyScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingLarge) {
                        TodayHeader(
                            title: "Today",
                            subtitle: "HQ overview",
                            onProfile: { showingProfile = true },
                            onSignOut: { showingSignOutConfirmation = true }
                        )

                        TodaySectionIntro(
                            title: "Organization summary",
                            message: "Current cross-school priorities and operational entry points."
                        )

                        FireflySectionCard {
                            HStack(spacing: FireflyTheme.Layout.spacingMedium) {
                                Image(systemName: "building.2.fill")
                                    .font(.title2)
                                    .foregroundColor(FireflyTheme.Colors.primaryAction)
                                    .frame(width: 48, height: 48)
                                    .background(FireflyTheme.Colors.wingMist)
                                    .clipShape(RoundedRectangle(cornerRadius: FireflyTheme.Layout.controlRadius))
                                VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingXSmall) {
                                    Text("\(model.schools.count)")
                                        .font(.title2.bold())
                                        .foregroundColor(FireflyTheme.Colors.primaryText)
                                    Text(model.schools.count == 1 ? "School" : "Schools")
                                        .font(.caption)
                                        .foregroundColor(FireflyTheme.Colors.secondaryText)
                                }
                                Spacer()
                                if model.phase.isLoading { ProgressView() }
                            }
                        }

                        VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingSmall) {
                            Text("Priorities")
                                .font(.headline)
                                .foregroundColor(FireflyTheme.Colors.primaryText)

                            WorkspaceLink(
                                title: "Schools",
                                subtitle: "Directory, directors, invitations, and school operations",
                                systemImage: "building.2.fill",
                                destination: HQSchoolsView()
                            )
                            WorkspaceLink(
                                title: "Children & Attendance",
                                subtitle: "Cross-school roster and attendance oversight",
                                systemImage: "person.2.crop.square.stack.fill",
                                destination: ChildrenAttendanceWorkspace()
                            )
                            WorkspaceLink(
                                title: "Training & Curriculum",
                                subtitle: "Staff learning and reviews across schools",
                                systemImage: "graduationcap.fill",
                                destination: AssignmentsView(filter: .learning, schoolSelection: .selectable)
                            )
                        }

                        if case .failed(let message) = model.phase {
                            FireflyInlineError(message: message)
                        }
                    }
                    .padding(FireflyTheme.Layout.cardPadding)
                }
                .refreshable { await model.load() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingProfile) { ProfileView() }
            .overlay { signOutOverlay }
            .task { await model.load() }
        }
    }

    @ViewBuilder
    private var signOutOverlay: some View {
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
}
