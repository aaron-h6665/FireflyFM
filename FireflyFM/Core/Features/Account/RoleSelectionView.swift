//
//  RoleSelectionView.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/11/26.
//

import SwiftUI

struct RoleSelectionView: View {
    // 1. Add the dismiss environment variable to handle the back action
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 24) {
                Text("What do you want to do?")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(AppConstants.Colors.primaryText)
                    .padding(.top, 10)
                
                VStack(spacing: 16) {
                    NavigationLink(destination: SignUpView(role: .teacher)) {
                        RoleCard(
                            title: "Staff / Teacher",
                            description: "Manage your classroom, log activities, and message parents.",
                            icon: "person.text.rectangle.fill"
                        )
                    }
                    
                    NavigationLink(destination: SignUpView(role: .parent)) {
                        RoleCard(
                            title: "Parent / Approved Pickup",
                            description: "Stay updated on your child's day and manage schedules.",
                            icon: "figure.2.and.child.holdinghands"
                        )
                    }
                }

                Text("Director accounts are created internally by FireflyFM or your school administrator.")
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                
                Spacer()
                
                HStack {
                    Spacer()
                    NavigationLink(destination: LoginView()) {
                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .foregroundColor(AppConstants.Colors.secondaryText)
                            Text("Sign In")
                                .fontWeight(.bold)
                                .foregroundColor(AppConstants.Colors.primaryAction)
                        }
                        .font(.footnote)
                    }
                    Spacer()
                }
                .padding(.bottom, 20)
            }
            .padding()
        }
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true) // Hide the default system back button
        // 2. Build the custom, accessible back button
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold)) // Bolder icon for visibility
                        Text("Back")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(AppConstants.Colors.primaryAction)
                }
                // Screen reader support
                .accessibilityLabel("Go back to the previous screen")
            }
        }
    }
}
// MARK: - Custom UI Component
struct RoleCard: View {
    let title: String
    let description: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(AppConstants.Colors.primaryText)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(AppConstants.Colors.primaryAction)
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppConstants.Colors.separator, lineWidth: 1)
        )
        // Groups the card elements so a screen reader reads it as one unified button
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}


    
#Preview("Light") {
    NavigationStack {
        RoleSelectionView().environmentObject(AuthManager(service: SupabaseAuthService()))
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        RoleSelectionView().environmentObject(AuthManager(service: SupabaseAuthService()))
    }
    .preferredColorScheme(.dark)
}
