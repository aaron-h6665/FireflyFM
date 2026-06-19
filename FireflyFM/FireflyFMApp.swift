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
    @StateObject private var authManager = AuthManager(service: SupabaseAuthService())
    @StateObject private var deepLinkManager = DeepLinkManager()
    @StateObject private var appSession = AppSessionManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(deepLinkManager)
                .environmentObject(appSession)
                .onOpenURL { url in
                    deepLinkManager.handle(url: url)
                }
        }
    }
}
