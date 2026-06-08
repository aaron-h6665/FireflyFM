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
    @State private var showSignUp = false
    
    var body: some View {
        Group {
            switch authManager.authState {
            case .notDetermind:
                ZStack {
                    Color(red: 0.04, green: 0.07, blue: 0.09).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                        ProgressView()
                            .tint(.yellow)
                    }
                }
            case .notAuthenticated:
                if showSignUp {
                    SignUpView(showLogin: { showSignUp = false })
                } else {
                    LoginView(showSignUp: { showSignUp = true })
                }
            case .authenticated:
                VStack(spacing: 24) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                    
                    VStack(spacing: 8) {
                        Image(systemName: "globe").imageScale(.large).foregroundStyle(.yellow)
                        Text("Hello, world!")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    
                    Button("Sign Out") {
                        Task { await authManager.signOut() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.04, green: 0.07, blue: 0.09).ignoresSafeArea())
            }
        }
        .task {
            await authManager.getAuthState()
        }
    }
}

#Preview {
    ContentView()
}
