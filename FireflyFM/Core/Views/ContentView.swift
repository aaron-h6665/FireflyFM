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
    @EnvironmentObject private var authManager: AuthManager
    @State private var showSignUp = false
    @State private var signupSuccess = false
    
    var body: some View {
        Group {
            switch authManager.authState {
            case .notDetermind:
                ZStack {
                    Color(red: 0.10, green: 0.15, blue: 0.20).ignoresSafeArea()
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
                    SignUpView(
                        showLogin: { 
                            showSignUp = false 
                        },
                        onSignupSuccess: {
                            signupSuccess = true
                            showSignUp = false
                        }
                    )
                } else {
                    LoginView(
                        showSignUp: { 
                            showSignUp = true 
                        },
                        signupSuccess: signupSuccess
                    )
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
                .background(Color(red: 0.10, green: 0.15, blue: 0.20).ignoresSafeArea())
            }
        }
        .task {
            await authManager.getAuthState()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
}
