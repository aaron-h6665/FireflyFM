import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable {
    case today
    case messages
    case calendar
    case workspace

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .messages: "Messages"
        case .calendar: "Calendar"
        case .workspace: "Workspace"
        }
    }

    func systemImage(selected: Bool) -> String {
        switch (self, selected) {
        case (.today, true): "sun.max.fill"
        case (.today, false): "sun.max"
        case (.messages, true): "message.fill"
        case (.messages, false): "message"
        case (.calendar, true): "calendar.badge.clock"
        case (.calendar, false): "calendar"
        case (.workspace, true): "square.grid.2x2.fill"
        case (.workspace, false): "square.grid.2x2"
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var notificationInbox: NotificationInboxStore
    @State private var selectedTab = AppTab.today.rawValue
    @State private var focusedEventId: UUID?

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(FireflyTheme.Colors.card)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            todayScreen
                .tabItem { tabLabel(.today) }
                .tag(AppTab.today.rawValue)

            ConversationsListView()
                .tabItem { tabLabel(.messages) }
                .tag(AppTab.messages.rawValue)

            EventsView(focusedEventId: $focusedEventId)
                .tabItem { tabLabel(.calendar) }
                .tag(AppTab.calendar.rawValue)

            workspaceScreen
                .tabItem { tabLabel(.workspace) }
                .tag(AppTab.workspace.rawValue)
        }
        .tint(FireflyTheme.Colors.primaryAction)
        .task(id: appSession.activeMembershipId) {
            await notificationInbox.refresh()
            await notificationInbox.startRealtime()
        }
        .onChange(of: appSession.activeMembershipId) { _, _ in
            selectedTab = AppTab.today.rawValue
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

    @ViewBuilder
    private var todayScreen: some View {
        switch appSession.role {
        case .parent:
            ParentTodayView(selectedTab: $selectedTab, focusedEventId: $focusedEventId)
        case .teacher:
            TeacherTodayView(selectedTab: $selectedTab, focusedEventId: $focusedEventId)
        case .schoolDirector:
            SchoolDirectorTodayView(selectedTab: $selectedTab, focusedEventId: $focusedEventId)
        case .hqDirector:
            HQDirectorTodayView()
        case .none:
            ContentUnavailableView("No Today view available", systemImage: "sun.max")
        }
    }

    @ViewBuilder
    private var workspaceScreen: some View {
        switch appSession.role {
        case .parent:
            ParentWorkspaceView()
        case .teacher:
            TeacherWorkspaceView()
        case .schoolDirector:
            SchoolDirectorWorkspaceView()
        case .hqDirector:
            HQDirectorWorkspaceView()
        case .none:
            ContentUnavailableView("No workspace available", systemImage: "building.2")
        }
    }

    private func tabLabel(_ tab: AppTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage(selected: selectedTab == tab.rawValue))
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
        .environmentObject(DeepLinkManager())
}
