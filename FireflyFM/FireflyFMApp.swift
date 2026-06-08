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
    @State private var authManager = AuthManager(service: SupabaseAuthService())

    var body: some Scene {
        WindowGroup {
            ContentView().environment(authManager)
        }
    }
}
