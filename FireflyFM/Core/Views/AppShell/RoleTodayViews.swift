import SwiftUI

/// Parent-owned composition. It deliberately remains separate from the
/// teacher screen so either workflow can evolve without dashboard flags.
struct ParentTodayView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appSession: AppSessionManager

    @Binding var selectedTab: Int
    @Binding var focusedEventId: UUID?
    @State private var showingProfile = false
    @State private var showingSignOutConfirmation = false
    @State private var refreshTrigger = 0

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        NavigationStack {
            FireflyScreen {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingLarge) {
                        TodayHeader(
                            title: "Today",
                            onProfile: { showingProfile = true },
                            onSignOut: { showingSignOutConfirmation = true }
                        )

                        TodaySectionIntro(
                            title: "What do you need to do?",
                            message: "The most common family actions are one tap away."
                        )

                        LazyVGrid(columns: columns, spacing: FireflyTheme.Layout.spacingMedium) {
                            NavigationLink {
                                ChildrenView()
                            } label: {
                                TodayActionCard(
                                    title: "My Children",
                                    subtitle: "Profiles and school records",
                                    systemImage: "figure.2.and.child.holdinghands",
                                    color: FireflyTheme.Colors.primaryAction
                                )
                            }
                            .buttonStyle(.plain)

                            Button { selectedTab = AppTab.messages.rawValue } label: {
                                TodayActionCard(
                                    title: "Messages",
                                    subtitle: "Connect with your school",
                                    systemImage: "message.fill",
                                    color: FireflyTheme.Colors.fireflyBlue
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                GuardianAttendanceQRView()
                            } label: {
                                TodayActionCard(
                                    title: "Scan Check-In Code",
                                    subtitle: "Check your child in or out",
                                    systemImage: "qrcode.viewfinder",
                                    color: .green
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        MessagesSpotlightCard(
                            systemImage: "heart.text.square.fill",
                            message: "Open your child’s family chat to see meals, naps, photos, classroom moments, and replies from the school.",
                            action: { selectedTab = AppTab.messages.rawValue }
                        )

                        AssignmentShortcutCard(
                            title: "Paperwork",
                            subtitle: "Complete paperwork and school requests.",
                            systemImage: "checklist",
                            destination: PaperworkWorkspaceView()
                        )

                        UpcomingEventsSection(
                            schoolId: appSession.activeSchool?.id,
                            refreshTrigger: refreshTrigger
                        ) { event in
                            focusedEventId = event.id
                            selectedTab = AppTab.calendar.rawValue
                        }

                        if let school = appSession.activeSchool {
                            TodaySchoolNewsletterSection(
                                school: school,
                                refreshTrigger: refreshTrigger
                            )
                        }
                    }
                    .padding(FireflyTheme.Layout.cardPadding)
                    .containerRelativeFrame(.horizontal, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .background(FireflyVerticalScrollLock())
                .refreshable { await refreshHome() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingProfile) { ProfileView() }
            .overlay { signOutOverlay }
        }
    }

    private func refreshHome() async {
        await appSession.refresh(selecting: appSession.activeMembershipId)
        refreshTrigger &+= 1
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
}

/// Teacher-owned composition. Shared cards provide consistent behavior, while
/// layout and destinations remain local to the teacher feature.
struct TeacherTodayView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appSession: AppSessionManager

    @Binding var selectedTab: Int
    @Binding var focusedEventId: UUID?
    @State private var showingProfile = false
    @State private var showingSignOutConfirmation = false
    @State private var refreshTrigger = 0

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        NavigationStack {
            FireflyScreen {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingLarge) {
                        TodayHeader(
                            title: "Today",
                            onProfile: { showingProfile = true },
                            onSignOut: { showingSignOutConfirmation = true }
                        )

                        TodaySectionIntro(
                            title: "What do you need to do?",
                            message: "The most common classroom actions are one tap away."
                        )

                        LazyVGrid(columns: columns, spacing: FireflyTheme.Layout.spacingMedium) {
                            NavigationLink {
                                AttendanceView()
                            } label: {
                                TodayActionCard(
                                    title: "Attendance",
                                    subtitle: "Check children in or out",
                                    systemImage: "person.crop.circle.badge.checkmark",
                                    color: .green
                                )
                            }
                            .buttonStyle(.plain)

                            Button { selectedTab = AppTab.messages.rawValue } label: {
                                TodayActionCard(
                                    title: "Messages",
                                    subtitle: "Update families",
                                    systemImage: "message.fill",
                                    color: FireflyTheme.Colors.fireflyBlue
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        MessagesSpotlightCard(
                            systemImage: "plus.square.fill",
                            message: "Open a child’s family chat and press + to log meals, naps, potty, health, observations, or other classroom moments. Family requests arrive there too.",
                            action: { selectedTab = AppTab.messages.rawValue }
                        )

                        AssignmentShortcutCard(
                            title: "Training & Curriculum",
                            subtitle: "Continue required learning and school work.",
                            systemImage: "graduationcap.fill",
                            destination: AssignmentsView(filter: .learning)
                        )

                        UpcomingEventsSection(
                            schoolId: appSession.activeSchool?.id,
                            refreshTrigger: refreshTrigger
                        ) { event in
                            focusedEventId = event.id
                            selectedTab = AppTab.calendar.rawValue
                        }

                        if let school = appSession.activeSchool {
                            TodaySchoolNewsletterSection(
                                school: school,
                                refreshTrigger: refreshTrigger
                            )
                        }
                    }
                    .padding(FireflyTheme.Layout.cardPadding)
                    .containerRelativeFrame(.horizontal, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .background(FireflyVerticalScrollLock())
                .refreshable { await refreshHome() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingProfile) { ProfileView() }
            .overlay { signOutOverlay }
        }
    }

    private func refreshHome() async {
        await appSession.refresh(selecting: appSession.activeMembershipId)
        refreshTrigger &+= 1
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
}
