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
                    .foregroundColor(.white)
                    .padding(.top, 10)
                
                VStack(spacing: 16) {
                    NavigationLink(destination: DirectorSignUpView()) {
                        RoleCard(
                            title: "School Director",
                            description: "Manage your facility, staff, and overall operations.",
                            icon: "building.columns.fill"
                        )
                    }
                    
                    NavigationLink(destination: TeacherSignUpView()) {
                        RoleCard(
                            title: "Staff / Teacher",
                            description: "Manage your classroom, log activities, and message parents.",
                            icon: "person.text.rectangle.fill"
                        )
                    }
                    
                    NavigationLink(destination: ParentSignUpView()) {
                        RoleCard(
                            title: "Parent / Approved Pickup",
                            description: "Stay updated on your child's day and manage schedules.",
                            icon: "figure.2.and.child.holdinghands"
                        )
                    }
                }
                
                Spacer()
                
                HStack {
                    Spacer()
                    NavigationLink(destination: LoginView()) {
                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .foregroundColor(.white.opacity(0.85))
                            Text("Sign In")
                                .fontWeight(.bold)
                                .foregroundColor(AppConstants.Colors.accessibleYellow) 
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
                    // Using our new high-contrast yellow
                    .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.20))
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
    
    private let cardColor = Color(red: 0.15, green: 0.22, blue: 0.28)
    // Adjusted yellow for maximum contrast ratio against the dark card color
    private let accessibleYellow = Color(red: 1.0, green: 0.85, blue: 0.20)
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85)) // Slightly increased opacity for better reading contrast
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(accessibleYellow)
        }
        .padding()
        .background(cardColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1) // Slightly thicker border for definition
        )
        // Groups the card elements so a screen reader reads it as one unified button
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Placeholder Views (To prevent build errors)
struct DirectorSignUpView: View { var body: some View { Text("Director Sign Up").foregroundColor(.white) } }
struct TeacherSignUpView: View { var body: some View { Text("Teacher Sign Up").foregroundColor(.white) } }
struct ParentSignUpView: View { var body: some View { Text("Parent Sign Up").foregroundColor(.white) } }
    
#Preview {
    NavigationStack {
        RoleSelectionView().environmentObject(AuthManager(service: SupabaseAuthService()))
    }
}
