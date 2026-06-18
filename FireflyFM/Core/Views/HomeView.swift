//
//  HomeView.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var showingProfile = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                
                VStack {
                    // Header
                    HStack {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                        
                        Spacer()
                        
                        Button {
                            showingProfile = true
                        } label: {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                                .foregroundColor(.white.opacity(0.8))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    Spacer()
                    
                    // Middle Blank Section
                    Text("Home Dashboard Placeholder")
                        .foregroundColor(.white.opacity(0.5))
                    
                    Spacer()
                    
                    // Temporary Sign Out Button just so we don't trap the user
                    Button("Sign Out") {
                        Task { await authManager.signOut() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppConstants.Colors.card)
                    .foregroundColor(.white)
                    .padding(.bottom)
                }
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthManager(service: SupabaseAuthService()))
}
