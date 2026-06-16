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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
        }
    }
}
