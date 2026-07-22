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
                } else {
                    HomeView()
                }
            }
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                    Text("Home")
                }
                .tag(0)
            
            CommunityRootView()
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "person.3.fill" : "person.3")
                    Text("Community")
                }
                .tag(1)
            
            EventsView()
                .tabItem {
                    Image(systemName: selectedTab == 2 ? "calendar.badge.clock" : "calendar")
                    Text("Calendar")
                }
                .tag(2)
            
            ConversationsListView()
                .tabItem {
                    Image(systemName: selectedTab == 3 ? "message.fill" : "message")
                    Text("Chat")
                }
                .tag(3)

            AssignmentsView(surface: appSession.role == .hqDirector ? .hqEducation : .all)
                .tabItem {
                    Image(systemName: selectedTab == 4 ? "checklist.checked" : "checklist")
                    Text("Work")
                }
                .tag(4)
        }
        .tint(AppConstants.Colors.primaryAction)
        .task(id: appSession.activeMembershipId) {
            await notificationInbox.refresh()
        }
        .onChange(of: appSession.activeMembershipId) { _, _ in
            selectedTab = 0
        }
        .onAppear {
            if deepLinkManager.pendingRoomInvite != nil {
                selectedTab = 3
            }
        }
        .onChange(of: deepLinkManager.pendingRoomInvite) { _, invite in
            if invite != nil {
                selectedTab = 3
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
        .environmentObject(DeepLinkManager())
}
