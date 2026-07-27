//
//  MainTabView.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var notificationInbox: NotificationInboxStore
    @State private var selectedTab = 0
    
    init() {
        // Customize the TabBar appearance
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(AppConstants.Colors.card) // Using the card color for the tab bar
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Group {
                if appSession.role == .hqDirector {
                    HQHomeView()
                } else if appSession.role == .teacher {
                    TeacherTodayView()
                } else {
                    HomeView()
                }
            }
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "sun.max.fill" : "sun.max")
                    Text("Today")
                }
                .tag(0)

            ConversationsListView()
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "message.fill" : "message")
                    Text("Messages")
                }
                .tag(1)
            
            EventsView()
                .tabItem {
                    Image(systemName: selectedTab == 2 ? "calendar.badge.clock" : "calendar")
                    Text("Calendar")
                }
                .tag(2)
            
            RoleWorkspaceView()
                .tabItem {
                    Image(systemName: selectedTab == 3 ? "square.grid.2x2.fill" : "square.grid.2x2")
                    Text("Workspace")
                }
                .tag(3)
        }
        .tint(AppConstants.Colors.primaryAction)
        .task(id: appSession.activeMembershipId) {
            await notificationInbox.refresh()
            await notificationInbox.startRealtime()
        }
        .onChange(of: appSession.activeMembershipId) { _, _ in
            selectedTab = 0
        }
        .sheet(
            isPresented: Binding(
                get: { deepLinkManager.pendingNotificationId != nil },
                set: { if !$0 { deepLinkManager.clearNotification() } }
            )
        ) {
            NotificationsView(focusNotificationId: deepLinkManager.pendingNotificationId)
        }
    }
}

private struct TeacherTodayView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @State private var showingProfile = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header

                        VStack(alignment: .leading, spacing: 5) {
                            Text("What do you need to do?")
                                .font(.title2.bold())
                            Text("The most common classroom actions are one tap away.")
                                .font(.subheadline)
                                .foregroundColor(AppConstants.Colors.secondaryText)
                        }

                        LazyVGrid(columns: columns, spacing: 14) {
                            teacherLink("Attendance", subtitle: "Check children in or out", symbol: "person.crop.circle.badge.checkmark", color: .green) {
                                AttendanceView()
                            }
                            teacherLink("Messages", subtitle: "Update families", symbol: "message.fill", color: AppConstants.Colors.fireflyBlue) {
                                ConversationsListView()
                            }
                            teacherLink("Care Today", subtitle: "Meals, naps, bathroom, health", symbol: "heart.text.square.fill", color: .orange) {
                                CareTodayView()
                            }
                            teacherLink("Family Requests", subtitle: "Absences, medication, notes", symbol: "person.2.badge.gearshape.fill", color: .purple) {
                                FamilyRequestsView()
                            }
                        }

                        NavigationLink {
                            AssignmentsView(surface: .curriculum)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "graduationcap.fill")
                                    .font(.title2)
                                    .frame(width: 46, height: 46)
                                    .foregroundColor(AppConstants.Colors.brandNavy)
                                    .background(AppConstants.Colors.fireflyGlow)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Training & Assignments").font(.headline)
                                    Text("Continue required learning and school work.")
                                        .font(.caption)
                                        .foregroundColor(AppConstants.Colors.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(AppConstants.Colors.secondaryText)
                            }
                            .padding()
                            .background(AppConstants.Colors.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingProfile) { ProfileView() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today")
                        .font(.largeTitle.bold())
                    Text(appSession.activeSchool?.name ?? "Your school")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.secondaryText)
                }
                Spacer()
                NotificationBellButton()
                Button { showingProfile = true } label: {
                    Circle()
                        .fill(AppConstants.Colors.wingMist)
                        .frame(width: AppConstants.Layout.minimumTapTarget, height: AppConstants.Layout.minimumTapTarget)
                        .overlay {
                            Text(appSession.profile?.initials ?? "FF")
                                .font(.caption.bold())
                                .foregroundColor(AppConstants.Colors.brandNavy)
                        }
                }
                .accessibilityLabel("Profile")
            }

            if appSession.canSwitchSchools {
                Picker("Active School", selection: Binding(
                    get: { appSession.activeMembershipId ?? appSession.memberships.first?.membership.id },
                    set: { membershipId in
                        if let membershipId { appSession.switchActiveMembership(to: membershipId) }
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

    private func teacherLink<Destination: View>(
        _ title: String,
        subtitle: String,
        symbol: String,
        color: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            .padding()
            .background(AppConstants.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius))
        }
        .buttonStyle(.plain)
    }
}

private struct RoleWorkspaceView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(workspaceSubtitle)
                            .font(.subheadline)
                            .foregroundColor(AppConstants.Colors.secondaryText)

                        switch appSession.role {
                        case .parent:
                            workspaceLink("My Children", subtitle: "Profiles, progress, and school records", symbol: "figure.2.and.child.holdinghands", destination: ChildrenView())
                            workspaceLink("Assignments & Forms", subtitle: "Paperwork and school requests", symbol: "checklist", destination: AssignmentsView(surface: .all))
                            workspaceLink("School Community", subtitle: "Newsletters, albums, and school updates", symbol: "person.3.fill", destination: CommunityRootView())
                        case .teacher:
                            workspaceLink("Training & Assignments", subtitle: "Required learning and school work", symbol: "graduationcap.fill", destination: AssignmentsView(surface: .curriculum))
                            workspaceLink("Children", subtitle: "Child profiles and classroom context", symbol: "figure.2.and.child.holdinghands", destination: ChildrenView())
                            workspaceLink("School Community", subtitle: "Posts, albums, and school information", symbol: "person.3.fill", destination: CommunityRootView())
                        case .schoolDirector:
                            workspaceLink("Children & Attendance", subtitle: "Manage rosters, identity, and attendance history", symbol: "person.2.crop.square.stack.fill", destination: ChildrenAttendanceWorkspace())
                            workspaceLink("People & Access", subtitle: "Invitations, onboarding, and school access", symbol: "person.badge.key.fill", destination: SchoolDirectorAccessWorkspace())
                            workspaceLink("Assignments", subtitle: "Create, review, and manage school work", symbol: "checklist", destination: AssignmentsView(surface: .all))
                            workspaceLink("School Community", subtitle: "Newsletters, posts, albums, and information", symbol: "person.3.fill", destination: CommunityRootView())
                        case .hqDirector:
                            workspaceLink("Schools", subtitle: "School-by-school operational overview", symbol: "building.2.fill", destination: HQHomeView())
                            workspaceLink("Attendance", subtitle: "Filter attendance and history by school", symbol: "calendar.badge.checkmark", destination: AttendanceView())
                            workspaceLink("Education", subtitle: "Assignments and curriculum across schools", symbol: "graduationcap.fill", destination: AssignmentsView(surface: .hqEducation))
                            workspaceLink("Communities", subtitle: "Open a school's community space", symbol: "person.3.fill", destination: CommunityRootView())
                        case .none:
                            ContentUnavailableView("No workspace available", systemImage: "building.2")
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Workspace")
        }
    }

    private var workspaceSubtitle: String {
        switch appSession.role {
        case .parent: "Everything about your child and school outside of Messages."
        case .teacher: "Less-frequent classroom tools stay organized here."
        case .schoolDirector: "School administration and oversight tools."
        case .hqDirector: "Cross-school administration and reporting tools."
        case .none: ""
        }
    }

    private func workspaceLink<Destination: View>(
        _ title: String,
        subtitle: String,
        symbol: String,
        destination: Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundColor(AppConstants.Colors.primaryAction)
                    .frame(width: 48, height: 48)
                    .background(AppConstants.Colors.wingMist)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundColor(AppConstants.Colors.primaryText)
                    Text(subtitle).font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(AppConstants.Colors.secondaryText)
            }
            .padding()
            .background(AppConstants.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius))
        }
        .buttonStyle(.plain)
    }
}

private struct ChildrenAttendanceWorkspace: View {
    var body: some View {
        List {
            NavigationLink("Children") { ChildrenView() }
            NavigationLink("Attendance") { AttendanceView() }
        }
        .navigationTitle("Children & Attendance")
    }
}

private struct SchoolDirectorAccessWorkspace: View {
    @EnvironmentObject private var appSession: AppSessionManager

    var body: some View {
        if let school = appSession.activeSchool {
            OnboardingManagementView(school: school, mode: .schoolDirector)
        } else {
            ContentUnavailableView("No active school", systemImage: "building.2")
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
        .environmentObject(DeepLinkManager())
}
