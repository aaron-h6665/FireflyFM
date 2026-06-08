//
//  ContentView.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/8/26.
//

import SwiftUI
import CoreData
import Supabase

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    
    
    var body: some View {
        Group {
            switch authManager.authState {
            case .notDetermind:
                ProgressView()
            case .notAuthenticated:
                LoginView()
            case .authenticated:
                VStack {
                    Image(systemName: "globe").imageScale(.large).foregroundStyle(.tint)
                    Text("Hello, world!")
                    
                    Button("Sign Out") {
                        Task { await AuthManager.signOut() }
                    }
                }
                .padding(<#T##insets: EdgeInsets##EdgeInsets#>)
            }
        }
    }
}

#Preview {
    ContentView()
}
