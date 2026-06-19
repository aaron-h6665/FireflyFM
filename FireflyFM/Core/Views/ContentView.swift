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
    @EnvironmentObject private var appSession: AppSessionManager
    @State private var showSignUp = false
    @State private var signupSuccess = false
    
    var body: some View {
        Group {
            switch authManager.authState {
            case .notDetermind:
                ZStack {
                    AppConstants.Colors.background.ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                        ProgressView()
                            .tint(AppConstants.Colors.accessibleYellow)
                    }
                }
            case .notAuthenticated:
                NavigationStack {
                    ZStack {
                        AppConstants.Colors.background.ignoresSafeArea()
                        
                        // Decorative Glow
                        VStack {
                            Circle()
                                .fill(AppConstants.Colors.accessibleYellow.opacity(0.15))
                                .frame(width: 400, height: 400)
                                .blur(radius: 60)
                                .offset(x: -150, y: -200)
                            Spacer()
                        }
                        
                        VStack(spacing: 40) {
                            Spacer()
                            
                            // Branding
                            VStack(spacing: 16) {
                                Image("Logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 140, height: 140)
                                
                                VStack(spacing: 8) {
                                    Text("Firefly Care") // Update with your actual app name
                                        .font(.system(size: 38, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    Text("Connecting directors, staff, and parents.")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.85)) // High contrast text
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                            }
                            
                            Spacer()
                            
                            // Navigation Buttons
                            VStack(spacing: 16) {
                                // Pushes to the Login View
                                NavigationLink(destination: LoginView()) {
                                    Text("Sign In")
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(AppConstants.Colors.accessibleYellow)
                                        .foregroundColor(.black)
                                        .cornerRadius(12)
                                        .shadow(color: AppConstants.Colors.accessibleYellow.opacity(0.3), radius: 10, x: 0, y: 5)
                                }
                                
                                // Pushes to the Role Selection View
                                NavigationLink(destination: RoleSelectionView()) {
                                    Text("Create an Account")
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(AppConstants.Colors.card)
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                        }
                    }
                }
//                if showSignUp {
//                    SignUpView(
//                        showLogin: { 
//                            showSignUp = false 
//                        },
//                        onSignupSuccess: {
//                            signupSuccess = true
//                            showSignUp = false
//                        }
//                    )
//                } else {
//                    LoginView(
//                        showSignUp: { 
//                            showSignUp = true 
//                        },
//                        signupSuccess: signupSuccess
//                    )
//                }
            case .authenticated:
                if appSession.isLoading {
                    ZStack {
                        AppConstants.Colors.background.ignoresSafeArea()
                        ProgressView("Loading school")
                            .tint(AppConstants.Colors.accessibleYellow)
                            .foregroundColor(.white)
                    }
                } else if appSession.hasSchoolAccess {
                    MainTabView()
                } else {
                    SchoolWelcomeView()
                }
            }
        }
        .task {
            await authManager.getAuthState()
        }
        .task(id: authManager.authState) {
            switch authManager.authState {
            case .authenticated:
                await appSession.refresh()
            case .notAuthenticated:
                appSession.clear()
            case .notDetermind:
                break
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
}
