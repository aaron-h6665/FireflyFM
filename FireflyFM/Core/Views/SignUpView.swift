//
//  SignUpView.swift
//  FireflyFM
//
//  Created by Gemini CLI on 6/8/26.
//

import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var showLogin: () -> Void
    var onSignupSuccess: () -> Void
    
    // Firefly Color Palette
    private let backgroundColor = Color(red: 0.10, green: 0.15, blue: 0.20)
    private let cardColor = Color(red: 0.15, green: 0.22, blue: 0.28)
    private let accentColor = Color.yellow
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            // Decorative Glows
            VStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 400, height: 400)
                    .blur(radius: 60)
                    .offset(x: 150, y: -200)
                Spacer()
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 300, height: 300)
                    .blur(radius: 50)
                    .offset(x: -150, y: 150)
            }
            
            ScrollView {
                VStack(spacing: 24) {
                    // Logo
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .padding(.top, 40)
                    
                    VStack(spacing: 8) {
                        Text("Join FireflyFM")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Create an account to start listening")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    VStack(spacing: 16) {
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.caption.bold())
                                .foregroundColor(accentColor)
                            TextField("name@example.com", text: $email)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.none)
                                .keyboardType(.emailAddress)
                                .padding()
                                .background(cardColor)
                                .cornerRadius(12)
                                .foregroundColor(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                        
                        // Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.caption.bold())
                                .foregroundColor(accentColor)
                            SecureField("Create a password", text: $password)
                                .padding()
                                .background(cardColor)
                                .cornerRadius(12)
                                .foregroundColor(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                        
                        // Confirm Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm Password")
                                .font(.caption.bold())
                                .foregroundColor(accentColor)
                            SecureField("Repeat your password", text: $confirmPassword)
                                .padding()
                                .background(cardColor)
                                .cornerRadius(12)
                                .foregroundColor(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Error Message
                    if let error = errorMessage ?? authManager.error?.localizedDescription {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // Sign Up Button
                    Button {
                        if password != confirmPassword {
                            errorMessage = "Passwords do not match"
                            return
                        }
                        errorMessage = nil
                        Task {
                            isLoading = true
                            let success = await authManager.signUp(withEmail: email, password: password)
                            isLoading = false
                            if success {
                                onSignupSuccess()
                            }
                        }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView().tint(.black)
                            } else {
                                Text("Create Account")
                                    .fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(accentColor)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                        .shadow(color: accentColor.opacity(0.4), radius: 10, x: 0, y: 5)
                    }
                    .padding(.horizontal)
                    .disabled(isLoading || email.isEmpty || password.isEmpty || confirmPassword.isEmpty)
                    
                    // Login Link
                    Button {
                        authManager.clearError()
                        showLogin()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .foregroundColor(.white.opacity(0.7))
                            Text("Sign In")
                                .fontWeight(.bold)
                                .foregroundColor(accentColor)
                        }
                        .font(.footnote)
                    }
                    .padding(.bottom, 20)
                }
                .padding()
            }
        }
    }
}

#Preview {
    SignUpView(showLogin: {}, onSignupSuccess: {})
        .environmentObject(AuthManager(service: SupabaseAuthService()))
}
