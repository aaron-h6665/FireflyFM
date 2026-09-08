//
//  FireflyFMApp.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/8/26.
//

import SwiftUI
import CoreData

@main
struct FireflyFMApp: App {
    @UIApplicationDelegateAdaptor(FireflyAppDelegate.self) private var appDelegate
    @StateObject private var authManager = AuthManager(service: SupabaseAuthService())
    @StateObject private var deepLinkManager = DeepLinkManager()
    @StateObject private var appSession = AppSessionManager()
    @StateObject private var notificationInbox = NotificationInboxStore()
    
    var body: some Scene {
        WindowGroup {
            rootView
                .safeAreaInset(edge: .top) {
                    #if DEBUG && targetEnvironment(simulator)
                    if AppConfiguration.paymentDemoEnabled {
                        PaymentDemoAccountMenu().environmentObject(authManager)
                    }
                    #endif
                }
                .environmentObject(authManager)
                .environmentObject(deepLinkManager)
                .environmentObject(appSession)
                .environmentObject(notificationInbox)
                .onOpenURL { url in
                    deepLinkManager.handle(url: url)
                }
                .onReceive(NotificationCenter.default.publisher(for: .fireflyRemoteNotificationTapped)) { notification in
                    if let url = notification.object as? URL { deepLinkManager.handle(url: url) }
                }
        }
    }

    @ViewBuilder
    private var rootView: some View {
#if DEBUG
        if let role = roleMatrixSmokeTestRole {
            RoleMatrixSmokeHost(role: role)
        } else {
            ContentView()
        }
#else
        ContentView()
#endif
    }

#if DEBUG
    private var roleMatrixSmokeTestRole: SchoolRole? {
        let prefix = "--ui-test-role="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return SchoolRole(rawValue: String(argument.dropFirst(prefix.count)))
    }
#endif
}

#if DEBUG
private struct RoleMatrixSmokeHost: View {
    let role: SchoolRole
    @EnvironmentObject private var appSession: AppSessionManager

    var body: some View {
        Group {
            if appSession.role == role {
                MainTabView()
            } else {
                ProgressView()
                    .task { appSession.configureForRoleMatrixSmokeTest(role: role) }
            }
        }
    }
}
#endif
