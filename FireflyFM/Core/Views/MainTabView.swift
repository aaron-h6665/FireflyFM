//
//  MainTabView.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
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
            HomeView()
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                    Text("Home")
                }
                .tag(0)
            
            NotificationsView()
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "bell.fill" : "bell")
                    Text("Notifications")
                }
                .tag(1)
            
            EventsView()
                .tabItem {
                    Image(systemName: selectedTab == 2 ? "calendar.badge.clock" : "calendar")
                    Text("Events")
                }
                .tag(2)
            
            ConversationsListView()
                .tabItem {
                    Image(systemName: selectedTab == 3 ? "message.fill" : "message")
                    Text("Chat")
                }
                .tag(3)
        }
        .tint(AppConstants.Colors.accessibleYellow) // This ensures the active tab uses our yellow
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
